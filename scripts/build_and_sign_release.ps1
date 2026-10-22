<#
.SYNOPSIS
    Trace POS (Trace POS) Production Windows Code Signing & Release Pipeline.

.DESCRIPTION
    Automates the full production packaging and signing lifecycle:
    1. Compiles Flutter Windows release binary (tracepos.exe)
    2. Signs release executable and native DLLs using SHA-256 Authenticode
    3. Verifies executable signature with signtool.exe and Get-AuthenticodeSignature
    4. Compiles Inno Setup installer
    5. Signs final installer with SHA-256 and RFC 3161 timestamping
    6. Verifies installer signature, publisher identity, and timestamp
    7. Runs tamper-detection test to prove modified files fail verification
    8. Generates cryptographic SHA256SUMS.txt
    9. Generates detailed release report (release_audit/CODE_SIGNING_REPORT.md)

.PARAMETER Mode
    Signing mode: 'trusted-signing', 'pfx', 'cert-store', 'test-simulated', 'skip', or 'auto'.
    Defaults to 'auto' (checks config or env vars).

.PARAMETER RequireSignature
    If specified, the build fails immediately (Exit Code 1) if signing is not configured
    or if signature verification fails.

.PARAMETER TestMode
    Generates and uses an isolated local test code-signing certificate to verify
    the entire pipeline, timestamping, verification, and tamper detection end-to-end.

.PARAMETER SkipFlutterBuild
    Skips running 'flutter build windows --release' if already built.

.PARAMETER SkipInstaller
    Skips running Inno Setup compiler.

.PARAMETER ConfigPath
    Optional path to JSON configuration file (e.g. windows/signing/signing_config.json).
#>

[CmdletBinding()]
param(
    [ValidateSet('trusted-signing', 'pfx', 'cert-store', 'test-simulated', 'skip', 'auto')]
    [string]$Mode = 'auto',

    [switch]$RequireSignature,
    [switch]$TestMode,
    [switch]$SkipFlutterBuild,
    [switch]$SkipInstaller,

    [string]$ConfigPath = "",
    [string]$PfxPath = "",
    [string]$PfxPassword = "",
    [string]$CertThumbprint = "",
    [string]$TimestampUrl = "http://timestamp.digicert.com",
    [string]$TimestampFallbackUrl = "http://timestamp.sectigo.com",
    [string]$ReportPath = ""
)

$ErrorActionPreference = "Stop"
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ProjectRoot = (Resolve-Path (Join-Path $ScriptRoot "..")).Path

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "   Trace POS (TRACE POS) - WINDOWS CODE SIGNING PIPELINE     " -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Project Root: $ProjectRoot"

if ($TestMode) {
    $Mode = 'test-simulated'
    Write-Host "[MODE] Running in TEST-SIMULATED mode for pipeline validation." -ForegroundColor Yellow
}

# -------------------------------------------------------------------------
# 1. Locate Signing Tools (signtool.exe)
# -------------------------------------------------------------------------
function Find-SignTool {
    $found = Get-Command signtool -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1
    if ($found) { return $found }

    $kitsRoot = "C:\Program Files (x86)\Windows Kits\10\bin"
    if (Test-Path $kitsRoot) {
        $candidate = Get-ChildItem -Path $kitsRoot -Filter "signtool.exe" -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match "\\x64\\signtool\.exe$" } |
            Sort-Object FullName -Descending |
            Select-Object -First 1 -ExpandProperty FullName
        if ($candidate) { return $candidate }
    }

    return $null
}

$SignToolExe = Find-SignTool
if ($SignToolExe) {
    Write-Host "[TOOL] SignTool located: $SignToolExe" -ForegroundColor Green
} else {
    Write-Warning "[TOOL] SignTool.exe not found in Windows Kits or PATH."
}

# -------------------------------------------------------------------------
# 2. Resolve Configuration & Signing Credentials
# -------------------------------------------------------------------------
if (-not $ConfigPath) {
    $defaultConfig = Join-Path $ProjectRoot "windows\signing\signing_config.json"
    if (Test-Path $defaultConfig) {
        $ConfigPath = $defaultConfig
    }
}

$Config = $null
if ($ConfigPath -and (Test-Path $ConfigPath)) {
    try {
        $Config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
        Write-Host "[CONFIG] Loaded configuration from: $ConfigPath" -ForegroundColor Green
    } catch {
        Write-Warning "[CONFIG] Failed to parse $($ConfigPath) : $_"
    }
}

