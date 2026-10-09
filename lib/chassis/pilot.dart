import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

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
// Fast-paths (checked in order):
//   1. Cold-boot push with URL     → OutsideOutcome(coldTap: true)
//   2. attribution key not packed  → SlotOutcome
//   3. no reachable network        → StallOutcome
//
// Normal path:
//   • Wake AppsFlyer early (before the reach-check), poll for signals,
//     dispatch the verdict synchronously on EVERY launch — never
//     return a stale cached URL while the operator has already rotated
//     the config. That stale-cache fast-path was the #1 complaint on
//     sibling projects: admin flips the URL in the dashboard, the user
//     relaunches, and still lands on the old destination because the
//     client short-circuited to its own cache before asking the server.
//
// Cache is now a FALLBACK only:
//   • Verdict transport failure (timeout / malformed / disarmed) and a
//     fresh cached URL exists → OutsideOutcome(cached). Protects users
//     from a temporary backend outage.
//   • Verdict returns ok=false (admin takedown) → cache is NOT reused;
//     we honour the server and route to the slot game.
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

    // 4. Make sure AppsFlyer is up (idempotent — no-op if 2.5 already
    //    ran it) and poll for the install/deep-link payload.
    //    The wait budget is longer on the very first run (so the Play
    //    Install Referrer has time to resolve into attribution data)
    //    and tight on returning runs so a re-launch feels snappy.
    await _attribution.start();
    final int wait = _vault.track == TrackMemory.initial
        ? RoutingCard.firstInstallAwaitSeconds
        : RoutingCard.returningInstallAwaitSeconds;
    await _attribution.awaitSignals(installSeconds: wait);

    // 5. Build body + call the Rust bridge. Even on an organic install
    //    (no OneLink click, af_status=Organic, empty clickEvent) the
    //    body is dispatched intact so the operator can serve a URL
    //    for organic installs via config — no client-side bypass.
    final Map<String, dynamic> body = await _composeBody();
    assert(() {
      final String? status = body['af_status']?.toString();
      debugPrint('[kqz.pilot] dispatching verdict '
          'track=${_vault.track.wireValue} af_status=$status '
          'body_keys=${body.keys.toList()}');
      return true;
    }());

    final VerdictAnswer answer = await _dispatcher
        .request(body)
        .timeout(Duration(seconds: RoutingCard.verdictTimeoutSeconds),
            onTimeout: () => VerdictAnswer.rejected('timeout'));

    if (answer.hasDestination) {
      // Dispatcher has already written the fresh URL into the vault
      // cache; stamp the track so returning cold-boot heuristics are
      // consistent.
      await _vault.stampTrack(TrackMemory.outside);
      assert(() {
        debugPrint('[kqz.pilot] fresh verdict url -> ${answer.url}');
        return true;
      }());
      return OutsideOutcome(answer.url!);
    }

    // Verdict path 1: TRANSPORT FAILURE (timeout / malformed / disarmed
    // bridge). Fall back to a fresh cached URL if we have one — a
    // transient backend blip must not demote a working user to the
    // slot game. `failureNote != null` is set by the dispatcher only
    // on transport errors, never on an authoritative server "deny".
    final bool transportFailed = answer.failureNote != null;
    if (transportFailed &&
        _vault.track == TrackMemory.outside &&
        !_vault.cachedUrlExpired) {
      final String? cached = await _vault.cachedUrl();
      if (cached != null && cached.isNotEmpty) {
        assert(() {
          debugPrint('[kqz.pilot] verdict ${answer.failureNote}; '
              'serving cached url');
          return true;
        }());
        return OutsideOutcome(cached);
      }
    }

    // Verdict path 2: AUTHORITATIVE DENY (ok=false, no transport
    // error). Operator pulled the gray branch — honour it, clear the
    // outside track memory so cached URLs cannot resurrect it on a
    // later transport error.
    await _vault.stampTrack(TrackMemory.slot);
    return const SlotOutcome();
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
