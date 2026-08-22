import 'package:flutter/material.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import '../services/app_theme_service.dart';

enum SongOption {
  queue,
  addToPlaylist,
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
    final primary = AppThemeService.instance.currentData.primary;
    final effectiveIconColor =
        iconColor ?? AppThemeService.instance.currentData.textDark;

    return M3EMenu(
      anchorBuilder: (context, open) => InkWell(
        onTap: open,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(4.0),
          child: Icon(Icons.more_vert_rounded,
              color: effectiveIconColor, size: iconSize),
        ),
      ),
      children: [
        M3EMenuGroup.entries(
          entries: [
            M3EMenuEntry(
              label: 'Play Next',
              leading: Icon(Icons.queue_music_rounded, color: primary, size: 20),
              onPressed: () => onOptionSelected(SongOption.queue),
            ),
            M3EMenuEntry(
              label: 'Add to Playlist',
              leading: Icon(Icons.playlist_add_rounded, color: primary, size: 20),
              onPressed: () => onOptionSelected(SongOption.addToPlaylist),
            ),
            M3EMenuEntry(
              label: 'Song Info',
              leading:
                  const Icon(Icons.info_outline_rounded, color: Colors.white70, size: 20),
              onPressed: () => onOptionSelected(SongOption.info),
            ),
            M3EMenuEntry(
              label: 'Share',
              leading:
                  const Icon(Icons.share_rounded, color: Colors.white70, size: 20),
              onPressed: () => onOptionSelected(SongOption.share),
            ),
          ],
        ),
        M3EMenuGroup.entries(
          entries: [
            M3EMenuEntry(
              label: 'Delete',
              leading:
                  const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
              onPressed: () => onOptionSelected(SongOption.delete),
            ),
          ],
        ),
      ],
    );
  }
}
