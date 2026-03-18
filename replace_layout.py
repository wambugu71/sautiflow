import re

with open('lib/now_playing_screen.dart', 'r', encoding='utf-8') as f:
    text = f.read()

# We want to replace the `LayoutBuilder` child block.
# Let's locate the LayoutBuilder

pattern = r'LayoutBuilder\(builder: \(context, constraints\) \{[\s\S]*?\}\),\n              \],\n            \),\n          \),\n        \);'

def create_replacement():
    return """LayoutBuilder(builder: (context, constraints) {
                  final isDesktop = constraints.maxWidth >= 800;
                  
                  final topAppBar = Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16.0, vertical: 8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.keyboard_arrow_down,
                              size: 32, color: textLight),
                          onPressed: widget.onMinimize,
                        ),
                        Flexible(
                          child: Column(
                            children: [
                              Text(
                                'PLAYING FROM PLAYLIST',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.5,
                                  color: primaryColor,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'Now Playing',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: textLight,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 48),
                      ],
                    ),
                  );

                  final pureAlbumArt = Padding(
                    padding: EdgeInsets.all(isDesktop ? 32.0 : 0.0),
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: 1.0,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(isDesktop ? 16.0 : 8.0),
                            color: surfaceColor,
                            boxShadow: [
                              BoxShadow(
                                color: primaryColor.withOpacity(0.3),
                                blurRadius: 40,
                                spreadRadius: 2,
                                offset: const Offset(0, 10),
                              ),
                            ],
                            image: widget.albumArt != null
                                ? DecorationImage(
                                    image: MemoryImage(widget.albumArt!),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ),
                  );

                  final pureLyrics = _isLoadingLyrics
                      ? Center(
                          child: LoadingIndicatorM3E(
                              color: primaryColor,
                              containerColor: primaryColor.withAlpha(50)))
                      : _lyricsRaw == null
                          ? Center(
                              child: Text(
                                'No lyrics available',
                                style: TextStyle(color: textDark, fontSize: 16),
                              ),
                            )
                          : LyricView(
                              controller: _lyricController,
                            );

                  final metadataWidget = Padding(
                    padding: EdgeInsets.symmetric(horizontal: isDesktop ? 0.0 : 32.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: textLight,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              InkWell(
                                onTap: subtitle.isNotEmpty &&
                                        title.isNotEmpty &&
                                        !title.contains("content://") &&
                                        sourceType != 'local'
                                    ? () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => ArtistProfileScreen(
                                              artistName: subtitle,
                                              onPlayTracks: widget.onPlayTracks,
                                            ),
                                          ),
                                        );
                                      }
                                    : null,
                                borderRadius: BorderRadius.circular(4),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 2.0, horizontal: 4.0),
                                  child: Text(
                                    subtitle,
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w500,
                                      color: textDark,
                                      decoration: sourceType != 'local'
                                          ? TextDecoration.underline
                                          : TextDecoration.none,
                                      decorationColor:
                                          textDark.withValues(alpha: 0.5),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        ValueListenableBuilder<List<LikedSong>>(
                          valueListenable: LikedSongsService.instance.likedSongsNotifier,
                          builder: (context, likedSongs, _) {
                            final trackId = widget.videoId ?? widget.getTitle(status.currentIndex);
                            final isCurrentlyLiked = likedSongs.any((s) => s.videoId == trackId);
                            return IconButton(
                              icon: Icon(
                                  isCurrentlyLiked
                                      ? Icons.favorite
                                      : Icons.favorite_border,
                                  size: 28,
                                  color: primaryColor),
                              onPressed: () async {
                                if (trackId.isEmpty) return;
                                if (isCurrentlyLiked) {
                                  await LikedSongsService.instance.removeLikedSong(trackId);
                                } else {
                                  await LikedSongsService.instance.addLikedSong(LikedSong(
                                    videoId: trackId,
                                    title: title,
                                    artist: subtitle,
                                    thumbnailUrl: widget.albumArt == null ? null : trackId,
                                    durationSeconds: duration.inSeconds,
                                    likedAt: DateTime.now(),
                                  ));
                                }
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  );

                  final visualizerWidget = _analyzerValues.isNotEmpty
                      ? Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: isDesktop ? 0.0 : 24.0, vertical: 24.0),
                          child: SizedBox(
                            height: 60,
                            child: _buildVisualizer(primaryColor, _analyzerValues),
                          ),
                        )
                      : const SizedBox(height: 108);

                  final progressBarWidget = Padding(
                    padding: EdgeInsets.symmetric(horizontal: isDesktop ? 0.0 : 24.0),
                    child: Column(
                      children: [
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 4.0,
                            activeTrackColor: primaryColor,
                            inactiveTrackColor: Colors.white24,
                            thumbColor: Colors.white,
                            overlayColor: primaryColor.withOpacity(0.2),
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14.0),
                          ),
                          child: Slider(
                            value: posMs,
                            min: 0.0,
                            max: maxMs,
                            onChanged: (v) {
                              widget.player.seekTo(Duration(milliseconds: v.toInt()));
                            },
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(_fmt(position),
                                  style: const TextStyle(
                                      fontSize: 12, color: textDark, fontFamily: 'monospace')),
                              Text(_fmt(duration),
                                  style: const TextStyle(
                                      fontSize: 12, color: textDark, fontFamily: 'monospace')),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );

                  final playbackControlsWidget = Padding(
                    padding: EdgeInsets.symmetric(
                        horizontal: isDesktop ? 0.0 : 24.0, vertical: 16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton(
                          icon: Icon(
                              status.shuffleEnabled ? Icons.shuffle_on : Icons.shuffle,
                              color: status.shuffleEnabled ? primaryColor : textDark),
                          onPressed: () {
                            widget.player.setShuffleModeEnabled(!status.shuffleEnabled);
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.skip_previous, size: 36, color: textLight),
                          onPressed: widget.player.seekToPrevious,
                        ),
                        GestureDetector(
                          onTap: status.isPlaying ? widget.player.pause : widget.player.play,
                          child: Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: primaryColor,
                              boxShadow: [
                                BoxShadow(
                                  color: primaryColor.withOpacity(0.4),
                                  blurRadius: 20,
                                  spreadRadius: 2,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Icon(
                              status.isPlaying ? Icons.pause : Icons.play_arrow,
                              size: 40,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.skip_next, size: 36, color: textLight),
                          onPressed: widget.player.seekToNext,
                        ),
                        PopupMenuButton<LoopMode>(
                          initialValue: status.loopMode,
                          icon: Icon(_loopIcon(status.loopMode),
                              color: status.loopMode != LoopMode.off ? primaryColor : textDark),
                          onSelected: widget.player.setLoopMode,
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: LoopMode.off, child: Text('Loop Off')),
                            PopupMenuItem(value: LoopMode.all, child: Text('Loop All')),
                            PopupMenuItem(value: LoopMode.one, child: Text('Loop One')),
                          ],
                        ),
                      ],
                    ),
                  );

                  final extraControlsWidget = Padding(
                    padding: EdgeInsets.symmetric(horizontal: isDesktop ? 0.0 : 48.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.tune, color: textLight, size: 26),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => EqScreen(
                                  player: widget.player,
                                  analyzerEnabled: true,
                                  analyzerType: 'bar',
                                ),
                              ),
                            );
                          },
                        ),
                        IconButton(
                          icon: Icon(
                            _showLyrics ? Icons.music_note : Icons.lyrics_outlined,
                            color: _showLyrics ? primaryColor : textLight,
                            size: 26,
                          ),
                          onPressed: () {
                            setState(() {
                              _showLyrics = !_showLyrics;
                            });
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.queue_music_outlined, color: textLight, size: 26),
                          onPressed: () => _showQueueSheet(context),
                        ),
                      ],
                    ),
                  );

                  final audioInfoWidget = Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: Colors.white.withValues(alpha: 0.05),
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.graphic_eq, size: 14, color: textDark.withValues(alpha: 0.6)),
                            const SizedBox(width: 4),
                            Text('$_audioFormat   / $_sampleRate',
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1.2,
                                    color: textDark.withValues(alpha: 0.6))),
                          ],
                        ),
                        Container(
                          width: 1, height: 12,
                          margin: const EdgeInsets.symmetric(horizontal: 12),
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.speaker_group, size: 14, color: textDark.withValues(alpha: 0.6)),
                            const SizedBox(width: 4),
                            Text(_channels,
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1.2,
                                    color: textDark.withValues(alpha: 0.6))),
                          ],
                        ),
                        Container(
                          width: 1, height: 12,
                          margin: const EdgeInsets.symmetric(horizontal: 12),
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.code, size: 14, color: textDark.withValues(alpha: 0.6)),
                            const SizedBox(width: 4),
                            Text(widget.codec,
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1.2,
                                    color: textDark.withValues(alpha: 0.6))),
                          ],
                        ),
                      ],
                    ),
                  );

                  Widget content;
                  if (isDesktop) {
                    content = Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Left Column (Album Art + Info)
                        Expanded(
                          flex: 5,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              topAppBar,
                              const Spacer(),
                              Expanded(flex: 8, child: pureAlbumArt),
                              const Spacer(),
                              audioInfoWidget,
                              const SizedBox(height: 16),
                            ],
                          ),
                        ),
                        const SizedBox(width: 48),
                        // Right Column (Controls + Lyrics)
                        Expanded(
                          flex: 7,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 48.0, top: 24.0, bottom: 24.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (_showLyrics)
                                  Expanded(child: pureLyrics)
                                else
                                  const Spacer(),
                                metadataWidget,
                                visualizerWidget,
                                progressBarWidget,
                                const SizedBox(height: 16),
                                playbackControlsWidget,
                                extraControlsWidget,
                                if (!_showLyrics)
                                  const Spacer(),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  } else {
                    content = Column(
                      children: [
                        const SizedBox(height: 24),
                        topAppBar,
                        Expanded(
                          child: _showLyrics ? Padding(padding: const EdgeInsets.symmetric(), child: pureLyrics) : Padding(padding: const EdgeInsets.symmetric(), child: pureAlbumArt),
                        ),
                        metadataWidget,
                        visualizerWidget,
                        progressBarWidget,
                        const SizedBox(height: 16),
                        playbackControlsWidget,
                        extraControlsWidget,
                        const SizedBox(height: 16),
                        audioInfoWidget,
                      ],
                    );
                  }

                  return Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: isDesktop ? 1200.0 : 600.0),
                      child: SafeArea(
                        child: content,
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        );"""

import sys
new_text = re.sub(pattern, create_replacement(), text)
if text == new_text:
    print("Failed to replace")
    sys.exit(1)

with open('lib/now_playing_screen.dart', 'w', encoding='utf-8') as f:
    f.write(new_text)

print("Replaced successfully")
