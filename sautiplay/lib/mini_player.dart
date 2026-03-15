import 'dart:typed_data';
import 'package:flutter/material.dart';

class MiniPlayer extends StatelessWidget {
  final String title;
  final String artist;
  final Uint8List? albumArt;
  final double progress; // 0.0 to 1.0
  final bool isPlaying;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onTap;

  const MiniPlayer({
    super.key,
    required this.title,
    required this.artist,
    this.albumArt,
    this.progress = 0.0,
    required this.isPlaying,
    required this.onPlayPause,
    required this.onNext,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 64,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xFF1C252E), // surfaceDarkColor
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
        child: Column(
          children: [
            // Top Progress Bar
            LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 2,
              backgroundColor: Colors.transparent,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(Color(0xFF137fec)),
            ),
            // Main content
            Expanded(
              child: Row(
                children: [
                  // Album Art
                  Container(
                    width: 48,
                    height: 48,
                    margin: const EdgeInsets.only(left: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF137fec)
                          .withValues(alpha: 0.2), // primaryColor
                      borderRadius: BorderRadius.circular(12),
                      image: albumArt != null
                          ? DecorationImage(
                              image: MemoryImage(albumArt!),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: albumArt == null
                        ? const Icon(
                            Icons.music_note,
                            color: Color(0xFF137fec),
                          )
                        : null,
                  ),
                  const SizedBox(width: 16),
                  // Track Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Controls
                  IconButton(
                    onPressed: onPlayPause,
                    icon: Icon(
                      isPlaying
                          ? Icons.pause_circle_filled
                          : Icons.play_circle_filled,
                      size: 32,
                      color: Colors.white,
                    ),
                  ),
                  IconButton(
                    onPressed: onNext,
                    icon: const Icon(
                      Icons.skip_next,
                      size: 28,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