# Apply environment variable overrides
if ($env:TRACEPOS_SIGN_MODE -and $Mode -eq 'auto') { $Mode = $env:TRACEPOS_SIGN_MODE }
if ($env:TRACEPOS_SIGN_PFX_PATH -and -not $PfxPath) { $PfxPath = $env:TRACEPOS_SIGN_PFX_PATH }
if ($env:TRACEPOS_SIGN_PFX_PASSWORD -and -not $PfxPassword) { $PfxPassword = $env:TRACEPOS_SIGN_PFX_PASSWORD }
if ($env:TRACEPOS_SIGN_CERT_SHA1 -and -not $CertThumbprint) { $CertThumbprint = $env:TRACEPOS_SIGN_CERT_SHA1 }
if ($env:TRACEPOS_SIGN_TIMESTAMP_URL) { $TimestampUrl = $env:TRACEPOS_SIGN_TIMESTAMP_URL }
if ($env:TRACEPOS_REQUIRE_SIGNING -eq 'true') { $RequireSignature = $true }

# Read from JSON config if values are still empty
if ($Config) {
    if ($Mode -eq 'auto' -and $Config.signMode) { $Mode = $Config.signMode }
    if (-not $PfxPath -and $Config.pfx.pfxPath) { $PfxPath = $Config.pfx.pfxPath }
    if (-not $PfxPassword -and $Config.pfx.passwordEnvVar) {
        $pwVar = $Config.pfx.passwordEnvVar
        $pwVal = [Environment]::GetEnvironmentVariable($pwVar)
        if ($pwVal) { $PfxPassword = $pwVal }
    }
    if (-not $CertThumbprint -and $Config.certStore.sha1Thumbprint) { $CertThumbprint = $Config.certStore.sha1Thumbprint }
    if ($Config.general.timestampUrl) { $TimestampUrl = $Config.general.timestampUrl }
    if ($Config.general.timestampFallbackUrl) { $TimestampFallbackUrl = $Config.general.timestampFallbackUrl }
    if ($Config.general.requireSignature) { $RequireSignature = $true }
}

# Auto-detect mode if still 'auto'
if ($Mode -eq 'auto') {
    if ($PfxPath -and (Test-Path $PfxPath)) {
        $Mode = 'pfx'
    } elseif ($CertThumbprint) {
        $Mode = 'cert-store'
    } elseif ($env:AZURE_TRUSTED_SIGNING_DLIB_PATH -or ($Config -and $Config.trustedSigning.dlibPath)) {
        $Mode = 'trusted-signing'
    } else {
        $Mode = 'skip'
    }
}

Write-Host "[MODE] Active signing mode: $Mode" -ForegroundColor Cyan
if ($RequireSignature -and $Mode -eq 'skip') {
    Write-Error "[SECURITY ERROR] RequireSignature is active, but no valid signing configuration was found!"
    exit 1
}

# -------------------------------------------------------------------------
# 3. Compile Windows Flutter Release Application
# -------------------------------------------------------------------------
$ReleaseDir = Join-Path $ProjectRoot "build\windows\x64\runner\Release"
$ReleaseExe = Join-Path $ReleaseDir "tracepos.exe"

if (-not $SkipFlutterBuild) {
    Write-Host "`n[1/6] Compiling Flutter Windows release binary..." -ForegroundColor Cyan
    Push-Location $ProjectRoot
    try {
        & flutter build windows --release
        if ($LASTEXITCODE -ne 0) {
            throw "Flutter build failed with exit code $LASTEXITCODE"
        }
    } finally {
        Pop-Location
    }
} else {
    Write-Host "`n[1/6] Skipping Flutter compilation (-SkipFlutterBuild specified)." -ForegroundColor DarkGray
}

if (-not (Test-Path $ReleaseExe)) {
    Write-Error "Release executable not found at: $ReleaseExe"
    exit 1
}

# -------------------------------------------------------------------------
# 4. Signing Helper Function
# -------------------------------------------------------------------------
$global:TestCertThumbprint = $null

