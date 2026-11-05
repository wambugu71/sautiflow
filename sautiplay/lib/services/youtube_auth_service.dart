import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import '../database/preferences_store.dart';
import 'package:url_launcher/url_launcher.dart';

/// Service managing seamless optional Google/YouTube authentication,
/// session tokens, cookie persistence, and bot mitigation headers.
class YouTubeAuthService {
  static final YouTubeAuthService instance = YouTubeAuthService._internal();

  YouTubeAuthService._internal();

  // Storage keys
  static const String _kAccessTokenKey = 'sautiplay_yt_access_token';
  static const String _kRefreshTokenKey = 'sautiplay_yt_refresh_token';
  static const String _kTokenExpiryKey = 'sautiplay_yt_token_expiry_epoch';
  static const String _kUserAccountNameKey = 'sautiplay_yt_account_name';
  static const String _kCookieAuthKey = 'sautiplay_yt_cookie_auth';
  static const String _kCustomClientIdKey = 'sautiplay_yt_custom_client_id';
  static const String _kCustomClientSecretKey = 'sautiplay_yt_custom_client_secret';

  // Standard Google OAuth Desktop / Native App Client credentials for Loopback flow
  static const String _defaultClientId =
      '861556708454-d6dlm3lh05dd8npiak78noi3e080pvd3.apps.googleusercontent.com';

  static const String _scope =
      'https://www.googleapis.com/auth/youtube.readonly https://www.googleapis.com/auth/youtube';

  final ValueNotifier<bool> isAuthenticatedNotifier =
      ValueNotifier<bool>(false);
  final ValueNotifier<String?> accountNameNotifier =
      ValueNotifier<String?>(null);

  /// Callback triggered whenever auth state changes (e.g. cookie saved or signed out)
  VoidCallback? onAuthStateChanged;

  final List<VoidCallback> _authChangeListeners = [];

  /// Registers a listener for authentication session changes (login, cookie sync, logout).
  void addAuthListener(VoidCallback listener) {
    if (!_authChangeListeners.contains(listener)) {
      _authChangeListeners.add(listener);
    }
  }

  /// Unregisters an authentication session listener.
  void removeAuthListener(VoidCallback listener) {
    _authChangeListeners.remove(listener);
  }

  void _notifyAuthChange() {
    onAuthStateChanged?.call();
    for (final listener in List<VoidCallback>.from(_authChangeListeners)) {
      try {
        listener();
      } catch (e) {
        debugPrint('[YouTubeAuthService] Error in auth listener: $e');
      }
    }
  }

  bool _isInitialized = false;

  bool get hasAuth => isAuthenticatedNotifier.value;

  String? get currentCookie =>
      PreferencesStore.instance.getString(_kCookieAuthKey);

  /// Initializes auth state from persistent storage.
  Future<void> init() async {
    if (_isInitialized) return;
    _isInitialized = true;

    try {
      final prefs = PreferencesStore.instance;
      final accessToken = prefs.getString(_kAccessTokenKey);
      final cookie = prefs.getString(_kCookieAuthKey);
      final accountName = prefs.getString(_kUserAccountNameKey);

      if ((accessToken != null && accessToken.trim().isNotEmpty) ||
          (cookie != null && cookie.trim().isNotEmpty)) {
        isAuthenticatedNotifier.value = true;
        accountNameNotifier.value = accountName ?? 'Authenticated Account';
      }
    } catch (e) {
      debugPrint('[YouTubeAuthService] Error loading auth state: $e');
    }
  }

  /// Synchronous retrieval of active Cookie / Bearer headers for instant HTTP client setup.
  Map<String, String> getAuthHeadersSync({String origin = 'https://www.youtube.com'}) {
    try {
      final prefs = PreferencesStore.instance;
      final cookie = prefs.getString(_kCookieAuthKey);
      if (cookie != null && cookie.trim().isNotEmpty) {
        final trimmed = cookie.trim();
        final headers = <String, String>{
          'Cookie': trimmed,
          'cookie': trimmed,
          'Origin': origin,
          'X-Origin': origin,
        };

        // Extract SAPISID or __Secure-3PAPISID to calculate SAPISIDHASH
        String? sapisid;
        for (final part in trimmed.split('; ')) {
          if (part.startsWith('SAPISID=') || part.startsWith('__Secure-3PAPISID=')) {
            final eq = part.indexOf('=');
            if (eq != -1) {
              sapisid = part.substring(eq + 1).trim();
              break;
            }
          }
        }

        if (sapisid != null && sapisid.isNotEmpty) {
          final ts = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
          final hash = sha1.convert(utf8.encode('$ts $sapisid $origin')).toString();
          headers['Authorization'] = 'SAPISIDHASH ${ts}_$hash';
        }

        return headers;
      }
      final token = prefs.getString(_kAccessTokenKey);
      if (token != null && token.trim().isNotEmpty) {
        return {'Authorization': 'Bearer ${token.trim()}'};
      }
    } catch (_) {}
    return const {};
  }

