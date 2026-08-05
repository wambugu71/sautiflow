import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/app_theme_service.dart';

class MusicInfoDialog extends StatefulWidget {
  final String title;
  final String artist;
  final String album;
  final String genre;
  final String year;
  final String trackNumber;
  final Uint8List? albumArt;
  final String sourceType; // 'local' or 'online' / 'stream'
  final String? videoId; // File path or Video ID / URL
  final String codec;
  final String sampleRate;
  final String channels;
  final String bitDepth;
  final int fileSizeBytes;
  final Duration duration;
  final void Function({
    required String title,
    required String artist,
    required String album,
    required String genre,
    required String year,
    required String trackNumber,
  })? onSaveTags;

  const MusicInfoDialog({
    super.key,
    required this.title,
    required this.artist,
    this.album = 'Unknown Album',
    this.genre = 'Unknown Genre',
    this.year = '',
    this.trackNumber = '',
    this.albumArt,
    required this.sourceType,
    this.videoId,
    this.codec = 'MP3',
    this.sampleRate = '44.1 kHz',
    this.channels = 'STEREO',
    this.bitDepth = '16 bit',
    this.fileSizeBytes = 0,
    required this.duration,
    this.onSaveTags,
  });

  @override
  State<MusicInfoDialog> createState() => _MusicInfoDialogState();
}

class _MusicInfoDialogState extends State<MusicInfoDialog> {
  int _selectedTab = 0; // 0 = Track Info, 1 = Edit Tags