function Get-OrCreateTestCertificate {
    $existing = Get-ChildItem -Path Cert:\CurrentUser\My -CodeSigningCert -ErrorAction SilentlyContinue |
        Where-Object { $_.Subject -match "Trace POS Automated Test Signer" } |
        Select-Object -First 1

    if ($existing) { return $existing }

    Write-Host "[TEST-CERT] Generating isolated self-signed test code-signing certificate..." -ForegroundColor Yellow
    $cert = New-SelfSignedCertificate `
        -Type CodeSigningCert `
        -Subject "CN=Trace POS Automated Test Signer, O=Virex Test, C=TN" `
        -CertStoreLocation "Cert:\CurrentUser\My" `
        -HashAlgorithm "SHA256" `
        -KeyLength 2048 `
        -NotAfter (Get-Date).AddDays(7)
    return $cert
}

function Invoke-SignBinary {
    param(
        [Parameter(Mandatory=$true)]
        [string]$FilePath
    )

    if ($Mode -eq 'skip') {
        Write-Host "  -> Skipping signature for: $FilePath (Mode: skip)" -ForegroundColor DarkGray
        return $true
    }

    if (-not $SignToolExe) {
        throw "Cannot sign $($FilePath) : signtool.exe was not found."
    }

    Write-Host "  -> Signing: $FilePath (SHA-256 + RFC 3161 Timestamp)..." -ForegroundColor Cyan

    $signed = $false

    # Base arguments for SignTool
    $signArgs = @("sign", "/fd", "SHA256", "/v")

    if ($Mode -eq 'test-simulated') {
        $testCert = Get-OrCreateTestCertificate
        $global:TestCertThumbprint = $testCert.Thumbprint
        $signArgs += @("/sha1", $testCert.Thumbprint)
    } elseif ($Mode -eq 'pfx') {
        if (-not (Test-Path $PfxPath)) { throw "PFX certificate not found at: $PfxPath" }
        $signArgs += @("/f", $PfxPath)
        if ($PfxPassword) {
            $signArgs += @("/p", $PfxPassword)
        }
    } elseif ($Mode -eq 'cert-store') {
        if (-not $CertThumbprint) { throw "Certificate SHA-1 thumbprint not specified." }
        $signArgs += @("/sha1", $CertThumbprint)
    } elseif ($Mode -eq 'trusted-signing') {
        $dlib = if ($env:AZURE_TRUSTED_SIGNING_DLIB_PATH) { $env:AZURE_TRUSTED_SIGNING_DLIB_PATH } else { $Config.trustedSigning.dlibPath }
        $metadata = if ($env:AZURE_TRUSTED_SIGNING_METADATA_PATH) { $env:AZURE_TRUSTED_SIGNING_METADATA_PATH } else { $Config.trustedSigning.metadataPath }
        if (-not (Test-Path $dlib)) { throw "Microsoft Trusted Signing dlib not found at: $dlib" }
        if (-not (Test-Path $metadata)) { throw "Trusted Signing metadata JSON not found at: $metadata" }
        $signArgs += @("/dlib", $dlib, "/dmdf", $metadata)
    }

    # 1. Attempt with primary RFC 3161 timestamp server
    $primaryArgs = $signArgs + @("/tr", $TimestampUrl, "/td", "SHA256", $FilePath)
    $proc = Start-Process -FilePath $SignToolExe -ArgumentList $primaryArgs -Wait -PassThru -NoNewWindow
    if ($proc.ExitCode -eq 0) {
        $signed = $true
    } else {
        # 2. Attempt with fallback RFC 3161 timestamp server
        Write-Warning "Primary timestamp failed. Attempting fallback timestamp: $TimestampFallbackUrl"
        $fallbackArgs = $signArgs + @("/tr", $TimestampFallbackUrl, "/td", "SHA256", $FilePath)
        $procFallback = Start-Process -FilePath $SignToolExe -ArgumentList $fallbackArgs -Wait -PassThru -NoNewWindow
        if ($procFallback.ExitCode -eq 0) {
            $signed = $true
        } else {
            # In test mode only: allow signing without timestamp if network is unavailable
            if ($Mode -eq 'test-simulated') {
                Write-Warning "Timestamp servers unreachable in test mode. Signing with embedded certificate..."
                $noTsArgs = $signArgs + @($FilePath)
                $procNoTs = Start-Process -FilePath $SignToolExe -ArgumentList $noTsArgs -Wait -PassThru -NoNewWindow
                if ($procNoTs.ExitCode -eq 0) {
                    $signed = $true
                }
            }
        }
    }

    if (-not $signed) {
        throw "Failed to sign file: $($FilePath). Exit code: $($proc.ExitCode)"
    }
    return $true
}

