import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'youtube_auth_service.dart';

/// Custom [YoutubeHttpClient] that dynamically injects authenticated user cookies
/// and headers from [YouTubeAuthService] into every YouTube Explode request.
class AuthenticatedYoutubeHttpClient extends YoutubeHttpClient {
  AuthenticatedYoutubeHttpClient([super.httpClient]);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await super.send(request);
    final setCookie =
        response.headers['set-cookie'] ?? response.headers['Set-Cookie'];
    if (setCookie != null && setCookie.isNotEmpty) {
      YouTubeAuthService.instance.updateCookiesFromSetCookieHeader(setCookie);
    }
    return response;
  }

  @override
  Map<String, String> get headers {
    final baseHeaders = super.headers;
    final authHeaders = YouTubeAuthService.instance.getAuthHeadersSync();

    final cookie = authHeaders['Cookie'];
    if (cookie != null && cookie.isNotEmpty) {
      final defaultCookies = 'PREF=hl=en&tz=UTC; SOCS=CAI; GPS=1';
      // Merge by name; user's session cookies win over defaults.
      final map = <String, String>{};
      for (final src in [cookie, defaultCookies]) {
        for (final part in src.split(';')) {
          final eq = part.indexOf('=');
          if (eq <= 0) continue;
          map.putIfAbsent(
              part.substring(0, eq).trim(), () => part.substring(eq + 1).trim());
        }
      }
      final mergedCookie =
          map.entries.map((e) => '${e.key}=${e.value}').join('; ');
      return {
        ...baseHeaders,
        ...authHeaders,
        'Cookie': mergedCookie,
        'cookie': mergedCookie,
      };
    }

    return {
      ...baseHeaders,
      ...authHeaders,
    };
  }
}
