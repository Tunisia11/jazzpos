param([switch]$VerifyInstall)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = Split-Path $PSScriptRoot -Parent
Set-Location $repo
if ($env:OS -ne 'Windows_NT') { throw 'A Windows build machine is required.' }
if ($env:RUN_LIVE_DB_TESTS -eq 'true') { throw 'Release tests must use disposable fixtures. Unset RUN_LIVE_DB_TESTS.' }
$iscc = 'C:\Program Files (x86)\Inno Setup 6\ISCC.exe'
if (!(Test-Path $iscc)) { throw 'Install Inno Setup 6 before building.' }
$buildStart = [DateTime]::UtcNow
function Flutter-Step([string[]]$FlutterArgs) {
  & flutter @FlutterArgs
  if ($LASTEXITCODE -ne 0) { throw "flutter $FlutterArgs failed ($LASTEXITCODE)" }
}
Flutter-Step @('clean')
Flutter-Step @('pub','get')
. (Join-Path $PSScriptRoot 'prepare_test_sqlite.ps1') -Repository $repo
Flutter-Step @('analyze')
Flutter-Step @('test')
$commit = (& git rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Git revision unavailable.' }
$dirty = [bool](& git status --porcelain)
$flutterVersion = (& flutter --version --machine | ConvertFrom-Json)
if ($LASTEXITCODE -ne 0) { throw 'Flutter version unavailable.' }
Flutter-Step @('build','windows','--release',"--dart-define=TRACE_BUILD_COMMIT=$commit")
$release = Join-Path $repo 'build\windows\x64\runner\Release'
$exe = Join-Path $release 'tracepos.exe'
if (!(Test-Path $exe) -or (Get-Item $exe).LastWriteTimeUtc -lt $buildStart) { throw 'No fresh Windows EXE.' }
$dist = Join-Path $repo 'dist'
New-Item -ItemType Directory -Force $dist | Out-Null
$sourceRoots = @('lib','test','windows\runner','windows\installer','assets')
$sourceFiles = @($sourceRoots | ForEach-Object { Get-ChildItem $_ -File -Recurse } | Where-Object { $_.FullName -notmatch '\\redist\\' })
$sourceFiles += @(Get-Item pubspec.yaml,pubspec.lock,windows\CMakeLists.txt,windows\build_windows_release.ps1,.github\workflows\windows_release.yml)
$sourceManifest = @($sourceFiles | Sort-Object FullName | ForEach-Object {
  @{path=$_.FullName.Substring($repo.Length+1).Replace('\','/'); sha256=(Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
})
$sourceManifest | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $release 'source-manifest.json') -Encoding UTF8
$metadata = @{
  commit=$commit; dirtyWorkingTree=$dirty; buildUtc=$buildStart.ToString('o');
  flutter=$flutterVersion; windowsRunner=$env:COMPUTERNAME; windowsVersion=[Environment]::OSVersion.VersionString;
  exeSHA256=(Get-FileHash $exe -Algorithm SHA256).Hash.ToLowerInvariant();
  sourceManifestSHA256=(Get-FileHash (Join-Path $release 'source-manifest.json') -Algorithm SHA256).Hash.ToLowerInvariant();
  physicalHardwareCertified=$false
}
$metadata | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $release 'build-info.json') -Encoding UTF8
Copy-Item (Join-Path $release 'build-info.json') (Join-Path $dist 'build-info.json') -Force
# Require the official runtime in the offline installer; never silently omit it.
$redistDir = Join-Path $PSScriptRoot 'installer\redist'
New-Item -ItemType Directory -Force $redistDir | Out-Null
$redist = Join-Path $redistDir 'vc_redist.x64.exe'
if (!(Test-Path $redist)) { Invoke-WebRequest 'https://aka.ms/vs/17/release/vc_redist.x64.exe' -OutFile $redist }
$signature = Get-AuthenticodeSignature $redist
if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'Microsoft Corporation') { throw 'Microsoft VC runtime signature is invalid.' }
& $iscc (Join-Path $PSScriptRoot 'installer\tracepos_setup.iss')
if ($LASTEXITCODE -ne 0) { throw 'Inno Setup failed.' }
$installer = Join-Path $dist 'Trace-POS-Setup-x64.exe'
if (!(Test-Path $installer) -or (Get-Item $installer).LastWriteTimeUtc -lt $buildStart) { throw 'No fresh Trace POS installer.' }
$zip = Join-Path $dist 'Trace-POS-Windows-x64.zip'
Compress-Archive -Path "$release\*" -DestinationPath $zip -Force
@($installer,$zip,$exe) | ForEach-Object {
  "{0}  {1}" -f (Get-FileHash $_ -Algorithm SHA256).Hash.ToLowerInvariant(), (Split-Path $_ -Leaf)
} | Set-Content (Join-Path $dist 'SHA256SUMS.txt') -Encoding ascii
if ($VerifyInstall) {
  & (Join-Path $PSScriptRoot 'verify_installer.ps1') -Installer $installer -ReleaseDirectory $release
}
Write-Host 'Fresh artifacts built. Physical printer/scanner/drawer acceptance is still required.'