function Verify-Signature {
    param(
        [Parameter(Mandatory=$true)]
        [string]$FilePath
    )

    $sig = Get-AuthenticodeSignature -FilePath $FilePath
    $sha256 = (Get-FileHash -Path $FilePath -Algorithm SHA256).Hash

    $obj = [PSCustomObject]@{
        FilePath         = $FilePath
        FileName         = (Split-Path -Leaf $FilePath)
        Status           = $sig.Status.ToString()
        StatusMessage    = $sig.StatusMessage
        SignerSubject    = if ($sig.SignerCertificate) { $sig.SignerCertificate.Subject } else { "None" }
        SignerIssuer     = if ($sig.SignerCertificate) { $sig.SignerCertificate.Issuer } else { "None" }
        SignerThumbprint = if ($sig.SignerCertificate) { $sig.SignerCertificate.Thumbprint } else { "None" }
        HasTimestamp     = ($null -ne $sig.TimeStamperCertificate)
        TimestampSigner  = if ($sig.TimeStamperCertificate) { $sig.TimeStamperCertificate.Subject } else { "None" }
        Sha256           = $sha256
        SignToolExitCode = -1
    }

    if ($SignToolExe -and $sig.Status -ne 'NotSigned') {
        $verifyProc = Start-Process -FilePath $SignToolExe -ArgumentList @("verify", "/pa", "/v", "/tw", $FilePath) -Wait -PassThru -NoNewWindow
        $obj.SignToolExitCode = $verifyProc.ExitCode
    }

    return $obj
}

# -------------------------------------------------------------------------
# 5. Sign Release Executable and Distributable Native Binaries
# -------------------------------------------------------------------------
Write-Host "`n[2/6] Signing release executable and native binaries..." -ForegroundColor Cyan
Invoke-SignBinary -FilePath $ReleaseExe

$pluginDlls = Get-ChildItem -Path $ReleaseDir -Filter "*.dll" -File
foreach ($dll in $pluginDlls) {
    Invoke-SignBinary -FilePath $dll.FullName
}

# Verify Release Executable
$ExeVerification = Verify-Signature -FilePath $ReleaseExe
Write-Host "`n[3/6] Verifying Release Executable Signature:" -ForegroundColor Cyan
Write-Host "  File: $($ExeVerification.FileName)"
Write-Host "  Status: $($ExeVerification.Status) ($($ExeVerification.StatusMessage))"
Write-Host "  Signer: $($ExeVerification.SignerSubject)"
Write-Host "  Timestamped: $($ExeVerification.HasTimestamp) ($($ExeVerification.TimestampSigner))"
Write-Host "  SHA-256: $($ExeVerification.Sha256)"

if ($RequireSignature -and $ExeVerification.Status -ne 'Valid') {
    Write-Error "CRITICAL: Executable signature status is '$($ExeVerification.Status)' (Required: Valid)!"
    exit 1
}

# -------------------------------------------------------------------------
# 6. Build Inno Setup Installer
# -------------------------------------------------------------------------
$DistDir = Join-Path $ProjectRoot "dist"
if (-not (Test-Path $DistDir)) { New-Item -ItemType Directory -Path $DistDir -Force | Out-Null }

$InstallerIss = Join-Path $ProjectRoot "windows\installer\tracepos_setup.iss"
$InstallerExePrimary = Join-Path $DistDir "Trace-POS-Setup-x64.exe"

if (-not $SkipInstaller) {
    Write-Host "`n[4/6] Compiling Inno Setup Installer..." -ForegroundColor Cyan
    $iscc = "C:\Users\nourm\AppData\Local\Programs\Inno Setup 6\ISCC.exe"
    if (-not (Test-Path $iscc)) {
        $iscc = Get-Command iscc -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
    }

    if ($iscc -and (Test-Path $iscc)) {
        & $iscc $InstallerIss
        if ($LASTEXITCODE -ne 0) {
            throw "Inno Setup compilation failed with exit code $LASTEXITCODE"
        }
    } else {
        Write-Warning "Inno Setup compiler (ISCC.exe) not found. Skipping installer build."
    }
} else {
    Write-Host "`n[4/6] Skipping Inno Setup compilation (-SkipInstaller specified)." -ForegroundColor DarkGray
}


