# Build libcoinburst_gateway.so for Android (ARM64 + ARMv7) on Windows.
# Mirror of tool/build_rust.sh. Produces artefacts under
# android/app/src/main/jniLibs/<abi>/libcoinburst_gateway.so.
#
# Usage:  pwsh tool/build_rust.ps1
#         pwsh tool/build_rust.ps1 -Debug
#
# Expects cargo-ndk and the Android NDK installed. Secrets for the sealed
# blobs (CB_ENDPOINT, CB_UPSTREAM_SECRET, …) must be exported in the shell
# before invocation.

param(
    [switch]$Debug
)

$ErrorActionPreference = "Stop"

$Root     = Split-Path -Parent $PSScriptRoot
$RustDir  = Join-Path $Root "rust"
$JniDir   = Join-Path $Root "android\app\src\main\jniLibs"
$Profile  = if ($Debug) { "dev" } else { "release" }
$SubDir   = if ($Debug) { "debug" } else { "release" }

if (-not $env:ANDROID_NDK_HOME) {
    $Candidates = @(
        "$env:LOCALAPPDATA\Android\Sdk\ndk",
        "$env:USERPROFILE\AppData\Local\Android\Sdk\ndk"
    )
    foreach ($c in $Candidates) {
        if (Test-Path $c) {
            $Latest = (Get-ChildItem $c | Sort-Object Name | Select-Object -Last 1).FullName
            $env:ANDROID_NDK_HOME = $Latest
            break
        }
    }
}
Write-Host "[rust] NDK: $($env:ANDROID_NDK_HOME)"

rustup target add aarch64-linux-android armv7-linux-androideabi | Out-Null

$BuildArgs = @()
if (-not $Debug) { $BuildArgs += "--release" }

New-Item -ItemType Directory -Force -Path $JniDir | Out-Null

Push-Location $RustDir
try {
    Write-Host "[rust] building arm64-v8a + armeabi-v7a (API 24)…"
    cargo ndk `
        -t arm64-v8a `
        -t armeabi-v7a `
        -P 24 `
        -o $JniDir `
        build @BuildArgs
} finally {
    Pop-Location
}

Write-Host "[rust] done:"
Get-ChildItem (Join-Path $JniDir "arm64-v8a\libcoinburst_gateway.so"),
              (Join-Path $JniDir "armeabi-v7a\libcoinburst_gateway.so")
