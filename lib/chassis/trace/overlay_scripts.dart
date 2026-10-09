import 'package:webview_flutter/webview_flutter.dart';

import 'native_bridge.dart';

// ─────────────────────────────────────────────────────────────────────────
// OVERLAY SCRIPTS — assembled JS enhancer bundle
// ─────────────────────────────────────────────────────────────────────────
// All three bodies ship sealed inside libcoinburst_gateway.so (see
// src/sealed.rs → js_safe_area / js_keyboard / js_autoplay). The Dart
// side only knows how to pull them and inject them in order on every
// `onPageFinished`.
//
// Hard rules in `.cursor/rules/webview_safe_area_injection.mdc`:
//   • never touch html / body / #app / #root
//   • CSS-variable overrides are safe (only hit sites that declare them)
//   • only touch padding-top / margin-top on known decorative headers
// All three bodies obey these rules — see rust/gateway.local for the
// pre-sealed source.
// ─────────────────────────────────────────────────────────────────────────

class OverlayScripts {
  OverlayScripts._();

  static Future<void> installAll(WebViewController controller) async {
    final NativeBridge bridge = NativeBridge.of();
    final List<String> bodies = <String>[
      bridge.overlaySafeArea(),
      bridge.overlayKeyboard(),
      bridge.overlayAutoplay(),
    ];
    for (final String body in bodies) {
      if (body.isEmpty) continue;
      try {
        await controller.runJavaScript(body);
      } catch (_) {
        // Partner site aborts the eval — move on to the next enhancer.
      }
    }
  }
}
