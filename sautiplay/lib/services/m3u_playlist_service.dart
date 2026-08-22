import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/local_song_item.dart';

class SavedM3uPlaylist {
  final String id;
  final String name;
  final String pathOrUrl;
  final bool isNetwork;
  final List<LocalSongItem> tracks;
  final DateTime dateAdded;

  const SavedM3uPlaylist({
    required this.id,
    required this.name,
    required this.pathOrUrl,
    required this.isNetwork,
    required this.tracks,
    required this.dateAdded,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'pathOrUrl': pathOrUrl,
        'isNetwork': isNetwork,
        'tracks': tracks.map((t) => t.toJson()).toList(),
        'dateAdded': dateAdded.toIso8601String(),
      };

  factory SavedM3uPlaylist.fromJson(Map<String, dynamic> json) =>
      SavedM3uPlaylist(
        id: json['id'] as String? ??
            DateTime.now().millisecondsSinceEpoch.toString(),
        name: json['name'] as String? ?? 'Untitled Playlist',
        pathOrUrl: json['pathOrUrl'] as String? ?? '',
        isNetwork: json['isNetwork'] as bool? ?? false,
        tracks: (json['tracks'] as List<dynamic>?)
                ?.map((t) =>
                    LocalSongItem.fromJson(Map<String, dynamic>.from(t as Map)))
                .toList() ??
            [],
        dateAdded: json['dateAdded'] != null
            ? DateTime.tryParse(json['dateAdded'] as String) ?? DateTime.now()
            : DateTime.now(),
      );
}

class M3uPlaylistService {
  M3uPlaylistService._();
  static final M3uPlaylistService instance = M3uPlaylistService._();

  static const String _kM3uPlaylistsKey = 'sp_m3u_playlists_json';

  Future<void> savePlaylists(List<SavedM3uPlaylist> playlists) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = playlists.map((p) => jsonEncode(p.toJson())).toList();
    await prefs.setStringList(_kM3uPlaylistsKey, jsonList);
  }

  Future<List<SavedM3uPlaylist>> loadPlaylists() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_kM3uPlaylistsKey) ?? [];
    final playlists = <SavedM3uPlaylist>[];

    for (final str in raw) {
      try {
        final map = jsonDecode(str) as Map<String, dynamic>;
        playlists.add(SavedM3uPlaylist.fromJson(map));
      } catch (_) {}
    }
    return playlists;
  }

  Future<void> saveSinglePlaylist(SavedM3uPlaylist playlist) async {
    final playlists = await loadPlaylists();
    final idx = playlists.indexWhere((p) => p.id == playlist.id);
    if (idx >= 0) {
      playlists[idx] = playlist;
    } else {
      playlists.add(playlist);
    }
    await savePlaylists(playlists);
  }

  Future<void> deletePlaylist(String playlistId) async {
    final playlists = await loadPlaylists();
    playlists.removeWhere((p) => p.id == playlistId);
    await savePlaylists(playlists);
  }

  /// Creates a new custom playlist from the provided [tracks].
  Future<SavedM3uPlaylist> createPlaylist({
    required String name,
    required List<LocalSongItem> tracks,
  }) async {
    final newPlaylist = SavedM3uPlaylist(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name.trim().isNotEmpty ? name.trim() : 'Untitled Playlist',
      pathOrUrl: '',
      isNetwork: false,
      tracks: List.from(tracks),
      dateAdded: DateTime.now(),
    );
    await saveSinglePlaylist(newPlaylist);
    return newPlaylist;
  }

  /// Appends [tracks] to an existing playlist, avoiding duplicate file paths.
  Future<SavedM3uPlaylist?> addTracksToPlaylist({
    required String playlistId,
    required List<LocalSongItem> tracks,
  }) async {
    final playlists = await loadPlaylists();
    final idx = playlists.indexWhere((p) => p.id == playlistId);
    if (idx == -1) return null;

    final current = playlists[idx];
    final existingPaths = current.tracks.map((t) => t.path).toSet();
    final updatedTracks = List<LocalSongItem>.from(current.tracks);

    for (final track in tracks) {
      if (!existingPaths.contains(track.path)) {
        updatedTracks.add(track);
        existingPaths.add(track.path);
      }
    }

    final updatedPlaylist = SavedM3uPlaylist(
      id: current.id,
      name: current.name,
      pathOrUrl: current.pathOrUrl,
      isNetwork: current.isNetwork,
      tracks: updatedTracks,
      dateAdded: current.dateAdded,
    );

    playlists[idx] = updatedPlaylist;
    await savePlaylists(playlists);
    return updatedPlaylist;
  }

  /// Removes a track by [trackPath] from the specified playlist.
  Future<SavedM3uPlaylist?> removeTrackFromPlaylist({
    required String playlistId,
    required String trackPath,
  }) async {
    final playlists = await loadPlaylists();
    final idx = playlists.indexWhere((p) => p.id == playlistId);
    if (idx == -1) return null;

    final current = playlists[idx];
    final updatedTracks =
        current.tracks.where((t) => t.path != trackPath).toList();

    final updatedPlaylist = SavedM3uPlaylist(
      id: current.id,
      name: current.name,
      pathOrUrl: current.pathOrUrl,
      isNetwork: current.isNetwork,
      tracks: updatedTracks,
      dateAdded: current.dateAdded,
    );

    playlists[idx] = updatedPlaylist;
    await savePlaylists(playlists);
    return updatedPlaylist;
  }

  /// Renames an existing playlist.
  Future<SavedM3uPlaylist?> renamePlaylist({
    required String playlistId,
    required String newName,
  }) async {
    final playlists = await loadPlaylists();
    final idx = playlists.indexWhere((p) => p.id == playlistId);
    if (idx == -1) return null;

    final current = playlists[idx];
    final updatedPlaylist = SavedM3uPlaylist(
      id: current.id,
      name: newName.trim().isNotEmpty ? newName.trim() : current.name,
      pathOrUrl: current.pathOrUrl,
      isNetwork: current.isNetwork,
      tracks: current.tracks,
      dateAdded: current.dateAdded,
    );

    playlists[idx] = updatedPlaylist;
    await savePlaylists(playlists);
    return updatedPlaylist;
  }

  /// Generates the `.m3u8` string content for a list of tracks.
  String generateM3u8Content({
    required String playlistName,
    required List<LocalSongItem> tracks,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('#EXTM3U');
    buffer.writeln('#PLAYLIST:$playlistName');

    for (final song in tracks) {
      final artistTitle =
          song.artist.isNotEmpty && song.artist != 'Unknown Artist'
              ? '${song.artist} - ${song.title}'
              : song.title;
      buffer.writeln('#EXTINF:-1,$artistTitle');
      buffer.writeln(song.path);
    }

    return buffer.toString();
  }

  /// Exports a list of [LocalSongItem] tracks to an `.m3u8` file on disk.
  Future<File> exportToM3u8({
    required String targetFilePath,
    required String playlistName,
    required List<LocalSongItem> tracks,
  }) async {
    final content = generateM3u8Content(
      playlistName: playlistName,
      tracks: tracks,
    );
    final file = File(targetFilePath);
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    return await file.writeAsString(content);
  }
}

