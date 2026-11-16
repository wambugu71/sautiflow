import 'package:material_ui/material_ui.dart';
import 'm3e_modal_helpers.dart';

import '../models/smart_playlist_rule.dart';
import '../services/app_theme_service.dart';
import '../services/m3u_playlist_service.dart';

class SmartPlaylistBuilderSheet extends StatefulWidget {
  const SmartPlaylistBuilderSheet({super.key});

  static Future<SavedM3uPlaylist?> show(BuildContext context) {
    return showSautiM3EBottomSheet<SavedM3uPlaylist?>(
      context,
      builder: (_) => const SmartPlaylistBuilderSheet(),
    );
  }

  @override
  State<SmartPlaylistBuilderSheet> createState() =>
      _SmartPlaylistBuilderSheetState();
}

class _SmartPlaylistBuilderSheetState extends State<SmartPlaylistBuilderSheet> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _limitController = TextEditingController();

  bool _matchAll = true;
  SmartPlaylistSort _sortBy = SmartPlaylistSort.titleAsc;
  final List<_EditableRule> _rules = [
    _EditableRule(
      field: SmartPlaylistField.genre,
      op: SmartPlaylistOperator.contains,
      value: '',
    ),
  ];

  int? _previewCount;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _refreshPreview();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _limitController.dispose();
    for (final r in _rules) {
      r.dispose();
    }
    super.dispose();
  }

  SmartPlaylistSpec _buildSpec() {
    return SmartPlaylistSpec(
      rules: _rules.map((r) => r.toRule()).toList(),
      matchAll: _matchAll,
      sortBy: _sortBy,
      limitCount: int.tryParse(_limitController.text.trim()),
    );
  }

  Future<void> _refreshPreview() async {
    final matches =
        await M3uPlaylistService.instance.evaluateSmartSpec(_buildSpec());
    if (mounted) {
      setState(() => _previewCount = matches.length);
    }
  }

  Future<void> _createFromPreset(
    ({String name, String description, SmartPlaylistSpec spec}) preset,
  ) async {
    setState(() => _isSaving = true);
    final created = await M3uPlaylistService.instance.createSmartPlaylist(
      name: preset.name,
      description: preset.description,
      spec: preset.spec,
    );
    if (mounted) Navigator.of(context).pop(created);
  }

  Future<void> _saveCustom() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a smart playlist name.')),
      );
      return;
    }
    setState(() => _isSaving = true);
    final created = await M3uPlaylistService.instance.createSmartPlaylist(
      name: name,
      spec: _buildSpec(),
    );
    if (mounted) Navigator.of(context).pop(created);
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
                  Icon(Icons.auto_awesome, color: primary, size: 22),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'New Smart Playlist',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (_previewCount != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$_previewCount matches',
                        style: TextStyle(
                          color: primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '1-Tap Presets',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: SmartPlaylistSpec.presets.map((preset) {
                  return ActionChip(
                    avatar: Icon(Icons.bolt, size: 16, color: primary),
                    label: Text(preset.name, style: const TextStyle(fontSize: 12)),
                    onPressed: _isSaving ? null : () => _createFromPreset(preset),
                  );
                }).toList(),
              ),
              const Divider(height: 24, color: Colors.white12),
              TextField(
                controller: _nameController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Custom Smart Playlist Name',
                  filled: true,
                  fillColor: card,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Match:', style: TextStyle(color: Colors.white70)),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('All Rules'),
                    selected: _matchAll,
                    onSelected: (_) {
                      setState(() => _matchAll = true);
                      _refreshPreview();
                    },
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Any Rule'),
                    selected: !_matchAll,
                    onSelected: (_) {
                      setState(() => _matchAll = false);
                      _refreshPreview();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ...List.generate(_rules.length, (i) {
                final rule = _rules[i];
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<SmartPlaylistField>(
                              initialValue: rule.field,
                              dropdownColor: card,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13),
                              decoration: const InputDecoration(
                                labelText: 'Field',
                                isDense: true,
                              ),
                              items: SmartPlaylistField.values
                                  .map((f) => DropdownMenuItem(
                                        value: f,
                                        child: Text(f.label),
                                      ))
                                  .toList(),
                              onChanged: (v) {
                                if (v == null) return;
                                setState(() => rule.field = v);
                                _refreshPreview();
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonFormField<SmartPlaylistOperator>(
                              initialValue: rule.op,
                              dropdownColor: card,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13),
                              decoration: const InputDecoration(
                                labelText: 'Condition',
                                isDense: true,
                              ),
                              items: SmartPlaylistOperator.values
                                  .map((o) => DropdownMenuItem(
                                        value: o,
                                        child: Text(o.label),
                                      ))
                                  .toList(),
                              onChanged: (v) {
                                if (v == null) return;
                                setState(() => rule.op = v);
                                _refreshPreview();
                              },
                            ),
                          ),
                          if (_rules.length > 1)
                            IconButton(
                              icon: const Icon(Icons.close,
                                  size: 18, color: Colors.white54),
                              onPressed: () {
                                setState(() {
                                  _rules.removeAt(i).dispose();
                                });
                                _refreshPreview();
                              },
                            ),
                        ],
                      ),
                      if (rule.op != SmartPlaylistOperator.isEmpty) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: rule.valueController,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 13),
                                decoration: InputDecoration(
                                  labelText: rule.op == SmartPlaylistOperator.between
                                      ? 'From'
                                      : 'Value',
                                  isDense: true,
                                ),
                                onChanged: (_) => _refreshPreview(),
                              ),
                            ),
                            if (rule.op == SmartPlaylistOperator.between) ...[
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: rule.value2Controller,
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 13),
                                  decoration: const InputDecoration(
                                    labelText: 'To',
                                    isDense: true,
                                  ),
                                  onChanged: (_) => _refreshPreview(),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ],
                  ),
                );
              }),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _rules.add(_EditableRule(
                      field: SmartPlaylistField.artist,
                      op: SmartPlaylistOperator.contains,
                      value: '',
                    ));
                  });
                },
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Rule'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<SmartPlaylistSort>(
                      initialValue: _sortBy,
                      dropdownColor: card,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: const InputDecoration(
                        labelText: 'Sort Order',
                        isDense: true,
                      ),
                      items: SmartPlaylistSort.values
                          .map((s) => DropdownMenuItem(
                                value: s,
                                child: Text(s.label),
                              ))
                          .toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _sortBy = v);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _limitController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: const InputDecoration(
                        labelText: 'Max Tracks',
                        hintText: 'All',
                        isDense: true,
                      ),
                      onChanged: (_) => _refreshPreview(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _isSaving ? null : _saveCustom,
                  icon: const Icon(Icons.check),
                  label: Text(_isSaving
                      ? 'Creating...'
                      : 'Create Smart Playlist (${_previewCount ?? 0})'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditableRule {
  SmartPlaylistField field;
  SmartPlaylistOperator op;
  final TextEditingController valueController;
  final TextEditingController value2Controller;

  _EditableRule({
    required this.field,
    required this.op,
    required String value,
    String? value2,
  })  : valueController = TextEditingController(text: value),
        value2Controller = TextEditingController(text: value2 ?? '');

  SmartPlaylistRule toRule() => SmartPlaylistRule(
        field: field,
        op: op,
        value: valueController.text.trim(),
        value2: value2Controller.text.trim().isEmpty
            ? null
            : value2Controller.text.trim(),
      );

  void dispose() {
    valueController.dispose();
    value2Controller.dispose();
  }
}
