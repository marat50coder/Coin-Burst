import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../game/slot_engine.dart';
import '../widgets/reel.dart';

class BonusScreen extends StatefulWidget {
  final double totalBet;
  final SlotEngine engine;

  const BonusScreen({
    super.key,
    required this.totalBet,
    required this.engine,
  });

  @override
  State<BonusScreen> createState() => _BonusScreenState();
}

enum _BonusPhase { intro, playing, outro }

class _BonusScreenState extends State<BonusScreen>
    with TickerProviderStateMixin {
  static const int totalSpins = 6;

  _BonusPhase _phase = _BonusPhase.intro;
  int _spinsLeft = totalSpins;
  double _totalWinMultiplier = 0;

  bool _isSpinning = false;
  final List<bool> _reelsSpinning = <bool>[false, false, false];

  // Visible 3×3 grid [col][row]. Shown by the reels when they stop. Each
  // spin is independent — no hold mechanic.
  List<List<Symbol>> _displayGrid = List<List<Symbol>>.generate(
    3,
    (_) => List<Symbol>.filled(3, Symbol.empty),
  );

  bool _thunderFlashActive = false;
  // Snapshot of the thunder + coin positions captured when the flash
  // starts; drives the lightning-strike / coin-pulse FX in the painter.
  List<List<int>> _lastThunderPositions = <List<int>>[];
  List<List<int>> _lastCoinPositionsAtFlash = <List<int>>[];

  late final AnimationController _introCtrl;
  late final AnimationController _flashCtrl;

  @override
  void initState() {
    super.initState();
    _introCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    )..forward();
    _flashCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
  }

  @override
  void dispose() {
    _introCtrl.dispose();
    _flashCtrl.dispose();
    super.dispose();
  }

  void _startBonus() {
    setState(() {
      _phase = _BonusPhase.playing;
    });
  }

  Future<void> _spinBonus() async {
    if (_isSpinning || _spinsLeft <= 0) return;

    // Pre-compute spin outcome. Each spin is independent — no held carry.
    final BonusSpinResult res = widget.engine.bonusSpin();

    setState(() {
      _isSpinning = true;
      _reelsSpinning[0] = true;
      _reelsSpinning[1] = true;
      _reelsSpinning[2] = true;
      _displayGrid = res.grid;
    });

    // Stop reels sequentially left → right (same cadence as base game).
    await Future.delayed(const Duration(milliseconds: 950));
    if (!mounted) return;
    setState(() => _reelsSpinning[0] = false);
    await Future.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    setState(() => _reelsSpinning[1] = false);
    await Future.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    setState(() => _reelsSpinning[2] = false);

    // Wait for the final reel's stop animation (720 ms) + a brief
    // post-settle beat so coins feel like they truly landed.
    await Future.delayed(const Duration(milliseconds: 950));
    if (!mounted) return;

    // Thunder lands → collect every coin on the SAME grid. No thunder →
    // nothing is credited this spin.
    if (res.thunder) {
      setState(() {
        _thunderFlashActive = true;
        _lastThunderPositions = res.thunderPositions;
        _lastCoinPositionsAtFlash = res.coinPositions;
      });
      _flashCtrl.forward(from: 0);
      await Future.delayed(const Duration(milliseconds: 1200));
      if (!mounted) return;
      setState(() {
        _thunderFlashActive = false;
      });
    }

    setState(() {
      _spinsLeft -= 1;
      _totalWinMultiplier += res.collectedMultiplier;
      _isSpinning = false;
    });

    if (_spinsLeft <= 0) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      setState(() {
        _phase = _BonusPhase.outro;
      });
    }
  }

  void _onReelFullyStopped(int reelIndex) {
    // Reel widget fires this when its stop animation finishes; the parent
    // orchestration already waits via Future.delayed, so this is purely a
    // signal for future use.
  }

  void _finish() {
    Navigator.of(context).pop(_totalWinMultiplier * widget.totalBet);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: <Widget>[
            Positioned.fill(child: _buildBackground()),
            if (_phase == _BonusPhase.intro) _buildIntro(),
            if (_phase == _BonusPhase.playing) _buildPlaying(),
            if (_phase == _BonusPhase.outro) _buildOutro(),
          ],
        ),
      ),
    );
  }

  Widget _buildBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.3),
          radius: 1.3,
          colors: <Color>[
            Color(0xFF4A1B7A),
            Color(0xFF1A1050),
            Color(0xFF05061A),
          ],
          stops: <double>[0, 0.55, 1],
        ),
      ),
    );
  }

  Widget _buildIntro() {
    return AnimatedBuilder(
      animation: _introCtrl,
      builder: (context, _) {
        final double v = Curves.easeOutBack
            .transform(_introCtrl.value.clamp(0.0, 1.0));
        return Center(
          child: Transform.scale(
            scale: v,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: <Color>[Color(0xFFFFD54F), Color(0xFFFF6EC7)],
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white, width: 4),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: const Color(0xFFFFD54F).withValues(alpha: 0.55),
                    blurRadius: 40,
                    spreadRadius: 6,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'CONGRATULATIONS!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 1.5,
                        shadows: <Shadow>[
                          Shadow(color: Colors.black87, blurRadius: 6),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'YOU WIN',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 4,
                      shadows: <Shadow>[
                        Shadow(color: Colors.black54, blurRadius: 3),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Image.asset(
                    'assets/Coin_Burst_gameplay_assets/7_wild_asset.webp',
                    height: 110,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '6 FREE SPINS',
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 3,
                      shadows: <Shadow>[
                        Shadow(color: Colors.black87, blurRadius: 6),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  ElevatedButton(
                    onPressed: _startBonus,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFFE91E63),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 42,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                    ),
                    child: const Text(
                      'START',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPlaying() {
    final double totalWinAmount = _totalWinMultiplier * widget.totalBet;
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: <Widget>[
              Expanded(
                child: _BonusStat(
                  label: 'FREE SPINS',
                  value: '$_spinsLeft',
                  color: const Color(0xFF4FD9FF),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _BonusStat(
                  label: 'TOTAL WIN',
                  value: _formatMoney(totalWinAmount),
                  color: const Color(0xFFFFD54F),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        // Reference panel showing GRAND / MAJOR / MINOR / MINI tiers.
        // Placed just above the reel frame instead of overlaying each coin.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Image.asset(
            'assets/Coin_Burst_gameplay_assets/bonuses_asset.webp',
            fit: BoxFit.contain,
            gaplessPlayback: true,
          ),
        ),
        const SizedBox(height: 6),
        Expanded(child: Center(child: _buildBonusFrame())),
        _buildSpinButton(),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildBonusFrame() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: AspectRatio(
        aspectRatio: 1.0,
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: Image.asset(
                'assets/Coin_Burst_gameplay_assets/slot_frame_asset.webp',
                fit: BoxFit.fill,
                gaplessPlayback: true,
              ),
            ),
            LayoutBuilder(
              builder: (context, cst) {
                final double innerLeft = cst.maxWidth * 0.115;
                final double innerRight = cst.maxWidth * 0.115;
                final double innerTop = cst.maxHeight * 0.125;
                final double innerBottom = cst.maxHeight * 0.145;
                final double innerW =
                    cst.maxWidth - innerLeft - innerRight;
                final double innerH =
                    cst.maxHeight - innerTop - innerBottom;
                final double cellW = innerW / 3;
                final double cellH = innerH / 3;

                return Stack(
                  children: <Widget>[
                    Positioned(
                      left: innerLeft,
                      top: innerTop,
                      width: innerW,
                      height: innerH,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Row(
                          children: <Widget>[
                            for (int col = 0; col < 3; col++)
                              ReelColumn(
                                key: ValueKey<int>(col),
                                reelIndex: col,
                                symbols: _displayGrid[col],
                                spinning: _reelsSpinning[col],
                                cellWidth: cellW,
                                cellHeight: cellH,
                                stripPool: bonusStripPool,
                                onStopped: () => _onReelFullyStopped(col),
                              ),
                          ],
                        ),
                      ),
                    ),
                    // Thunder-collect FX overlay: lightning across the grid
                    // + golden pulse on every coin cell. Makes it very
                    // obvious which coins were just credited.
                    if (_thunderFlashActive)
                      Positioned(
                        left: innerLeft,
                        top: innerTop,
                        width: innerW,
                        height: innerH,
                        child: IgnorePointer(
                          child: AnimatedBuilder(
                            animation: _flashCtrl,
                            builder: (context, _) {
                              return CustomPaint(
                                painter: _ThunderCollectPainter(
                                  grid: _displayGrid,
                                  thunderPositions: _lastThunderPositions,
                                  coinPositions: _lastCoinPositionsAtFlash,
                                  cellW: cellW,
                                  cellH: cellH,
                                  progress: _flashCtrl.value,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpinButton() {
    final bool canSpin = !_isSpinning && _spinsLeft > 0;
    return GestureDetector(
      onTap: canSpin ? _spinBonus : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: canSpin
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    Color(0xFFFFD54F),
                    Color(0xFFFF8A00),
                    Color(0xFFE91E63),
                  ],
                )
              : const LinearGradient(
                  colors: <Color>[Color(0xFF444444), Color(0xFF222222)],
                ),
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: canSpin
                  ? const Color(0xFFFF8A00).withValues(alpha: 0.55)
                  : Colors.black45,
              blurRadius: 24,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Center(
          child: Text(
            canSpin ? 'SPIN' : '...',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 2,
              shadows: <Shadow>[
                Shadow(color: Colors.black87, blurRadius: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOutro() {
    final double amount = _totalWinMultiplier * widget.totalBet;
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding:
            const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: <Color>[Color(0xFFFFD54F), Color(0xFFFF6EC7)],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white, width: 4),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: const Color(0xFFFFD54F).withValues(alpha: 0.6),
              blurRadius: 40,
              spreadRadius: 6,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text(
              'BONUS COMPLETE',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 3,
                shadows: <Shadow>[
                  Shadow(color: Colors.black87, blurRadius: 4),
                ],
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'TOTAL WIN',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
                letterSpacing: 3,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _formatMoney(amount),
              style: const TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                shadows: <Shadow>[
                  Shadow(color: Colors.black87, blurRadius: 6),
                ],
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _finish,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFFE91E63),
                padding: const EdgeInsets.symmetric(
                    horizontal: 42, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
              child: const Text(
                'COLLECT',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BonusStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _BonusStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFF0C1340), Color(0xFF161F55)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10,
              letterSpacing: 2,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Paints the thunder-collect FX: a jagged lightning bolt from every
/// thunder cell to every coin on the grid + a golden halo pulse on the
/// coins + a radial white flash fading out.
class _ThunderCollectPainter extends CustomPainter {
  final List<List<Symbol>> grid;
  final List<List<int>> thunderPositions; // [row, col]
  final List<List<int>> coinPositions; // [row, col]
  final double cellW;
  final double cellH;
  final double progress; // 0..1

  _ThunderCollectPainter({
    required this.grid,
    required this.thunderPositions,
    required this.coinPositions,
    required this.cellW,
    required this.cellH,
    required this.progress,
  });

  Offset _center(int row, int col) =>
      Offset(col * cellW + cellW / 2, row * cellH + cellH / 2);

  @override
  void paint(Canvas canvas, Size size) {
    final double flashAlpha = (1 - progress) * 0.55;

    // Fading full-grid white flash in the first 25% of the animation.
    if (progress < 0.3) {
      final double a = (1 - progress / 0.3) * 0.4;
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = Colors.white.withValues(alpha: a),
      );
    }

    // Lightning bolts from each thunder to each coin.
    for (final List<int> t in thunderPositions) {
      final Offset from = _center(t[0], t[1]);
      for (final List<int> c in coinPositions) {
        final Offset to = _center(c[0], c[1]);
        // Draw the bolt in the first 60% of the animation.
        if (progress < 0.75) {
          _drawBolt(canvas, from, to, progress / 0.75);
        }
      }
    }

    // Golden halo pulse on each coin cell.
    for (final List<int> c in coinPositions) {
      final Offset center = _center(c[0], c[1]);
      final double r =
          cellW * 0.42 * (1 + 0.35 * sin(progress * pi * 2));
      final Paint halo = Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            const Color(0xFFFFEE58).withValues(alpha: flashAlpha + 0.25),
            const Color(0xFFFFC107).withValues(alpha: flashAlpha * 0.6),
            Colors.transparent,
          ],
          stops: const <double>[0, 0.55, 1],
        ).createShader(Rect.fromCircle(center: center, radius: r));
      canvas.drawCircle(center, r, halo);
    }
  }

  void _drawBolt(Canvas canvas, Offset a, Offset b, double t) {
    // Reveal the bolt from a→b over `t` ∈ [0,1].
    final int segments = 10;
    final Random rnd = Random((a.dx * 97 + b.dy * 31).toInt());
    final List<Offset> pts = <Offset>[a];
    for (int i = 1; i < segments; i++) {
      final double f = i / segments;
      final Offset base = Offset.lerp(a, b, f)!;
      final double jitter = 10 + rnd.nextDouble() * 10;
      final Offset perp =
          Offset(-(b.dy - a.dy), b.dx - a.dx);
      final double len = perp.distance;
      final Offset norm =
          len == 0 ? Offset.zero : Offset(perp.dx / len, perp.dy / len);
      final double side = (rnd.nextDouble() - 0.5) * jitter;
      pts.add(base + norm * side);
    }
    pts.add(b);

    // How many segments are drawn right now.
    final int shown = (pts.length * t).clamp(2, pts.length).toInt();
    final Path path = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (int i = 1; i < shown; i++) {
      path.lineTo(pts[i].dx, pts[i].dy);
    }

    final Paint glow = Paint()
      ..color = const Color(0xFF4FD9FF).withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    final Paint core = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, glow);
    canvas.drawPath(path, core);
  }

  @override
  bool shouldRepaint(covariant _ThunderCollectPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.thunderPositions != thunderPositions ||
      oldDelegate.coinPositions != coinPositions;
}

String _formatMoney(double v) {
  final bool neg = v < 0;
  final double abs = v.abs();
  final String s = abs.toStringAsFixed(2);
  final List<String> parts = s.split('.');
  final String intPart = parts[0];
  final String dec = parts[1];
  final StringBuffer buf = StringBuffer();
  final int len = intPart.length;
  for (int i = 0; i < len; i++) {
    final int fromEnd = len - i;
    buf.write(intPart[i]);
    if (fromEnd > 1 && fromEnd % 3 == 1) buf.write(',');
  }
  return '${neg ? '-' : ''}${buf.toString()}.$dec';
}
