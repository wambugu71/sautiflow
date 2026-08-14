import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter_m3shapes_extended/flutter_m3shapes_extended.dart';
import 'package:material_3_expressive/components/loading_indicator/m3e_loading_indicator.dart';
import '../services/app_theme_service.dart';

// Global cache to prevent re-reading files on scroll
final Map<String, Uint8List?> _albumArtCache = {};
final Map<String, bool> _albumArtAttempted = {};

Future<Uint8List?> _extractArtTask(String path) async {
  try {
    final metadata = readMetadata(File(path), getImage: true);
    if (metadata.pictures.isNotEmpty) {
      return metadata.pictures.first.bytes;
    }

    // Fallback to directory
    final dir = File(path).parent;
    if (dir.existsSync()) {
      final files = dir.listSync();
      for (final f in files) {
        if (f is File) {
          final lowerPath = f.path.toLowerCase();
          if (lowerPath.endsWith('.jpg') ||
              lowerPath.endsWith('.jpeg') ||
              lowerPath.endsWith('.png') ||
              lowerPath.endsWith('.webp')) {
            return f.readAsBytesSync();
          }
        }
      }
    }
  } catch (e) {
    debugPrint('[LocalAlbumArt] Failed to read art for $path: $e');
  }
  return null;
}

class LocalAlbumArt extends StatefulWidget {
  final String path;
  final double size;
  final double borderRadius;
  final IconData fallbackIcon;
  final Shapes shape;
  final bool useM3Shape;

  const LocalAlbumArt({
    super.key,
    required this.path,
    this.size = 64.0,
    this.borderRadius = 12.0,
    this.fallbackIcon = Icons.music_note,
    this.shape = Shapes.pill,
    this.useM3Shape = true,
  });

  @override
  State<LocalAlbumArt> createState() => _LocalAlbumArtState();
}

class _LocalAlbumArtState extends State<LocalAlbumArt> {
  Uint8List? _imageData;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadAlbumArt();
  }

  @override
  void didUpdateWidget(LocalAlbumArt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _loadAlbumArt();
    }
  }

  Future<void> _loadAlbumArt() async {
    if (!mounted) return;

    if (_albumArtAttempted[widget.path] == true) {
      setState(() {
        _imageData = _albumArtCache[widget.path];
        _isLoading = false;
        _hasError = _imageData == null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _hasError = false;
      _imageData = null;
    });

    try {
      final bytes = await compute(_extractArtTask, widget.path);

      _albumArtAttempted[widget.path] = true;
      _albumArtCache[widget.path] = bytes;

      if (mounted) {
        setState(() {
          _imageData = bytes;
          _isLoading = false;
          _hasError = bytes == null;
        });
      }
    } catch (e) {
      debugPrint('[LocalAlbumArt] Compute error for ${widget.path}: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeData = AppThemeProvider.of(context);
    final cardColor = themeData.cardDark;
    final double? containerWidth = widget.size.isFinite ? widget.size : null;
    final double? containerHeight = widget.size.isFinite ? widget.size : null;

    final Widget innerContent = LayoutBuilder(
      builder: (context, constraints) {
        double side = 48.0;
        if (constraints.maxWidth.isFinite && constraints.maxWidth > 0) {
          side = constraints.maxWidth;
        } else if (widget.size.isFinite && widget.size > 0) {
          side = widget.size;
        }
        final double iconSize = (side * 0.5).clamp(12.0, 120.0);
        final double progressSize = (side * 0.4).clamp(12.0, 48.0);

        if (_isLoading) {
          return Center(
            child: SizedBox(
                width: progressSize,
                height: progressSize,
                child: M3ELoadingIndicator(
                  color: themeData.primary.withAlpha(180),
                  containerColor: themeData.primary.withAlpha(100),
                  variant: M3ELoadingIndicatorVariant.contained,
                ) // CircularProgressIndicator(
                //strokeWidth: 2.0,
                //valueColor: AlwaysStoppedAnimation<Color>(themeData.primary.withAlpha(180)),
                //),
                ),
          );
        }

        if (_imageData != null && !_hasError) {
          return Image.memory(
            _imageData!,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              debugPrint(
                  '[LocalAlbumArt] Image.memory decode error for ${widget.path}: $error');
              return _buildFallback(iconSize, themeData.textDark);
            },
          );
        }

        return _buildFallback(iconSize, themeData.textDark);
      },
    );

    if (widget.useM3Shape) {
      return RepaintBoundary(
        child: M3EContainer(
          widget.shape,
          width: containerWidth,
          height: containerHeight,
          color: cardColor,
          clipBehavior: Clip.antiAlias,
          /*boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(51),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],*/
          child: innerContent,
        ),
      );
    }

    return RepaintBoundary(
      child: Container(
        width: containerWidth,
        height: containerHeight,
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(widget.borderRadius),
          /*boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(51),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],*/
        ),
        clipBehavior: Clip.antiAlias,
        child: innerContent,
      ),
    );
  }

  Widget _buildFallback(double iconSize, Color iconColor) {
    return Center(
      child: Icon(
        widget.fallbackIcon,
        color: iconColor,
        size: iconSize.isFinite ? iconSize : 24.0,
      ),
    );
  }
}
