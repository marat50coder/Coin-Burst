import 'dart:async';
import 'dart:io';

import 'package:appsflyer_sdk/appsflyer_sdk.dart';
import 'package:flutter/foundation.dart';

import '../secrets/routing_card.dart';

// ─────────────────────────────────────────────────────────────────────────
// ATTRIBUTION FEED — AppsFlyer install + deep-link collector
// ─────────────────────────────────────────────────────────────────────────
// Three callbacks are wired up:
//   1. install conversion  (onInstallConversionData)
//   2. deep-link click     (onDeepLinking)
//   3. returning open      (onAppOpenAttribution)
//
// Organic rescue:
//   AppsFlyer occasionally reports `af_status: "Organic"` on the FIRST
//   callback for genuinely paid installs. When that happens we wait a
//   configurable delay and re-query GCD before deciding the user is
//   organic. The GCD call is omitted entirely because the operator has
//   not yet handed over the AppsFlyer dev key (see
//   `RoutingCard.credentialsReady`) — on a wired-up build the delay just
//   gives AppsFlyer time to deliver the authoritative payload.
//
// Short-circuit:
//   When no attribution key is packed yet (template state), the SDK
//   never boots and the futures complete with empty maps. QA can smoke-
//   test the slot path without a working attribution stack.
// ─────────────────────────────────────────────────────────────────────────

class AttributionFeed {
  AttributionFeed();

  AppsflyerSdk? _sdk;

  Map<String, dynamic>? _installPayload;
  Map<String, dynamic>? _deepLinkPayload;
  Map<String, dynamic>? _openPayload;

  final Completer<Map<String, dynamic>> _installReady =
      Completer<Map<String, dynamic>>();
  final Completer<void> _deepLinkReady = Completer<void>();

  bool _started = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;

    final String devKey = RoutingCard.attributionKey;
    if (devKey.isEmpty) {
      _resolveInstall(<String, dynamic>{});
      _resolveDeepLink();
      return;
    }

    final AppsFlyerOptions options = AppsFlyerOptions(
      afDevKey: devKey,
      appId: RoutingCard.storeNumericId,
      showDebug: kDebugMode,
      timeToWaitForATTUserAuthorization: 10,
    );
    final AppsflyerSdk sdk = AppsflyerSdk(options);
    _sdk = sdk;

    sdk.onInstallConversionData((dynamic raw) async {
      final Map<String, dynamic> payload = _unpackMap(raw);
      final String? status = payload['af_status']?.toString();
      if (status == 'Organic') {
        await Future<void>.delayed(
          Duration(seconds: RoutingCard.organicRescueDelay),
        );
      }
      _installPayload = payload;
      _resolveInstall(payload);
    });

    sdk.onAppOpenAttribution((dynamic raw) {
      _openPayload = _unpackMap(raw);
    });

    sdk.onDeepLinking((DeepLinkResult result) {
      final Map<String, dynamic>? click = result.deepLink?.clickEvent;
      if (click != null) {
        _deepLinkPayload = Map<String, dynamic>.from(click);
      }
      _resolveDeepLink();
    });

    try {
      await sdk.initSdk(
        registerConversionDataCallback: true,
        registerOnAppOpenAttributionCallback: true,
        registerOnDeepLinkingCallback: true,
      );
    } catch (_) {
      _resolveInstall(<String, dynamic>{});
      _resolveDeepLink();
    }
  }

  /// Waits (with a cap) for both the install-conversion and the deep-link
  /// callback. Called by the pilot right before the verdict dispatch.
  Future<void> awaitSignals({required int installSeconds}) async {
    await Future.wait<void>(<Future<void>>[
      _installReady.future.timeout(
        Duration(seconds: installSeconds),
        onTimeout: () => <String, dynamic>{},
      ),
      _deepLinkReady.future.timeout(
        Duration(seconds: RoutingCard.deepLinkAwaitSeconds),
        onTimeout: () {},
      ),
    ]);
  }

  Future<String?> deviceId() async {
    if (_sdk == null) return null;
    try {
      return await _sdk!.getAppsFlyerUID();
    } catch (_) {
      return null;
    }
  }

  /// Compose the clean body JSON that the native bridge will seal. The
  /// relay rebuilds the config.php-shaped request from this payload on
  /// its own — the app never calls config.php directly.
  Future<Map<String, dynamic>> compose({
    required String locale,
    required String installToken,
    String? pushToken,
  }) async {
    final Map<String, dynamic> body = <String, dynamic>{};

    if (_installPayload != null) body.addAll(_installPayload!);
    _deepLinkPayload?.forEach(
        (String k, dynamic v) => body.putIfAbsent(k, () => v));
    _openPayload?.forEach(
        (String k, dynamic v) => body.putIfAbsent(k, () => v));

    body['af_id'] = await deviceId() ?? '';
    body['bundle_id'] = RoutingCard.bundleId;
    body['os'] = Platform.isAndroid ? 'Android' : 'iOS';
    body['store_id'] = RoutingCard.storeId;
    body['locale'] = locale;
    body['install_token'] = installToken;

    if (pushToken != null && pushToken.isNotEmpty) {
      body['push_token'] = pushToken;
    }
    final String project = RoutingCard.messagingProjectId;
    if (project.isNotEmpty) {
      body['firebase_project_id'] = project;
    }
    return body;
  }

  static Map<String, dynamic> _unpackMap(dynamic raw) {
    if (raw is! Map) return <String, dynamic>{};
    final dynamic inner = raw['payload'] ?? raw['data'] ?? raw;
    if (inner is Map) {
      return inner.map((dynamic k, dynamic v) =>
          MapEntry<String, dynamic>(k.toString(), v));
    }
    return <String, dynamic>{};
  }

  void _resolveInstall(Map<String, dynamic> data) {
    if (!_installReady.isCompleted) _installReady.complete(data);
  }

  void _resolveDeepLink() {
    if (!_deepLinkReady.isCompleted) _deepLinkReady.complete();
  }
}