  late TextEditingController _titleController;
  late TextEditingController _artistController;
  late TextEditingController _albumController;
  late TextEditingController _genreController;
  late TextEditingController _yearController;
  late TextEditingController _trackNumController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.title);
    _artistController = TextEditingController(text: widget.artist);
    _albumController = TextEditingController(text: widget.album);
    _genreController = TextEditingController(text: widget.genre);
    _yearController = TextEditingController(text: widget.year);
    _trackNumController = TextEditingController(text: widget.trackNumber);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _artistController.dispose();
    _albumController.dispose();
    _genreController.dispose();
    _yearController.dispose();
    _trackNumController.dispose();
    super.dispose();
  }

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return 'Stream / Dynamic';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0 ? '${h.toString().padLeft(2, '0')}:$m:$s' : '$m:$s';
  }

  void _copyToClipboard(BuildContext context) {
    final summary = '''
Title: ${widget.title}
Artist: ${widget.artist}
Source: ${widget.sourceType.toUpperCase()}
Codec: ${widget.codec}
Sample Rate: ${widget.sampleRate}
Bit Depth: ${widget.bitDepth}
Channels: ${widget.channels}
Duration: ${_formatDuration(widget.duration)}
Path/ID: ${widget.videoId ?? 'N/A'}
''';
    Clipboard.setData(ClipboardData(text: summary));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Track metadata copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _handleSaveTags() {
    if (widget.onSaveTags != null) {
      widget.onSaveTags!(
        title: _titleController.text.trim(),
        artist: _artistController.text.trim(),
        album: _albumController.text.trim(),
        genre: _genreController.text.trim(),
        year: _yearController.text.trim(),
        trackNumber: _trackNumController.text.trim(),
      );
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = AppThemeService.instance.currentData.primary;
    final surfaceColor = AppThemeService.instance.currentData.cardDark;
    final cardBgColor = AppThemeService.instance.currentData.bgDark;
    final textDark = AppThemeService.instance.currentData.textDark;

    final isLocal = widget.sourceType.toLowerCase() == 'local';

    return Dialog(
      backgroundColor: cardBgColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24.0),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.1), width: 1),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Header Card ──────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: surfaceColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.05),
                  ),
                ),
                child: Row(
                  children: [
                    // Album Art
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: primaryColor.withValues(alpha: 0.2),
                        image: widget.albumArt != null && widget.albumArt!.isNotEmpty
                            ? DecorationImage(
                                image: MemoryImage(widget.albumArt!),
                                fit: BoxFit.cover,
                              )
                            : const DecorationImage(
                                image: AssetImage('assets/icon/splash.png'),
                                fit: BoxFit.cover,
                              ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    // Title & Artist & Source Badge
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _titleController.text.isNotEmpty
                                ? _titleController.text
                                : widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _artistController.text.isNotEmpty
                                ? _artistController.text
                                : widget.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: textDark,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: isLocal
                                  ? const Color(0xFF0EA5E9).withValues(alpha: 0.2)
                                  : const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isLocal
                                    ? const Color(0xFF0EA5E9).withValues(alpha: 0.5)
                                    : const Color(0xFF8B5CF6).withValues(alpha: 0.5),
                                width: 0.8,
                              ),
                            ),
                            child: Text(
                              isLocal ? 'LOCAL FILE' : 'ONLINE STREAM',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                                color: isLocal
                                    ? const Color(0xFF38BDF8)
                                    : const Color(0xFFA78BFA),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── Tab Switcher ──────────────────────────────────────────────
              Container(
                height: 40,
                decoration: BoxDecoration(
                  color: surfaceColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedTab = 0),
                        child: Container(
                          decoration: BoxDecoration(
                            color: _selectedTab == 0 ? primaryColor : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(
                            child: Text(
                              'Track Info',
                              style: TextStyle(
                                color: _selectedTab == 0 ? Colors.white : textDark,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedTab = 1),
                        child: Container(
                          decoration: BoxDecoration(
                            color: _selectedTab == 1 ? primaryColor : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(
                            child: Text(
                              'Edit Tags',
                              style: TextStyle(
                                color: _selectedTab == 1 ? Colors.white : textDark,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── Content Area ──────────────────────────────────────────────
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: _selectedTab == 0 ? _buildTrackInfoTab() : _buildEditTagsTab(),
                ),
              ),

              const SizedBox(height: 16),

              // ── Action Footer ─────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (_selectedTab == 0)
                    TextButton.icon(
                      onPressed: () => _copyToClipboard(context),
                      icon: Icon(Icons.copy, size: 16, color: primaryColor),
                      label: Text('Copy Metadata', style: TextStyle(color: primaryColor, fontSize: 13, fontWeight: FontWeight.w600)),
                    )
                  else
                    const SizedBox.shrink(),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text('Close', style: TextStyle(color: textDark)),
                      ),
                      if (_selectedTab == 1) ...[
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _handleSaveTags,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          ),
                          child: const Text('Save Tags', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTrackInfoTab() {
    return Column(
      children: [
        _buildInfoTile(
          icon: Icons.subtitles,
          label: 'Title',
          value: widget.title,
        ),
        _buildInfoTile(
          icon: Icons.person,
          label: 'Artist',
          value: widget.artist,
        ),
        _buildInfoTile(
          icon: Icons.album,
          label: 'Album',
          value: widget.album,
        ),
        _buildInfoTile(
          icon: Icons.audiotrack,
          label: 'Codec / Format',
          value: widget.codec.toUpperCase(),
        ),
        _buildInfoTile(
          icon: Icons.graphic_eq,
          label: 'Sample Rate',
          value: widget.sampleRate,
        ),
        _buildInfoTile(
          icon: Icons.tune,
          label: 'Bit Depth',
          value: widget.bitDepth.isNotEmpty ? widget.bitDepth : '16 bit',
        ),
        _buildInfoTile(
          icon: Icons.speaker,
          label: 'Channels',
          value: widget.channels,
        ),
        _buildInfoTile(
          icon: Icons.storage,
          label: 'File Size',
          value: _formatFileSize(widget.fileSizeBytes),
        ),
        _buildInfoTile(
          icon: Icons.timer,
          label: 'Duration',
          value: _formatDuration(widget.duration),
        ),
        if (widget.videoId != null && widget.videoId!.isNotEmpty)
          _buildInfoTile(
            icon: Icons.link,
            label: widget.sourceType == 'local' ? 'File Path' : 'Stream URL / ID',
            value: widget.videoId!,
            isCopyable: true,
          ),
      ],
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String label,
    required String value,
    bool isCopyable = false,
  }) {
    final surfaceColor = AppThemeService.instance.currentData.cardDark;
    final textDark = AppThemeService.instance.currentData.textDark;
    final primaryColor = AppThemeService.instance.currentData.primary;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.03)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: primaryColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 11, color: textDark, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                SelectableText(
                  value,
                  style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w600),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          if (isCopyable)
            IconButton(
              icon: Icon(Icons.copy, size: 16, color: textDark),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: value));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Copied $label'), duration: const Duration(seconds: 1)),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildEditTagsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTagTextField(
          controller: _titleController,
          label: 'Track Title',
          icon: Icons.title,
        ),
        const SizedBox(height: 12),
        _buildTagTextField(
          controller: _artistController,
          label: 'Artist',
          icon: Icons.person,
        ),
        const SizedBox(height: 12),
        _buildTagTextField(
          controller: _albumController,
          label: 'Album',
          icon: Icons.album,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildTagTextField(
                controller: _genreController,
                label: 'Genre',
                icon: Icons.style,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildTagTextField(
                controller: _yearController,
                label: 'Year',
                icon: Icons.calendar_today,
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildTagTextField(
          controller: _trackNumController,
          label: 'Track Number',
          icon: Icons.format_list_numbered,
          keyboardType: TextInputType.number,
        ),
      ],
    );
  }

  Widget _buildTagTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
  }) {
    final surfaceColor = AppThemeService.instance.currentData.cardDark;
    final primaryColor = AppThemeService.instance.currentData.primary;

    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
        prefixIcon: Icon(icon, color: primaryColor, size: 20),
        filled: true,
        fillColor: surfaceColor,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primaryColor, width: 1.5),
        ),
      ),
    );
  }
}
