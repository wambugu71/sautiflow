import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// On-device JavaScript Challenge Solver for mobile platforms (Android & iOS).
///
/// Uses a headless [WebViewController] to evaluate yt-dlp/ejs challenges
/// inside the mobile OS's native JS engine (V8 on Android, JavaScriptCore on iOS)
/// without requiring Node.js, Deno, or an external fallback server.
class WebViewEJSSolver extends BaseEJSSolver {
  final WebViewController _controller;

  WebViewEJSSolver._(this._controller);

  /// Initializes the WebView solver with pre-bundled EJS modules.
  /// Returns null if not on Android or iOS, or if initialization fails.
  static Future<WebViewEJSSolver?> tryInit() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      return null;
    }

    try {
      debugPrint('[WebViewEJSSolver] Initializing mobile JS engine...');
      final modules = await EJSBuilder.getJSModules();

      final pageReadyCompleter = Completer<void>();
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageFinished: (url) {
              if (!pageReadyCompleter.isCompleted) {
                pageReadyCompleter.complete();
              }
            },
            onWebResourceError: (error) {
              debugPrint('[WebViewEJSSolver] Web resource notice: ${error.description}');
            },
          ),
        );

      // Load a clean local HTML scaffold with no remote baseUrl to prevent network latency
      await controller.loadHtmlString('<!DOCTYPE html><html><head></head><body></body></html>');
      await pageReadyCompleter.future.timeout(const Duration(seconds: 3));

      // Inject the pre-bundled EJS modules directly into the JavaScript runtime
      await controller.runJavaScript(modules);

      // Quick verification that jsc() is defined
      final check = await controller.runJavaScriptReturningResult("typeof jsc === 'function'").timeout(const Duration(seconds: 2));
      final isFunction = check.toString().contains('true') || check.toString().contains('function');
      if (isFunction) {
        debugPrint('[WebViewEJSSolver] ✓ Mobile WebView solver initialized and ready.');
        return WebViewEJSSolver._(controller);
      } else {
        debugPrint('[WebViewEJSSolver] Notice: jsc function check returned: $check');
        return null;
      }
    } catch (e) {
      debugPrint('[WebViewEJSSolver] Mobile WebView solver skipped (using direct visionOS): $e');
      return null;
    }
  }

  @override
  Future<String> executeJavaScript(String jsCode) async {
    final wrapped = '''
(() => {
  try {
    return $jsCode;
  } catch (err) {
    return JSON.stringify({ error: String(err) });
  }
})()
''';

    final raw = await _controller.runJavaScriptReturningResult(wrapped);
    return _cleanResult(raw);
  }

  static String _cleanResult(Object? raw) {
    if (raw == null) {
      throw Exception('WebView returned null evaluation result');
    }
    if (raw is String) {
      var str = raw.trim();
      // Handle JSON-stringified string wrappers from Android evaluateJavascript
      if (str.startsWith('"') && str.endsWith('"') && str.length > 1) {
        try {
          final decoded = jsonDecode(str);
          if (decoded is String) return decoded;
        } catch (_) {}
      }
      return str;
    }
    return jsonEncode(raw);
  }
}
