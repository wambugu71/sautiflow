import 'package:material_ui/material_ui.dart';
import 'm3e_modal_helpers.dart';

import '../models/local_song_item.dart';
import '../services/app_theme_service.dart';
import '../services/metadata_intelligence_service.dart';

class BatchTagEditorSheet extends StatefulWidget {
  final List<LocalSongItem> tracks;

  const BatchTagEditorSheet({super.key, required this.tracks});

  static Future<int?> show(
    BuildContext context, {
    required List<LocalSongItem> tracks,
  }) {
    return showSautiM3EBottomSheet<int?>(
      context,
      builder: (_) => BatchTagEditorSheet(tracks: tracks),
    );
  }

  @override
  State<BatchTagEditorSheet> createState() => _BatchTagEditorSheetState();
}

class _BatchTagEditorSheetState extends State<BatchTagEditorSheet> {
  final TextEditingController _artistController = TextEditingController();
  final TextEditingController _albumController = TextEditingController();
  final TextEditingController _albumArtistController = TextEditingController();
  final TextEditingController _genreController = TextEditingController();
  final TextEditingController _yearController = TextEditingController();
  final TextEditingController _discController = TextEditingController();

  bool _autoNumber = false;
  bool _autoInferMissing = false;
  bool _normalizeCasing = false;
  bool _isSaving = false;

  @override
  void dispose() {
    _artistController.dispose();
    _albumController.dispose();
    _albumArtistController.dispose();
    _genreController.dispose();
    _yearController.dispose();
    _discController.dispose();
    super.dispose();
  }

  Future<void> _applyBatch() async {
    setState(() => _isSaving = true);
    final updated = await MetadataIntelligenceService.instance.batchUpdateTags(
      widget.tracks,
      artist: _artistController.text,
      album: _albumController.text,
      albumArtist: _albumArtistController.text,
      genre: _genreController.text,
      year: int.tryParse(_yearController.text.trim()),
      discNumber: int.tryParse(_discController.text.trim()),
      autoNumber: _autoNumber,
      autoInferMissing: _autoInferMissing,
      normalizeCasing: _normalizeCasing,
    );
    if (mounted) Navigator.of(context).pop(updated);
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeService.instance.currentData;
    final primary = theme.primary;
    final card = theme.cardDark;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.edit_note, color: primary, size: 24),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Batch Edit ${widget.tracks.length} Tracks',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Leave any field blank to keep existing values.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _albumController,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Album',
                  filled: true,
                  fillColor: card,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _artistController,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        labelText: 'Artist',
                        filled: true,
                        fillColor: card,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _albumArtistController,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        labelText: 'Album Artist',
                        filled: true,
                        fillColor: card,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _genreController,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        labelText: 'Genre',
                        filled: true,
                        fillColor: card,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _yearController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        labelText: 'Year',
                        filled: true,
                        fillColor: card,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _discController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        labelText: 'Disc #',
                        filled: true,
                        fillColor: card,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SwitchListTile.adaptive(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Auto-infer missing tags from file paths',
                    style: TextStyle(color: Colors.white, fontSize: 13)),
                value: _autoInferMissing,
                onChanged: (v) => setState(() => _autoInferMissing = v),
              ),
              SwitchListTile.adaptive(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Clean noise & apply smart title case',
                    style: TextStyle(color: Colors.white, fontSize: 13)),
                value: _normalizeCasing,
                onChanged: (v) => setState(() => _normalizeCasing = v),
              ),
              SwitchListTile.adaptive(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                    'Auto-number tracks (1..${widget.tracks.length})',
                    style: const TextStyle(color: Colors.white, fontSize: 13)),
                value: _autoNumber,
                onChanged: (v) => setState(() => _autoNumber = v),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _isSaving ? null : _applyBatch,
                  icon: const Icon(Icons.save),
                  label: Text(_isSaving
                      ? 'Applying...'
                      : 'Apply to ${widget.tracks.length} Tracks'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
