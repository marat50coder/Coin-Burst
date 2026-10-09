import 'package:flutter/material.dart';

import '../secrets/routing_card.dart';
import '../secrets/sealed_blobs.dart';
import '../trace/signal_bus.dart';
import '../trace/vault.dart';
import 'burst_button.dart';
import 'portal_scene.dart';

// ─────────────────────────────────────────────────────────────────────────
// INVITE SCENE — one-shot push opt-in before the portal loads
// ─────────────────────────────────────────────────────────────────────────
// Only shown when `vault.shouldShowInvite` is true — first launch, or
// after the snooze window expired. Accept triggers the OS prompt;
// either tap forwards to the portal.
//
// Button design follows the slot theme (gold big action, dark gold-
// outlined secondary) via `burst_button.dart` — not the template's
// sky-blue pill.
// ─────────────────────────────────────────────────────────────────────────

class InviteScene extends StatefulWidget {
  const InviteScene({
    super.key,
    required this.vault,
    required this.signalBus,
    required this.landingUrl,
  });

  final SessionVault vault;
  final SignalBus signalBus;
  final String landingUrl;

  @override
  State<InviteScene> createState() => _InviteSceneState();
}

class _InviteSceneState extends State<InviteScene> {
  Future<void> _accept() async {
    final bool granted = await widget.signalBus.askForPermission();
    if (!granted) {
      await widget.vault.snoozeInvite(_snoozeMark());
    }
    if (mounted) _forward();
  }

  Future<void> _skip() async {
    await widget.vault.snoozeInvite(_snoozeMark());
    if (mounted) _forward();
  }

  int _snoozeMark() =>
      DateTime.now().millisecondsSinceEpoch ~/ 1000 +
      RoutingCard.inviteSnoozeSeconds;

  void _forward() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => PortalScene(
          url: widget.landingUrl,
          vault: widget.vault,
          signalBus: widget.signalBus,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;
    final Orientation orient = MediaQuery.of(context).orientation;
    final bool landscape = orient == Orientation.landscape;

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
          // Darken the lower third so the copy and buttons sit on a
          // readable backdrop regardless of the artwork.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.center,
                end: Alignment.bottomCenter,
                colors: <Color>[Colors.transparent, Color(0xCC000000)],
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
                  _InviteCopy(landscape: landscape),
                  SizedBox(height: landscape ? 14 : 22),
                  BurstBigButton(
                    label: unlockInviteAccept(),
                    width:
                        landscape ? size.width * 0.42 : size.width * 0.78,
                    compact: landscape,
                    onTap: _accept,
                  ),
                  SizedBox(height: landscape ? 10 : 14),
                  BurstGhostButton(
                    label: unlockInviteSkip(),
                    width:
                        landscape ? size.width * 0.42 : size.width * 0.78,
                    compact: landscape,
                    onTap: _skip,
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

class _InviteCopy extends StatelessWidget {
  const _InviteCopy({required this.landscape});

  final bool landscape;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          unlockInviteTitle(),
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
          unlockInviteBody(),
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
      ],
    );
  }
}
