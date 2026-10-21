param([Parameter(Mandatory)][string]$Repository)
$ErrorActionPreference='Stop'
# Build the locked plugin's SQLite library for Dart unit tests before compiling the application.
# This uses the same SQLite source and compile definitions as the shipped plugin.
$plugin=Join-Path $Repository 'windows\flutter\ephemeral\.plugin_symlinks\sqlite3_flutter_libs\windows'
if (!(Test-Path $plugin)) { throw 'sqlite3_flutter_libs plugin not generated; run flutter pub get first.' }
$cmake=Get-Content (Join-Path $plugin 'CMakeLists.txt') -Raw
$start=$cmake.IndexOf('include(FetchContent)')
$end=$cmake.IndexOf('# Ensure sqlite3 actually gets build')
if ($start -lt 0 -or $end -le $start) { throw 'SQLite plugin build layout changed; review test dependency preparation.' }
$testSource=Join-Path $Repository 'build\test-sqlite-source'
$testBuild=Join-Path $Repository 'build\test-sqlite-build'
New-Item -ItemType Directory -Force $testSource | Out-Null
("cmake_minimum_required(VERSION 3.14)`nproject(trace_test_sqlite LANGUAGES C)`n"+$cmake.Substring($start,$end-$start)) | Set-Content (Join-Path $testSource 'CMakeLists.txt')
Copy-Item (Join-Path $plugin 'sqlite3_flutter.c') $testSource -Force
& cmake -S $testSource -B $testBuild -G 'Visual Studio 17 2022' -A x64
if ($LASTEXITCODE -ne 0) { throw 'SQLite test library configuration failed.' }
& cmake --build $testBuild --config Release
if ($LASTEXITCODE -ne 0) { throw 'SQLite test library compilation failed.' }
$env:PATH=(Join-Path $testBuild 'Release')+';'+$env:PATH
