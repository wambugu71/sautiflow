import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../videos/video_controller.dart';
import '../js_challenge.dart';
import 'ejs.dart';

/// Base class for EJS solvers that handles common caching and parsing logic.
/// Subclasses must implement [executeJavaScript] to provide the JS engine-specific execution.
abstract class BaseEJSSolver extends BaseJSChallengeSolver {
  // Caches
  final _playerCache = <String, String>{};
  final _sigCache = <(String, String, JSChallengeType), String>{};
  final _preprocPlayer = <String, String>{};

  /// Executes JavaScript code and returns the JSON string result.
  Future<String> executeJavaScript(String jsCode);

  @override
  Future<Map<String, String?>> solveBulk(
      String playerUrl, Map<JSChallengeType, List<String>> requests) async {
    // Filter out already cached challenges
    final uncachedRequests = <JSChallengeType, List<String>>{};
    final cachedResults = <String, String?>{};

    for (final entry in requests.entries) {
      final type = entry.key;
      final challenges = entry.value;
      final uncached = <String>[];

      for (final challenge in challenges) {
        final key = (playerUrl, challenge, type);
        if (_sigCache.containsKey(key)) {
          cachedResults[challenge] = _sigCache[key]!;
        } else {
          uncached.add(challenge);
        }
      }

      if (uncached.isNotEmpty) {
        uncachedRequests[type] = uncached;
      }
    }

    // If all challenges are cached, return early
    if (uncachedRequests.isEmpty) {
      return cachedResults;
    }

    // Get player script (from cache or fetch)
    late String playerScript;
    var isPreprocessed = false;
    if (_preprocPlayer.containsKey(playerUrl)) {
      playerScript = _preprocPlayer[playerUrl]!;
      isPreprocessed = true;
    } else if (_playerCache.containsKey(playerUrl)) {
      playerScript = _playerCache[playerUrl]!;
    } else if (VideoController.getCachedPlayerScript(playerUrl) != null) {
      playerScript = _playerCache[playerUrl] =
          VideoController.getCachedPlayerScript(playerUrl)!;
    } else {
      final resp = await http.get(Uri.parse(playerUrl));
      playerScript = _playerCache[playerUrl] = resp.body;
    }

    Future<Map<String, dynamic>> runJsc({required bool preproc}) async {
      final jsCall = EJSBuilder.buildJSCall(playerScript, uncachedRequests,
          isPreprocessed: preproc);
      final resultJson = await executeJavaScript(jsCall);
      return json.decode(resultJson) as Map<String, dynamic>;
    }

    var data = await runJsc(preproc: isPreprocessed);
    if (isPreprocessed && data['type'] != 'result') {
      _preprocPlayer.remove(playerUrl);
      if (_playerCache.containsKey(playerUrl)) {
        playerScript = _playerCache[playerUrl]!;
      } else {
        final resp = await http.get(Uri.parse(playerUrl));
        playerScript = _playerCache[playerUrl] = resp.body;
      }
      data = await runJsc(preproc: false);
    }

    if (data['type'] != 'result') {
      throw Exception('Unexpected response type: ${data['type']} (${data['error']})');
    }

    // Store preprocessed player if available
    if (data['preprocessed_player'] != null) {
      _preprocPlayer[playerUrl] = data['preprocessed_player'] as String;
    }

    // Process all responses
    final responses = data['responses'] as List;
    for (final response in responses) {
      if (response['type'] != 'result') {
        throw Exception('Unexpected item response type: ${response['type']}');
      }

      final responseData = response['data'] as Map<String, dynamic>;
      for (final entry in responseData.entries) {
        final challenge = entry.key;
        final decoded = entry.value as String?;

        // Find the type for this challenge
        JSChallengeType? challengeType;
        for (final typeEntry in uncachedRequests.entries) {
          if (typeEntry.value.contains(challenge)) {
            challengeType = typeEntry.key;
            break;
          }
        }

        if (challengeType != null) {
          final key = (playerUrl, challenge, challengeType);
          if (decoded != null) {
            _sigCache[key] = decoded;
            cachedResults[challenge] = decoded;
          } else {
            cachedResults[challenge] = null;
          }
        }
      }
    }

    return cachedResults;
  }

  @override
  Future<String> solve(
      String playerUrl, JSChallengeType type, String challenge) async {
    final key = (playerUrl, challenge, type);
    if (_sigCache.containsKey(key)) {
      return _sigCache[key]!;
    }

    final results = await solveBulk(playerUrl, {
      type: [challenge]
    });
    final decoded = results[challenge];
    if (decoded == null) {
      throw Exception('No data for challenge: $challenge');
    }
    return decoded;
  }
}
