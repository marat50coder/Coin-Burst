import 'package:flutter/material.dart';

import '../game/slot_engine.dart';

/// Paytable screen — combines "Combinations" (3-of-a-kind payouts) and
/// "Line Cost" (how the total bet is split across 5 paylines).
class PaytableScreen extends StatelessWidget {
  final double currentBet;

  const PaytableScreen({super.key, required this.currentBet});

  double get _perLineBet => currentBet / SlotEngine.numLines;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: <Widget>[
            Positioned.fill(child: _buildBackground()),
            Column(
              children: <Widget>[
                _buildHeader(context),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        _section(
                          title: 'LINE COST',
                          accent: const Color(0xFF4FD9FF),
                          child: Column(
                            children: <Widget>[
                              _kv('Total bet', _formatMoney(currentBet)),
                              _kv('Active paylines',
                                  '${SlotEngine.numLines}'),
                              _kv(
                                'Cost per line',
                                _formatMoney(_perLineBet),
                                highlight: true,
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Each winning payline pays its '
                                'tier multiplier × cost per line.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        _section(
                          title: 'COMBINATIONS',
                          accent: const Color(0xFFFFD54F),
                          child: Column(
                            children: const <Widget>[
                              _PayRow(
                                symbol: Symbol.wild,
                                text: 'x3 anywhere → 6 Free Spins',
                              ),
                              _PayRow(
                                symbol: Symbol.bar,
                                text: '3 in line → x430 per line',
                              ),
                              _PayRow(
                                symbol: Symbol.bell,
                                text: '3 in line → x170 per line',
                              ),
                              _PayRow(
                                symbol: Symbol.grape,
                                text: '3 in line → x85 per line',
                              ),
                              _PayRow(
                                symbol: Symbol.watermelon,
                                text: '3 in line → x48 per line',
                              ),
                              _PayRow(
                                symbol: Symbol.orange,
                                text: '3 in line → x30 per line',
                              ),
                              _PayRow(
                                symbol: Symbol.lemon,
                                text: '3 in line → x20 per line',
                              ),
                              _PayRow(
                                symbol: Symbol.cherry,
                                text: '3 in line → x14 per line',
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Only 3-of-a-kind pays. 5 paylines: '
                                '3 rows + 2 diagonals.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        _section(
                          title: 'BONUS COINS',
                          accent: const Color(0xFFFF6EC7),
                          child: Column(
                            children: const <Widget>[
                              _PayRow(
                                symbol: Symbol.coinGrand,
                                text: 'GRAND → x350 of total bet',
                              ),
                              _PayRow(
                                symbol: Symbol.coinMajor,
                                text: 'MAJOR → x55 of total bet',
                              ),
                              _PayRow(
                                symbol: Symbol.coinMinor,
                                text: 'MINOR → x17 of total bet',
                              ),
                              _PayRow(
                                symbol: Symbol.coinMini,
                                text: 'MINI → x5 of total bet',
                              ),
                              _PayRow(
                                symbol: Symbol.thunder,
                                text:
                                    'Thunder: pays all coins on the SAME '
                                    'spin. No thunder → no payout.',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
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
            Color(0xFF2C1458),
            Color(0xFF0B0F30),
            Color(0xFF05061A),
          ],
          stops: <double>[0, 0.55, 1],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: <Widget>[
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: <Color>[Color(0xFF1A2560), Color(0xFF0A0E27)],
                ),
                border: Border.all(
                  color: const Color(0xFFFFD54F),
                  width: 2,
                ),
              ),
              child: const Icon(
                Icons.arrow_back,
                color: Color(0xFFFFD54F),
                size: 22,
              ),
            ),
          ),
          const Spacer(),
          const Text(
            'PAYTABLE',
            style: TextStyle(
              color: Color(0xFFFFD54F),
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: 4,
              shadows: <Shadow>[
                Shadow(color: Colors.black87, blurRadius: 6),
              ],
            ),
          ),
          const Spacer(),
          const SizedBox(width: 46),
        ],
      ),
    );
  }

  Widget _section({
    required String title,
    required Color accent,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFF161F55), Color(0xFF0C1340)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent, width: 2),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: accent.withValues(alpha: 0.25),
            blurRadius: 14,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: accent,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _kv(String k, String v, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              k,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.78),
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            v,
            style: TextStyle(
              color: highlight
                  ? const Color(0xFFFFD54F)
                  : const Color(0xFF4FD9FF),
              fontSize: highlight ? 20 : 16,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _PayRow extends StatelessWidget {
  final Symbol symbol;
  final String text;
  const _PayRow({required this.symbol, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 36,
            height: 36,
            child: Image.asset(symbol.asset ?? '', fit: BoxFit.contain),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
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
