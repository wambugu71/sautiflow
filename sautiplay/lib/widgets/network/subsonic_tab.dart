import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sautiflow/sautiflow.dart';

import '../../album_detail_screen.dart' show TrackInfo;
import '../../services/app_theme_service.dart';
import '../../services/subsonic_service.dart';

typedef PlayRemoteQueueCallback = Future<void> Function(
  List<TrackInfo> tracks,
  List<AudioSource> sources,
  int initialIndex,
);

enum _SubsonicSection { albums, artists, playlists, search }

class SubsonicTab extends StatefulWidget {
  final PlayRemoteQueueCallback? onPlayQueue;

  const SubsonicTab({super.key, this.onPlayQueue});

  @override
  State<SubsonicTab> createState() => _SubsonicTabState();
}

class _SubsonicTabState extends State<SubsonicTab> {
  List<SubsonicConfig> _configs = [];
  SubsonicConfig? _selected;

  _SubsonicSection _section = _SubsonicSection.albums;
  String _albumSort = 'recent';

  bool _isLoading = false;
  String? _error;

  List<SubsonicAlbum> _albums = [];
  List<SubsonicArtist> _artists = [];
  List<SubsonicPlaylist> _playlists = [];
  SubsonicSearchResult? _searchResult;

  // Drill-down stack
  SubsonicArtist? _selectedArtist;
  List<SubsonicAlbum> _artistAlbums = [];
  SubsonicAlbum? _selectedAlbum;
  SubsonicPlaylist? _selectedPlaylist;
  List<SubsonicTrack> _tracks = [];

  final TextEditingController _searchCtrl = TextEditingController();

  Color get _cardDark => context.cardDark;
  Color get _primary => context.primaryColor;
  Color get _textMuted => context.textMuted;

