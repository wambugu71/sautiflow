import 'package:cached_network_image/cached_network_image.dart';
import 'package:dart_ytmusic_api/dart_ytmusic_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_m3shapes_extended/flutter_m3shapes_extended.dart';
import 'dart:io';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'album_detail_screen.dart';
import 'services/app_theme_service.dart';

enum AudioQualityPreset {
  low, // ~50 kbps (Data Saver)
  medium, // ~70 kbps (Mobile)
  high, // ~128 kbps (AAC Native)
  audiophile, // ~160 kbps (Opus Max)
}

class StreamExtractionTestScreen extends StatefulWidget {
  final Future<void> Function(List<TrackInfo> tracks, {int initialIndex})?
      onPlayTracks;

  const StreamExtractionTestScreen({super.key, this.onPlayTracks});

  @override
  State<StreamExtractionTestScreen> createState() =>
      _StreamExtractionTestScreenState();
}

class _StreamExtractionTestScreenState
    extends State<StreamExtractionTestScreen> {
  final TextEditingController _searchController =
      TextEditingController(text: 'Bohemian Rhapsody Queen');
  final YTMusic _ytMusic = YTMusic();
  final YoutubeExplode _ytExplode = YoutubeExplode();

  Color get _bgDark => context.bgDark;
  Color get _surfaceDark => context.cardDark;
  Color get _primary => context.primaryColor;
  Color get _textPrimary => context.textPrimary;
  Color get _textSecondary => context.textMuted;

  bool _isSearching = false;
  bool _isResolvingStream = false;
  List<SongDetailed> _searchResults = [];
  List<String> _suggestions = [];

  SongDetailed? _selectedSong;
  StreamManifest? _manifest;
  AudioOnlyStreamInfo? _selectedStream;
  AudioQualityPreset _qualityPreset = AudioQualityPreset.audiophile;
  bool _preferAac = false;

  String? _httpStatusLog;

  @override
  void initState() {
    super.initState();
    _initAndSearch();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _ytExplode.close();
    super.dispose();
  }

  Future<void> _initAndSearch() async {
    setState(() => _isSearching = true);
    try {
      await _ytMusic.initialize();
      await _performSearch(_searchController.text.trim());
    } catch (e) {
      final err = e.toString().toLowerCase();
      if (!err.contains('socketexception') && !err.contains('failed host lookup')) {
        debugPrint('Search error: $e');
      }
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _performSearch(String query) async {
    if (query.isEmpty) return;
    setState(() {
      _isSearching = true;
      _httpStatusLog = null;
    });

    try {
      final results = await _ytMusic.searchSongs(query);
      if (mounted) {
        setState(() {
          _searchResults = results;
          if (results.isNotEmpty) {
            _selectSong(results.first);
          }
        });
      }
    } catch (e) {
      final err = e.toString().toLowerCase();
      if (!err.contains('socketexception') && !err.contains('failed host lookup')) {
        debugPrint('Error searching songs: $e');
      }
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _fetchSuggestions(String query) async {
    if (query.isEmpty) {
      setState(() => _suggestions = []);
      return;
    }
    try {
      final suggestions = await _ytMusic.getSearchSuggestions(query);
      if (mounted) {
        setState(() => _suggestions = suggestions);
      }
    } catch (_) {}
  }

  Future<void> _selectSong(SongDetailed song) async {
    setState(() {
      _selectedSong = song;
      _isResolvingStream = true;
      _manifest = null;
      _selectedStream = null;
      _httpStatusLog = null;
    });

    try {
      final manifest =
          await _ytExplode.videos.streams.getManifest(song.videoId);
      if (mounted) {
        setState(() {
          _manifest = manifest;
          _updateSelectedStream();
          _isResolvingStream = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _httpStatusLog = 'Error resolving stream manifest: $e';
          _isResolvingStream = false;
        });
      }
    }
  }

  void _updateSelectedStream() {
    if (_manifest == null) return;
    final streams = _manifest!.audioOnly.toList()
      ..sort(
          (a, b) => a.bitrate.bitsPerSecond.compareTo(b.bitrate.bitsPerSecond));

    if (streams.isEmpty) return;

    if (_preferAac) {
      final aacStreams =
          streams.where((s) => s.container == StreamContainer.mp4).toList();
      if (aacStreams.isNotEmpty) {
        _selectedStream = _qualityPreset == AudioQualityPreset.low
            ? aacStreams.first
            : aacStreams.last;
        return;
      }
    }

    switch (_qualityPreset) {
      case AudioQualityPreset.low:
        _selectedStream = streams.first;
        break;
      case AudioQualityPreset.medium:
        final mid = streams
            .where((s) =>
                s.bitrate.kiloBitsPerSecond >= 60 &&
                s.bitrate.kiloBitsPerSecond <= 100)
            .toList();
        _selectedStream =
            mid.isNotEmpty ? mid.first : streams[streams.length ~/ 2];
        break;
      case AudioQualityPreset.high:
        final high = streams
            .where((s) => s.bitrate.kiloBitsPerSecond >= 120)
            .toList();
        _selectedStream = high.isNotEmpty ? high.first : streams.last;
        break;
      case AudioQualityPreset.audiophile:
        _selectedStream = streams.last;
        break;
    }
  }

  Future<void> _testHttpReachability(String streamUrl) async {
    setState(() => _httpStatusLog = 'Testing HTTP HEAD & Range requests...');
    final client = HttpClient();
    try {
      final headReq = await client.headUrl(Uri.parse(streamUrl));
      final headRes = await headReq.close();

      final rangeReq = await client.getUrl(Uri.parse(streamUrl));
      rangeReq.headers.set('Range', 'bytes=0-65535');
      final rangeRes = await rangeReq.close();
      final bytes = await rangeRes.fold<List<int>>([], (prev, elem) => prev..addAll(elem));

      if (mounted) {
        setState(() {
          _httpStatusLog =
              '✅ HEAD Status: ${headRes.statusCode} | Content-Type: ${headRes.headers.value(HttpHeaders.contentTypeHeader)}\n'
              '✅ Range Request Status: ${rangeRes.statusCode} (Expected 206)\n'
              '✅ Initial Buffer: ${bytes.length} bytes received';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _httpStatusLog = '❌ HTTP Stream Error: $e');
      }
    } finally {
      client.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgDark,
      appBar: AppBar(
        backgroundColor: _surfaceDark,
        elevation: 0,
        title: const Text(
          'Stream Extraction & Discovery Test',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: Row(
        children: [
          // Left: Search & Results
          Expanded(
            flex: 5,
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(
                    color: _surfaceDark.withValues(alpha: 0.8),
                    width: 1,
                  ),
                ),
              ),
              child: Column(
                children: [
                  _buildSearchBar(),
                  if (_suggestions.isNotEmpty) _buildSuggestionsList(),
                  Expanded(
                    child: _isSearching
                        ? Center(
                            child: M3ELoadingIndicator(color: _primary),
                          )
                        : _buildSearchResultsList(),
                  ),
                ],
              ),
            ),
          ),

          // Right: Stream Manifest, Bitrate & Player Inspector
          Expanded(
            flex: 6,
            child: _selectedSong == null
                ? Center(
                    child: Text(
                      'Select a track to inspect streams',
                      style: TextStyle(color: _textSecondary),
                    ),
                  )
                : _buildStreamInspector(),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: _surfaceDark,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              style: TextStyle(color: _textPrimary),
              onChanged: _fetchSuggestions,
              onSubmitted: _performSearch,
              decoration: InputDecoration(
                hintText: 'Search YouTube Music (Song / Artist)...',
                hintStyle: TextStyle(color: _textSecondary),
                prefixIcon: Icon(Icons.search_rounded, color: _primary),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear_rounded),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _suggestions = []);
                  },
                ),
                filled: true,
                fillColor: _bgDark,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          M3EButton.icon(
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            label: const Text('Search'),
            onPressed: () => _performSearch(_searchController.text.trim()),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionsList() {
    return Container(
      height: 48,
      color: _surfaceDark,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        itemCount: _suggestions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final s = _suggestions[i];
          return ActionChip(
            label: Text(s, style: const TextStyle(fontSize: 12)),
            backgroundColor: _bgDark,
            side: BorderSide(color: _primary.withValues(alpha: 0.3)),
            onPressed: () {
              _searchController.text = s;
              setState(() => _suggestions = []);
              _performSearch(s);
            },
          );
        },
      ),
    );
  }

  Widget _buildSearchResultsList() {
    if (_searchResults.isEmpty) {
      return Center(
        child: Text('No results found.', style: TextStyle(color: _textSecondary)),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _searchResults.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final song = _searchResults[i];
        final isSelected = _selectedSong?.videoId == song.videoId;
        final thumb = song.thumbnails.isNotEmpty ? song.thumbnails.first.url : null;

        return ListTile(
          selected: isSelected,
          selectedTileColor: _primary.withValues(alpha: 0.15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isSelected ? _primary : Colors.transparent,
              width: 1.5,
            ),
          ),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: thumb != null
                ? CachedNetworkImage(
                    imageUrl: thumb,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                  )
                : Container(
                    width: 48,
                    height: 48,
                    color: _surfaceDark,
                    child: const Icon(Icons.music_note_rounded),
                  ),
          ),
          title: Text(
            song.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _textPrimary,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          subtitle: Text(
            '${song.artist.name} • ${song.duration != null ? "${song.duration}s" : "--"}',
            style: TextStyle(color: _textSecondary, fontSize: 12),
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => _selectSong(song),
        );
      },
    );
  }

  Widget _buildStreamInspector() {
    final song = _selectedSong!;
    final thumb = song.thumbnails.isNotEmpty ? song.thumbnails.last.url : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Track Header Card
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              M3EContainer(
                Shapes.slanted,
                width: 96,
                height: 96,
                clipBehavior: Clip.antiAlias,
                child: thumb != null
                    ? CachedNetworkImage(imageUrl: thumb, fit: BoxFit.cover)
                    : Container(color: _surfaceDark),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.name,
                      style: TextStyle(
                        color: _textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Artist: ${song.artist.name}',
                      style: TextStyle(color: _textSecondary, fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          'Video ID: ${song.videoId}',
                          style: TextStyle(
                            color: _primary,
                            fontFamily: 'monospace',
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy_rounded, size: 14),
                          tooltip: 'Copy Video ID',
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: song.videoId));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Video ID copied!')),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),

          // Quality Preset Selector
          Text(
            '1. Select Quality Preset / Bandwidth Mode',
            style: TextStyle(
              color: _textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: AudioQualityPreset.values.map((preset) {
              final isSel = _qualityPreset == preset;
              return ChoiceChip(
                label: Text(
                  _presetLabel(preset),
                  style: TextStyle(
                    color: isSel ? Colors.white : _textPrimary,
                    fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                selected: isSel,
                selectedColor: _primary,
                backgroundColor: _surfaceDark,
                onSelected: (_) {
                  setState(() {
                    _qualityPreset = preset;
                    _updateSelectedStream();
                  });
                },
              );
            }).toList(),
          ),

          const SizedBox(height: 12),
          Row(
            children: [
              Checkbox(
                value: _preferAac,
                activeColor: _primary,
                onChanged: (val) {
                  setState(() {
                    _preferAac = val ?? false;
                    _updateSelectedStream();
                  });
                },
              ),
              Text(
                'Prefer Native AAC / MP4 Container (Optimized for Miniaudio)',
                style: TextStyle(color: _textSecondary, fontSize: 13),
              ),
            ],
          ),

          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 16),

          // Available Streams in Manifest
          Text(
            '2. Stream Manifest Inspector',
            style: TextStyle(
              color: _textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 12),

          if (_isResolvingStream)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: M3ELoadingIndicator(color: _primary),
              ),
            )
          else if (_manifest != null) ...[
            Container(
              decoration: BoxDecoration(
                color: _surfaceDark,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _primary.withValues(alpha: 0.2)),
              ),
              child: Column(
                children: _manifest!.audioOnly.map((s) {
                  final isCurrent = _selectedStream?.tag == s.tag;
                  return Container(
                    color: isCurrent ? _primary.withValues(alpha: 0.15) : null,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        Icon(
                          isCurrent
                              ? Icons.radio_button_checked_rounded
                              : Icons.radio_button_unchecked_rounded,
                          color: isCurrent ? _primary : _textSecondary,
                          size: 18,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Tag ${s.tag}',
                          style: TextStyle(
                            color: _textPrimary,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                          ),
                        ),
                        const SizedBox(width: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _bgDark,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            s.container.name.toUpperCase(),
                            style: TextStyle(
                              color: _primary,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          s.audioCodec,
                          style: TextStyle(color: _textSecondary, fontSize: 13),
                        ),
                        const Spacer(),
                        Text(
                          '${s.bitrate.kiloBitsPerSecond.toStringAsFixed(1)} kbps',
                          style: TextStyle(
                            color: _textPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          '${(s.size.totalBytes / (1024 * 1024)).toStringAsFixed(2)} MB',
                          style: TextStyle(
                            color: _textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 20),

            // Active Direct URL & Verification
            if (_selectedStream != null) ...[
              Text(
                '3. Live Stream URL & Connectivity Verification',
                style: TextStyle(
                  color: _textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _bgDark,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _selectedStream!.url.toString(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _textSecondary,
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      tooltip: 'Copy Direct Stream URL',
                      onPressed: () {
                        Clipboard.setData(
                          ClipboardData(text: _selectedStream!.url.toString()),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Direct Stream URL copied!')),
                        );
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              Row(
                children: [
                  M3EButton.icon(
                    icon: const Icon(Icons.network_check_rounded, size: 18),
                    label: const Text('Test HTTP Stream'),
                    onPressed: () => _testHttpReachability(
                      _selectedStream!.url.toString(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (widget.onPlayTracks != null)
                    M3EButton.icon(
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: const Text('Play via Sautiflow Engine'),
                      onPressed: () {
                        final track = TrackInfo.fromSongDetailed(song);
                        Navigator.of(context).popUntil((route) => route.isFirst);
                        widget.onPlayTracks!([track]);
                      },
                    ),
                ],
              ),

              if (_httpStatusLog != null) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _surfaceDark,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _primary.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    _httpStatusLog!,
                    style: TextStyle(
                      color: _textPrimary,
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ],
          ],
        ],
      ),
    );
  }

  String _presetLabel(AudioQualityPreset preset) {
    switch (preset) {
      case AudioQualityPreset.low:
        return 'Data Saver (~50k)';
      case AudioQualityPreset.medium:
        return 'Balanced (~70k)';
      case AudioQualityPreset.high:
        return 'High AAC (~128k)';
      case AudioQualityPreset.audiophile:
        return 'Audiophile Opus (~160k)';
    }
  }
}
