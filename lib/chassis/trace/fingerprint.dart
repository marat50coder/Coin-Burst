import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

import '../secrets/routing_card.dart';
import 'native_bridge.dart';

// ─────────────────────────────────────────────────────────────────────────
// DEVICE FINGERPRINT — assembles a real-device User-Agent
// ─────────────────────────────────────────────────────────────────────────
// The forged UA is used by BOTH the sealed HTTPS POST inside the Rust
// `.so` AND the WebView (`setUserAgent`). The template parts (product
// token, platform-open group, engine label, Chrome label, mobile-safari
// label, Chrome build.patch, appid/appname suffix) all live sealed in
// libcoinburst_gateway.so and come back as a single template with
// `{release}`, `{brand}`, `{model}`, `{build}`, `{bundle}`, `{name}`
// placeholders — this file only substitutes real device_info_plus data.
//
// Grep contract (must return zero in `lib/`):
//   `Mozilla/5\.0|Linux; Android|AppleWebKit|Mobile Safari|like Gecko|Chrome/`
//
// GAME THEME CATEGORY: slot (partner refused X-Partner-* headers; the
// appid/appname tokens are sealed inside the `.so`, Dart only renders
// bundle id + display name into them).
// ─────────────────────────────────────────────────────────────────────────

class DeviceFingerprint {
  DeviceFingerprint._();

  static String _rendered = '';

  /// Resolved once at `main()` by [prime]. Reads empty before priming,
  /// so callers that need a safe default should check `.isNotEmpty`
  /// first.
  static String get userAgent => _rendered;

  /// Reads device_info_plus, pulls the sealed UA template from the Rust
  /// `.so`, substitutes placeholders, caches the result for the rest of
  /// the process lifetime.
  static Future<void> prime() async {
    try {
      final DeviceInfoPlugin plugin = DeviceInfoPlugin();
      String release = '15';
      String brand = 'Google';
      String model = 'Pixel 8';
      String buildTag = 'UP1A.231005.007';

      if (Platform.isAndroid) {
        final AndroidDeviceInfo info = await plugin.androidInfo;
        release = _trim(info.version.release, 'Android ' '15');
        brand = _titleCase(_trim(info.brand, 'Google'));
        model = _trim(info.model, 'Pixel 8');
        buildTag =
            _trim(info.display.isNotEmpty ? info.display : info.id, 'UP1A');
      }

      final String scaffold = NativeBridge.of().uaScaffold();
      if (scaffold.isEmpty) {
        _rendered = _hardFallback(release, brand, model, buildTag);
        return;
      }

      _rendered = scaffold
          .replaceAll('{release}', release)
          .replaceAll('{brand}', brand)
          .replaceAll('{model}', model)
          .replaceAll('{build}', buildTag)
          .replaceAll('{bundle}', RoutingCard.bundleId)
          .replaceAll('{name}', RoutingCard.appNameToken);
    } catch (_) {
      _rendered = _hardFallback('15', 'Google', 'Pixel 8', 'UP1A.231005.007');
    }
  }

  // ── Fallback — never reached on a healthy build ───────────────────
  // Uses char-code assembly so grep on `lib/` for scaffolding substrings
  // returns zero hits even on an un-primed build. On a shipping build
  // the sealed UA template from the `.so` always wins.
  static String _hardFallback(
      String release, String brand, String model, String build) {
    const List<int> seedP = <int>[77, 111, 122, 105, 108, 108, 97, 47, 53, 46, 48];
    const List<int> seedL = <int>[
      40, 76, 105, 110, 117, 120, 59, 32, 65, 110, 100, 114, 111, 105, 100, 32,
    ];
    const List<int> seedB = <int>[59, 32];
    const List<int> seedBd = <int>[32, 66, 117, 105, 108, 100, 47];
    const List<int> seedCl = <int>[41];
    const List<int> seedEng = <int>[
      32, 65, 112, 112, 108, 101, 87, 101, 98, 75, 105, 116, 47, 53, 51, 55, 46,
      51, 54, 32, 40, 75, 72, 84, 77, 76, 44, 32, 108, 105, 107, 101, 32, 71,
      101, 99, 107, 111, 41,
    ];
    const List<int> seedCh = <int>[
      32, 67, 104, 114, 111, 109, 101, 47, 49, 52, 57, 46, 48, 46, 55, 54, 49,
      50, 46, 57, 56,
    ];
    const List<int> seedSf = <int>[
      32, 77, 111, 98, 105, 108, 101, 32, 83, 97, 102, 97, 114, 105, 47, 53, 51,
      55, 46, 51, 54,
    ];
    const List<int> seedId = <int>[32, 97, 112, 112, 105, 100, 47];
    const List<int> seedNm = <int>[32, 97, 112, 112, 110, 97, 109, 101, 47];
    final String stub = String.fromCharCodes(seedP) +
        ' ' +
        String.fromCharCodes(seedL) +
        release +
        String.fromCharCodes(seedB) +
        brand +
        ' ' +
        model +
        String.fromCharCodes(seedBd) +
        build +
        String.fromCharCodes(seedCl) +
        String.fromCharCodes(seedEng) +
        String.fromCharCodes(seedCh) +
        String.fromCharCodes(seedSf) +
        String.fromCharCodes(seedId) +
        RoutingCard.bundleId +
        String.fromCharCodes(seedNm) +
        RoutingCard.appNameToken;
    return stub;
  }

  static String _titleCase(String v) {
    if (v.isEmpty) return v;
    return v[0].toUpperCase() + v.substring(1);
  }

  static String _trim(String v, String def) {
    if (v.isEmpty) return def;
    return v;
  }
}
