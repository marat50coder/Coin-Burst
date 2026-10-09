import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/outcome.dart';
import 'fingerprint.dart';
import 'native_bridge.dart';
import 'vault.dart';

// ─────────────────────────────────────────────────────────────────────────
// VERDICT DISPATCHER — hands the clean body JSON to the Rust `.so`
// ─────────────────────────────────────────────────────────────────────────
// This file deliberately knows nothing about the endpoint URL, the
// envelope field names, or the HMAC key. It serialises the body JSON,
// resolves the User-Agent string, hands both to the sealed native
// bridge, and parses the verdict JSON that comes back.
//
// A successful verdict with a URL also writes to the vault cache so a
// returning cold start can skip the network call entirely.
// ─────────────────────────────────────────────────────────────────────────

class VerdictDispatcher {
  VerdictDispatcher(this._vault);

  final SessionVault _vault;

  Future<VerdictAnswer> request(Map<String, dynamic> body) async {
    final NativeBridge bridge = NativeBridge.of();
    if (!bridge.armed()) {
      return VerdictAnswer.rejected('bridge_disarmed');
    }

    final String ua = DeviceFingerprint.userAgent;
    try {
      final String raw = bridge.dispatch(jsonEncode(body), ua);
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return VerdictAnswer.rejected('malformed');
      }
      final Map<String, dynamic> map = Map<String, dynamic>.from(decoded);
      final bool ok = map['ok'] == true;
      final String? url =
          map['url'] is String ? map['url'] as String : null;
      final int status = (map['status'] as num?)?.toInt() ?? 0;

      final VerdictAnswer answer = VerdictAnswer(
        granted: ok,
        url: url,
        statusCode: status,
      );

      if (answer.hasDestination) {
        // No explicit expiry on the wire today — RoutingCard supplies
        // the default lifetime window.
        await _vault.cacheUrl(answer.url!, null);
      }

      assert(() {
        // ignore: avoid_print
        debugPrint('[kqz.pilot] verdict ok=$ok status=$status');
        return true;
      }());

      return answer;
    } catch (e) {
      return VerdictAnswer.rejected('transport:$e');
    }
  }
}
