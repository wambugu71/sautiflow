import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:metadata_god/metadata_god.dart';

class LocalAlbumArt extends StatefulWidget {
  final String path;
  final double size;
  final double borderRadius;
  final IconData fallbackIcon;

  const LocalAlbumArt({
    super.key,
    required this.path,
    this.size = 64.0,
    this.borderRadius = 12.0,
    this.fallbackIcon = Icons.music_note,
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
    setState(() {
      _isLoading = true;
      _hasError = false;
      _imageData = null;
    });

    try {
      final metadata = await MetadataGod.readMetadata(file: widget.path);
      if (metadata.picture != null && metadata.picture!.data.isNotEmpty) {
        if (mounted) {
          setState(() {
            _imageData = metadata.picture!.data;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _hasError = true;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
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
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: const Color(0xFF18232E),
        borderRadius: BorderRadius.circular(widget.borderRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: _buildContent(),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return Center(
        child: SizedBox(
          width: widget.size * 0.4,
          height: widget.size * 0.4,
          child: const CircularProgressIndicator(
            strokeWidth: 2.0,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white54),
          ),
        ),
      );
    }

    if (_imageData != null && !_hasError) {
      return Image.memory(
        _imageData!,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _buildFallback(),
      );
    }

    return _buildFallback();
  }

  Widget _buildFallback() {
    return Center(
      child: Icon(
        widget.fallbackIcon,
        color: Colors.white.withOpacity(0.5),
        size: widget.size * 0.5,
      ),
    );
  }
}