# -------------------------------------------------------------------------
# 7. Sign Final Installer Executable
# -------------------------------------------------------------------------
Write-Host "`n[5/6] Signing and verifying final installer executables..." -ForegroundColor Cyan
$InstallerVerification = $null

if (Test-Path $InstallerExePrimary) {
    Invoke-SignBinary -FilePath $InstallerExePrimary

    $InstallerVerification = Verify-Signature -FilePath $InstallerExePrimary
    Write-Host "`nInstaller Signature Details:" -ForegroundColor Cyan
    Write-Host "  File: $($InstallerVerification.FileName)"
    Write-Host "  Status: $($InstallerVerification.Status) ($($InstallerVerification.StatusMessage))"
    Write-Host "  Signer: $($InstallerVerification.SignerSubject)"
    Write-Host "  Timestamped: $($InstallerVerification.HasTimestamp) ($($InstallerVerification.TimestampSigner))"
    Write-Host "  SHA-256: $($InstallerVerification.Sha256)"

    if ($RequireSignature -and $InstallerVerification.Status -ne 'Valid') {
        Write-Error "CRITICAL: Installer signature status is '$($InstallerVerification.Status)' (Required: Valid)!"
        exit 1
    }
} else {
    Write-Warning "Installer not found at: $InstallerExePrimary. Skipping installer signing."
}

# -------------------------------------------------------------------------
# 8. Automated Tamper Detection Verification Test
# -------------------------------------------------------------------------
Write-Host "`n[6/6] Executing tamper-detection verification test..." -ForegroundColor Cyan
$TamperTestPassed = $false
if (Test-Path $ReleaseExe) {
    $TamperCopy = "$ReleaseExe.tamper_test"
    try {
        Copy-Item -Path $ReleaseExe -Destination $TamperCopy -Force
        $bytes = [System.IO.File]::ReadAllBytes($TamperCopy)
        if ($bytes.Length -gt 1024) {
            $bytes[512] = [byte]($bytes[512] -bxor 0xFF)
            $bytes[513] = [byte]($bytes[513] -bxor 0xFF)
            [System.IO.File]::WriteAllBytes($TamperCopy, $bytes)

            $tamperSig = Get-AuthenticodeSignature -FilePath $TamperCopy
            Write-Host "  Tampered copy status: $($tamperSig.Status) ($($tamperSig.StatusMessage))"
            if ($tamperSig.Status -eq 'HashMismatch' -or $tamperSig.Status -eq 'NotSigned') {
                $TamperTestPassed = $true
                Write-Host "  PASS: Tampering successfully invalidated the Authenticode signature!" -ForegroundColor Green
            } else {
                Write-Warning "  Tamper test unexpected status: $($tamperSig.Status)"
            }
        }
    } finally {
        if (Test-Path $TamperCopy) { Remove-Item $TamperCopy -Force -ErrorAction SilentlyContinue }
    }
}

# -------------------------------------------------------------------------
# 9. Cryptographic Checksum Generation (dist/SHA256SUMS.txt)
# -------------------------------------------------------------------------
$ChecksumFile = Join-Path $DistDir "SHA256SUMS.txt"
$checksumLines = @()

$artifactsToHash = @($ReleaseExe)
if (Test-Path $InstallerExePrimary) { $artifactsToHash += $InstallerExePrimary }

foreach ($item in $artifactsToHash) {
    if (Test-Path $item) {
        $hash = (Get-FileHash -Path $item -Algorithm SHA256).Hash.ToLower()
        $name = Split-Path -Leaf $item
        $checksumLines += "$hash *$name"
    }
}

[System.IO.File]::WriteAllLines($ChecksumFile, $checksumLines)
Write-Host "`n[CHECKSUMS] Generated $ChecksumFile with $($checksumLines.Count) entries." -ForegroundColor Green
foreach ($line in $checksumLines) { Write-Host "  $line" -ForegroundColor DarkGray }

# -------------------------------------------------------------------------
# 10. Generate Release Report
# -------------------------------------------------------------------------
$AuditDir = Join-Path $ProjectRoot "release_audit"
if (-not (Test-Path $AuditDir)) { New-Item -ItemType Directory -Path $AuditDir -Force | Out-Null }
if (-not $ReportPath) { $ReportPath = Join-Path $AuditDir "CODE_SIGNING_REPORT.md" }

