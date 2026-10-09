import 'package:http/http.dart' as http;

import 'fingerprint.dart';

// ─────────────────────────────────────────────────────────────────────────
// TAGGED COURIER — http.Client that always stamps the forged UA
// ─────────────────────────────────────────────────────────────────────────
// Only used for ancillary Dart-side HTTPS calls (GCD rescue, push image
// prefetch). The verdict POST itself runs inside the Rust `.so` so the
// endpoint URL never materialises in Dart memory.
//
// Every outbound call carries the exact same UA the WebView installs —
// otherwise a reviewer running Charles Proxy sees two different browser
// signatures from the same cold start, which clusters.
// ─────────────────────────────────────────────────────────────────────────

class TaggedCourier extends http.BaseClient {
  TaggedCourier();

  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final String ua = DeviceFingerprint.userAgent;
    if (ua.isNotEmpty) {
      request.headers['User-Agent'] = ua;
    }
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}

/// Shared singleton primed after `DeviceFingerprint.prime()` completes in
/// `main()`.
final TaggedCourier courier = TaggedCourier();
