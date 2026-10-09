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
//   • Portrait + Landscape backdrops are swapped on orientation change.
//   • A horizontal progress bar sweeps L→R.  It is deliberately capped
//     at ~88 % until the pilot resolves — the final sprint to 100 %
//     only runs in the ~280 ms immediately before the route switch so
//     the fill mirrors the actual readiness of the next screen.
//   • The "Loading…" caption animates its own trailing dots (1→2→3).
// ─────────────────────────────────────────────────────────────────────────

const Duration _minVisible = Duration(milliseconds: 1800);
// How long the final 88 → 100 % sweep lasts just before pushReplacement.
const Duration _finalSprint = Duration(milliseconds: 280);
// How often the "Loading" dots animate.
const Duration _dotsTick = Duration(milliseconds: 420);

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

class _WarmupScreenState extends State<WarmupScreen>
    with TickerProviderStateMixin {
  bool _routed = false;

  late final AnimationController _bar;
  late final Animation<double> _barValue;
  late final Timer _dotsTimer;
  int _dotCount = 1;

  @override
  void initState() {
    super.initState();
    _enterFullscreen();

    // Fake-progress sweeps 0 → 0.88 over the minimum visible window.
    // The last 0.12 is reserved for the "we're actually about to
    // launch" sprint triggered in [_handoff].
    _bar = AnimationController(
      vsync: this,
      duration: _minVisible,
      lowerBound: 0.0,
      upperBound: 1.0,
    );
    _barValue = Tween<double>(begin: 0.0, end: 0.88).animate(
      CurvedAnimation(parent: _bar, curve: Curves.easeOut),
    );
    _bar.forward();

    _dotsTimer = Timer.periodic(_dotsTick, (_) {
      if (!mounted) return;
      setState(() => _dotCount = (_dotCount % 3) + 1);
    });

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
    await _handoff(outcome);
  }

  /// Final 88 % → 100 % sweep, then push the resolved route. The
  /// 100 % frame is intentionally visible for one tick before the
  /// transition so the user perceives "fully loaded → go".
  Future<void> _handoff(Outcome outcome) async {
    _bar.stop();
    final AnimationController sprint = AnimationController(
      vsync: this,
      duration: _finalSprint,
    );
    final Animation<double> sprintValue = Tween<double>(
      begin: _barValue.value,
      end: 1.0,
    ).animate(CurvedAnimation(parent: sprint, curve: Curves.easeInOut));
    sprintValue.addListener(() {
      if (!mounted) return;
      setState(() {
        // Pin [_barValue] to the sprint output while it's running.
        _finalFill = sprintValue.value;
      });
    });
    await sprint.forward();
    // Hold the full bar for a single frame so the user visibly sees
    // 100 % before the next screen pushes.
    await Future<void>.delayed(const Duration(milliseconds: 60));
    sprint.dispose();
    if (!mounted || _routed) return;
    _routed = true;
    _route(outcome);
  }

  double _finalFill = 0.0;

  void _route(Outcome outcome) {
    switch (outcome) {
      case SlotOutcome():
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
  void dispose() {
    _dotsTimer.cancel();
    _bar.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Orientation orient = MediaQuery.of(context).orientation;
    final bool landscape = orient == Orientation.landscape;
    final Size size = MediaQuery.of(context).size;
    final String bg = landscape
        ? 'assets/Coin_Burst_additional_assets/Horizontal_Loading_Screen.webp'
        : 'assets/Coin_Burst_additional_assets/Vertical_Loading_Screen.webp';

    final double barWidth =
        (landscape ? size.width * 0.46 : size.width * 0.68)
            .clamp(220.0, 540.0);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Image.asset(bg, fit: BoxFit.cover, gaplessPlayback: true),
          Positioned(
            left: 0,
            right: 0,
            bottom: size.height * (landscape ? 0.11 : 0.09),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _LoadingCaption(dotCount: _dotCount),
                  const SizedBox(height: 14),
                  _ProgressBar(
                    width: barWidth,
                    animation: _bar,
                    sprintFill: _routed || _finalFill > 0 ? _finalFill : null,
                    cappedTween: _barValue,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Loading caption with 1 → 2 → 3 trailing dots ──────────────────────
class _LoadingCaption extends StatelessWidget {
  const _LoadingCaption({required this.dotCount});

  final int dotCount;

  @override
  Widget build(BuildContext context) {
    // Hold the dot slot at a fixed width so the caption doesn't jitter
    // horizontally while the dots cycle.
    final String dots = '.' * dotCount;
    final String padded = dots.padRight(3, ' ');
    return Text(
      'Loading$padded',
      style: const TextStyle(
        color: Color(0xFFFFE07A),
        fontSize: 16,
        fontWeight: FontWeight.w800,
        letterSpacing: 2.2,
        height: 1.0,
        shadows: <Shadow>[
          Shadow(color: Colors.black87, blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
    );
  }
}

// ── Horizontal L→R progress bar ───────────────────────────────────────
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({
    required this.width,
    required this.animation,
    required this.cappedTween,
    this.sprintFill,
  });

  final double width;
  final AnimationController animation;
  final Animation<double> cappedTween;
  final double? sprintFill;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: AnimatedBuilder(
        animation: animation,
        builder: (BuildContext context, _) {
          final double value = sprintFill ?? cappedTween.value;
          return _BarPainter(fill: value, width: width);
        },
      ),
    );
  }
}

class _BarPainter extends StatelessWidget {
  const _BarPainter({required this.fill, required this.width});

  final double fill;
  final double width;

  @override
  Widget build(BuildContext context) {
    const double height = 10.0;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xA0100000),
        borderRadius: BorderRadius.circular(height / 2),
        border: Border.all(color: const Color(0xFFB2650E), width: 1.4),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height / 2),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: fill.clamp(0.0, 1.0),
            heightFactor: 1.0,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: <Color>[
                    Color(0xFFFFE07A),
                    Color(0xFFF5B536),
                    Color(0xFFB2650E),
                  ],
                  stops: <double>[0.0, 0.55, 1.0],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
