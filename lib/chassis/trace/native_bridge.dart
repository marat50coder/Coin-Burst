import 'dart:ffi' as ffi;
import 'dart:io' show Platform;

import 'package:ffi/ffi.dart';

// ─────────────────────────────────────────────────────────────────────────
// NATIVE BRIDGE — dart:ffi wrapper over libcoinburst_gateway.so
// ─────────────────────────────────────────────────────────────────────────
// None of the gray-part string literals live here. The `.so` seals the
// endpoint URL, the HMAC key, the envelope field names, the Chrome
// version suffix, the UA scaffold, and the three JS enhancer bodies.
// This file only names the exported FFI symbols (`nx_*`) and remembers
// to send every returned `*mut c_char` back through `nx_release`.
// ─────────────────────────────────────────────────────────────────────────

typedef _NxCStringNative = ffi.Pointer<Utf8> Function();
typedef _NxCString = ffi.Pointer<Utf8> Function();

typedef _NxDispatchNative = ffi.Pointer<Utf8> Function(
    ffi.Pointer<Utf8>, ffi.Pointer<Utf8>);
typedef _NxDispatch = ffi.Pointer<Utf8> Function(
    ffi.Pointer<Utf8>, ffi.Pointer<Utf8>);

typedef _NxReleaseNative = ffi.Void Function(ffi.Pointer<Utf8>);
typedef _NxRelease = void Function(ffi.Pointer<Utf8>);

typedef _NxArmCheckNative = ffi.Int32 Function();
typedef _NxArmCheck = int Function();

/// Thin wrapper over the `nx_*` symbols. One instance per process —
/// obtain via `NativeBridge.of()` which lazily opens the `.so`.
class NativeBridge {
  NativeBridge._(this._lib)
      : _uaScaffold = _lib.lookupFunction<_NxCStringNative, _NxCString>(
            'nx_ua_scaffold'),
        _overlaySafeArea = _lib.lookupFunction<_NxCStringNative, _NxCString>(
            'nx_overlay_safe_area'),
        _overlayKeyboard = _lib.lookupFunction<_NxCStringNative, _NxCString>(
            'nx_overlay_keyboard'),
        _overlayAutoplay = _lib.lookupFunction<_NxCStringNative, _NxCString>(
            'nx_overlay_autoplay'),
        _dispatch = _lib
            .lookupFunction<_NxDispatchNative, _NxDispatch>('nx_dispatch_envelope'),
        _armCheck = _lib
            .lookupFunction<_NxArmCheckNative, _NxArmCheck>('nx_arm_check'),
        _release = _lib
            .lookupFunction<_NxReleaseNative, _NxRelease>('nx_release');

  // Keep the DynamicLibrary pinned so GC doesn't close the handle while
  // function pointers are still live. Never read after init.
  // ignore: unused_field
  final ffi.DynamicLibrary _lib;
  final _NxCString _uaScaffold;
  final _NxCString _overlaySafeArea;
  final _NxCString _overlayKeyboard;
  final _NxCString _overlayAutoplay;
  final _NxDispatch _dispatch;
  final _NxArmCheck _armCheck;
  final _NxRelease _release;

  static NativeBridge? _singleton;

  static NativeBridge of() {
    _singleton ??= _open();
    return _singleton!;
  }

  static NativeBridge _open() {
    if (Platform.isAndroid) {
      return NativeBridge._(
          ffi.DynamicLibrary.open('libcoinburst_gateway.so'));
    }
    if (Platform.isIOS) {
      return NativeBridge._(ffi.DynamicLibrary.process());
    }
    throw UnsupportedError(
        'coinburst gateway is not shipped for ${Platform.operatingSystem}');
  }

  /// Returns the UA template with `{release}`, `{brand}`, `{model}`,
  /// `{build}`, `{bundle}`, `{name}` placeholders. The caller substitutes
  /// real device_info_plus values.
  String uaScaffold() => _drain(_uaScaffold());

  /// Three JS enhancer bodies. Each is injected on `onPageFinished` in
  /// the portal scene.
  String overlaySafeArea() => _drain(_overlaySafeArea());
  String overlayKeyboard() => _drain(_overlayKeyboard());
  String overlayAutoplay() => _drain(_overlayAutoplay());

  /// End-to-end call. Hands over a clean body JSON + the fully-rendered
  /// User-Agent string; the `.so` HMAC-seals the envelope, POSTs to the
  /// sealed endpoint, and returns the verdict JSON `{"ok", "url",
  /// "status"}`. Any transport failure degrades to `ok:false,url:""`.
  String dispatch(String bodyJson, String userAgent) {
    final body = bodyJson.toNativeUtf8();
    final ua = userAgent.toNativeUtf8();
    try {
      return _drain(_dispatch(body, ua));
    } finally {
      calloc.free(body);
      calloc.free(ua);
    }
  }

  /// Health probe — true iff every sealed blob decrypts to a non-empty
  /// UTF-8 string. The gray branch stays closed if this returns false.
  bool armed() => _armCheck() == 1;

  String _drain(ffi.Pointer<Utf8> ptr) {
    if (ptr == ffi.nullptr) return '';
    try {
      return ptr.toDartString();
    } finally {
      _release(ptr);
    }
  }
}
