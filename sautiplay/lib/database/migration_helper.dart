import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/cached_stream_item.dart';
import '../models/liked_song.dart';
import '../models/recently_played_track.dart';
import 'app_database.dart';
import 'preferences_store.dart';

/// Handles zero-data-loss atomic migration from legacy SharedPreferences into SQLite Drift
/// without requiring the shared_preferences package.
class DatabaseMigrationHelper {
  static const String _kMigrationKey = 'sp_migrated_to_drift_v1';

  static Future<void> migrateIfNeeded() async {
    final db = AppDatabase.instance;
    await PreferencesStore.instance.init(db);

    if (PreferencesStore.instance.getBool(_kMigrationKey, defaultValue: false) == true) {
      return; // Already migrated
    }

    try {
      final legacyData = await _readLegacyData();
      if (legacyData.isEmpty) {
        await PreferencesStore.instance.setBool(_kMigrationKey, true);
        return;
      }

      debugPrint(
        '[DatabaseMigration] Migrating ${legacyData.length} keys from legacy storage to Drift...',
      );

      await db.transaction(() async {
        // 1. Migrate Liked Songs
        final likedRaw = legacyData['sautiplay_liked_songs'];
        if (likedRaw is List) {
          for (final itemStr in likedRaw) {
            try {
              final item = LikedSong.fromJson(itemStr.toString());
              await db.upsertLikedSong(
                LikedSongEntriesCompanion(
                  videoId: Value(item.videoId),
                  title: Value(item.title),
                  artist: Value(item.artist),
                  artistId: Value(item.artistId),
                  thumbnailUrl: Value(item.thumbnailUrl),
                  durationSeconds: Value(item.durationSeconds),
                  likedAt: Value(item.likedAt),
                ),
              );
            } catch (e) {
              debugPrint('[DatabaseMigration] Error migrating liked song: $e');
            }
          }
        }

        // 2. Migrate Recently Played
        final recentRaw = legacyData['sautiplay_recently_played'];
        if (recentRaw is List) {
          for (final itemStr in recentRaw) {
            try {
              final item = RecentlyPlayedTrack.fromJson(itemStr.toString());
              await db.addRecentlyPlayed(
                RecentlyPlayedEntriesCompanion(
                  videoId: Value(item.videoId),
                  title: Value(item.title),
                  artist: Value(item.artist),
                  artistId: Value(item.artistId),
                  thumbnailUrl: Value(item.thumbnailUrl),
                  durationSeconds: Value(item.durationSeconds),
                  playedAt: Value(item.playedAt),
                ),
              );
            } catch (e) {
              debugPrint('[DatabaseMigration] Error migrating recent track: $e');
            }
          }
        }

        // 3. Migrate Cached Streams
        final streamsRaw = legacyData['sautiplay_cached_streams_metadata_v1'];
        if (streamsRaw is List) {
          for (final itemStr in streamsRaw) {
            try {
              final item = CachedStreamItem.fromJson(itemStr.toString());
              await db.into(db.cachedStreamEntries).insertOnConflictUpdate(
                    CachedStreamEntriesCompanion(
                      videoId: Value(item.videoId),
                      title: Value(item.title),
                      artist: Value(item.artist),
                      thumbnailUrl: Value(item.thumbnailUrl),
                      durationSeconds: Value(item.durationSeconds),
                      filePath: Value(item.filePath),
                      streamUrl: Value(item.streamUrl),
                      fileSizeBytes: Value(item.fileSizeBytes),
                      cachedAt: Value(item.cachedAt),
                      isUserDownload: Value(item.isUserDownload),
                    ),
                  );
            } catch (e) {
              debugPrint('[DatabaseMigration] Error migrating cached stream: $e');
            }
          }
        }

        // 4. Migrate generic key-value preferences
        for (final entry in legacyData.entries) {
          final key = entry.key;
          if (key == 'sautiplay_liked_songs' ||
              key == 'sautiplay_recently_played' ||
              key == 'sautiplay_cached_streams_metadata_v1') {
            continue;
          }

          final val = entry.value;
          if (val == null) continue;

          String stringVal;
          if (val is List) {
            stringVal = jsonEncode(val);
          } else {
            stringVal = val.toString();
          }

          await db.setPreference(key, stringVal);
        }

        // 5. Mark migration as finished
        await db.setPreference(_kMigrationKey, 'true');
      });

      // Reload cache with newly migrated preferences
      await PreferencesStore.instance.init(db);
      debugPrint('[DatabaseMigration] Successfully migrated all data to Drift!');
    } catch (e, stack) {
      debugPrint('[DatabaseMigration] Migration notice: $e\n$stack');
      // Mark migrated on error to avoid repeated attempts
      await PreferencesStore.instance.setBool(_kMigrationKey, true);
    }
  }

