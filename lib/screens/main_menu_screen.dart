import 'package:flutter/material.dart';

import 'paytable_screen.dart';
import 'webview_screen.dart';

/// Full-screen main menu reachable from the hamburger button on the home
/// screen. Hosts exactly three navigation targets:
///   • Privacy Policy
///   • Support
///   • Paytable (combinations + line cost)
class MainMenuScreen extends StatelessWidget {
  final double currentBet;

  const MainMenuScreen({super.key, required this.currentBet});

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
                const SizedBox(height: 10),
                _buildTitle(),
                const SizedBox(height: 30),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 10,
                    ),
                    child: Column(
                      children: <Widget>[
                        _MenuCard(
                          icon: Icons.auto_awesome,
                          label: 'Paytable',
                          sub: 'Combinations & line cost',
                          accent: const Color(0xFFFFD54F),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  PaytableScreen(currentBet: currentBet),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _MenuCard(
                          icon: Icons.policy,
                          label: 'Privacy Policy',
                          sub: 'How we handle your data',
                          accent: const Color(0xFF4FD9FF),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const WebViewScreen(
                                title: 'Privacy Policy',
                                url: 'https://coinburstt.com/privacy-policy',
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _MenuCard(
                          icon: Icons.support_agent,
                          label: 'Support',
                          sub: 'Get help from our team',
                          accent: const Color(0xFFFF6EC7),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const WebViewScreen(
                                title: 'Support',
                                url: 'https://coinburstt.com/support',
                              ),
                            ),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
        ],
      ),
    );
  }

  Widget _buildTitle() {
    return const Center(
      child: Text(
        'MENU',
        style: TextStyle(
          color: Color(0xFFFFD54F),
          fontSize: 36,
          fontWeight: FontWeight.w900,
          letterSpacing: 10,
          shadows: <Shadow>[
            Shadow(color: Colors.black87, blurRadius: 6),
          ],
        ),
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sub;
  final Color accent;
  final VoidCallback onTap;

  const _MenuCard({
    required this.icon,
    required this.label,
    required this.sub,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: <Color>[Color(0xFF161F55), Color(0xFF0C1340)],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: accent, width: 2),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: accent.withValues(alpha: 0.35),
              blurRadius: 18,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withValues(alpha: 0.18),
                border: Border.all(color: accent, width: 2),
              ),
              child: Icon(icon, color: accent, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    label,
                    style: TextStyle(
                      color: accent,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: Colors.white54,
              size: 28,
            ),
          ],
        ),
      ),
    );
  }
}
