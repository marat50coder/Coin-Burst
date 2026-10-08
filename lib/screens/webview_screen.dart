import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class WebViewScreen extends StatefulWidget {
  final String title;
  final String url;

  /// User-Agent to install on the WebView before loading [url]. Primary
  /// use case: the gray-part branch needs the exact same UA that the Rust
  /// gateway used for the `/edge/sync` POST so the upstream fingerprint
  /// stays consistent across the two legs.
  final String? userAgent;

  /// When true, the AppBar is hidden entirely and the content fills the
  /// whole screen. Used by the gray-part landing so the WebView looks
  /// like a stand-alone page instead of a tab inside the game.
  final bool fullScreen;

  const WebViewScreen({
    super.key,
    required this.title,
    required this.url,
    this.userAgent,
    this.fullScreen = false,
  });

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF07091E));
    final ua = widget.userAgent;
    if (ua != null && ua.isNotEmpty) {
      _controller.setUserAgent(ua);
    }
    _controller
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (WebResourceError err) {
            if (!mounted) return;
            // Only report main-frame failures to avoid false positives.
            if (err.isForMainFrame ?? true) {
              setState(() {
                _loading = false;
                _error = true;
              });
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF07091E),
      appBar: widget.fullScreen
          ? null
          : AppBar(
              backgroundColor: const Color(0xFF0C1033),
              foregroundColor: Colors.white,
              title: Text(
                widget.title,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              iconTheme: const IconThemeData(color: Color(0xFFFFD54F)),
            ),
      body: Stack(
        children: [
          if (!_error) WebViewWidget(controller: _controller),
          if (_loading && !_error)
            const Center(
              child: CircularProgressIndicator(
                color: Color(0xFFFFD54F),
              ),
            ),
          if (_error)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.wifi_off,
                        color: Color(0xFFFFD54F), size: 56),
                    const SizedBox(height: 10),
                    const Text(
                      'Unable to load the page.\nPlease check your connection.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _error = false;
                          _loading = true;
                        });
                        _controller.loadRequest(Uri.parse(widget.url));
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFD54F),
                        foregroundColor: Colors.black,
                      ),
                      child: const Text('RETRY'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
