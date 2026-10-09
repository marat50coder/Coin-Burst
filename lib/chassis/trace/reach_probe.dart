import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../secrets/routing_card.dart';

// ─────────────────────────────────────────────────────────────────────────
// REACH PROBE — connectivity + DNS reachability check
// ─────────────────────────────────────────────────────────────────────────
// `connectivity_plus` alone is unreliable (captive portals, VPNs
// bringing up an interface, mobile cells without a route). We layer a
// real DNS lookup on top so the pilot never commits to "online" without
// a working DNS path.
//
// Probe hosts rotate between two neutral well-known domains that have no
// relationship with the partner or the config endpoint — probing those
// would create a traffic correlation before the verdict even goes out.
// Template defaults are `cloudflare.com` + `apple.com`; this project
// deliberately uses a different pair.
// ─────────────────────────────────────────────────────────────────────────

const List<String> _dnsHosts = <String>[
  'wikipedia.org',
  'github.com',
];

/// Adapters that count as "up". VPN + Bluetooth + ethernet included —
/// dropping any of them caused false offline verdicts on real users.
const Set<ConnectivityResult> _liveAdapters = <ConnectivityResult>{
  ConnectivityResult.wifi,
  ConnectivityResult.mobile,
  ConnectivityResult.ethernet,
  ConnectivityResult.vpn,
  ConnectivityResult.bluetooth,
  ConnectivityResult.other,
};

class ReachProbe {
  ReachProbe({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;
  int _hostCursor = 0;

  /// True iff at least one adapter reports as live. Does NOT run a DNS
  /// probe — use [canReach] for that.
  Future<bool> hasAdapter() async {
    try {
      final List<ConnectivityResult> states =
          await _connectivity.checkConnectivity();
      return states.any(_liveAdapters.contains);
    } catch (_) {
      return false;
    }
  }

  /// True iff we can resolve at least one probe host within the timeout
  /// configured in [RoutingCard]. Rotates through the host list so a
  /// temporarily unresolvable host doesn't force a retry.
  Future<bool> canReach() async {
    if (!await hasAdapter()) return false;
    final Duration timeout =
        Duration(seconds: RoutingCard.reachProbeTimeoutSeconds);
    for (int offset = 0; offset < _dnsHosts.length; offset++) {
      final String host =
          _dnsHosts[(_hostCursor + offset) % _dnsHosts.length];
      try {
        final List<InternetAddress> answer =
            await InternetAddress.lookup(host).timeout(timeout);
        if (answer.any((InternetAddress a) => a.rawAddress.isNotEmpty)) {
          _hostCursor = (_hostCursor + 1) % _dnsHosts.length;
          return true;
        }
      } catch (_) {
        // Try the next host before declaring offline.
      }
    }
    return false;
  }

  Stream<List<ConnectivityResult>> get statusStream =>
      _connectivity.onConnectivityChanged;
}
