import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'm3e_modal_helpers.dart';
import '../database/app_database.dart';
import '../services/app_theme_service.dart';
import '../services/metadata_intelligence_service.dart';
import 'adaptive_marquee_text.dart';

class MusicInfoDialog extends StatefulWidget {
  final String title;
  final String artist;
  final String album;
  final String genre;
  final String year;
  final String trackNumber;
  final String albumArtist;
  final String discNumber;
  final String composer;
  final String bpm;
  final String musicalKey;
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
  final void Function({
    required String title,
    required String artist,
    required String album,
    required String genre,
    required String year,
    required String trackNumber,
    required String albumArtist,
    required String discNumber,
    required String composer,
    required String bpm,
    required String musicalKey,
  })? onSaveExtendedTags;
  final VoidCallback? onUndoTags;

  const MusicInfoDialog({
    super.key,
    required this.title,
    required this.artist,
    this.album = 'Unknown Album',
    this.genre = 'Unknown Genre',
    this.year = '',
    this.trackNumber = '',
    this.albumArtist = '',
    this.discNumber = '',
    this.composer = '',
    this.bpm = '',
    this.musicalKey = '',
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
    this.onSaveExtendedTags,
    this.onUndoTags,
  });

  static Future<void> show(
    BuildContext context, {
    required String title,
    required String artist,
    String album = 'Unknown Album',
    String genre = 'Unknown Genre',
    String year = '',
    String trackNumber = '',
    String albumArtist = '',
    String discNumber = '',
    String composer = '',
    String bpm = '',
    String musicalKey = '',
    Uint8List? albumArt,
    required String sourceType,
    String? videoId,
    String codec = 'MP3',
    String sampleRate = '44.1 kHz',
    String channels = 'STEREO',
    String bitDepth = '16 bit',
    int fileSizeBytes = 0,
    required Duration duration,
    void Function({
      required String title,
      required String artist,
      required String album,
      required String genre,
      required String year,
      required String trackNumber,
    })? onSaveTags,
    void Function({
      required String title,
      required String artist,
      required String album,
      required String genre,
      required String year,
      required String trackNumber,
      required String albumArtist,
      required String discNumber,
      required String composer,
      required String bpm,
      required String musicalKey,
    })? onSaveExtendedTags,
    VoidCallback? onUndoTags,
  }) async {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final dialogWidget = MusicInfoDialog(
      title: title,
      artist: artist,
      album: album,
      genre: genre,
      year: year,
      trackNumber: trackNumber,
      albumArtist: albumArtist,
      discNumber: discNumber,
      composer: composer,
      bpm: bpm,
      musicalKey: musicalKey,
      albumArt: albumArt,
      sourceType: sourceType,
      videoId: videoId,
      codec: codec,
      sampleRate: sampleRate,
      channels: channels,
      bitDepth: bitDepth,
      fileSizeBytes: fileSizeBytes,
      duration: duration,
      onSaveTags: onSaveTags,
      onSaveExtendedTags: onSaveExtendedTags,
      onUndoTags: onUndoTags,
    );

    if (isMobile) {
      await showSautiM3EBottomSheet<void>(
        context,
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: dialogWidget,
          ),
        ),
      );
    } else {
      await showSautiM3EDialog<void>(
        context,
        dialog: dialogWidget,
      );
    }
  }

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
  late TextEditingController _albumArtistController;
  late TextEditingController _discNumController;
  late TextEditingController _composerController;
  late TextEditingController _bpmController;
  late TextEditingController _musicalKeyController;

  String? _inferenceBanner;
  bool _hasUndoHistory = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.title);
    _artistController = TextEditingController(text: widget.artist);
    _albumController = TextEditingController(text: widget.album);
    _genreController = TextEditingController(text: widget.genre);
    _yearController = TextEditingController(text: widget.year);
    _trackNumController = TextEditingController(text: widget.trackNumber);
    _albumArtistController = TextEditingController(text: widget.albumArtist);
    _discNumController = TextEditingController(text: widget.discNumber);
    _composerController = TextEditingController(text: widget.composer);
    _bpmController = TextEditingController(text: widget.bpm);
    _musicalKeyController = TextEditingController(text: widget.musicalKey);
    _checkUndoHistory();
  }

  Future<void> _checkUndoHistory() async {
    final path = widget.videoId;
    if (path == null || widget.sourceType.toLowerCase() != 'local') return;
    final has = await AppDatabase.instance.hasTagEditHistory(path);
    if (mounted) {
      setState(() => _hasUndoHistory = has);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _artistController.dispose();
    _albumController.dispose();
    _genreController.dispose();
    _yearController.dispose();
    _trackNumController.dispose();
    _albumArtistController.dispose();
    _discNumController.dispose();
    _composerController.dispose();
    _bpmController.dispose();
    _musicalKeyController.dispose();
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
    if (widget.onSaveExtendedTags != null) {
      widget.onSaveExtendedTags!(
        title: _titleController.text.trim(),
        artist: _artistController.text.trim(),
        album: _albumController.text.trim(),
        genre: _genreController.text.trim(),
        year: _yearController.text.trim(),
        trackNumber: _trackNumController.text.trim(),
        albumArtist: _albumArtistController.text.trim(),
        discNumber: _discNumController.text.trim(),
        composer: _composerController.text.trim(),
        bpm: _bpmController.text.trim(),
        musicalKey: _musicalKeyController.text.trim(),
      );
    } else if (widget.onSaveTags != null) {
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

  void _guessFromFilename() {
    final path = widget.videoId;
    if (path == null || path.isEmpty) return;
    final inferred = MetadataIntelligenceService.instance.inferFromPath(path);
    if (!inferred.hasAny) return;
    setState(() {
      if (inferred.title != null) _titleController.text = inferred.title!;
      if (inferred.artist != null) _artistController.text = inferred.artist!;
      if (inferred.album != null) _albumController.text = inferred.album!;
      if (inferred.trackNumber != null) {
        _trackNumController.text = inferred.trackNumber.toString();
      }
      if (inferred.discNumber != null) {
        _discNumController.text = inferred.discNumber.toString();
      }
      if (inferred.year != null) {
        _yearController.text = inferred.year.toString();
      }
      final pct = (inferred.confidence * 100).round();
      _inferenceBanner =
          'Inferred ($pct% confidence • ${inferred.matchedPattern}). Review & Save.';
    });
  }

  void _cleanAndTitleCase() {
    final svc = MetadataIntelligenceService.instance;
    setState(() {
      _titleController.text = svc.normalizeTitleCase(_titleController.text);
      _artistController.text = svc.normalizeTitleCase(_artistController.text);
      _albumController.text = svc.normalizeTitleCase(_albumController.text);
      _inferenceBanner = 'Cleaned noise & applied smart title casing.';
    });
  }

  Future<void> _handleUndoLastEdit() async {
    final path = widget.videoId;
    if (path == null) return;
    final restored = await MetadataIntelligenceService.instance.undoLastEdit(path);
    if (restored == null || !mounted) return;
    setState(() {
      _titleController.text = restored.title;
      _artistController.text = restored.artist;
      _albumController.text = restored.album;
      _genreController.text = restored.genre;
      _yearController.text = restored.year?.toString() ?? '';
      _trackNumController.text = restored.trackNumber?.toString() ?? '';
      _albumArtistController.text = restored.albumArtist ?? '';
      _discNumController.text = restored.discNumber?.toString() ?? '';
      _composerController.text = restored.composer ?? '';
      _bpmController.text = restored.bpm?.toString() ?? '';
      _musicalKeyController.text = restored.musicalKey ?? '';
      _inferenceBanner = 'Reverted to previous tag snapshot.';
    });
    await _checkUndoHistory();
    widget.onUndoTags?.call();
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = AppThemeService.instance.currentData.primary;
    final surfaceColor = AppThemeService.instance.currentData.cardDark;
    final textDark = AppThemeService.instance.currentData.textDark;

    final isLocal = widget.sourceType.toLowerCase() == 'local';

    final screenHeight = MediaQuery.of(context).size.height;
    final maxContentHeight = (screenHeight * 0.55).clamp(280.0, 480.0);

    return M3EDialog(
      title: 'Track Info & Tags',
      topDivider: true,
      bottomDivider: true,
      content: SizedBox(
        width: 520,
        height: maxContentHeight,
        child: Column(
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
                      image:
                          widget.albumArt != null && widget.albumArt!.isNotEmpty
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
                        AdaptiveMarqueeText(
                          text: _titleController.text.isNotEmpty
                              ? _titleController.text
                              : widget.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        AdaptiveMarqueeText(
                          text: _artistController.text.isNotEmpty
                              ? _artistController.text
                              : widget.artist,
                          style: TextStyle(
                            color: textDark,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: isLocal
                                ? const Color(0xFF0EA5E9).withValues(alpha: 0.2)
                                : const Color(0xFF8B5CF6)
                                    .withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isLocal
                                  ? const Color(0xFF0EA5E9)
                                      .withValues(alpha: 0.5)
                                  : const Color(0xFF8B5CF6)
                                      .withValues(alpha: 0.5),
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
            const SizedBox(height: 12),

            // ── Tab Switcher ──────────────────────────────────────────────
            M3ESegmentedButton<int>(
              segments: const [
                M3ESegment(value: 0, label: 'Track Info'),
                M3ESegment(value: 1, label: 'Edit Tags'),
              ],
              selected: {_selectedTab},
              onSelectionChanged: (val) {
                if (val.isNotEmpty) {
                  setState(() => _selectedTab = val.first);
                }
              },
            ),
            const SizedBox(height: 12),

            // ── Content Area ──────────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: _selectedTab == 0
                    ? _buildTrackInfoTab()
                    : _buildEditTagsTab(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (_selectedTab == 0)
          M3EButton(
            onPressed: () => _copyToClipboard(context),
            child: Row(
              children: [
                const Icon(Icons.copy),
                const SizedBox(width: 4),
                const Text('Copy Metadata')
              ],
            ),
          ),
        M3EButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        if (_selectedTab == 1)
          M3EButton(
            onPressed: _handleSaveTags,
            child: const Text('Save Tags'),
          ),
      ],
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
            label:
                widget.sourceType == 'local' ? 'File Path' : 'Stream URL / ID',
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
                  style: TextStyle(
                      fontSize: 11,
                      color: textDark,
                      fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                SelectableText(
                  value,
                  style: const TextStyle(
                      fontSize: 13,
                      color: Colors.white,
                      fontWeight: FontWeight.w600),
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
                  SnackBar(
                      content: Text('Copied $label'),
                      duration: const Duration(seconds: 1)),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildEditTagsTab() {
    final primaryColor = AppThemeService.instance.currentData.primary;
    final isLocal = widget.sourceType.toLowerCase() == 'local';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isLocal) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                avatar: Icon(Icons.auto_fix_high, size: 16, color: primaryColor),
                label: const Text('Guess from Path', style: TextStyle(fontSize: 12)),
                onPressed: _guessFromFilename,
              ),
              ActionChip(
                avatar: Icon(Icons.cleaning_services_outlined,
                    size: 16, color: primaryColor),
                label: const Text('Clean & Title Case',
                    style: TextStyle(fontSize: 12)),
                onPressed: _cleanAndTitleCase,
              ),
              if (_hasUndoHistory)
                ActionChip(
                  avatar: const Icon(Icons.undo, size: 16, color: Colors.amber),
                  label: const Text('Undo Edit', style: TextStyle(fontSize: 12)),
                  onPressed: _handleUndoLastEdit,
                ),
            ],
          ),
          if (_inferenceBanner != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: primaryColor.withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  Icon(Icons.auto_awesome, size: 15, color: primaryColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _inferenceBanner!,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
        ],
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
          controller: _albumArtistController,
          label: 'Album Artist',
          icon: Icons.group,
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
        Row(
          children: [
            Expanded(
              child: _buildTagTextField(
                controller: _trackNumController,
                label: 'Track #',
                icon: Icons.format_list_numbered,
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildTagTextField(
                controller: _discNumController,
                label: 'Disc #',
                icon: Icons.disc_full,
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildTagTextField(
          controller: _composerController,
          label: 'Composer',
          icon: Icons.music_note,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildTagTextField(
                controller: _bpmController,
                label: 'BPM',
                icon: Icons.speed,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildTagTextField(
                controller: _musicalKeyController,
                label: 'Key (e.g. Am, C)',
                icon: Icons.piano,
              ),
            ),
          ],
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

    return Material(
      color: Colors.transparent,
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          labelStyle:
              TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
          prefixIcon: Icon(icon, color: primaryColor, size: 20),
          filled: true,
          fillColor: surfaceColor,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
      ),
    );
  }
}
