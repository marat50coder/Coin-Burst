import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../secrets/routing_card.dart';
import '../trace/fingerprint.dart';
import '../trace/overlay_scripts.dart';
import '../trace/reach_probe.dart';
import '../trace/signal_bus.dart';
import '../trace/vault.dart';
import 'offline_scene.dart';

// ─────────────────────────────────────────────────────────────────────────
// PORTAL SCENE — WebView shell for the gray-part content
// ─────────────────────────────────────────────────────────────────────────
// Hosts the destination URL with:
//   • Forged UA (identical between the Rust POST and this WebView)
//   • Both orientations + immersive system UI
//   • External-scheme hand-off (tel: / mailto: / intent: / market:)
//   • Redirect-loop recovery with a bounded retry
//   • Debounced live connectivity guard
//   • Warm push URL delivery via `SignalBus.onIncomingUrl`
//   • Native file chooser via MethodChannel (no file_picker dep)
//   • OverlayScripts injected on every `onPageFinished`
//
// Zero client-side classification of partner pages (no deposit /
// cashier / register / login regex). Any funnel logic lives server-side.
// ─────────────────────────────────────────────────────────────────────────

class PortalScene extends StatefulWidget {
  const PortalScene({
    super.key,
    required this.url,
    required this.vault,
    required this.signalBus,
  });

  final String url;
  final SessionVault vault;
  final SignalBus signalBus;

  @override
  State<PortalScene> createState() => _PortalSceneState();
}

