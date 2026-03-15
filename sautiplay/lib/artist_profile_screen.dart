import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dart_ytmusic_api/dart_ytmusic_api.dart';
import 'package:loading_indicator_m3e/loading_indicator_m3e.dart';
import 'album_detail_screen.dart'; // For TrackInfo + routing

const _bgDark = Color(0xFF0a0a0a); // background-dark from HTML
const _surfaceDark = Color(0xFF111722); // surface-dark from HTML
const _primary = Color(0xFF2a75ef); // primary from HTML

class ArtistProfileScreen extends StatefulWidget {
  final String artistName;
  final Future<void> Function(List<TrackInfo> tracks, {int initialIndex})?
      onPlayTracks;

  const ArtistProfileScreen({
    super.key,
    required this.artistName,
    this.onPlayTracks,
  });

  @override
  State<ArtistProfileScreen> createState() => _ArtistProfileScreenState();
}

class _ArtistProfileScreenState extends State<ArtistProfileScreen> {
  final YTMusic _ytMusic = YTMusic();

  bool _isLoading = true;
  String? _error;

  ArtistFull? _artistFull;
  String? _artistId;

  // Header image fallback
  String? _headerImageUrl;

  @override
  void initState() {
    super.initState();
    _loadArtist();
  }

  Future<void> _loadArtist() async {
    try {
      await _ytMusic.initialize();
      // 1. Search for the artist to get their ID and highest-res thumbnail
      final results = await _ytMusic.search(widget.artistName);
      if (results.isEmpty) {
        throw Exception("Artist not found");
      }

      SearchResult? artistSearchItem;
      try {
        artistSearchItem = results.firstWhere((item) =>
            item is ArtistDetailed || item is ArtistDetailedSearchResult);
      } catch (e) {
        artistSearchItem = null;
      }

      if (artistSearchItem == null) {
        throw Exception("Could not resolve artist ID");
      }

      final artistInfo = artistSearchItem is ArtistDetailedSearchResult
          ? artistSearchItem.artistDetailed
          : artistSearchItem as ArtistDetailed;

      _artistId = artistInfo.artistId;
      _headerImageUrl = _getBestThumbnail(artistInfo.thumbnails);

      // 2. Fetch full artist details
      final fullProfile = await _ytMusic.getArtist(_artistId!);

      if (mounted) {
        setState(() {
          _artistFull = fullProfile;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  String? _getBestThumbnail(List<ThumbnailFull> thumbs) {
    if (thumbs.isEmpty) return null;
    final sorted = List<ThumbnailFull>.from(thumbs)
      ..sort((a, b) => b.width.compareTo(a.width));
    return sorted.first.url;
  }

  String _formatDuration(int? seconds) {
    if (seconds == null || seconds <= 0) return '--:--';
    final m = (seconds ~/ 60).toString();
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgDark,
      body: _isLoading
          ? _buildLoading()
          : _error != null
              ? _buildError()
              : _buildContent(),
    );
  }

  Widget _buildLoading() {
    return Center(
      child: LoadingIndicatorM3E(
        color: _primary,
        containerColor: _primary.withOpacity(0.2),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline,
              size: 64, color: Colors.white.withOpacity(0.3)),
          const SizedBox(height: 16),
          Text(
            'Could not load artist profile',
            style: TextStyle(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              _error ?? 'Unknown error',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _isLoading = true;
                _error = null;
              });
              _loadArtist();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _primary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
            ),
            child: const Text('Retry', style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }

  Widget _buildContent() {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        _buildSliverAppBar(),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 24),
                _buildTopTracksSection(),
                const SizedBox(height: 32),
                _buildDiscographySection('Albums', _artistFull!.topAlbums),
                const SizedBox(height: 32),
                _buildDiscographySection(
                    'Singles & EPs', _artistFull!.topSingles),
                const SizedBox(height: 32),
                // Since bio isn't natively available in `ArtistFull` in dart_ytmusic_api,
                // we'll rely on what's available or omit it. The HTML had it, but API doesn't.
                const SizedBox(height: 120), // Padding for player
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSliverAppBar() {
    // The HTML design uses a 45vh tall hero image with gradients
    final heroHeight = MediaQuery.of(context).size.height * 0.45;

    return SliverAppBar(
      expandedHeight: heroHeight.clamp(300, 500),
      pinned: true,
      backgroundColor: _bgDark.withOpacity(0.9),
      elevation: 0,
      leading: IconButton(
        icon: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.black26,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.arrow_back, color: Colors.white),
        ),
        onPressed: () => Navigator.pop(context),
      ),
      /*actions: [
        IconButton(
          icon: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.black26,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.more_horiz, color: Colors.white),
          ),
          onPressed: () {},
        ),
        const SizedBox(width: 8),
      ],*/
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            // Background Image
            if (_headerImageUrl != null)
              CachedNetworkImage(
                imageUrl: _headerImageUrl!,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(color: _surfaceDark),
                errorWidget: (context, url, error) =>
                    Container(color: _surfaceDark),
              )
            else
              Container(color: _surfaceDark),

            // Gradients from HTML
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.3),
                      Colors.transparent,
                      _bgDark,
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: heroHeight / 2,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      _bgDark.withOpacity(
                          1), // HTML used an overlapping to-transparent gradient
                      _bgDark.withOpacity(0.6),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // Header Content
            Positioned(
              bottom: 24,
              left: 24,
              right: 24,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.verified, color: _primary, size: 20),
                      const SizedBox(width: 8),
                      Text('VERIFIED ARTIST',
                          style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.2)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _artistFull?.name ?? widget.artistName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      height: 1.1,
                      letterSpacing: -1.0,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      /*Container(
                         padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                         decoration: BoxDecoration(
                           color: Colors.white.withOpacity(0.1),
                           borderRadius: BorderRadius.circular(30),
                           border: Border.all(color: Colors.white.withOpacity(0.1)),
                         ),
                         child: Row(
                           children: [
                             Text('Follow', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                             const SizedBox(width: 8),
                             Text('24.5M', style: TextStyle(color: Colors.white60, fontSize: 12)),
                           ],
                         ),
                       ),*/
                      const SizedBox(),
                      GestureDetector(
                        onTap: () {
                          if (widget.onPlayTracks != null &&
                              _artistFull!.topSongs.isNotEmpty) {
                            final tracks = _artistFull!.topSongs
                                .map((s) => TrackInfo.fromSongDetailed(s))
                                .toList();
                            widget.onPlayTracks!(tracks, initialIndex: 0);
                          }
                        },
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                              color: _primary,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: _primary.withOpacity(0.4),
                                  blurRadius: 20,
                                  spreadRadius: 0,
                                )
                              ]),
                          child: const Icon(Icons.play_arrow,
                              color: Colors.white, size: 32),
                        ),
                      )
                    ],
                  )
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildTopTracksSection() {
    if (_artistFull!.topSongs.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Top Tracks',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold),
            ),
            /*TextButton(
              onPressed: () {},
              child: const Text('SEE ALL', style: TextStyle(color: Colors.white54, fontSize: 12, tracking: 1.2)),
            )*/
          ],
        ),
        const SizedBox(height: 16),
        ..._artistFull!.topSongs.asMap().entries.take(5).map((entry) {
          final idx = entry.key;
          final track = entry.value;
          return _buildTrackItem(idx, track);
        }),
      ],
    );
  }

  Widget _buildTrackItem(int index, SongDetailed item) {
    return InkWell(
      onTap: () {
        if (widget.onPlayTracks != null) {
          final tracks = _artistFull!.topSongs
              .map((s) => TrackInfo.fromSongDetailed(s))
              .toList();
          widget.onPlayTracks!(tracks, initialIndex: index);
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              child: Text('${index + 1}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white54,
                      fontSize: 14,
                      fontWeight: FontWeight.w500)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          item.name,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (item.name.toLowerCase().contains("explicit")) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                              color: Colors.white10,
                              borderRadius: BorderRadius.circular(4)),
                          child: const Text('E',
                              style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ],
                  ),
                  //  const SizedBox(height: 2),
                  //  Text('3.4B Plays', style: TextStyle(color: Colors.white38, fontSize: 12)),
                ],
              ),
            ),
            Text(_formatDuration(item.duration),
                style: const TextStyle(color: Colors.white54, fontSize: 14)),
            const SizedBox(width: 16),
            /*Icon(Icons.more_vert, color: Colors.white54, size: 20)*/
          ],
        ),
      ),
    );
  }

  Widget _buildDiscographySection(String title, List<AlbumDetailed> albums) {
    if (albums.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold),
            ),
            /* TextButton(
              onPressed: () {},
              child: const Text('SHOW ALL', style: TextStyle(color: Colors.white54, fontSize: 12, tracking: 1.2)),
            )*/
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 190,
          child: ListView.separated(
            physics: const BouncingScrollPhysics(),
            scrollDirection: Axis.horizontal,
            itemCount: albums.length,
            separatorBuilder: (context, index) => const SizedBox(width: 16),
            itemBuilder: (context, index) {
              final album = albums[index];
              return _buildAlbumCard(album);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAlbumCard(AlbumDetailed album) {
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
      child: SizedBox(
        width: 140,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: _surfaceDark,
              ),
              clipBehavior: Clip.antiAlias,
              child: thumb != null
                  ? CachedNetworkImage(
                      imageUrl: thumb,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Center(
                          child: Icon(Icons.album,
                              color: Colors.white24, size: 40)),
                      errorWidget: (context, url, err) => Center(
                          child: Icon(Icons.album,
                              color: Colors.white24, size: 40)),
                    )
                  : const Center(
                      child:
                          Icon(Icons.album, color: Colors.white24, size: 40)),
            ),
            const SizedBox(height: 8),
            Text(
              album.name,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              '${album.year != null ? '${album.year} • ' : ''}Album',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
