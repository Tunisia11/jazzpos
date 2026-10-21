param([Parameter(Mandatory)][string]$Installer,[Parameter(Mandatory)][string]$ReleaseDirectory)
$ErrorActionPreference='Stop'
# Run only on a disposable Windows runner; never use this smoke test on a client database.
if ($env:CI -ne 'true' -and $env:TRACE_DISPOSABLE_WINDOWS -ne 'true') { throw 'Installer verification requires CI or TRACE_DISPOSABLE_WINDOWS=true on a disposable machine.' }
$installRoot=Join-Path $env:TEMP ('TracePOS-verification-'+[guid]::NewGuid().ToString('N'))
$setup=Start-Process -FilePath $Installer -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/CURRENTUSER',"/DIR=`"$installRoot`"",'/TASKS=') -Wait -PassThru
if ($setup.ExitCode -ne 0) { throw "Installer failed: $($setup.ExitCode)" }
$verified=0
Get-ChildItem $ReleaseDirectory -File -Recurse | ForEach-Object {
  $relative=$_.FullName.Substring($ReleaseDirectory.Length).TrimStart('\')
  $installed=Join-Path $installRoot $relative
  if (!(Test-Path $installed)) { throw "Installer omitted $relative" }
  if ((Get-FileHash $_.FullName).Hash -ne (Get-FileHash $installed).Hash) { throw "Installed content mismatch: $relative" }
  $verified++
}
$info=Get-Content (Join-Path $installRoot 'build-info.json') -Raw | ConvertFrom-Json
$app=Start-Process (Join-Path $installRoot 'jazzpos.exe') -PassThru
try {
  Start-Sleep -Seconds 12
  if ($app.HasExited) { throw 'Installed application exited during startup.' }
  $second=Start-Process (Join-Path $installRoot 'jazzpos.exe') -PassThru
  if (!$second.WaitForExit(15000)) { Stop-Process -Id $second.Id; throw 'Second instance did not exit.' }
  $app.Refresh()
  if ($app.HasExited) { throw 'Second launch killed first instance.' }
  $evidence=@{installedPath=$installRoot;verifiedFiles=$verified;commit=$info.commit;firstLaunchAlive=$true;secondLaunchExited=$true;physicalHardwareCertified=$false;verifiedUtc=[DateTime]::UtcNow.ToString('o')}
  $dist=Split-Path $Installer -Parent
  $evidence | ConvertTo-Json | Set-Content (Join-Path $dist 'installer-verification.json') -Encoding UTF8
} finally {
  if (!$app.HasExited) { $null=$app.CloseMainWindow(); if (!$app.WaitForExit(5000)) { Stop-Process -Id $app.Id } }
}
