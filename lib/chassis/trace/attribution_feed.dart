import 'dart:async';
import 'dart:io';

import 'package:appsflyer_sdk/appsflyer_sdk.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../secrets/routing_card.dart';
import 'reach_probe.dart';

// ─────────────────────────────────────────────────────────────────────────
// ATTRIBUTION FEED — AppsFlyer install + deep-link collector
// ─────────────────────────────────────────────────────────────────────────
// Three callbacks are wired up:
//   1. install conversion  (onInstallConversionData)
//   2. deep-link click     (onDeepLinking)
//   3. returning open      (onAppOpenAttribution)
//
// Offline-first boot behaviour (the whole reason this file is not a
// twenty-line passthrough):
//
//   * `start()` registers all callbacks synchronously, then kicks off
//     `initSdk()` in a detached Future — so a user that opened the app
//     *offline* after clicking a OneLink still gets the SDK alive in
//     time to collect the Play Install Referrer. Google Play only
//     delivers the referrer broadcast once; miss it and the deeplink
//     is gone for the lifetime of this install.
//
//   * `awaitSignals()` is poll-based, not completer-based. The pilot
//     may re-run after an offline-to-online transition — a completer
//     that was already fulfilled with an empty payload would return
//     stale emptiness instantly on the second attempt, so we poll
//     `_installPayload` instead and let a late-arriving callback win.
//
//   * `start()` is idempotent and re-queues `initSdk()` on each call
//     until it completes successfully, in case the first attempt
//     threw because the native side needed the network.
//
// Organic rescue:
//   AppsFlyer occasionally reports `af_status: "Organic"` on the FIRST
//   callback for genuinely paid installs. When that happens we wait a
//   configurable delay and let the SDK re-fire with authoritative data.
//
// Short-circuit:
//   When no attribution key is packed (template state), the SDK never
//   boots and the futures resolve immediately with empty payloads.
// ─────────────────────────────────────────────────────────────────────────

class AttributionFeed {
  AttributionFeed();

  AppsflyerSdk? _sdk;

  Map<String, dynamic>? _installPayload;
  Map<String, dynamic>? _deepLinkPayload;
  Map<String, dynamic>? _openPayload;

  bool _started = false;
  bool _callbacksBound = false;
  bool _initOk = false;
  bool _initInFlight = false;

  StreamSubscription<List<ConnectivityResult>>? _netSub;

  Future<void> start() async {
    final String devKey = RoutingCard.attributionKey;
    if (devKey.isEmpty) {
      // Template state — mark the signals as "already here" with empty
      // payloads so the pilot doesn't block.
      _installPayload ??= const <String, dynamic>{};
      _deepLinkPayload ??= const <String, dynamic>{};
      _started = true;
      return;
    }

    if (!_started) {
      _started = true;
      _bindSdk(devKey);
    }

    // Each call to `start()` nudges initSdk if it still has not
    // completed successfully — pilot re-runs after reconnect and this
    // is where the SDK finally gets to talk to the network.
    if (!_initOk && !_initInFlight) {
      unawaited(_kickInit());
    }
  }

  void _bindSdk(String devKey) {
    if (_callbacksBound) return;

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
      assert(() {
        debugPrint(
            '[kqz.attr] conversion data arrived: ${payload.keys.toList()}');
        return true;
      }());
    });

    sdk.onAppOpenAttribution((dynamic raw) {
      _openPayload = _unpackMap(raw);
    });

    sdk.onDeepLinking((DeepLinkResult result) {
      final Map<String, dynamic>? click = result.deepLink?.clickEvent;
      if (click != null) {
        _deepLinkPayload = Map<String, dynamic>.from(click);
      } else {
        _deepLinkPayload ??= const <String, dynamic>{};
      }
      assert(() {
        debugPrint('[kqz.attr] deeplink arrived: '
            'status=${result.status} payload=${_deepLinkPayload?.keys.toList()}');
        return true;
      }());
    });

    _callbacksBound = true;

    // Re-poke initSdk whenever an adapter flips to "connected" — if
    // the very first attempt happened offline the SDK may need an
    // explicit nudge once DNS egress is back.
    _netSub ??=
        ReachProbe().statusStream.listen((List<ConnectivityResult> states) {
      final bool anyAdapter = states.any(
        (ConnectivityResult s) => s != ConnectivityResult.none,
      );
      if (anyAdapter && !_initOk && !_initInFlight) {
        unawaited(_kickInit());
      }
    });
  }

  Future<void> _kickInit() async {
    if (_sdk == null || _initOk || _initInFlight) return;
    _initInFlight = true;
    try {
      await _sdk!.initSdk(
        registerConversionDataCallback: true,
        registerOnAppOpenAttributionCallback: true,
        registerOnDeepLinkingCallback: true,
      );
      _initOk = true;
      assert(() {
        debugPrint('[kqz.attr] initSdk succeeded');
        return true;
      }());
    } catch (e, st) {
      assert(() {
        debugPrint('[kqz.attr] initSdk threw (will retry on next '
            'connectivity flip): $e\n$st');
        return true;
      }());
    } finally {
      _initInFlight = false;
    }
  }

  /// Polls `_installPayload` and `_deepLinkPayload` until both are
  /// populated or until the per-signal budget runs out. Called by the
  /// pilot right before the verdict dispatch.
  Future<void> awaitSignals({required int installSeconds}) async {
    if (!_started) return;
    await Future.wait<void>(<Future<void>>[
      _pollFor(
        () => _installPayload,
        timeout: Duration(seconds: installSeconds),
      ),
      _pollFor(
        () => _deepLinkPayload,
        timeout: Duration(seconds: RoutingCard.deepLinkAwaitSeconds),
      ),
    ]);
  }

  Future<void> _pollFor(
    Map<String, dynamic>? Function() read, {
    required Duration timeout,
  }) async {
    final DateTime deadline = DateTime.now().add(timeout);
    while (read() == null && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 180));
    }
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

  void dispose() {
    _netSub?.cancel();
    _netSub = null;
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
}
