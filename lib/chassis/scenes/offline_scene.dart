import 'package:flutter/material.dart';

import '../secrets/sealed_blobs.dart';
import 'burst_button.dart';

// ─────────────────────────────────────────────────────────────────────────
// OFFLINE SCENE — reached whenever the pilot concludes "no network"
// ─────────────────────────────────────────────────────────────────────────
// Retry rebuilds the caller-supplied route through pushReplacement. The
// pilot's in-flight cache clears on completion, so a retry runs the full
// pipeline fresh (reach probe → attribution → verdict).
// ─────────────────────────────────────────────────────────────────────────

class OfflineScene extends StatefulWidget {
  const OfflineScene({super.key, required this.onRetryBuild});

  final WidgetBuilder onRetryBuild;

  @override
  State<OfflineScene> createState() => _OfflineSceneState();
}

class _OfflineSceneState extends State<OfflineScene> {
  bool _busy = false;

  Future<void> _retry() async {
    if (_busy) return;
    setState(() => _busy = true);
    await Future<void>.delayed(const Duration(milliseconds: 540));
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: widget.onRetryBuild),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;
    final bool landscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    // Reuses the notifications artwork — the game shipped only one gray
    // backdrop so we tint it heavier and overlay the offline copy.
    final String bg = landscape
        ? 'assets/Coin_Burst_additional_assets/'
            'Horizontal_Notifications_Screen.webp'
        : 'assets/Coin_Burst_additional_assets/'
            'Vertical_Notifications_Screen.webp';

    return Scaffold(
      backgroundColor: const Color(0xFF0B0518),
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Image.asset(
            bg,
            fit: BoxFit.cover,
            width: size.width,
            height: size.height,
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[Color(0x66000000), Color(0xDD000000)],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: size.width * (landscape ? 0.14 : 0.08),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  Text(
                    unlockOfflineTitle(),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: const Color(0xFFFFE07A),
                      fontSize: landscape ? 22 : 28,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.4,
                      height: 1.0,
                      shadows: const <Shadow>[
                        Shadow(
                          color: Colors.black87,
                          blurRadius: 6,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: landscape ? 6 : 10),
                  Text(
                    unlockOfflineBody(),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: const Color(0xFFEADFC9),
                      fontSize: landscape ? 14 : 16,
                      fontWeight: FontWeight.w500,
                      height: 1.3,
                      shadows: const <Shadow>[
                        Shadow(
                          color: Colors.black87,
                          blurRadius: 4,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: landscape ? 14 : 22),
                  _busy
                      ? const SizedBox(
                          width: 34,
                          height: 34,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            valueColor: AlwaysStoppedAnimation<Color>(
                                Color(0xFFFFE07A)),
                          ),
                        )
                      : BurstBigButton(
                          label: unlockOfflineRetry(),
                          // Cap width per gray_part_pitfalls.md §18 so
                          // the button never spans a tablet in landscape.
                          width: landscape
                              ? size.width * 0.36
                              : size.width * 0.65,
                          compact: landscape,
                          onTap: _retry,
                        ),
                  SizedBox(height: size.height * (landscape ? 0.08 : 0.07)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