  @override
  void initState() {
    super.initState();
    _loadConfigs();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadConfigs() async {
    final configs = await SubsonicService.getSavedConfigs();
    if (!mounted) return;
    setState(() {
      _configs = configs;
      if (_selected != null) {
        final match = configs.where((c) => c.id == _selected!.id);
        _selected = match.isNotEmpty
            ? match.first
            : (configs.isNotEmpty ? configs.first : null);
      } else if (configs.isNotEmpty) {
        _selected = configs.first;
      }
    });
    if (_selected != null) {
      _loadSection();
    }
  }

  Future<void> _loadSection() async {
    final cfg = _selected;
    if (cfg == null) return;
    setState(() {
      _isLoading = true;
      _error = null;
      _selectedArtist = null;
      _selectedAlbum = null;
      _selectedPlaylist = null;
    });

    try {
      switch (_section) {
        case _SubsonicSection.albums:
          final albums = await SubsonicService.getAlbumList(
            cfg,
            type: _albumSort,
            size: 60,
          );
          if (!mounted) return;
          setState(() {
            _albums = albums;
            _isLoading = false;
          });
          break;
        case _SubsonicSection.artists:
          final artists = await SubsonicService.getArtists(cfg);
          if (!mounted) return;
          setState(() {
            _artists = artists;
            _isLoading = false;
          });
          break;
        case _SubsonicSection.playlists:
          final playlists = await SubsonicService.getPlaylists(cfg);
          if (!mounted) return;
          setState(() {
            _playlists = playlists;
            _isLoading = false;
          });
          break;
        case _SubsonicSection.search:
          final q = _searchCtrl.text.trim();
          if (q.isEmpty) {
            setState(() {
              _searchResult = const SubsonicSearchResult();
              _isLoading = false;
            });
            return;
          }
          final res = await SubsonicService.search(cfg, q);
          if (!mounted) return;
          setState(() {
            _searchResult = res;
            _isLoading = false;
          });
          break;
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Future<void> _openArtist(SubsonicArtist artist) async {
    final cfg = _selected;
    if (cfg == null) return;
    setState(() {
      _isLoading = true;
      _error = null;
      _selectedArtist = artist;
      _selectedAlbum = null;
      _selectedPlaylist = null;
    });
    try {
      final albums = await SubsonicService.getArtistAlbums(cfg, artist.id);
      if (!mounted) return;
      setState(() {
        _artistAlbums = albums;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Future<void> _openAlbum(SubsonicAlbum album) async {
    final cfg = _selected;
    if (cfg == null) return;
    setState(() {
      _isLoading = true;
      _error = null;
      _selectedAlbum = album;
      _selectedPlaylist = null;
    });
    try {
      final tracks = await SubsonicService.getAlbumTracks(cfg, album.id);
      if (!mounted) return;
      setState(() {
        _tracks = tracks;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Future<void> _openPlaylist(SubsonicPlaylist playlist) async {
    final cfg = _selected;
    if (cfg == null) return;
    setState(() {
      _isLoading = true;
      _error = null;
      _selectedPlaylist = playlist;
      _selectedAlbum = null;
    });
    try {
      final tracks = await SubsonicService.getPlaylistTracks(cfg, playlist.id);
      if (!mounted) return;
      setState(() {
        _tracks = tracks;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Future<void> _playTracks(List<SubsonicTrack> list, int initialIndex) async {
    final cfg = _selected;
    if (cfg == null || list.isEmpty) return;
    if (widget.onPlayQueue == null) return;

    final trackInfos = <TrackInfo>[];
    final sources = <AudioSource>[];

    for (final t in list) {
      final streamUrl = SubsonicService.buildStreamUrl(cfg, t.id);
      final coverUrl = SubsonicService.buildCoverArtUrl(cfg, t.coverArtId, size: 500);
      trackInfos.add(TrackInfo(
        videoId: streamUrl,
        title: t.title,
        artist: t.artist,
        album: t.album,
        trackNumber: t.trackNumber,
        durationSeconds: t.durationSeconds > 0 ? t.durationSeconds : null,
        thumbnailUrl: coverUrl,
      ));
      sources.add(AudioSource.network(
        streamUrl,
        title: t.title,
        artist: t.artist,
        album: t.album,
        trackNumber: t.trackNumber,
        duration: t.durationSeconds > 0
            ? Duration(seconds: t.durationSeconds)
            : null,
        replayGainTrackDb: t.replayGainTrackDb,
        replayGainAlbumDb: t.replayGainAlbumDb,
      ));
    }

    await widget.onPlayQueue!(trackInfos, sources, initialIndex);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildServerBar(),
        if (_selected != null) _buildSectionBar(),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildServerBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: _cardDark,
      child: Row(
        children: [
          Icon(Icons.album_rounded, color: _primary),
          const SizedBox(width: 12),
          Expanded(
            child: _configs.isEmpty
                ? Text(
                    'No Navidrome / Subsonic servers configured',
                    style: TextStyle(color: _textMuted),
                  )
                : DropdownButtonHideUnderline(
                    child: DropdownButton<SubsonicConfig>(
                      value: _selected,
                      dropdownColor: _cardDark,
                      isExpanded: true,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                      items: _configs
                          .map((c) => DropdownMenuItem(
                                value: c,
                                child: Text(
                                  '${c.name} (${c.username})',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _selected = val);
                          _loadSection();
                        }
                      },
                    ),
                  ),
          ),
          IconButton(
            icon: Icon(Icons.add_circle_outline_rounded, color: _primary),
            tooltip: 'Add Server',
            onPressed: () => _showServerDialog(),
          ),
          if (_selected != null) ...[
            IconButton(
              icon: const Icon(Icons.edit_outlined, color: Colors.white70, size: 20),
              tooltip: 'Edit Server',
              onPressed: () => _showServerDialog(existing: _selected),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded,
                  color: Colors.redAccent, size: 20),
              tooltip: 'Delete Server',
              onPressed: () async {
                await SubsonicService.deleteConfig(_selected!.id);
                _selected = null;
                _loadConfigs();
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      color: Colors.black26,
      child: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _sectionChip('Albums', _SubsonicSection.albums, Icons.album_rounded),
                const SizedBox(width: 8),
                _sectionChip('Artists', _SubsonicSection.artists, Icons.person_rounded),
                const SizedBox(width: 8),
                _sectionChip('Playlists', _SubsonicSection.playlists, Icons.queue_music_rounded),
                const SizedBox(width: 8),
                _sectionChip('Search', _SubsonicSection.search, Icons.search_rounded),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, color: Colors.white70, size: 20),
                  tooltip: 'Refresh',
                  onPressed: _loadSection,
                ),
              ],
            ),
          ),
          if (_section == _SubsonicSection.albums &&
              _selectedAlbum == null &&
              _selectedArtist == null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _sortChip('Recent', 'recent'),
                    _sortChip('Newest', 'newest'),
                    _sortChip('Most Played', 'frequent'),
                    _sortChip('Random', 'random'),
                    _sortChip('Starred', 'starred'),
                    _sortChip('A–Z', 'alphabeticalByName'),
                  ],
                ),
              ),
            ),
          if (_section == _SubsonicSection.search)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextField(
                controller: _searchCtrl,
                style: const TextStyle(color: Colors.white),
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _loadSection(),
                decoration: InputDecoration(
                  hintText: 'Search artists, albums, tracks…',
                  hintStyle: TextStyle(color: _textMuted),
                  filled: true,
                  fillColor: _cardDark,
                  isDense: true,
                  prefixIcon: Icon(Icons.search_rounded, color: _primary),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.arrow_forward_rounded, color: Colors.white70),
                    onPressed: _loadSection,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionChip(String label, _SubsonicSection sec, IconData icon) {
    final active = _section == sec;
    return ChoiceChip(
      avatar: Icon(icon, size: 16, color: active ? Colors.black : Colors.white70),
      label: Text(label),
      selected: active,
      selectedColor: _primary,
      backgroundColor: _cardDark,
      labelStyle: TextStyle(
        color: active ? Colors.black : Colors.white,
        fontWeight: FontWeight.w600,
        fontSize: 12,
      ),
      onSelected: (_) {
        setState(() => _section = sec);
        _loadSection();
      },
    );
  }

  Widget _sortChip(String label, String sortType) {
    final active = _albumSort == sortType;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text(label),
        selected: active,
        selectedColor: _primary.withValues(alpha: 0.25),
        checkmarkColor: _primary,
        backgroundColor: _cardDark,
        labelStyle: TextStyle(
          color: active ? _primary : Colors.white70,
          fontSize: 11,
        ),
        onSelected: (_) {
          setState(() => _albumSort = sortType);
          _loadSection();
        },
      ),
    );
  }

  Widget _buildBody() {
    if (_selected == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.library_music_rounded,
                  size: 64, color: _textMuted.withValues(alpha: 0.45)),
              const SizedBox(height: 16),
              const Text(
                'Connect Navidrome or Subsonic',
                style: TextStyle(
                    color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Stream your indexed FLAC/DSD library with full cover art, '
                'ReplayGain, and search—at home or over mobile data.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _textMuted, fontSize: 13),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primary,
                  foregroundColor: Colors.black,
                ),
                onPressed: () => _showServerDialog(),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add Navidrome Server'),
              ),
            ],
          ),
        ),
      );
    }

    if (_isLoading) {
      return Center(child: CircularProgressIndicator(color: _primary));
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: Colors.redAccent, size: 48),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _loadSection,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_selectedAlbum != null) {
      return _buildTrackListView(
        title: _selectedAlbum!.name,
        subtitle: _selectedAlbum!.artist,
        coverArtId: _selectedAlbum!.coverArtId,
        onBack: () => setState(() => _selectedAlbum = null),
      );
    }

    if (_selectedPlaylist != null) {
      return _buildTrackListView(
        title: _selectedPlaylist!.name,
        subtitle: '${_selectedPlaylist!.songCount} tracks',
        coverArtId: _selectedPlaylist!.coverArtId,
        onBack: () => setState(() => _selectedPlaylist = null),
      );
    }

    if (_selectedArtist != null) {
      return Column(
        children: [
          _drillHeader(
            _selectedArtist!.name,
            '${_artistAlbums.length} albums',
            () => setState(() => _selectedArtist = null),
          ),
          Expanded(child: _buildAlbumGrid(_artistAlbums)),
        ],
      );
    }

    switch (_section) {
      case _SubsonicSection.albums:
        return _buildAlbumGrid(_albums);
      case _SubsonicSection.artists:
        return _buildArtistList(_artists);
      case _SubsonicSection.playlists:
        return _buildPlaylistList(_playlists);
      case _SubsonicSection.search:
        return _buildSearchResults();
    }
  }

  Widget _drillHeader(String title, String subtitle, VoidCallback onBack) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: _cardDark,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: onBack,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
                Text(subtitle,
                    style: TextStyle(color: _textMuted, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlbumGrid(List<SubsonicAlbum> albums) {
    if (albums.isEmpty) {
      return Center(
        child: Text('No albums found', style: TextStyle(color: _textMuted)),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 190,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.78,
      ),
      itemCount: albums.length,
      itemBuilder: (context, index) {
        final album = albums[index];
        final artUrl =
            SubsonicService.buildCoverArtUrl(_selected!, album.coverArtId);
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _openAlbum(album),
          child: Container(
            decoration: BoxDecoration(
              color: _cardDark,
              borderRadius: BorderRadius.circular(12),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: artUrl != null
                      ? CachedNetworkImage(
                          imageUrl: artUrl,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                            color: Colors.black26,
                            child: Icon(Icons.album_rounded,
                                color: _textMuted, size: 40),
                          ),
                          errorWidget: (_, __, ___) => Container(
                            color: Colors.black26,
                            child: Icon(Icons.album_rounded,
                                color: _textMuted, size: 40),
                          ),
                        )
                      : Container(
                          width: double.infinity,
                          color: Colors.black26,
                          child: Icon(Icons.album_rounded,
                              color: _textMuted, size: 40),
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        album.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        album.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: _textMuted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildArtistList(List<SubsonicArtist> artists) {
    if (artists.isEmpty) {
      return Center(
        child: Text('No artists found', style: TextStyle(color: _textMuted)),
      );
    }
    return ListView.separated(
      itemCount: artists.length,
      separatorBuilder: (_, __) =>
          Divider(height: 1, color: Colors.white.withValues(alpha: 0.05)),
      itemBuilder: (context, index) {
        final artist = artists[index];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: _primary.withValues(alpha: 0.18),
            child: Icon(Icons.person_rounded, color: _primary),
          ),
          title: Text(artist.name, style: const TextStyle(color: Colors.white)),
          subtitle: Text('${artist.albumCount} albums',
              style: TextStyle(color: _textMuted, fontSize: 12)),
          trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white54),
          onTap: () => _openArtist(artist),
        );
      },
    );
  }

  Widget _buildPlaylistList(List<SubsonicPlaylist> playlists) {
    if (playlists.isEmpty) {
      return Center(
        child: Text('No playlists found', style: TextStyle(color: _textMuted)),
      );
    }
    return ListView.separated(
      itemCount: playlists.length,
      separatorBuilder: (_, __) =>
          Divider(height: 1, color: Colors.white.withValues(alpha: 0.05)),
      itemBuilder: (context, index) {
        final pl = playlists[index];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: _primary.withValues(alpha: 0.18),
            child: Icon(Icons.queue_music_rounded, color: _primary),
          ),
          title: Text(pl.name, style: const TextStyle(color: Colors.white)),
          subtitle: Text('${pl.songCount} tracks',
              style: TextStyle(color: _textMuted, fontSize: 12)),
          trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white54),
          onTap: () => _openPlaylist(pl),
        );
      },
    );
  }

  Widget _buildSearchResults() {
    final res = _searchResult;
    if (res == null ||
        (res.artists.isEmpty && res.albums.isEmpty && res.songs.isEmpty)) {
      return Center(
        child: Text(
          _searchCtrl.text.trim().isEmpty
              ? 'Enter a query to search your library'
              : 'No matches found',
          style: TextStyle(color: _textMuted),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        if (res.albums.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text('Albums',
                style: TextStyle(
                    color: _primary, fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          ...res.albums.map((a) => ListTile(
                leading: Icon(Icons.album_rounded, color: _primary),
                title: Text(a.name, style: const TextStyle(color: Colors.white)),
                subtitle: Text(a.artist, style: TextStyle(color: _textMuted)),
                onTap: () => _openAlbum(a),
              )),
        ],
        if (res.artists.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text('Artists',
                style: TextStyle(
                    color: _primary, fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          ...res.artists.map((a) => ListTile(
                leading: Icon(Icons.person_rounded, color: _primary),
                title: Text(a.name, style: const TextStyle(color: Colors.white)),
                onTap: () => _openArtist(a),
              )),
        ],
        if (res.songs.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text('Tracks',
                style: TextStyle(
                    color: _primary, fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          ...List.generate(res.songs.length, (i) {
            final t = res.songs[i];
            return _buildTrackTile(t, () => _playTracks(res.songs, i));
          }),
        ],
      ],
    );
  }

  Widget _buildTrackListView({
    required String title,
    required String subtitle,
    String? coverArtId,
    required VoidCallback onBack,
  }) {
    final artUrl = SubsonicService.buildCoverArtUrl(_selected!, coverArtId, size: 300);
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          color: _cardDark,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                onPressed: onBack,
              ),
              if (artUrl != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: artUrl,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15)),
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: _textMuted, fontSize: 12)),
                  ],
                ),
              ),
              if (_tracks.isNotEmpty)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primary,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                  onPressed: () => _playTracks(_tracks, 0),
                  icon: const Icon(Icons.play_arrow_rounded, size: 20),
                  label: const Text('Play All'),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: _tracks.length,
            separatorBuilder: (_, __) =>
                Divider(height: 1, color: Colors.white.withValues(alpha: 0.05)),
            itemBuilder: (context, index) => _buildTrackTile(
              _tracks[index],
              () => _playTracks(_tracks, index),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTrackTile(SubsonicTrack t, VoidCallback onTap) {
    final badge = t.qualityBadge;
    return ListTile(
      leading: SizedBox(
        width: 32,
        child: Center(
          child: Text(
            t.trackNumber != null && t.trackNumber! > 0
                ? '${t.trackNumber}'
                : '•',
            style: TextStyle(color: _textMuted, fontWeight: FontWeight.w600),
          ),
        ),
      ),
      title: Text(
        t.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        badge.isNotEmpty ? '${t.artist} • $badge' : t.artist,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: _textMuted, fontSize: 12),
      ),
      trailing: Text(
        _formatDuration(t.durationSeconds),
        style: TextStyle(color: _textMuted, fontSize: 12),
      ),
      onTap: onTap,
    );
  }

  String _formatDuration(int seconds) {
    if (seconds <= 0) return '';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  void _showServerDialog({SubsonicConfig? existing}) {
    final nameCtrl = TextEditingController(text: existing?.name ?? 'Navidrome');
    final urlCtrl = TextEditingController(text: existing?.baseUrl ?? '');
    final userCtrl = TextEditingController(text: existing?.username ?? '');
    final passCtrl = TextEditingController(text: existing?.password ?? '');
    String format = existing?.transcodeFormat ?? 'raw';
    bool plaintext = existing?.usePlaintextAuth ?? false;
    bool testing = false;
    String? testStatus;
    bool testOk = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          SubsonicConfig buildDraft() => SubsonicConfig(
                id: existing?.id ??
                    DateTime.now().millisecondsSinceEpoch.toString(),
                name: nameCtrl.text.trim().isEmpty
                    ? 'Navidrome'
                    : nameCtrl.text.trim(),
                baseUrl: urlCtrl.text.trim(),
                username: userCtrl.text.trim(),
                password: passCtrl.text,
                usePlaintextAuth: plaintext,
                transcodeFormat: format,
              );

          return AlertDialog(
            backgroundColor: _cardDark,
            title: Text(
              existing == null ? 'Add Navidrome / Subsonic' : 'Edit Server',
              style: const TextStyle(color: Colors.white),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: _inputDeco('Display Name'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: urlCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: _inputDeco('Server URL (e.g. https://music.example.com)'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: userCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: _inputDeco('Username'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: passCtrl,
                    obscureText: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: _inputDeco('Password'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: format,
                    dropdownColor: _cardDark,
                    style: const TextStyle(color: Colors.white),
                    decoration: _inputDeco('Stream Format'),
                    items: const [
                      DropdownMenuItem(value: 'raw', child: Text('Raw (Bit-Perfect)')),
                      DropdownMenuItem(value: 'opus', child: Text('Opus (Transcode)')),
                      DropdownMenuItem(value: 'mp3', child: Text('MP3 (Transcode)')),
                      DropdownMenuItem(value: 'aac', child: Text('AAC (Transcode)')),
                    ],
                    onChanged: (v) => setDlg(() => format = v ?? 'raw'),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Legacy Plaintext Auth',
                        style: TextStyle(color: Colors.white70, fontSize: 13)),
                    value: plaintext,
                    activeThumbColor: _primary,
                    onChanged: (v) => setDlg(() => plaintext = v),
                  ),
                  if (testStatus != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: (testOk ? Colors.green : Colors.redAccent)
                            .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        testStatus!,
                        style: TextStyle(
                          color: testOk ? Colors.greenAccent : Colors.redAccent,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: testing
                    ? null
                    : () async {
                        setDlg(() {
                          testing = true;
                          testStatus = null;
                        });
                        final err = await SubsonicService.testConnection(buildDraft());
                        if (!ctx.mounted) return;
                        setDlg(() {
                          testing = false;
                          testOk = err == null;
                          testStatus = err ?? 'Connected successfully!';
                        });
                      },
                child: testing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text('Test', style: TextStyle(color: _primary)),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primary,
                  foregroundColor: Colors.black,
                ),
                onPressed: () async {
                  if (urlCtrl.text.trim().isEmpty || userCtrl.text.trim().isEmpty) {
                    return;
                  }
                  final draft = buildDraft();
                  await SubsonicService.saveConfig(draft);
                  _selected = draft;
                  if (ctx.mounted) Navigator.of(ctx).pop();
                  _loadConfigs();
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  InputDecoration _inputDeco(String label) => InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: _textMuted, fontSize: 13),
        isDense: true,
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
          borderRadius: BorderRadius.circular(8),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: _primary),
          borderRadius: BorderRadius.circular(8),
        ),
      );
}
