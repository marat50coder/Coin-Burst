import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../game/slot_engine.dart';

/// A single reel column. Shows 3 symbols vertically.
///
/// The parent fully controls spin/stop via `spinning` and `anticipating`.
/// Internally we drive scrolling with a `Ticker` so stops are deterministic
/// and we always land on `symbols` (indexed row 0..2 top..bottom).
///
/// Lifecycle:
///  * `spinning` false → true: start infinite scroll
///  * `anticipating` toggles mid-spin: scroll speed changes immediately
///  * `spinning` true → false: ease-out stop onto `symbols`, then onStopped()
class ReelColumn extends StatefulWidget {
  final int reelIndex;
  final List<Symbol> symbols;
  final bool spinning;
  final bool anticipating;
  final VoidCallback? onStopped;
  final Set<int> highlightedRows;
  final double cellWidth;
  final double cellHeight;

  /// Pool of symbols used to populate the random portion of the scrolling
  /// strip. Defaults to the base-game pool, override for the bonus game.
  final List<Symbol> stripPool;

  const ReelColumn({
    super.key,
    required this.reelIndex,
    required this.symbols,
    required this.spinning,
    required this.cellWidth,
    required this.cellHeight,
    this.anticipating = false,
    this.onStopped,
    this.highlightedRows = const <int>{},
    this.stripPool = baseStripPool,
  });

  @override
  State<ReelColumn> createState() => _ReelColumnState();
}

enum _Phase { idle, spinning, stopping }

