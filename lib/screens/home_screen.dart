import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../game/slot_engine.dart';
import '../widgets/reel.dart';
import 'bonus_screen.dart';
import 'main_menu_screen.dart';
import 'paytable_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin {
  final SlotEngine _engine = SlotEngine();

  double _balance = 1000.0;
  final List<double> _betOptions = const <double>[1, 2, 5, 10, 25, 50, 100];
  int _betIndex = 1;

  bool _isSpinning = false;
  // Guards `_revealOutcome` so neither the onStopped callbacks nor the
  // safety timeout can trigger the win reveal twice (which previously could
  // push the bonus modal a second time → "2 bonus games credited").
  bool _outcomeRevealed = false;

  // Per-reel spin state. Reels are stopped sequentially left → right.
  final List<bool> _reelsSpinning = <bool>[false, false, false];
  final List<bool> _reelsAnticipating = <bool>[false, false, false];

  int _stoppedReels = 0; // counter for onStopped callbacks

  SpinResult? _lastResult;
  double _lastWin = 0;
  bool _showBigWin = false;
  late AnimationController _bigWinCtrl;

  // Current grid shown by reels [col][row].
  List<List<Symbol>> _displayGrid = List<List<Symbol>>.generate(
    3,
    (_) => <Symbol>[Symbol.cherry, Symbol.lemon, Symbol.orange],
  );

  // Highlighted cells per column (set of rows).
  List<Set<int>> _highlighted = List<Set<int>>.generate(3, (_) => <int>{});

  // Winning line indices (into SlotEngine.paylines) currently animated.
  List<LinePayout> _activeWinLines = <LinePayout>[];

  @override
  void initState() {
    super.initState();
    _bigWinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _loadBalance();
    final SpinResult r = _engine.spin(totalBet: _bet);
    _displayGrid = r.grid;
  }

  Future<void> _loadBalance() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final double? b = prefs.getDouble('cb_balance');
    if (b != null && mounted) {
      setState(() {
        _balance = b;
      });
    }
  }

  Future<void> _saveBalance() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('cb_balance', _balance);
  }

  double get _bet => _betOptions[_betIndex];

  @override
  void dispose() {
    _bigWinCtrl.dispose();
    super.dispose();
  }

  void _changeBet(int delta) {
    if (_isSpinning) return;
    setState(() {
      _betIndex = (_betIndex + delta).clamp(0, _betOptions.length - 1);
    });
  }

  Future<void> _spin() async {
    if (_isSpinning) return;
    if (_balance < _bet) {
      _showMessage('Insufficient balance');
      return;
    }

    // Compute the next result up front, then start spinning.
    final SpinResult r = _engine.spin(totalBet: _bet);
    _lastResult = r;

    setState(() {
      _balance -= _bet;
      _lastWin = 0;
      _showBigWin = false;
      _highlighted = List<Set<int>>.generate(3, (_) => <int>{});
      _activeWinLines = <LinePayout>[];
      _isSpinning = true;
      _outcomeRevealed = false;
      _stoppedReels = 0;
      _displayGrid = r.grid;
      _reelsSpinning[0] = true;
      _reelsSpinning[1] = true;
      _reelsSpinning[2] = true;
      _reelsAnticipating[0] = false;
      _reelsAnticipating[1] = false;
      _reelsAnticipating[2] = false;
    });

    // All reels spin in parallel. We stop reels sequentially:
    //  * Reel 0 after 950 ms
    //  * Reel 1 after +350 ms
    //  * Reel 2 after +350 ms (normal) OR +anticipation if 2 wilds on R0+R1.
    await Future.delayed(const Duration(milliseconds: 950));
    if (!mounted) return;
    setState(() {
      _reelsSpinning[0] = false;
    });

    await Future.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    setState(() {
      _reelsSpinning[1] = false;
    });

    // Count wilds visible on reels 0 and 1 (after they've stopped).
    final int wildsR01 = _countWildsInColumn(r.grid[0]) +
        _countWildsInColumn(r.grid[1]);
    if (wildsR01 >= 2) {
      // Anticipation: slow golden/fire spin on reel 2 before it stops.
      // Long enough that the player clearly sees the FX before the final
      // reveal — fixes "zoom didn't finish before bonus started".
      setState(() {
        _reelsAnticipating[2] = true;
      });
      await Future.delayed(const Duration(milliseconds: 2400));
      if (!mounted) return;
      setState(() {
        _reelsSpinning[2] = false;
      });
    } else {
      await Future.delayed(const Duration(milliseconds: 350));
      if (!mounted) return;
      setState(() {
        _reelsSpinning[2] = false;
      });
    }

    // Wait for reels to finish their stop animations. The reel widgets fire
    // onStopped() when fully settled; _onReelFullyStopped tracks these and
    // triggers win reveal once all 3 are done.
    //
    // Safety timeout: unconditionally reveal in case a callback was missed
    // (shouldn't happen but keeps the UI responsive). Must be strictly
    // greater than the slowest reel's stop duration (720ms normal /
    // 1400ms anticipating) + the 300ms post-settle beat above.
    await Future.delayed(const Duration(milliseconds: 3000));
    if (!mounted) return;
    if (_isSpinning && !_outcomeRevealed) {
      _revealOutcome();
    }
  }

  int _countWildsInColumn(List<Symbol> col) {
    int c = 0;
    for (final Symbol s in col) {
      if (s == Symbol.wild) c++;
    }
    return c;
  }

  void _onReelFullyStopped(int reelIndex) {
    _stoppedReels++;
    if (_stoppedReels >= 3 && _isSpinning && !_outcomeRevealed) {
      // Small post-settle beat so the final symbols read as "landed" before
      // the win line + highlights pop in on top of them.
      Future<void>.delayed(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        if (_isSpinning && !_outcomeRevealed) _revealOutcome();
      });
    }
  }

  Future<void> _revealOutcome() async {
    // Hard idempotency guard: whichever of the onStopped callback or the
    // safety timeout fires first wins — the other becomes a no-op.
    if (_outcomeRevealed) return;
    _outcomeRevealed = true;

    final SpinResult? r = _lastResult;
    if (r == null) {
      setState(() {
        _isSpinning = false;
      });
      return;
    }

    final List<Set<int>> hl =
        List<Set<int>>.generate(3, (_) => <int>{});
    for (final LinePayout w in r.wins) {
      for (final List<int> pos in w.positions) {
        hl[pos[1]].add(pos[0]);
      }
    }
    // Always highlight every wild (bonus scatter) that landed, even if
    // only 1 or 2 appeared — gives the player clear feedback that bonus
    // symbols are present on the grid.
    for (final List<int> p in r.wildScatterPositions) {
      hl[p[1]].add(p[0]);
    }

    final double lineWin = r.winMultiplierOfTotalBet * _bet;

    setState(() {
      _highlighted = hl;
      _activeWinLines = r.wins;
      _lastWin = lineWin;
      _balance += lineWin;
      _reelsAnticipating[0] = false;
      _reelsAnticipating[1] = false;
      _reelsAnticipating[2] = false;
    });
    await _saveBalance();

    if (lineWin >= _bet * 10) {
      setState(() {
        _showBigWin = true;
      });
      _bigWinCtrl.forward(from: 0);
    }

    if (r.triggersBonus) {
      // Wait for the ENTIRE spin to visually settle — R3 ease-out finished,
      // highlights pulsing on the 3 wilds — before the bonus intro slides
      // in. 2.5s is comfortably longer than any lingering reel motion.
      await Future.delayed(const Duration(milliseconds: 2500));
      if (!mounted) return;

      final double bonusWin = await Navigator.of(context).push<double>(
            MaterialPageRoute<double>(
              builder: (_) => BonusScreen(
                totalBet: _bet,
                engine: _engine,
              ),
              fullscreenDialog: true,
            ),
          ) ??
          0;

      if (!mounted) return;
      setState(() {
        _balance += bonusWin;
        _lastWin += bonusWin;
      });
      await _saveBalance();
      if (bonusWin >= _bet * 20) {
        setState(() => _showBigWin = true);
        _bigWinCtrl.forward(from: 0);
      }
    }

    setState(() {
      _isSpinning = false;
    });
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Pure black behind the SafeArea padding → status bar + nav bar
      // insets render as a clean black band, while the gradient game
      // background lives inside the SafeArea.
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: <Widget>[
            Positioned.fill(child: _buildBackground()),
            Column(
              children: <Widget>[
                _buildTopBar(),
                const SizedBox(height: 4),
                _buildLogo(),
                const SizedBox(height: 4),
                _buildStats(),
                const SizedBox(height: 10),
                Expanded(child: Center(child: _buildSlotFrame())),
                _buildBetControls(),
                _buildSpinButton(),
                const SizedBox(height: 14),
              ],
            ),
            if (_showBigWin)
              Positioned.fill(child: _buildBigWinOverlay()),
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
          radius: 1.2,
          colors: <Color>[
            Color(0xFF2C1458),
            Color(0xFF0B0F30),
            Color(0xFF05061A),
          ],
          stops: <double>[0, 0.55, 1],
        ),
      ),
      child: CustomPaint(
        painter: _StarsPainter(),
        size: Size.infinite,
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: <Widget>[
          _CircleIconButton(icon: Icons.menu, onTap: _openMenu),
          const Spacer(),
          _CircleIconButton(icon: Icons.help_outline, onTap: _openPaytable),
        ],
      ),
    );
  }

  Widget _buildLogo() {
    return SizedBox(
      height: 56,
      child: Image.asset(
        'assets/Coin_Burst_additional_assets/Game_Name.webp',
        fit: BoxFit.contain,
      ),
    );
  }

  Widget _buildStats() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _StatBox(
              label: 'BALANCE',
              value: _formatMoney(_balance),
              color: const Color(0xFF4FD9FF),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _StatBox(
              label: 'WIN',
              value: _formatMoney(_lastWin),
              color: const Color(0xFFFFD54F),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlotFrame() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      // The native frame artwork is wide (1024x620). We stretch it to a
      // taller aspect so a 3x3 grid of near-square cells fills the inner
      // panel area with large, legible symbols.
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
                // Inner playable area within the frame. The frame has an
                // outer silver/blue border, so we inset the reel region to
                // match the inner panel area of the artwork.
                // Visually-balanced inner panel insets so the reel area is
                // centered inside the frame artwork. Keeps a small extra
                // bottom margin for the decorative arrow strip.
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
                      // Hard-clip the whole reel area so no scrolling symbol
                      // can bleed over the frame artwork.
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            for (int col = 0; col < 3; col++)
                              ReelColumn(
                                key: ValueKey<int>(col),
                                reelIndex: col,
                                symbols: _displayGrid[col],
                                spinning: _reelsSpinning[col],
                                anticipating: _reelsAnticipating[col],
                                cellWidth: cellW,
                                cellHeight: cellH,
                                highlightedRows: _highlighted[col],
                                onStopped: () => _onReelFullyStopped(col),
                              ),
                          ],
                        ),
                      ),
                    ),
                    // Draw winning paylines through the cells.
                    if (!_isSpinning && _activeWinLines.isNotEmpty)
                      Positioned(
                        left: innerLeft,
                        top: innerTop,
                        width: innerW,
                        height: innerH,
                        child: IgnorePointer(
                          child: _WinLinesOverlay(
                            lines: _activeWinLines,
                            cellW: cellW,
                            cellH: cellH,
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

  Widget _buildBetControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          _CircleIconButton(
            icon: Icons.remove,
            size: 42,
            onTap: () => _changeBet(-1),
          ),
          const SizedBox(width: 14),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: <Color>[Color(0xFF0E1636), Color(0xFF1A2560)],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: const Color(0xFFFFD54F),
                width: 2,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Text(
                  'BET',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatMoney(_bet),
                  style: const TextStyle(
                    color: Color(0xFFFFD54F),
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          _CircleIconButton(
            icon: Icons.add,
            size: 42,
            onTap: () => _changeBet(1),
          ),
        ],
      ),
    );
  }

  Widget _buildSpinButton() {
    return GestureDetector(
      onTap: _spin,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: _isSpinning
              ? const LinearGradient(
                  colors: <Color>[Color(0xFF444444), Color(0xFF222222)],
                )
              : const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    Color(0xFFFFD54F),
                    Color(0xFFFF8A00),
                    Color(0xFFE91E63),
                  ],
                ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: _isSpinning
                  ? Colors.black45
                  : const Color(0xFFFF8A00).withValues(alpha: 0.55),
              blurRadius: 24,
              spreadRadius: 2,
            ),
          ],
          border: Border.all(color: Colors.white, width: 3),
        ),
        child: Center(
          child: Text(
            _isSpinning ? '...' : 'SPIN',
            style: const TextStyle(
              fontSize: 22,
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

  Widget _buildBigWinOverlay() {
    return GestureDetector(
      onTap: () => setState(() => _showBigWin = false),
      child: AnimatedBuilder(
        animation: _bigWinCtrl,
        builder: (context, _) {
          final double v = Curves.easeOutBack.transform(
            _bigWinCtrl.value.clamp(0.0, 1.0),
          );
          return Container(
            color: Colors.black.withValues(alpha: 0.55),
            alignment: Alignment.center,
            child: Transform.scale(
              scale: v,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 36, vertical: 28),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: <Color>[Color(0xFFFFD54F), Color(0xFFFF6EC7)],
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white, width: 4),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color:
                          const Color(0xFFFFD54F).withValues(alpha: 0.6),
                      blurRadius: 40,
                      spreadRadius: 6,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Text(
                      'BIG WIN!',
                      style: TextStyle(
                        fontSize: 44,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 4,
                        shadows: <Shadow>[
                          Shadow(color: Colors.black87, blurRadius: 6),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _formatMoney(_lastWin),
                      style: const TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        shadows: <Shadow>[
                          Shadow(color: Colors.black87, blurRadius: 4),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'TAP TO CONTINUE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        letterSpacing: 3,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _openMenu() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MainMenuScreen(currentBet: _bet),
      ),
    );
  }

  void _openPaytable() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PaytableScreen(currentBet: _bet),
      ),
    );
  }
}

// ---------- helpers / sub-widgets ----------

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

class _WinLinesOverlay extends StatefulWidget {
  final List<LinePayout> lines;
  final double cellW;
  final double cellH;

  const _WinLinesOverlay({
    required this.lines,
    required this.cellW,
    required this.cellH,
  });

  @override
  State<_WinLinesOverlay> createState() => _WinLinesOverlayState();
}

class _WinLinesOverlayState extends State<_WinLinesOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return CustomPaint(
          painter: _WinLinesPainter(
            lines: widget.lines,
            cellW: widget.cellW,
            cellH: widget.cellH,
            progress: _ctrl.value,
          ),
          size: Size.infinite,
        );
      },
    );
  }
}

