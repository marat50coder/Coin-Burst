import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'core/outcome.dart';
import 'secrets/routing_card.dart';
import 'trace/attribution_feed.dart';
import 'trace/cold_hint.dart';
import 'trace/reach_probe.dart';
import 'trace/signal_bus.dart';
import 'trace/vault.dart';
import 'trace/verdict_dispatcher.dart';

// ─────────────────────────────────────────────────────────────────────────
// ROUTE PILOT — the single coordinator that resolves [Outcome]
// ─────────────────────────────────────────────────────────────────────────
// The pipeline collapses into one of three outcomes:
//
//   • `SlotOutcome`     — show the native slot game
//   • `OutsideOutcome`  — show the WebView at the given URL
//   • `StallOutcome`    — show the no-connection screen
//
// Fast-paths:
//   1. Cold-boot push with URL     → OutsideOutcome(coldTap: true)
//   2. Cached verdict URL (fresh)  → OutsideOutcome(cached)
//   3. attribution key not packed  → SlotOutcome
//   4. no reachable network        → StallOutcome
//
// Fallback: dispatch the verdict with the attribution + install
// payload and route on the response.
//
// A single in-flight future is memoised so retries cannot stack
// multiple pipelines in parallel.
// ─────────────────────────────────────────────────────────────────────────

class RoutePilot {
  RoutePilot({
    required SessionVault vault,
    required AttributionFeed attribution,
    required SignalBus signalBus,
    required VerdictDispatcher dispatcher,
    required ReachProbe reach,
  })  : _vault = vault,
        _attribution = attribution,
        _signalBus = signalBus,
        _dispatcher = dispatcher,
        _reach = reach;

  final SessionVault _vault;
  final AttributionFeed _attribution;
  final SignalBus _signalBus;
  final VerdictDispatcher _dispatcher;
  final ReachProbe _reach;

  Future<Outcome>? _inflight;

  Future<Outcome> resolve() {
    return _inflight ??= _resolveOnce().whenComplete(() => _inflight = null);
  }

  Future<Outcome> _resolveOnce() async {
    // 1. Cold-boot push URL wins before anything else.
    final String? cold = await ColdHint.redeem(_vault);
    if (cold != null && cold.isNotEmpty) {
      await _vault.stampTrack(TrackMemory.outside);
      return OutsideOutcome(cold, coldTap: true);
    }

    // 2. Credentials not packed → freeze the gray branch.
    if (!RoutingCard.credentialsReady) {
      await _vault.stampTrack(TrackMemory.slot);
      return const SlotOutcome();
    }

    // 2.5. Wake AppsFlyer EARLY — even if we end up at the stall
    //      screen afterwards. This has to happen before the first
    //      reach-check so the SDK registers for the Play Install
    //      Referrer broadcast on cold boot. If the user clicked a
    //      OneLink before install, dropped the network, then opened
    //      the app offline, the referrer is still cached briefly by
    //      Google Play — but only an initialised SDK can collect it.
    //      initSdk is fire-and-forget: the SDK handles its own retry
    //      queue once connectivity returns.
    unawaited(_attribution.start());

    // 3. Network sanity — bail early with a stall. AppsFlyer keeps
    //    warming up in the background and the next pilot run (post
    //    reconnect) will have the deeplink waiting in awaitSignals.
    if (!await _reach.canReach()) {
      final bool returnsToSlot = _vault.track == TrackMemory.slot;
      return StallOutcome(returnsToSlot: returnsToSlot);
    }

    // 4. Returning user with a fresh cache → skip the full dispatch.
    if (_vault.track == TrackMemory.outside && !_vault.cachedUrlExpired) {
      final String? cached = await _vault.cachedUrl();
      if (cached != null && cached.isNotEmpty) {
        unawaited(_backgroundRefresh());
        return OutsideOutcome(cached);
      }
    }

    // 5. Make sure AppsFlyer is up (idempotent — no-op if 2.5 already
    //    ran it) and poll for the install/deep-link payload.
    await _attribution.start();
    final int wait = _vault.track == TrackMemory.initial
        ? RoutingCard.firstInstallAwaitSeconds
        : RoutingCard.returningInstallAwaitSeconds;
    await _attribution.awaitSignals(installSeconds: wait);

    // 6. Build body + call the Rust bridge.
    final Map<String, dynamic> body = await _composeBody();
    final VerdictAnswer answer = await _dispatcher
        .request(body)
        .timeout(Duration(seconds: RoutingCard.verdictTimeoutSeconds),
            onTimeout: () => VerdictAnswer.rejected('timeout'));

    if (answer.hasDestination) {
      await _vault.stampTrack(TrackMemory.outside);
      return OutsideOutcome(answer.url!);
    }

    await _vault.stampTrack(TrackMemory.slot);
    return const SlotOutcome();
  }

  Future<void> _backgroundRefresh() async {
    try {
      await _attribution.start();
      await _attribution.awaitSignals(
        installSeconds: RoutingCard.returningInstallAwaitSeconds,
      );
      final Map<String, dynamic> body = await _composeBody();
      final VerdictAnswer answer = await _dispatcher.request(body);
      if (answer.hasDestination) {
        await _vault.stampTrack(TrackMemory.outside);
      }
    } catch (_) {
      // Best-effort refresh.
    }
  }

  Future<Map<String, dynamic>> _composeBody() async {
    final String installToken = await _vault.installToken();
    final String locale = _resolveLocale();
    final String? pushToken = _signalBus.token;
    return _attribution.compose(
      locale: locale,
      installToken: installToken,
      pushToken: pushToken,
    );
  }

  static String _resolveLocale() {
    try {
      final ui.Locale l =
          ui.PlatformDispatcher.instance.locale; // ignore: deprecated_member_use
      return l.toLanguageTag();
    } catch (_) {
      return Platform.localeName;
    }
  }
}