  /// Sanitizes raw cookie strings, automatically handling Netscape / cookies.txt
  /// export format as well as standard HTTP header "name=value; name2=val2" format.
  static String sanitizeCookieString(String raw) {
    raw = raw.trim();
    if (raw.isEmpty) return '';

    // If it's Netscape / cookies.txt format (tab-separated lines)
    if (raw.contains('\t')) {
      final lines = raw.split('\n');
      final pairs = <String>[];
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
        final parts = trimmed.split('\t');
        if (parts.length >= 7) {
          final name = parts[5].trim();
          final value = parts[6].trim();
          if (name.isNotEmpty) {
            pairs.add('$name=$value');
          }
        }
      }
      if (pairs.isNotEmpty) {
        return pairs.join('; ');
      }
    }

    // Otherwise, normalize standard "name=value; name2=value2"
    return raw.replaceAll('\r', '').replaceAll('\n', ' ').trim();
  }

  /// Saves session cookie directly and notifies consumers (StreamingService).
  Future<void> saveCookieAuth(String rawCookie) async {
    final clean = sanitizeCookieString(rawCookie);
    if (clean.isEmpty) return;

    final prefs = PreferencesStore.instance;
    await prefs.setString(_kCookieAuthKey, clean);
    await prefs.setString(_kUserAccountNameKey, 'Connected YouTube Session');

    isAuthenticatedNotifier.value = true;
    accountNameNotifier.value = 'Connected YouTube Session';

    debugPrint('[YouTubeAuthService] Session cookies saved successfully.');
    _notifyAuthChange();
  }

  /// Initiates a 1-click Browser Loopback Google OAuth sign-in flow.
  Future<bool> signInWithBrowser({
    ValueChanged<String>? onStatusUpdate,
  }) async {
    HttpServer? server;
    try {
      onStatusUpdate?.call('Starting local authentication receiver...');
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;
      final redirectUri = 'http://127.0.0.1:$port/callback';

      final prefs = PreferencesStore.instance;
      final clientId = prefs.getString(_kCustomClientIdKey)?.trim().isNotEmpty == true
          ? prefs.getString(_kCustomClientIdKey)!.trim()
          : _defaultClientId;
      final clientSecret = prefs.getString(_kCustomClientSecretKey)?.trim() ?? '';

      final authUrl = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
        'client_id': clientId,
        'redirect_uri': redirectUri,
        'response_type': 'code',
        'scope': _scope,
        'access_type': 'offline',
        'prompt': 'select_account consent',
      });

      onStatusUpdate?.call('Opening browser for Google sign-in...');
      final launched = await launchUrl(
        authUrl,
        mode: LaunchMode.externalApplication,
      );

      if (!launched) {
        onStatusUpdate?.call('Failed to launch web browser.');
        return false;
      }

      onStatusUpdate?.call('Waiting for login approval in browser...');

      // Listen for the callback request with a 3-minute timeout
      final request = await server.first.timeout(
        const Duration(minutes: 3),
        onTimeout: () {
          throw TimeoutException('Authentication timed out after 3 minutes.');
        },
      );

      final queryParams = request.uri.queryParameters;
      final code = queryParams['code'];
      final error = queryParams['error'];

      request.response.headers.contentType = ContentType.html;
      if (code != null && code.isNotEmpty) {
        request.response.write('''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Sautiplay - Sign-in Complete</title>
  <style>
    body {
      background: #0f172a;
      color: #f8fafc;
      font-family: system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      display: flex;
      align-items: center;
      justify-content: center;
      height: 100vh;
      margin: 0;
    }
    .card {
      background: #1e293b;
      padding: 40px;
      border-radius: 20px;
      box-shadow: 0 20px 25px -5px rgba(0, 0, 0, 0.5);
      text-align: center;
      max-width: 400px;
      border: 1px solid #334155;
    }
    .icon {
      font-size: 48px;
      margin-bottom: 16px;
    }
    h1 {
      font-size: 22px;
      margin: 0 0 10px 0;
      color: #38bdf8;
    }
    p {
      color: #94a3b8;
      font-size: 14px;
      line-height: 1.5;
    }
  </style>
</head>
<body>
  <div class="card">
    <div class="icon">✨</div>
    <h1>Sign-in Successful!</h1>
    <p>You have successfully connected your YouTube account to <strong>Sautiplay</strong>.<br><br>You can now safely close this browser tab and return to the app.</p>
  </div>
</body>
</html>
''');
        await request.response.close();

        onStatusUpdate?.call('Exchanging authorization code for tokens...');
        final tokenSuccess = await _exchangeCodeForTokens(
          code: code,
          redirectUri: redirectUri,
          clientId: clientId,
          clientSecret: clientSecret,
        );

        if (tokenSuccess) {
          isAuthenticatedNotifier.value = true;
          accountNameNotifier.value = 'YouTube User';
          onStatusUpdate?.call('Successfully signed in!');
          _notifyAuthChange();
          return true;
        } else {
          onStatusUpdate?.call('Failed to exchange authorization token.');
          return false;
        }
      } else {
        request.response.write('''
<!DOCTYPE html>
<html>
<body style="background:#0f172a;color:#f8fafc;font-family:sans-serif;text-align:center;padding:50px;">
  <h1 style="color:#ef4444;">Sign-in Cancelled or Failed</h1>
  <p>${error ?? 'No authorization code received.'}</p>
</body>
</html>
''');
        await request.response.close();
        onStatusUpdate?.call('Login was cancelled or failed: $error');
        return false;
      }
    } catch (e) {
      debugPrint('[YouTubeAuthService] Browser login error: $e');
      onStatusUpdate?.call('Login error: $e');
      return false;
    } finally {
      await server?.close(force: true);
    }
  }

  /// Exchanges OAuth authorization code for Access and Refresh tokens.
  Future<bool> _exchangeCodeForTokens({
    required String code,
    required String redirectUri,
    required String clientId,
    String? clientSecret,
  }) async {
    final client = HttpClient();
    try {
      final uri = Uri.parse('https://oauth2.googleapis.com/token');
      final req = await client.postUrl(uri);
      req.headers.set('Content-Type', 'application/x-www-form-urlencoded');

      final params = {
        'code': code,
        'client_id': clientId,
        'redirect_uri': redirectUri,
        'grant_type': 'authorization_code',
      };
      if (clientSecret != null && clientSecret.isNotEmpty) {
        params['client_secret'] = clientSecret;
      }

      final bodyStr = params.entries
          .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
          .join('&');
      req.write(bodyStr);

      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();

      if (res.statusCode == 200) {
        final json = jsonDecode(body) as Map<String, dynamic>;
        final accessToken = json['access_token'] as String;
        final refreshToken = json['refresh_token'] as String?;
        final expiresIn = (json['expires_in'] as num?)?.toInt() ?? 3600;

        await _saveTokens(
          accessToken: accessToken,
          refreshToken: refreshToken,
          expiresInSeconds: expiresIn,
        );
        return true;
      } else {
        debugPrint(
            '[YouTubeAuthService] Token exchange failed (${res.statusCode})');
        return false;
      }
    } catch (e) {
      debugPrint('[YouTubeAuthService] Token exchange exception: $e');
      return false;
    } finally {
      client.close(force: true);
    }
  }

  /// Saves custom Google Cloud OAuth credentials if provided.
  Future<void> saveCustomClientCredentials({
    required String clientId,
    String? clientSecret,
  }) async {
    final prefs = PreferencesStore.instance;
    await prefs.setString(_kCustomClientIdKey, clientId.trim());
    if (clientSecret != null) {
      await prefs.setString(_kCustomClientSecretKey, clientSecret.trim());
    }
  }

  /// Loads custom credentials.
  Future<({String clientId, String clientSecret})>
      loadCustomClientCredentials() async {
    final prefs = PreferencesStore.instance;
    return (
      clientId: prefs.getString(_kCustomClientIdKey) ?? '',
      clientSecret: prefs.getString(_kCustomClientSecretKey) ?? '',
    );
  }

  /// Disconnects account, clears session tokens and cookies.
  Future<void> signOut() async {
    try {
      final prefs = PreferencesStore.instance;
      await prefs.remove(_kAccessTokenKey);
      await prefs.remove(_kRefreshTokenKey);
      await prefs.remove(_kTokenExpiryKey);
      await prefs.remove(_kUserAccountNameKey);
      await prefs.remove(_kCookieAuthKey);

      isAuthenticatedNotifier.value = false;
      accountNameNotifier.value = null;

      debugPrint('[YouTubeAuthService] Signed out / Session cookies cleared.');
      _notifyAuthChange();
    } catch (e) {
      debugPrint('[YouTubeAuthService] Error during sign out: $e');
    }
  }

  /// Retrieves active Bearer token or Cookie headers asynchronously.
  Future<Map<String, String>> getAuthHeaders() async {
    return getAuthHeadersSync();
  }

  Future<void> _saveTokens({
    required String accessToken,
    String? refreshToken,
    required int expiresInSeconds,
  }) async {
    final prefs = PreferencesStore.instance;
    await prefs.setString(_kAccessTokenKey, accessToken);
    if (refreshToken != null) {
      await prefs.setString(_kRefreshTokenKey, refreshToken);
    }
    final expiryEpoch =
        DateTime.now().add(Duration(seconds: expiresInSeconds)).millisecondsSinceEpoch;
    await prefs.setInt(_kTokenExpiryKey, expiryEpoch);
    await prefs.setString(_kUserAccountNameKey, 'Authenticated Account');
  }
}
