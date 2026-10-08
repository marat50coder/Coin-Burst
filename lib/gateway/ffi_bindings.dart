// Dart ↔ Rust bindings for libcoinburst_gateway.so.
//
// None of the gray-part strings live here — the whole point of the Rust
// crate is that the APK contains the endpoint, upstream secret, envelope
// field names, and User-Agent only in sealed form. All we do on the Dart
// side is call the exported `cb_*` functions and remember to free every
// returned C-string pointer through `cb_free_cstring`.

import 'dart:ffi' as ffi;
import 'dart:io' show Platform;

import 'package:ffi/ffi.dart';

typedef _CbCStringReturnNative = ffi.Pointer<Utf8> Function();
typedef _CbCStringReturn = ffi.Pointer<Utf8> Function();

typedef _CbCStringArgReturnNative = ffi.Pointer<Utf8> Function(
    ffi.Pointer<Utf8>);
typedef _CbCStringArgReturn = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8>);

typedef _CbFreeNative = ffi.Void Function(ffi.Pointer<Utf8>);
typedef _CbFree = void Function(ffi.Pointer<Utf8>);

typedef _CbGateReadyNative = ffi.Int32 Function();
typedef _CbGateReady = int Function();

/// Thin, side-effect-free wrapper around the Rust FFI surface. One instance
/// is enough; obtain it via [GatewayBindings.instance].
class GatewayBindings {
  GatewayBindings._(this._lib)
      : _endpoint = _lib
            .lookupFunction<_CbCStringReturnNative, _CbCStringReturn>(
                'cb_endpoint'),
        _userAgent = _lib
            .lookupFunction<_CbCStringReturnNative, _CbCStringReturn>(
                'cb_user_agent'),
        _packEnvelope = _lib.lookupFunction<_CbCStringArgReturnNative,
            _CbCStringArgReturn>('cb_pack_envelope'),
        _syncCall = _lib.lookupFunction<_CbCStringArgReturnNative,
            _CbCStringArgReturn>('cb_sync_call'),
        _gateReady = _lib
            .lookupFunction<_CbGateReadyNative, _CbGateReady>('cb_gate_ready'),
        _free = _lib
            .lookupFunction<_CbFreeNative, _CbFree>('cb_free_cstring');

  static GatewayBindings? _instance;

  /// Loads `libcoinburst_gateway.so` the first time it's accessed. Throws
  /// [UnsupportedError] on platforms where we don't ship a build.
  static GatewayBindings get instance => _instance ??= _open();

  // Held so the DynamicLibrary isn't collected while the function pointers
  // above are still live. The field is intentionally never read after init.
  // ignore: unused_field
  final ffi.DynamicLibrary _lib;
  final _CbCStringReturn _endpoint;
  final _CbCStringReturn _userAgent;
  final _CbCStringArgReturn _packEnvelope;
  final _CbCStringArgReturn _syncCall;
  final _CbGateReady _gateReady;
  final _CbFree _free;

  static GatewayBindings _open() {
    if (Platform.isAndroid) {
      return GatewayBindings._(
          ffi.DynamicLibrary.open('libcoinburst_gateway.so'));
    }
    if (Platform.isIOS) {
      // iOS not shipped yet — gray-part is Android-only for now. Keep the
      // branch here so adding the iOS build later is a one-liner.
      return GatewayBindings._(ffi.DynamicLibrary.process());
    }
    throw UnsupportedError(
        'coinburst_gateway native library is not shipped for ${Platform.operatingSystem}');
  }

  /// Returns `/edge/sync` endpoint used by the Rust side for its HTTPS
  /// POST. Dart only reads it in debug flows; release code should prefer
  /// [syncCall] which never surfaces the URL to Dart memory.
  String endpoint() => _consume(_endpoint());

  /// Returns the Chrome-on-Android User-Agent the WebView should install
  /// before loading the verdict URL.
  String userAgent() => _consume(_userAgent());

  /// Packs a clean body JSON into the on-wire envelope (XOR + HMAC).
  String packEnvelope(String bodyJson) {
    final arg = bodyJson.toNativeUtf8();
    try {
      return _consume(_packEnvelope(arg));
    } finally {
      calloc.free(arg);
    }
  }

  /// End-to-end call: Rust packs the envelope, POSTs to the sealed
  /// endpoint, and returns a verdict JSON `{"ok":bool,"url":string,
  /// "status":int}`. Any transport failure degrades to `{"ok":false,…}`.
  String syncCall(String bodyJson) {
    final arg = bodyJson.toNativeUtf8();
    try {
      return _consume(_syncCall(arg));
    } finally {
      calloc.free(arg);
    }
  }

  /// Returns `true` iff every sealed blob decrypts to a non-empty value.
  bool gateReady() => _gateReady() == 1;

  String _consume(ffi.Pointer<Utf8> ptr) {
    if (ptr == ffi.nullptr) return '';
    try {
      return ptr.toDartString();
    } finally {
      _free(ptr);
    }
  }
}
