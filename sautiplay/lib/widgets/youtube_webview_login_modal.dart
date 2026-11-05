import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/youtube_auth_service.dart';

/// In-app WebView modal that allows users to sign in to their Google/YouTube
/// account directly within the application and automatically intercepts
/// the session cookies upon successful sign-in.
class YouTubeWebViewLoginModal extends StatefulWidget {
  const YouTubeWebViewLoginModal({super.key});

  /// Convenience helper to display the login modal.
  static Future<bool?> show(BuildContext context) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: false,
      builder: (context) => const YouTubeWebViewLoginModal(),
    );
  }

  @override
  State<YouTubeWebViewLoginModal> createState() =>
      _YouTubeWebViewLoginModalState();
}

class _YouTubeWebViewLoginModalState extends State<YouTubeWebViewLoginModal> {
  late final WebViewController _controller;
  final WebViewCookieManager _cookieManager = WebViewCookieManager();

  int _progress = 0;
  bool _isLoading = true;
  bool _isSuccess = false;
  String? _statusText;

  // Custom User-Agent to prevent Google's "403: disallowed_useragent" WebView block
  static String get _customUserAgent {
    if (!kIsWeb && Platform.isIOS) {
      return 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1';
    }
    return 'Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.6723.107 Mobile Safari/537.36';
  }

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(_customUserAgent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (mounted) setState(() => _progress = progress);
          },
          onPageStarted: (url) {
            if (mounted) setState(() => _isLoading = true);
            _checkIfAuthenticated(url);
          },
          onPageFinished: (url) {
            if (mounted) {
              setState(() {
                _isLoading = false;
                _progress = 100;
              });
            }
            _checkIfAuthenticated(url);
          },
          onNavigationRequest: (request) {
            _checkIfAuthenticated(request.url);
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(
        Uri.parse(
          'https://accounts.google.com/ServiceLogin?service=youtube&continue=https%3A%2F%2Fm.youtube.com%2F',
        ),
      );
  }

  /// Inspects cookies when the user navigates back to YouTube.
  Future<void> _checkIfAuthenticated(String url) async {
    if (_isSuccess) return;

    final uri = Uri.tryParse(url);
    if (uri == null) return;

    // Trigger check whenever user is on youtube.com domain
    final isYouTube = uri.host.endsWith('youtube.com');
    final isAuthPage = uri.path.contains('ServiceLogin') ||
        uri.path.contains('signin') ||
        uri.host.contains('accounts.google');

    if (isYouTube && !isAuthPage) {
      try {
        final domains = [
          Uri.parse('https://m.youtube.com'),
          Uri.parse('https://www.youtube.com'),
          Uri.parse('https://music.youtube.com'),
          Uri.parse('https://youtube.com'),
          Uri.parse('https://accounts.google.com'),
          Uri.parse('https://google.com'),
        ];

        final Map<String, String> merged = {};
        for (final domain in domains) {
          try {
            final cookies = await _cookieManager.getCookies(domain: domain);
            for (final c in cookies) {
              if (c.name.isNotEmpty && c.value.isNotEmpty) {
                merged[c.name] = c.value;
              }
            }
          } catch (_) {}
        }

        try {
          final jsCookies = await _controller.runJavaScriptReturningResult('document.cookie');
          if (jsCookies is String && jsCookies.isNotEmpty) {
            final clean = jsCookies.replaceAll('"', '').trim();
            for (final part in clean.split(';')) {
              final eq = part.indexOf('=');
              if (eq > 0) {
                merged.putIfAbsent(
                  part.substring(0, eq).trim(),
                  () => part.substring(eq + 1).trim(),
                );
              }
            }
          }
        } catch (_) {}

        if (merged.containsKey('LOGIN_INFO') ||
            merged.containsKey('SAPISID') ||
            merged.containsKey('__Secure-3PAPISID') ||
            merged.containsKey('SID')) {
          _isSuccess = true;
          final cookieStr =
              merged.entries.map((e) => '${e.key}=${e.value}').join('; ');

          await YouTubeAuthService.instance.saveCookieAuth(cookieStr);

          if (mounted) {
            setState(() {
              _statusText = '✓ Successfully connected to YouTube!';
            });
            await Future.delayed(const Duration(milliseconds: 900));
            if (mounted) Navigator.of(context).pop(true);
          }
        }
      } catch (e) {
        debugPrint('[WebViewLogin] Error extracting cookies: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);
    final insets = MediaQuery.viewInsetsOf(context);

    return Padding(
      padding: EdgeInsets.only(bottom: insets.bottom),
      child: Container(
        height: size.height * 0.92,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              // Drag handle
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Sign in to YouTube',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            _statusText ?? 'Session cookies are captured automatically upon sign in',
                            style: TextStyle(
                              fontSize: 11,
                              color: _isSuccess
                                  ? Colors.greenAccent
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                if (_isLoading && !_isSuccess)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),

          // Progress indicator
          if (_progress < 100 && !_isSuccess)
            LinearProgressIndicator(
              value: _progress / 100.0,
              minHeight: 2.5,
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
            ),

          // WebView Area
          Expanded(
            child: Stack(
              children: [
                WebViewWidget(controller: _controller),
                if (_isSuccess)
                  Container(
                    color: Colors.black.withValues(alpha: 0.85),
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.check_circle_rounded,
                          color: Colors.greenAccent,
                          size: 56,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Connected to YouTube!',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Session cookies captured. Stream bot immunity is active.',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  ),
);
  }
}
