import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

import '../trace/reach_probe.dart';

// ─────────────────────────────────────────────────────────────────────────
// OFFLINE SCENE — reached whenever the pilot concludes "no network"
// ─────────────────────────────────────────────────────────────────────────
// Pure Flutter chrome: no background artwork, just a dark gradient with
// the two copy lines on top. A connectivity watcher auto-returns the
// user to the exact page they lost connection on as soon as a reach
// probe confirms real DNS egress (not just a captive-portal adapter).
// ─────────────────────────────────────────────────────────────────────────

class OfflineScene extends StatefulWidget {
  const OfflineScene({super.key, required this.onRetryBuild});

  final WidgetBuilder onRetryBuild;

  @override
  State<OfflineScene> createState() => _OfflineSceneState();
}

class _OfflineSceneState extends State<OfflineScene> {
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  Timer? _probeDebounce;
  bool _resuming = false;

  @override
  void initState() {
    super.initState();
    // Any adapter flip (wifi/mobile/vpn) triggers a debounced reach probe —
    // the OS can briefly report "connected" while DNS is still broken on a
    // captive portal, so we never trust the raw stream alone.
    _connSub =
        ReachProbe().statusStream.listen((List<ConnectivityResult> states) {
      final bool anyAdapter = states.any(
        (ConnectivityResult s) => s != ConnectivityResult.none,
      );
      if (!anyAdapter) {
        _probeDebounce?.cancel();
        return;
      }
      _probeDebounce?.cancel();
      _probeDebounce =
          Timer(const Duration(milliseconds: 650), _confirmAndResume);
    });

    // Also run a probe on mount in case the connection recovered between
    // the pilot's drop-detection and the OfflineScene being pushed.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _confirmAndResume(),
    );
  }

  Future<void> _confirmAndResume() async {
    if (_resuming || !mounted) return;
    final bool online = await ReachProbe().canReach();
    if (!online || !mounted || _resuming) return;
    _resuming = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: widget.onRetryBuild),
    );
  }

  @override
  void dispose() {
    _probeDebounce?.cancel();
    _connSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;
    final bool landscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      backgroundColor: const Color(0xFF07040F),
      body: Container(
        width: size.width,
        height: size.height,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              Color(0xFF14091F),
              Color(0xFF0A0514),
              Color(0xFF1A0B2E),
            ],
            stops: <double>[0.0, 0.55, 1.0],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: size.width * (landscape ? 0.12 : 0.08),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    'NO INTERNET CONNECTION',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: const Color(0xFFFFE07A),
                      fontSize: landscape ? 22 : 26,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                      height: 1.15,
                      shadows: const <Shadow>[
                        Shadow(
                          color: Colors.black87,
                          blurRadius: 6,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: landscape ? 10 : 14),
                  Text(
                    'Check your connection and try again',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: const Color(0xFFEADFC9),
                      fontSize: landscape ? 14 : 16,
                      fontWeight: FontWeight.w500,
                      height: 1.35,
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
              ),
            ),
          ),
        ),
      ),
    );
  }
}
