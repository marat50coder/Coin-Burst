import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────
// BURST BUTTON — casino-themed button for the gray-side screens
// ─────────────────────────────────────────────────────────────────────────
// Replaces the template's sky-blue pill button entirely. The design is
// slot-adjacent (gold centre with a burgundy bevel + inner glow) so it
// reads as part of the Coin Burst identity instead of a generic Material
// button.
//
// Three variants:
//   • [BurstBigButton]   — primary action (Accept, Retry). Full-width,
//                           tall, flat gold with 3-stop gradient.
//   • [BurstGhostButton] — secondary action (Skip). Same shape as the
//                           big one but with a semi-transparent fill
//                           and only an outline — meets WCAG target
//                           dimensions, never a transparent text link.
// ─────────────────────────────────────────────────────────────────────────

const Color _goldHigh = Color(0xFFFFE07A);
const Color _goldMid = Color(0xFFF5B536);
const Color _goldLow = Color(0xFFB2650E);
const Color _burgundy = Color(0xFF4C0C14);
const Color _emberShadow = Color(0xB0100000);

class BurstBigButton extends StatefulWidget {
  const BurstBigButton({
    super.key,
    required this.label,
    required this.onTap,
    this.compact = false,
    this.width,
  });

  final String label;
  final VoidCallback onTap;
  final bool compact;
  final double? width;

  @override
  State<BurstBigButton> createState() => _BurstBigButtonState();
}

class _BurstBigButtonState extends State<BurstBigButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      child: AnimatedScale(
        duration: const Duration(milliseconds: 110),
        scale: _pressed ? 0.96 : 1.0,
        child: Container(
          width: widget.width,
          height: widget.compact ? 46 : 56,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: <Color>[_goldHigh, _goldMid, _goldLow],
              stops: <double>[0.0, 0.55, 1.0],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _burgundy, width: 2.5),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: _emberShadow,
                offset: Offset(0, 5),
                blurRadius: 10,
              ),
            ],
          ),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              // Inner highlight — gives the gold a subtle "lit from
              // above" feel.
              Positioned(
                top: 2,
                left: 6,
                right: 6,
                child: Container(
                  height: 10,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    gradient: LinearGradient(
                      colors: <Color>[
                        Colors.white.withValues(alpha: 0.75),
                        Colors.white.withValues(alpha: 0.0),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ),
              Center(
                child: Text(
                  widget.label,
                  textAlign: TextAlign.center,
                  // `height: 1.0` kills font-provided baseline drift —
                  // see gray_part_pitfalls.md §13.
                  style: TextStyle(
                    color: _burgundy,
                    fontSize: widget.compact ? 17 : 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                    height: 1.0,
                    shadows: const <Shadow>[
                      Shadow(
                        color: Color(0x66FFFFFF),
                        offset: Offset(0, 1),
                        blurRadius: 0,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class BurstGhostButton extends StatefulWidget {
  const BurstGhostButton({
    super.key,
    required this.label,
    required this.onTap,
    this.compact = false,
    this.width,
  });

  final String label;
  final VoidCallback onTap;
  final bool compact;
  final double? width;

  @override
  State<BurstGhostButton> createState() => _BurstGhostButtonState();
}

class _BurstGhostButtonState extends State<BurstGhostButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      child: AnimatedScale(
        duration: const Duration(milliseconds: 110),
        scale: _pressed ? 0.96 : 1.0,
        child: Container(
          width: widget.width,
          // Minimum 44 dp tap target per WCAG. Skip never ships as a
          // transparent text link in this project.
          height: widget.compact ? 46 : 54,
          decoration: BoxDecoration(
            // Solid translucent fill, not just an outline — WCAG rules
            // in gray_part_pitfalls.md §12.
            color: const Color(0xCC18060C),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _goldMid, width: 2.5),
          ),
          child: Center(
            child: Text(
              widget.label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _goldHigh,
                fontSize: widget.compact ? 17 : 19,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                height: 1.0,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