class _PortalSceneState extends State<PortalScene>
    with WidgetsBindingObserver {
  late final WebViewController _controller;
  bool _spinner = true;
  bool _offlineGate = false;
  String? _mainFrameUrl;
  int _redirectAttempts = 0;
  Timer? _dropDebounce;
  StreamSubscription<List<ConnectivityResult>>? _connSub;

  // Methodchannel name is a per-project token; must match
  // MainActivity.kt → `pickerChannelName`.
  static const MethodChannel _picker = MethodChannel('kqz/picker');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _enterImmersive();
    _buildController();

    widget.signalBus.onIncomingUrl = (String url) {
      if (mounted) _controller.loadRequest(Uri.parse(url));
    };

    _connSub =
        ReachProbe().statusStream.listen((List<ConnectivityResult> states) {
      final bool allNone = states.isNotEmpty &&
          states.every((ConnectivityResult s) => s == ConnectivityResult.none);
      if (!allNone) {
        _dropDebounce?.cancel();
        return;
      }
      _dropDebounce?.cancel();
      _dropDebounce = Timer(
        Duration(milliseconds: RoutingCard.reachDropDebounceMs),
        _showOffline,
      );
    });
  }

  void _enterImmersive() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: const <SystemUiOverlay>[SystemUiOverlay.bottom],
    );
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
      systemNavigationBarContrastEnforced: false,
    ));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _enterImmersive();
  }

  void _buildController() {
    final String ua = DeviceFingerprint.userAgent;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..enableZoom(false);
    if (ua.isNotEmpty) {
      _controller.setUserAgent(ua);
    }
    _controller.setNavigationDelegate(NavigationDelegate(
      onPageStarted: (_) {
        if (mounted) setState(() => _spinner = true);
      },
      onPageFinished: (_) {
        if (mounted) setState(() => _spinner = false);
        _redirectAttempts = 0;
        OverlayScripts.installAll(_controller);
      },
      onWebResourceError: _onError,
      onNavigationRequest: _onNavigate,
    ));

    _configureAndroidChrome();
    _controller.loadRequest(Uri.parse(widget.url));
  }

  void _onError(WebResourceError err) {
    if (err.isForMainFrame != true) return;
    final String desc = err.description.toLowerCase();

    final bool isLoop = desc.contains('too_many_redirects') ||
        desc.contains('too many redirects') ||
        err.errorCode == -1007 ||
        err.errorCode == -9;

    if (isLoop &&
        _mainFrameUrl != null &&
        _redirectAttempts < RoutingCard.redirectLoopRetries) {
      _redirectAttempts++;
      _controller.loadRequest(Uri.parse(_mainFrameUrl!));
      return;
    }

    // Cover the WebView with the spinner IMMEDIATELY so the native
    // Android error page never flashes — see gray_part_pitfalls.md §4.
    if (mounted) setState(() => _spinner = true);

    final bool isConnectivity = desc.contains('name_not_resolved') ||
        desc.contains('address_unreachable') ||
        desc.contains('internet_disconnected') ||
        desc.contains('network_changed') ||
        err.errorCode == -105 ||
        err.errorCode == -106 ||
        err.errorCode == -21 ||
        err.errorCode == -2 ||
        err.errorCode == -6;

    if (isConnectivity) {
      _showOffline();
    } else {
      _guardWithProbe();
    }
  }

  NavigationDecision _onNavigate(NavigationRequest req) {
    final Uri? uri = Uri.tryParse(req.url);
    if (uri == null) return NavigationDecision.prevent;
    const Set<String> inApp = <String>{
      'http',
      'https',
      'about',
      'data',
      'blob',
    };
    if (inApp.contains(uri.scheme)) {
      if (req.isMainFrame) _mainFrameUrl = req.url;
      return NavigationDecision.navigate;
    }
    _handoffExternally(uri);
    return NavigationDecision.prevent;
  }

  void _configureAndroidChrome() {
    if (!Platform.isAndroid) return;
    if (_controller.platform is! AndroidWebViewController) return;
    final AndroidWebViewController controller =
        _controller.platform as AndroidWebViewController;

    controller.setMediaPlaybackRequiresUserGesture(false);
    controller.setOnPlatformPermissionRequest(
      (PlatformWebViewPermissionRequest r) => r.grant(),
    );
    controller.setOnShowFileSelector(_pickFiles);

    final AndroidWebViewCookieManager cookies = AndroidWebViewCookieManager(
      AndroidWebViewCookieManagerCreationParams
          .fromPlatformWebViewCookieManagerCreationParams(
        const PlatformWebViewCookieManagerCreationParams(),
      ),
    );
    cookies.setAcceptThirdPartyCookies(controller, true);
  }

  Future<List<String>> _pickFiles(FileSelectorParams params) async {
    try {
      final List<Object?>? picked = await _picker
          .invokeMethod<List<Object?>>('pick', <String, Object>{
        'multiple': params.mode == FileSelectorMode.openMultiple,
        'mimeTypes': params.acceptTypes
            .where((String t) => t.trim().isNotEmpty)
            .toList(),
      });
      if (picked == null) return const <String>[];
      return picked.whereType<String>().toList();
    } catch (_) {
      return const <String>[];
    }
  }

  Future<void> _handoffExternally(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Future<void> _guardWithProbe() async {
    if (_offlineGate) return;
    final bool online = await ReachProbe().canReach();
    if (online) return;
    _showOffline();
  }

  void _showOffline() {
    if (_offlineGate || !mounted) return;
    _offlineGate = true;
    final String current = _mainFrameUrl ?? widget.url;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => OfflineScene(
          onRetryBuild: (_) => PortalScene(
            url: current,
            vault: widget.vault,
            signalBus: widget.signalBus,
          ),
        ),
      ),
    );
  }

  Future<void> _stepBack() async {
    if (await _controller.canGoBack()) await _controller.goBack();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dropDebounce?.cancel();
    _connSub?.cancel();
    widget.signalBus.onIncomingUrl = null;
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool landscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, _) async {
        if (!didPop) await _stepBack();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: false,
        body: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Padding(
              // Apply viewPadding on both axes so a punch-hole camera on
              // either long edge in landscape doesn't swallow content —
              // see gray_part_pitfalls.md §14.
              padding: MediaQuery.viewPaddingOf(context),
              child: WebViewWidget(controller: _controller),
            ),
            if (_spinner && !landscape)
              const ColoredBox(
                color: Color(0x80000000),
                child: Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(
                        Color(0xFFFFE07A)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