class _WinLinesPainter extends CustomPainter {
  final List<LinePayout> lines;
  final double cellW;
  final double cellH;
  final double progress; // 0..1 pulsing

  _WinLinesPainter({
    required this.lines,
    required this.cellW,
    required this.cellH,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // One line color per index for variety.
    const List<Color> palette = <Color>[
      Color(0xFFFFEB3B),
      Color(0xFF00E5FF),
      Color(0xFFFF4081),
      Color(0xFF76FF03),
      Color(0xFFFF6E40),
    ];

    for (final LinePayout line in lines) {
      final Color base = palette[line.lineIndex % palette.length];
      final Paint stroke = Paint()
        ..color = base.withValues(alpha: 0.55 + 0.4 * progress)
        ..strokeWidth = 5 + 2 * progress
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      final Paint glow = Paint()
        ..color = base.withValues(alpha: 0.35 * (0.5 + 0.5 * progress))
        ..strokeWidth = 14
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      final Path path = Path();
      for (int i = 0; i < line.positions.length; i++) {
        final List<int> pos = line.positions[i]; // [row, col]
        final double cx = pos[1] * cellW + cellW / 2;
        final double cy = pos[0] * cellH + cellH / 2;
        if (i == 0) {
          path.moveTo(cx, cy);
        } else {
          path.lineTo(cx, cy);
        }
      }
      canvas.drawPath(path, glow);
      canvas.drawPath(path, stroke);
    }
  }

  @override
  bool shouldRepaint(covariant _WinLinesPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.lines != lines;
}

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  const _CircleIconButton({
    required this.icon,
    required this.onTap,
    this.size = 46,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[Color(0xFF1A2560), Color(0xFF0A0E27)],
          ),
          border: Border.all(color: const Color(0xFFFFD54F), width: 2),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Colors.black54,
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon,
            color: const Color(0xFFFFD54F), size: size * 0.5),
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatBox({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFF0C1340), Color(0xFF161F55)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color, width: 2),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: color.withValues(alpha: 0.4),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.65),
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
                shadows: const <Shadow>[
                  Shadow(color: Colors.black87, blurRadius: 3),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StarsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Random r = Random(13);
    final Paint p = Paint()..color = Colors.white.withValues(alpha: 0.15);
    for (int i = 0; i < 60; i++) {
      final double x = r.nextDouble() * size.width;
      final double y = r.nextDouble() * size.height;
      canvas.drawCircle(Offset(x, y), r.nextDouble() * 1.4 + 0.3, p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
