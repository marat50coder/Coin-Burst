import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'chassis/pilot.dart';
import 'chassis/trace/attribution_feed.dart';
import 'chassis/trace/fingerprint.dart';
import 'chassis/trace/reach_probe.dart';
import 'chassis/trace/signal_bus.dart';
import 'chassis/trace/vault.dart';
import 'chassis/trace/verdict_dispatcher.dart';
import 'warmup/warmup_screen.dart';

// ─────────────────────────────────────────────────────────────────────────
// APP ENTRY POINT
// ─────────────────────────────────────────────────────────────────────────
// Order of operations matters:
//   1. ensureInitialized BEFORE any plugin / platform channel call
//   2. SystemChrome once at startup (immersive-sticky lives on the slot
//      side; portrait/landscape handled per screen)
//   3. Firebase first — SignalBus relies on it being up
//   4. SessionVault.warmUp loads SharedPreferences before pilot runs
//   5. DeviceFingerprint.prime pulls model/release/build and substitutes
//      them into the sealed UA scaffold
//   6. WarmupScreen owns the splash and routes to one of three outcomes
// ─────────────────────────────────────────────────────────────────────────

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Immersive by default — individual screens override as needed.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  } catch (_) {
    // google-services.json not provisioned yet — SignalBus will no-op.
  }

  await DeviceFingerprint.prime();

  final SessionVault vault = SessionVault();
  await vault.warmUp();

  final SignalBus signalBus = SignalBus(vault);
  await signalBus.wireUp();

  final AttributionFeed attribution = AttributionFeed();
  final VerdictDispatcher dispatcher = VerdictDispatcher(vault);
  final ReachProbe reach = ReachProbe();

  final RoutePilot pilot = RoutePilot(
    vault: vault,
    attribution: attribution,
    signalBus: signalBus,
    dispatcher: dispatcher,
    reach: reach,
  );

  signalBus.onTokenRotated = (_) {
    // Fire-and-forget — pilot will pick the new token up on the next
    // boot via `SignalBus.token`.
  };

  runApp(CoinBurstApp(
    pilot: pilot,
    vault: vault,
    signalBus: signalBus,
  ));
}

class CoinBurstApp extends StatelessWidget {
  const CoinBurstApp({
    super.key,
    required this.pilot,
    required this.vault,
    required this.signalBus,
  });

  final RoutePilot pilot;
  final SessionVault vault;
  final SignalBus signalBus;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Coin Burst',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0E27),
        fontFamily: 'Roboto',
        useMaterial3: true,
      ),
      home: WarmupScreen(
        pilot: pilot,
        vault: vault,
        signalBus: signalBus,
      ),
    );
  }
}
