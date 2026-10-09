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
// Shown when `vault.shouldShowInvite` is true — first launch, or after
// the snooze window expired. Accept triggers the OS prompt; either tap
// forwards to the portal.
//
// Layout:
//   • No overlay copy — the artwork already carries the headline / sub.
//   • Portrait: Accept + Skip stacked vertically.
//   • Landscape: Accept + Skip side-by-side on a single row, each pill
//                is half-width (2× narrower than the single-column
//                variant used in portrait). Aligned on the SAME Y so a
//                single visual baseline — the Skip label row — carries
//                both actions.
//   • Everything lives above the system nav bar via `SafeArea`.
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
          SafeArea(
            child: landscape
                ? _buildLandscape(size)
                : _buildPortrait(size),
          ),
        ],
      ),
    );
  }

  // ── Portrait ────────────────────────────────────────────────────
  // Stacked column pinned near the bottom. No overlay copy.
  Widget _buildPortrait(Size size) {
    final double buttonWidth = size.width * 0.78;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: size.width * 0.08),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          BurstBigButton(
            label: unlockInviteAccept(),
            width: buttonWidth,
            onTap: _accept,
          ),
          const SizedBox(height: 14),
          BurstGhostButton(
            label: unlockInviteSkip(),
            width: buttonWidth,
            onTap: _skip,
          ),
          SizedBox(height: size.height * 0.07),
        ],
      ),
    );
  }

  // ── Landscape ───────────────────────────────────────────────────
  // Accept + Skip side-by-side on one row, each 2× narrower than the
  // portrait variant. Positioned so the Skip pill is roughly where the
  // artwork expects the primary action row.
  Widget _buildLandscape(Size size) {
    // Portrait pill width is `size.width * 0.42`. Half of that keeps
    // visual balance when both buttons live on a single row.
    final double buttonWidth = size.width * 0.21;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: size.width * 0.1),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              BurstBigButton(
                label: unlockInviteAccept(),
                width: buttonWidth,
                compact: true,
                onTap: _accept,
              ),
              const SizedBox(width: 18),
              BurstGhostButton(
                label: unlockInviteSkip(),
                width: buttonWidth,
                compact: true,
                onTap: _skip,
              ),
            ],
          ),
          SizedBox(height: size.height * 0.1),
        ],
      ),
    );
  }
}
