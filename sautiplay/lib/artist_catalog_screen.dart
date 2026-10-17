import 'package:cached_network_image/cached_network_image.dart';
import 'package:dart_ytmusic_api/dart_ytmusic_api.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:shimmer/shimmer.dart';

import 'album_detail_screen.dart';
import 'services/app_theme_service.dart';

enum ArtistCatalogType {
  songs,
  albums,
  singles,
}

class ArtistCatalogScreen extends StatefulWidget {
  final String artistId;
  final String artistName;
  final ArtistCatalogType initialType;
  final Future<void> Function(List<TrackInfo> tracks, {int initialIndex})? onPlayTracks;

  const ArtistCatalogScreen({
    super.key,
    required this.artistId,
    required this.artistName,
    this.initialType = ArtistCatalogType.albums,
    this.onPlayTracks,
  });

  @override
  State<ArtistCatalogScreen> createState() => _ArtistCatalogScreenState();
}

class _ArtistCatalogScreenState extends State<ArtistCatalogScreen> {
  final YTMusic _ytMusic = YTMusic();
  late ArtistCatalogType _selectedType;

  Color get _bgDark => context.bgDark;
  Color get _surfaceDark => context.cardDark;
  Color get _primary => context.primaryColor;
  Color get _textPrimary => context.textPrimary;
  Color get _textDark => context.textMuted;
  Color get _outline => context.outlineColor;

  bool _loading = true;
  String? _error;

  List<SongDetailed> _songs = [];
  List<AlbumDetailed> _albums = [];
  List<AlbumDetailed> _singles = [];

  final Set<ArtistCatalogType> _loadedTypes = {};

  @override
  void initState() {
    super.initState();
    _selectedType = widget.initialType;
    _loadCatalogForType(_selectedType);
  }

