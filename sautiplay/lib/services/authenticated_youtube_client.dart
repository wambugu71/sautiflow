import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'youtube_auth_service.dart';

/// Custom [YoutubeHttpClient] that dynamically injects authenticated user cookies
/// and headers from [YouTubeAuthService] into every YouTube Explode request.
class AuthenticatedYoutubeHttpClient extends YoutubeHttpClient {
  AuthenticatedYoutubeHttpClient([super.httpClient]);

  @override
  Map<String, String> get headers {
    final baseHeaders = super.headers;
    final authHeaders = YouTubeAuthService.instance.getAuthHeadersSync();

    final cookie = authHeaders['Cookie'];
    if (cookie != null && cookie.isNotEmpty) {
      final defaultCookies = baseHeaders['cookie'] ?? 'PREF=hl=en&tz=UTC; SOCS=CAI; GPS=1';
      final mergedCookie = '$cookie; $defaultCookies';
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
