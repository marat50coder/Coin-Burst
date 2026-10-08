#!/usr/bin/env bash
# Build libcoinburst_gateway.so for Android (ARM64 + ARMv7) and drop the
# artefacts under android/app/src/main/jniLibs/<abi>/.  The .so files MUST
# be committed to the repo so the APK bundles them without a Gradle step.
#
# Usage:  tool/build_rust.sh           # release build (default)
#         tool/build_rust.sh --debug   # debug build (symbols, no LTO)
#
# Env (optional):
#   ANDROID_NDK_HOME   Path to the NDK to use (defaults to the newest one
#                      installed under ~/Library/Android/sdk/ndk/).
#   CB_ENDPOINT, CB_UPSTREAM_SECRET, CB_SCHEMA_REV, CB_WEBVIEW_UA, …
#                      Secrets injected at compile time by build.rs. The
#                      script picks them up from the shell env — do NOT
#                      hardcode them here.

set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
RUST_DIR="$ROOT/rust"
JNI_DIR="$ROOT/android/app/src/main/jniLibs"

PROFILE="release"
if [[ "${1:-}" == "--debug" ]]; then
  PROFILE="dev"
fi

# ── pick NDK ────────────────────────────────────────────────────────────
if [[ -z "${ANDROID_NDK_HOME:-}" ]]; then
  NDK_PARENT="$HOME/Library/Android/sdk/ndk"
  if [[ ! -d "$NDK_PARENT" ]]; then
    NDK_PARENT="$HOME/Android/Sdk/ndk"
  fi
  ANDROID_NDK_HOME="$(ls -1d "$NDK_PARENT"/* | sort -V | tail -n1)"
fi
echo "[rust] NDK: $ANDROID_NDK_HOME"
export ANDROID_NDK_HOME

# ── rust targets ────────────────────────────────────────────────────────
rustup target add aarch64-linux-android armv7-linux-androideabi >/dev/null

BUILD_ARGS=()
if [[ "$PROFILE" == "release" ]]; then
  BUILD_ARGS+=(--release)
fi

mkdir -p "$JNI_DIR"

# ── build (cargo-ndk 4.x drops .so straight into -o/<abi>/) ─────────────
pushd "$RUST_DIR" >/dev/null
echo "[rust] building arm64-v8a + armeabi-v7a (API 24)…"
cargo ndk \
  -t arm64-v8a \
  -t armeabi-v7a \
  -P 24 \
  -o "$JNI_DIR" \
  build "${BUILD_ARGS[@]}"
popd >/dev/null

echo "[rust] done:"
ls -lh "$JNI_DIR/arm64-v8a/libcoinburst_gateway.so" \
       "$JNI_DIR/armeabi-v7a/libcoinburst_gateway.so"