class _ReelColumnState extends State<ReelColumn>
    with SingleTickerProviderStateMixin {
  final Random _rng = Random();
  Ticker? _ticker;
  _Phase _phase = _Phase.idle;
  Duration _lastTick = Duration.zero;
  double _scrollOffsetCells = 0;
  List<Symbol> _strip = <Symbol>[];

  // Stop-animation state.
  double _stopStart = 0;
  double _stopTarget = 0;
  Duration _stopElapsed = Duration.zero;
  Duration _stopDuration = const Duration(milliseconds: 500);

  // Uniform spin speed across all reels during the main phase. Only the
  // anticipation state slows it down for the golden-reel suspense.
  double get _spinSpeedCellsPerSec => widget.anticipating ? 6.0 : 18.0;

  @override
  void initState() {
    super.initState();
    _buildStripIdle();
    _ticker = createTicker(_onTick);
    if (widget.spinning) _startSpinning();
  }

  @override
  void didUpdateWidget(covariant ReelColumn oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!oldWidget.spinning && widget.spinning) {
      _startSpinning();
      return;
    }
    if (oldWidget.spinning && !widget.spinning) {
      _startStopping();
      return;
    }

    // If idle and symbols changed (shouldn't happen mid-flight), refresh.
    if (_phase == _Phase.idle &&
        !_sameSymbols(oldWidget.symbols, widget.symbols)) {
      _buildStripIdle();
      setState(() {});
    }
  }

  bool _sameSymbols(List<Symbol> a, List<Symbol> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  void _buildStripIdle() {
    _strip = <Symbol>[
      widget.symbols[0],
      widget.symbols[1],
      widget.symbols[2],
    ];
    _scrollOffsetCells = 0;
  }

  void _buildStripForSpin() {
    const int len = 32;
    final List<Symbol> pool = widget.stripPool;
    _strip = List<Symbol>.generate(
      len,
      (_) => pool[_rng.nextInt(pool.length)],
    );
    _strip[len - 3] = widget.symbols[0];
    _strip[len - 2] = widget.symbols[1];
    _strip[len - 1] = widget.symbols[2];
    _scrollOffsetCells = 0;
  }

  void _startSpinning() {
    _buildStripForSpin();
    _phase = _Phase.spinning;
    _lastTick = Duration.zero;
    if (!(_ticker?.isActive ?? false)) {
      _ticker?.start();
    }
    if (mounted) setState(() {});
  }

  void _startStopping() {
    final int len = _strip.length;
    _stopStart = _scrollOffsetCells;
    _stopTarget = (len - 3).toDouble();
    // Ensure forward motion with at least 2 cells of travel.
    while (_stopTarget - _stopStart < 2.0) {
      _stopTarget += len;
    }
    _phase = _Phase.stopping;
    _stopElapsed = Duration.zero;
    _stopDuration = widget.anticipating
        ? const Duration(milliseconds: 1400)
        : const Duration(milliseconds: 720);
    if (!(_ticker?.isActive ?? false)) {
      _ticker?.start();
    }
    if (mounted) setState(() {});
  }

  void _onTick(Duration elapsed) {
    final Duration dt = _lastTick == Duration.zero
        ? Duration.zero
        : elapsed - _lastTick;
    _lastTick = elapsed;

    if (_phase == _Phase.spinning) {
      final double dtSec = dt.inMicroseconds / 1000000.0;
      final double newOffset =
          _scrollOffsetCells + _spinSpeedCellsPerSec * dtSec;
      if (mounted) {
        setState(() {
          _scrollOffsetCells = newOffset;
        });
      }
      return;
    }

    if (_phase == _Phase.stopping) {
      _stopElapsed += dt;
      final double raw =
          _stopElapsed.inMicroseconds / _stopDuration.inMicroseconds;
      if (raw >= 1.0) {
        _phase = _Phase.idle;
        _buildStripIdle();
        _ticker?.stop();
        _lastTick = Duration.zero;
        if (mounted) setState(() {});
        widget.onStopped?.call();
        return;
      }
      // Cubic ease-out blends more smoothly between the fast spin and the
      // dead stop, avoiding the "snap" users reported.
      final double eased =
          Curves.easeOutCubic.transform(raw.clamp(0.0, 1.0));
      final double v = _stopStart + (_stopTarget - _stopStart) * eased;
      if (mounted) {
        setState(() {
          _scrollOffsetCells = v;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final double h = widget.cellHeight;
    final double w = widget.cellWidth;
    final double viewportHeight = h * 3;

    return ClipRect(
      child: SizedBox(
        width: w,
        height: viewportHeight,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: <Widget>[
            _buildScrollingStrip(w, h),

            // Winning row highlight — ONLY when fully stopped (idle).
            if (_phase == _Phase.idle)
              for (int row = 0; row < 3; row++)
                if (widget.highlightedRows.contains(row))
                  Positioned(
                    top: row * h,
                    left: 0,
                    width: w,
                    height: h,
                    child: const IgnorePointer(child: _WinHighlight()),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildScrollingStrip(double w, double h) {
    final int len = _strip.length;
    final int floorIdx = _scrollOffsetCells.floor();
    final double frac = _scrollOffsetCells - floorIdx;
    final List<Widget> cells = <Widget>[];
    // Positioned cells avoid RenderFlex overflow and still animate smoothly.
    for (int i = -1; i <= 3; i++) {
      final int idx = ((floorIdx + i) % len + len) % len;
      cells.add(Positioned(
        left: 0,
        top: (i - frac) * h,
        width: w,
        height: h,
        child: _SymbolCell(
          symbol: _strip[idx],
          width: w,
          height: h,
        ),
      ));
    }
    return Stack(
      clipBehavior: Clip.hardEdge,
      children: cells,
    );
  }
}

class _SymbolCell extends StatelessWidget {
  final Symbol symbol;
  final double width;
  final double height;
  const _SymbolCell({
    required this.symbol,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    // Empty bonus cell renders nothing (keeps slot panel visible underneath).
    if (symbol == Symbol.empty) {
      return SizedBox(width: width, height: height);
    }

    final String? path = symbol.asset;
    if (path == null) {
      return SizedBox(width: width, height: height);
    }

    // Axis-independent padding keeps the symbol visually centered inside
    // the cell regardless of whether cells are slightly wider than tall or
    // vice-versa. BoxFit.contain + Center → geometric centre of the cell.
    final double padW = width * 0.08;
    final double padH = height * 0.08;
    final Widget image = ClipRect(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: padW, vertical: padH),
        child: Center(
          child: Image.asset(
            path,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
          ),
        ),
      ),
    );

    // Coin / fruit / wild — always centered inside its cell. The
    // denominations are displayed in a separate reference panel above the
    // grid in the bonus screen, so no per-cell plate overlay here.
    return SizedBox(width: width, height: height, child: image);
  }
}

class _WinHighlight extends StatefulWidget {
  const _WinHighlight();

  @override
  State<_WinHighlight> createState() => _WinHighlightState();
}

class _WinHighlightState extends State<_WinHighlight>
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
        final double opacity = 0.4 + 0.5 * _ctrl.value;
        return Container(
          margin: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: const Color(0xFFFFD54F).withValues(alpha: opacity),
              width: 3,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: const Color(0xFFFFC107)
                    .withValues(alpha: opacity * 0.6),
                blurRadius: 20,
                spreadRadius: 1,
              ),
            ],
          ),
        );
      },
    );
  }
}

// Anticipation visual overlay was removed per design feedback — the slow R3
// spin alone creates enough suspense without the fire/glow treatment.
