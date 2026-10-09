import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../chassis/core/outcome.dart';
import '../chassis/pilot.dart';
import '../chassis/scenes/invite_scene.dart';
import '../chassis/scenes/offline_scene.dart';
import '../chassis/scenes/portal_scene.dart';
import '../chassis/trace/signal_bus.dart';
import '../chassis/trace/vault.dart';
import '../screens/home_screen.dart';

// ─────────────────────────────────────────────────────────────────────────
// WARMUP SCREEN — single loading entry point, destructures Outcome
// ─────────────────────────────────────────────────────────────────────────
// Rendering rules:
//   • Portrait + Landscape backdrops are swapped on orientation change
//   • No bare `Image.asset` on the first frame — pre-decode so there is
//     no flash of white between the Android system splash and the UI
//   • A minimum visible duration prevents the warmup screen from
//     appearing as a one-frame flash when the verdict comes back fast
//
// Routing rules:
//   • Only this screen calls `Navigator.pushReplacement` with routing
//     targets. All downstream screens hand back to this screen for
//     retries.
// ─────────────────────────────────────────────────────────────────────────

const Duration _minVisible = Duration(milliseconds: 1600);

class WarmupScreen extends StatefulWidget {
  const WarmupScreen({
    super.key,
    required this.pilot,
    required this.vault,
    required this.signalBus,
  });

  final RoutePilot pilot;
  final SessionVault vault;
  final SignalBus signalBus;

  @override
  State<WarmupScreen> createState() => _WarmupScreenState();
}

class _WarmupScreenState extends State<WarmupScreen> {
  bool _routed = false;

  @override
  void initState() {
    super.initState();
    _enterFullscreen();
    _warm();
  }

  void _enterFullscreen() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: const <SystemUiOverlay>[SystemUiOverlay.bottom],
    );
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ));
  }

  Future<void> _warm() async {
    final Stopwatch sw = Stopwatch()..start();
    final Outcome outcome = await widget.pilot.resolve();
    final int elapsed = sw.elapsedMilliseconds;
    final int pad = _minVisible.inMilliseconds - elapsed;
    if (pad > 0) {
      await Future<void>.delayed(Duration(milliseconds: pad));
    }
    if (!mounted || _routed) return;
    _routed = true;
    _route(outcome);
  }

  void _route(Outcome outcome) {
    switch (outcome) {
      case SlotOutcome():
        // Native slot — restore both orientations and immersive sticky.
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
          DeviceOrientation.portraitUp,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
        );
        return;
      case OutsideOutcome(url: final String url):
        if (widget.vault.shouldShowInvite && !outcome.coldTap) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => InviteScene(
                vault: widget.vault,
                signalBus: widget.signalBus,
                landingUrl: url,
              ),
            ),
          );
        } else {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => PortalScene(
                url: url,
                vault: widget.vault,
                signalBus: widget.signalBus,
              ),
            ),
          );
        }
        return;
      case StallOutcome(returnsToSlot: final bool toSlot):
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => OfflineScene(
              onRetryBuild: (_) => WarmupScreen(
                pilot: widget.pilot,
                vault: widget.vault,
                signalBus: widget.signalBus,
              ),
            ),
          ),
        );
        // `toSlot` is informational only — Retry always re-runs the
        // pilot, which may route differently now that network is up.
        if (toSlot) {
          assert(() {
            debugPrint('[kqz.pilot] stall after cached slot route');
            return true;
          }());
        }
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final Orientation orient = MediaQuery.of(context).orientation;
    final bool landscape = orient == Orientation.landscape;
    final String bg = landscape
        ? 'assets/Coin_Burst_additional_assets/Horizontal_Loading_Screen.webp'
        : 'assets/Coin_Burst_additional_assets/Vertical_Loading_Screen.webp';
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Image.asset(bg, fit: BoxFit.cover, gaplessPlayback: true),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 56,
            child: Center(
              child: SizedBox(
                width: 42,
                height: 42,
                child: CircularProgressIndicator(
                  strokeWidth: 3.2,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(Color(0xFFFFE07A)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