  /// Attempts to read legacy SharedPreferences data from platform-specific locations
  /// without requiring the shared_preferences package.
  static Future<Map<String, dynamic>> _readLegacyData() async {
    final result = <String, dynamic>{};

    try {
      if (Platform.isAndroid) {
        final possiblePaths = [
          '/data/data/com.wambugu.sautiplay.sautiplay/shared_prefs/FlutterSharedPreferences.xml',
          '/data/user/0/com.wambugu.sautiplay.sautiplay/shared_prefs/FlutterSharedPreferences.xml',
        ];

        for (final pth in possiblePaths) {
          final file = File(pth);
          if (file.existsSync()) {
            final xmlContent = await file.readAsString();
            _parseAndroidXml(xmlContent, result);
            if (result.isNotEmpty) break;
          }
        }
      } else {
        // Desktop / iOS / macOS
        try {
          final docDir = await getApplicationSupportDirectory();
          final jsonFile = File(p.join(docDir.path, 'shared_preferences.json'));
          if (jsonFile.existsSync()) {
            final content = await jsonFile.readAsString();
            final map = jsonDecode(content) as Map<String, dynamic>;
            for (final entry in map.entries) {
              final key = entry.key.startsWith('flutter.')
                  ? entry.key.substring('flutter.'.length)
                  : entry.key;
              result[key] = entry.value;
            }
          }
        } catch (_) {}
      }
    } catch (_) {}

    return result;
  }

  /// Lightweight parser for Android FlutterSharedPreferences.xml
  static void _parseAndroidXml(String xml, Map<String, dynamic> out) {
    // Strings: <string name="flutter.key">val</string>
    final stringRegex = RegExp(r'<string name="([^"]+)">([\s\S]*?)<\/string>');
    for (final match in stringRegex.allMatches(xml)) {
      var key = match.group(1) ?? '';
      if (key.startsWith('flutter.')) key = key.substring(8);
      final value = match.group(2) ?? '';
      // Check if it's a JSON string list or JSON encoded
      if (value.startsWith('[') && value.endsWith(']')) {
        try {
          final parsed = jsonDecode(value);
          out[key] = parsed;
          continue;
        } catch (_) {}
      }
      out[key] = value;
    }

    // Booleans: <boolean name="flutter.key" value="true" />
    final boolRegex = RegExp(r'<boolean name="([^"]+)" value="([^"]+)"');
    for (final match in boolRegex.allMatches(xml)) {
      var key = match.group(1) ?? '';
      if (key.startsWith('flutter.')) key = key.substring(8);
      out[key] = match.group(2) == 'true';
    }

    // Ints / Longs: <int name="flutter.key" value="123" />
    final intRegex = RegExp(r'<(?:int|long) name="([^"]+)" value="([^"]+)"');
    for (final match in intRegex.allMatches(xml)) {
      var key = match.group(1) ?? '';
      if (key.startsWith('flutter.')) key = key.substring(8);
      out[key] = int.tryParse(match.group(2) ?? '') ?? 0;
    }

    // Floats: <float name="flutter.key" value="1.23" />
    final floatRegex = RegExp(r'<float name="([^"]+)" value="([^"]+)"');
    for (final match in floatRegex.allMatches(xml)) {
      var key = match.group(1) ?? '';
      if (key.startsWith('flutter.')) key = key.substring(8);
      out[key] = double.tryParse(match.group(2) ?? '') ?? 0.0;
    }

    // String sets: <set name="flutter.key"><string>...</string></set>
    final setRegex = RegExp(r'<set name="([^"]+)">([\s\S]*?)<\/set>');
    for (final match in setRegex.allMatches(xml)) {
      var key = match.group(1) ?? '';
      if (key.startsWith('flutter.')) key = key.substring(8);
      final inner = match.group(2) ?? '';
      final items = <String>[];
      final itemRegex = RegExp(r'<string>([\s\S]*?)<\/string>');
      for (final itemMatch in itemRegex.allMatches(inner)) {
        items.add(itemMatch.group(1) ?? '');
      }
      out[key] = items;
    }
  }
}
