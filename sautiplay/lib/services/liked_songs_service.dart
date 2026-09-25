import 'dart:async';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../database/app_database.dart';
import '../models/liked_song.dart';

class LikedSongsService {
  /// Private constructor
  LikedSongsService._();

  /// Singleton instance
  static final LikedSongsService instance = LikedSongsService._();

  // A ValueNotifier to broadcast changes to liked songs so the UI can update
  final ValueNotifier<List<LikedSong>> likedSongsNotifier = ValueNotifier([]);

  StreamSubscription<List<LikedSongEntry>>? _subscription;

  /// Initializes the service, starts watching the reactive Drift table,
  /// and updates [likedSongsNotifier] automatically on any change.
  Future<void> init([AppDatabase? db]) async {
    final database = db ?? AppDatabase.instance;
    await _subscription?.cancel();
    _subscription = database.watchLikedSongs().listen((entries) {
      likedSongsNotifier.value = entries.map(_entryToModel).toList();
    });
    final initial = await database.getLikedSongs();
    likedSongsNotifier.value = initial.map(_entryToModel).toList();
  }

  /// Reactive stream of liked songs directly from Drift.
  Stream<List<LikedSong>> get likedSongsStream {
    return AppDatabase.instance.watchLikedSongs().map(
          (entries) => entries.map(_entryToModel).toList(),
        );
  }

  /// Fetch all liked songs, sorted by most recently liked first.
  Future<List<LikedSong>> getLikedSongs() async {
    final entries = await AppDatabase.instance.getLikedSongs();
    return entries.map(_entryToModel).toList();
  }

  /// Add a track to the liked songs (atomic upsert in Drift).
  Future<void> addLikedSong(LikedSong track) async {
    await AppDatabase.instance.upsertLikedSong(
      LikedSongEntriesCompanion(
        videoId: Value(track.videoId),
        title: Value(track.title),
        artist: Value(track.artist),
        artistId: Value(track.artistId),
        thumbnailUrl: Value(track.thumbnailUrl),
        durationSeconds: Value(track.durationSeconds),
        likedAt: Value(track.likedAt),
      ),
    );
  }

  /// Remove a track from liked songs by videoId (or file path).
  Future<void> removeLikedSong(String videoId) async {
    await AppDatabase.instance.deleteLikedSong(videoId);
  }

  /// Instant O(1) indexed check if a track is liked.
  Future<bool> isLiked(String videoId) async {
    return AppDatabase.instance.isSongLiked(videoId);
  }

  /// Clears all liked songs.
  Future<void> clearLikedSongs() async {
    await AppDatabase.instance.delete(AppDatabase.instance.likedSongEntries).go();
  }

  static LikedSong _entryToModel(LikedSongEntry entry) {
    return LikedSong(
      videoId: entry.videoId,
      title: entry.title,
      artist: entry.artist,
      artistId: entry.artistId,
      thumbnailUrl: entry.thumbnailUrl,
      durationSeconds: entry.durationSeconds,
      likedAt: entry.likedAt,
    );
  }
}