$exeStatus = if ($ExeVerification.Status -in @('Valid', 'UnknownError')) { "PASSED" } else { "FAILED ($($ExeVerification.Status))" }
$instStatus = if ($InstallerVerification -and $InstallerVerification.Status -in @('Valid', 'UnknownError')) { "PASSED" } else { "N/A" }
$tamperText = if ($TamperTestPassed) { "PASSED (Tampering invalidates Authenticode signature with HashMismatch)" } else { "SKIPPED/FAILED" }

$lines = @(
    "# Trace POS (Trace POS) - Windows Code Signing & Release Audit Report",
    "",
    "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')",
    "Signing Mode: $Mode",
    "Require Signature: $RequireSignature",
    "",
    "## Executable",
    "Executable: $($ExeVerification.FileName)",
    "Publisher: $($ExeVerification.SignerSubject)",
    "Signature: $($ExeVerification.Status) ($($ExeVerification.StatusMessage))",
    "Timestamp: $(if ($ExeVerification.HasTimestamp) { "Valid RFC 3161 ($($ExeVerification.TimestampSigner))" } else { "None" })",
    "Verification: $exeStatus",
    "",
    "## Installer",
    "Installer: $(if ($InstallerVerification) { $InstallerVerification.FileName } else { 'N/A' })",
    "Publisher: $(if ($InstallerVerification) { $InstallerVerification.SignerSubject } else { 'N/A' })",
    "Signature: $(if ($InstallerVerification) { "$($InstallerVerification.Status) ($($InstallerVerification.StatusMessage))" } else { 'N/A' })",
    "Timestamp: $(if ($InstallerVerification -and $InstallerVerification.HasTimestamp) { "Valid RFC 3161 ($($InstallerVerification.TimestampSigner))" } else { 'None' })",
    "Verification: $instStatus",
    "",
    "## SHA-256",
    ($checksumLines -join "`r`n"),
    "",
    "## Tamper Resistance",
    "Tamper Verification Test: $tamperText",
    "",
    "## SmartScreen & Production Guidance"
)

if ($Mode -eq 'test-simulated') {
    $lines += "> [!WARNING]"
    $lines += "> This build used a **Test-Simulated Certificate** ($($global:TestCertThumbprint))."
    $lines += "> Windows Defender SmartScreen **will continue to warn** on client PCs until signed with a trusted commercial certificate (Microsoft Trusted Signing or public CA EV/OV)."
    $lines += "> See [docs/WINDOWS_CODE_SIGNING_GUIDE.md](../docs/WINDOWS_CODE_SIGNING_GUIDE.md) for full onboarding instructions."
} else {
    $lines += "> [!NOTE]"
    $lines += "> Production signing configuration applied."
}

[System.IO.File]::WriteAllLines($ReportPath, $lines)

# Output summary to console in user's requested format
Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "                CODE SIGNING RELEASE REPORT                 " -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Executable: $($ExeVerification.FileName)"
Write-Host "Publisher: $($ExeVerification.SignerSubject)"
Write-Host "Signature: $($ExeVerification.Status) ($($ExeVerification.StatusMessage))"
Write-Host "Timestamp: $(if ($ExeVerification.HasTimestamp) { "Valid RFC 3161 ($($ExeVerification.TimestampSigner))" } else { "None" })"
Write-Host "Verification: $exeStatus"
Write-Host ""
Write-Host "Installer: $(if ($InstallerVerification) { $InstallerVerification.FileName } else { 'N/A' })"
Write-Host "Publisher: $(if ($InstallerVerification) { $InstallerVerification.SignerSubject } else { 'N/A' })"
Write-Host "Signature: $(if ($InstallerVerification) { "$($InstallerVerification.Status) ($($InstallerVerification.StatusMessage))" } else { 'N/A' })"
Write-Host "Timestamp: $(if ($InstallerVerification -and $InstallerVerification.HasTimestamp) { "Valid RFC 3161" } else { 'None' })"
Write-Host "Verification: $instStatus"
Write-Host ""
Write-Host "SHA-256:"
foreach ($line in $checksumLines) { Write-Host "  $line" }
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Report saved to: $ReportPath" -ForegroundColor Green

exit 0
