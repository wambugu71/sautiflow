import 'package:flutter/material.dart';

enum SongOption {
  queue,
  info,
  share,
  delete,
}

class SongOptionsMenuButton extends StatelessWidget {
  final ValueChanged<SongOption> onOptionSelected;
  final double iconSize;
  final Color iconColor;

  const SongOptionsMenuButton({
    super.key,
    required this.onOptionSelected,
    this.iconSize = 24.0,
    this.iconColor = const Color(0xFF94A3B8),
  });

  @override
  Widget build(BuildContext context) {
    const surfaceColor = Color(0xFF18232E);

    return PopupMenuButton<SongOption>(
      icon: Icon(Icons.more_vert, color: iconColor, size: iconSize),
      color: surfaceColor,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Colors.white.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      onSelected: onOptionSelected,
      itemBuilder: (BuildContext context) => [
        const PopupMenuItem<SongOption>(
          value: SongOption.queue,
          child: Row(
            children: [
              Icon(Icons.queue_music, color: Color(0xFF137FEC), size: 20),
              SizedBox(width: 12),
              Text(
                'Play Next',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const PopupMenuItem<SongOption>(
          value: SongOption.info,
          child: Row(
            children: [
              Icon(Icons.info_outline, color: Colors.white70, size: 20),
              SizedBox(width: 12),
              Text(
                'Song Info',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const PopupMenuItem<SongOption>(
          value: SongOption.share,
          child: Row(
            children: [
              Icon(Icons.share_rounded, color: Colors.white70, size: 20),
              SizedBox(width: 12),
              Text(
                'Share',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(height: 1),
        const PopupMenuItem<SongOption>(
          value: SongOption.delete,
          child: Row(
            children: [
              Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
              SizedBox(width: 12),
              Text(
                'Delete',
                style: TextStyle(
                  color: Colors.redAccent,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