  Future<void> _loadCatalogForType(ArtistCatalogType type) async {
    if (_loadedTypes.contains(type)) {
      setState(() => _selectedType = type);
      return;
    }

    setState(() {
      _selectedType = type;
      _loading = true;
      _error = null;
    });

    try {
      await _ytMusic.initialize();
      switch (type) {
        case ArtistCatalogType.songs:
          final songs = await _ytMusic.getArtistSongs(widget.artistId);
          if (mounted) {
            setState(() {
              _songs = songs;
              _loadedTypes.add(type);
              _loading = false;
            });
          }
          break;
        case ArtistCatalogType.albums:
          final albums = await _ytMusic.getArtistAlbums(widget.artistId);
          if (mounted) {
            setState(() {
              _albums = albums;
              _loadedTypes.add(type);
              _loading = false;
            });
          }
          break;
        case ArtistCatalogType.singles:
          final singles = await _ytMusic.getArtistSingles(widget.artistId);
          if (mounted) {
            setState(() {
              _singles = singles;
              _loadedTypes.add(type);
              _loading = false;
            });
          }
          break;
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load catalog: $e';
          _loading = false;
        });
      }
    }
  }

  String _formatDuration(int? seconds) {
    if (seconds == null || seconds <= 0) return '--:--';
    final m = (seconds ~/ 60).toString();
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String? _getBestThumbnail(List<ThumbnailFull> thumbs) {
    if (thumbs.isEmpty) return null;
    final sorted = List<ThumbnailFull>.from(thumbs)
      ..sort((a, b) => b.width.compareTo(a.width));
    return sorted.first.url;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 800;
        final maxWidth = isDesktop ? 1000.0 : double.infinity;

        return Scaffold(
          backgroundColor: _bgDark,
          body: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverAppBar(
                    pinned: true,
                    backgroundColor: _bgDark,
                    surfaceTintColor: Colors.transparent,
                    elevation: 0,
                    leading: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Center(
                        child: M3EIconButton(
                          icon: const Icon(Icons.arrow_back_rounded, size: 20),
                          variant: M3EIconButtonVariant.tonal,
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),
                    ),
                    title: Text(
                      widget.artistName,
                      style: TextStyle(
                        color: _textPrimary,
                        fontSize: isDesktop ? 20 : 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    bottom: PreferredSize(
                      preferredSize: const Size.fromHeight(56),
                      child: _buildCategoryTabs(isDesktop),
                    ),
                  ),
                  if (_loading)
                    _buildShimmer(isDesktop)
                  else if (_error != null)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _buildErrorState(),
                    )
                  else
                    _buildBody(isDesktop),
                  const SliverToBoxAdapter(child: SizedBox(height: 120)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCategoryTabs(bool isDesktop) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isDesktop ? 32 : 16, vertical: 8),
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            _buildTabChip('Albums', ArtistCatalogType.albums),
            const SizedBox(width: 8),
            _buildTabChip('Singles & EPs', ArtistCatalogType.singles),
            const SizedBox(width: 8),
            _buildTabChip('All Songs', ArtistCatalogType.songs),
          ],
        ),
      ),
    );
  }

  Widget _buildTabChip(String label, ArtistCatalogType type) {
    final isSelected = _selectedType == type;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => _loadCatalogForType(type),
      selectedColor: _primary,
      backgroundColor: _surfaceDark,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : _textDark,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
        fontSize: 13,
      ),
      side: BorderSide(
        color: isSelected ? _primary : _outline.withValues(alpha: 0.18),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded, size: 54, color: Colors.redAccent.withValues(alpha: 0.7)),
            const SizedBox(height: 16),
            Text(
              'Failed to load catalog',
              style: TextStyle(color: _textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? 'Unknown error',
              textAlign: TextAlign.center,
              style: TextStyle(color: _textDark, fontSize: 13),
            ),
            const SizedBox(height: 20),
            M3EButton.icon(
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
              onPressed: () => _loadCatalogForType(_selectedType),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(bool isDesktop) {
    switch (_selectedType) {
      case ArtistCatalogType.albums:
        return _buildAlbumGrid(_albums, isDesktop);
      case ArtistCatalogType.singles:
        return _buildAlbumGrid(_singles, isDesktop);
      case ArtistCatalogType.songs:
        return _buildSongsList(_songs, isDesktop);
    }
  }

  Widget _buildAlbumGrid(List<AlbumDetailed> items, bool isDesktop) {
    if (items.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Text(
            'No items found',
            style: TextStyle(color: _textDark, fontSize: 14),
          ),
        ),
      );
    }

    final crossAxisCount = isDesktop ? 5 : 2;

    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: isDesktop ? 32 : 16, vertical: 16),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 14,
          mainAxisSpacing: 18,
          childAspectRatio: 0.76,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final album = items[index];
            final thumb = _getBestThumbnail(album.thumbnails);

            return InkWell(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AlbumDetailScreen(
                      item: album,
                      onPlayTracks: widget.onPlayTracks,
                    ),
                  ),
                );
              },
              borderRadius: BorderRadius.circular(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: _surfaceDark,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: thumb != null
                          ? CachedNetworkImage(
                              imageUrl: thumb,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: double.infinity,
                              memCacheWidth: 400,
                              memCacheHeight: 400,
                              placeholder: (_, __) => Container(color: _surfaceDark),
                              errorWidget: (_, __, ___) => Center(
                                child: Icon(Icons.album_rounded, color: _textDark.withValues(alpha: 0.4), size: 36),
                              ),
                            )
                          : Center(
                              child: Icon(Icons.album_rounded, color: _textDark.withValues(alpha: 0.4), size: 36),
                            ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    album.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    album.year != null ? '${album.year}' : 'Release',
                    style: TextStyle(color: _textDark, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            );
          },
          childCount: items.length,
        ),
      ),
    );
  }

  Widget _buildSongsList(List<SongDetailed> songs, bool isDesktop) {
    if (songs.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Text(
            'No songs found',
            style: TextStyle(color: _textDark, fontSize: 14),
          ),
        ),
      );
    }

    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: isDesktop ? 32 : 16, vertical: 12),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final song = songs[index];
            final thumb = _getBestThumbnail(song.thumbnails);
            final isFirst = index == 0;
            final isLast = index == songs.length - 1;
            final borderRadius = BorderRadius.only(
              topLeft: Radius.circular(isFirst ? 20 : 6),
              topRight: Radius.circular(isFirst ? 20 : 6),
              bottomLeft: Radius.circular(isLast ? 20 : 6),
              bottomRight: Radius.circular(isLast ? 20 : 6),
            );

            final hasAlbum = song.album != null && song.album!.name.isNotEmpty;

            return Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Material(
                color: _surfaceDark,
                shape: RoundedRectangleBorder(
                  borderRadius: borderRadius,
                  side: BorderSide(color: _outline.withValues(alpha: 0.12)),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () {
                    if (widget.onPlayTracks != null) {
                      final trackInfos = songs.map((s) {
                        return TrackInfo.fromSongDetailed(
                          s,
                          album: s.album?.name,
                          albumId: s.album?.albumId,
                        );
                      }).toList();
                      Navigator.of(context).popUntil((r) => r.isFirst);
                      widget.onPlayTracks!(trackInfos, initialIndex: index);
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 24,
                          child: Text(
                            '${index + 1}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _textDark,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 44,
                            height: 44,
                            child: thumb != null
                                ? CachedNetworkImage(
                                    imageUrl: thumb,
                                    fit: BoxFit.cover,
                                    memCacheWidth: 100,
                                    memCacheHeight: 100,
                                    placeholder: (_, __) => Container(color: _bgDark),
                                    errorWidget: (_, __, ___) => Container(
                                      color: _bgDark,
                                      child: Icon(Icons.music_note_rounded, color: _textDark, size: 20),
                                    ),
                                  )
                                : Container(
                                    color: _bgDark,
                                    child: Icon(Icons.music_note_rounded, color: _textDark, size: 20),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                song.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: _textPrimary,
                                  fontSize: isDesktop ? 15 : 13.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      widget.artistName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: _textDark, fontSize: isDesktop ? 13 : 11.5),
                                    ),
                                  ),
                                  if (hasAlbum) ...[
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 5),
                                      child: Container(
                                        width: 3,
                                        height: 3,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: _textDark.withValues(alpha: 0.5),
                                        ),
                                      ),
                                    ),
                                    Icon(Icons.album_outlined, size: 11, color: _textDark.withValues(alpha: 0.7)),
                                    const SizedBox(width: 3),
                                    Flexible(
                                      child: Text(
                                        song.album!.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: _textDark.withValues(alpha: 0.8),
                                          fontSize: isDesktop ? 12.5 : 11,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatDuration(song.duration),
                          style: TextStyle(
                            color: _textDark,
                            fontSize: isDesktop ? 13 : 11.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.play_circle_outline_rounded, size: 22),
                          color: _primary,
                          tooltip: 'Play track',
                          onPressed: () {
                            if (widget.onPlayTracks != null) {
                              final trackInfos = songs.map((s) {
                                return TrackInfo.fromSongDetailed(
                                  s,
                                  album: s.album?.name,
                                  albumId: s.album?.albumId,
                                );
                              }).toList();
                              Navigator.of(context).popUntil((r) => r.isFirst);
                              widget.onPlayTracks!(trackInfos, initialIndex: index);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
          childCount: songs.length,
        ),
      ),
    );
  }

  Widget _buildShimmer(bool isDesktop) {
    switch (_selectedType) {
      case ArtistCatalogType.albums:
      case ArtistCatalogType.singles:
        return _buildAlbumGridShimmer(isDesktop);
      case ArtistCatalogType.songs:
        return _buildSongsListShimmer(isDesktop);
    }
  }

  Widget _buildAlbumGridShimmer(bool isDesktop) {
    final crossAxisCount = isDesktop ? 5 : 2;
    final surface = context.cardDark;
    final highlight = surface.withValues(alpha: 0.55);

    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: isDesktop ? 32 : 16, vertical: 16),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 16,
          mainAxisSpacing: 20,
          childAspectRatio: 0.76,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            return Shimmer.fromColors(
              baseColor: surface,
              highlightColor: highlight,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AspectRatio(
                    aspectRatio: 1,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    height: 14,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: 60,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            );
          },
          childCount: isDesktop ? 10 : 6,
        ),
      ),
    );
  }

  Widget _buildSongsListShimmer(bool isDesktop) {
    final surface = context.cardDark;
    final highlight = surface.withValues(alpha: 0.55);

    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: isDesktop ? 32 : 16, vertical: 12),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final isFirst = index == 0;
            final isLast = index == 7;
            return Shimmer.fromColors(
              baseColor: surface,
              highlightColor: highlight,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Container(
                  height: 62,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(isFirst ? 20 : 6),
                      topRight: Radius.circular(isFirst ? 20 : 6),
                      bottomLeft: Radius.circular(isLast ? 20 : 6),
                      bottomRight: Radius.circular(isLast ? 20 : 6),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 20,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: double.infinity,
                              height: 13,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              width: 120,
                              height: 10,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        width: 32,
                        height: 10,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
          childCount: 8,
        ),
      ),
    );
  }
}
