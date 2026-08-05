import 'package:flutter/material.dart';
import '../services/app_theme_service.dart';

enum SongOption {
  queue,
  info,
  share,
  delete,
}

class SongOptionsMenuButton extends StatelessWidget {
  final ValueChanged<SongOption> onOptionSelected;
  final double iconSize;
  final Color? iconColor;

  const SongOptionsMenuButton({
    super.key,
    required this.onOptionSelected,
    this.iconSize = 24.0,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final surfaceColor = AppThemeService.instance.currentData.cardDark;
    final primary = AppThemeService.instance.currentData.primary;
    final effectiveIconColor = iconColor ?? AppThemeService.instance.currentData.textDark;

    return PopupMenuButton<SongOption>(
      icon: Icon(Icons.more_vert, color: effectiveIconColor, size: iconSize),
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
        PopupMenuItem<SongOption>(
          value: SongOption.queue,
          child: Row(
            children: [
              Icon(Icons.queue_music, color: primary, size: 20),
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
