import 'package:flutter/material.dart';
import 'package:projectm_visualizer/projectm_visualizer.dart';

import '../services/app_theme_service.dart';
import '../services/projectm_preset_manager.dart';

/// Modal sheet for browsing, downloading, and importing Milkdrop presets.
class ProjectMPresetManagerDialog extends StatefulWidget {
  const ProjectMPresetManagerDialog({
    super.key,
    required this.activePresetId,
    required this.onPresetSelected,
  });

  final String activePresetId;
  final ValueChanged<ProjectMPreset> onPresetSelected;

  /// Convenience helper to display as a bottom sheet.
  static Future<void> show(
    BuildContext context, {
    String? activePresetId,
    String? currentPresetId,
    required ValueChanged<ProjectMPreset> onPresetSelected,
  }) {
    final effectiveId = activePresetId ?? currentPresetId ?? '';
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => ProjectMPresetManagerDialog(
        activePresetId: effectiveId,
        onPresetSelected: onPresetSelected,
      ),
    );
  }

  @override
  State<ProjectMPresetManagerDialog> createState() =>
      _ProjectMPresetManagerDialogState();
}

class _ProjectMPresetManagerDialogState
    extends State<ProjectMPresetManagerDialog> {
  final ProjectMPresetManager _manager = ProjectMPresetManager.instance;
  final TextEditingController _searchCtrl = TextEditingController();

  String _searchQuery = '';
  String _selectedCategory = 'All';
  late String _activePresetId;

  @override
  void initState() {
    super.initState();
    _activePresetId = widget.activePresetId;
    _manager.initialize();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themePrimary = context.primaryColor;
    final bgDark = context.bgDark;
    final cardDark = context.cardDark;
    final outline = context.outlineColor;
    final textPrimary = context.textPrimary;
    final textMuted = context.textMuted;
    final maxSheetHeight = MediaQuery.sizeOf(context).height * 0.85;

    return Container(
      constraints: BoxConstraints(maxHeight: maxSheetHeight),
      decoration: BoxDecoration(
        color: bgDark,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: outline),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: textMuted.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: themePrimary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    color: themePrimary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Milkdrop Presets',
                        style: TextStyle(
                          color: textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      ValueListenableBuilder<List<ProjectMPreset>>(
                        valueListenable: _manager.presetsNotifier,
                        builder: (context, presets, _) {
                          return Text(
                            '${presets.length} presets',
                            style: TextStyle(
                              color: textMuted,
                              fontSize: 12,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  color: textMuted,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          Divider(height: 1, color: outline),

          // Download & Import Banner
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: _buildCuratedPackCard(themePrimary, cardDark, outline),
          ),

          // Search bar & Import action
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: cardDark,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: outline),
                    ),
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: (val) => setState(() => _searchQuery = val.trim()),
                      style: TextStyle(color: textPrimary, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Search presets...',
                        hintStyle: TextStyle(color: textMuted, fontSize: 13),
                        prefixIcon: Icon(Icons.search_rounded,
                            size: 18, color: textMuted),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 16),
                                color: textMuted,
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: _pickLocalPresets,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: cardDark,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: outline),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.file_open_outlined,
                            size: 16, color: themePrimary),
                        const SizedBox(width: 6),
                        Text(
                          'Import',
                          style: TextStyle(
                            color: themePrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Category Chips Bar
          _buildCategoryChips(themePrimary),

          const SizedBox(height: 6),

          // Preset List
          Expanded(
            child: ValueListenableBuilder<List<ProjectMPreset>>(
              valueListenable: _manager.presetsNotifier,
              builder: (context, allPresets, _) {
                final filtered = allPresets.where((preset) {
                  final matchesCat = _selectedCategory == 'All' ||
                      preset.category.toLowerCase().contains(_selectedCategory.toLowerCase());
                  final matchesQuery = _searchQuery.isEmpty ||
                      preset.displayName
                          .toLowerCase()
                          .contains(_searchQuery.toLowerCase()) ||
                      preset.category
                          .toLowerCase()
                          .contains(_searchQuery.toLowerCase());
                  return matchesCat && matchesQuery;
                }).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.search_off_rounded,
                            size: 40, color: textMuted),
                        const SizedBox(height: 8),
                        Text(
                          _searchQuery.isNotEmpty
                              ? 'No presets match "$_searchQuery"'
                              : 'No presets in $_selectedCategory',
                          style: TextStyle(color: textMuted, fontSize: 13),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final preset = filtered[index];
                    final isSelected = preset.id == _activePresetId ||
                        (preset.filePath != null &&
                            preset.filePath == _activePresetId);

                    return _buildPresetTile(
                      preset: preset,
                      isSelected: isSelected,
                      primaryColor: themePrimary,
                      cardDark: cardDark,
                      outline: outline,
                      textPrimary: textPrimary,
                      textMuted: textMuted,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCuratedPackCard(Color primary, Color cardDark, Color outline) {
    final textPrimary = context.textPrimary;
    final textMuted = context.textMuted;
    final onPrimary = Theme.of(context).colorScheme.onPrimary;
    final errorColor = Theme.of(context).colorScheme.error;

    return ValueListenableBuilder<ProjectMPackStatus>(
      valueListenable: _manager.statusNotifier,
      builder: (context, status, _) {
        final isDownloading =
            status.state == PackDownloadState.downloading ||
            status.state == PackDownloadState.extracting;
        final isError = status.state == PackDownloadState.error;
        final isInstalled = _manager.isCuratedPackDownloaded;

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isInstalled
                ? primary.withValues(alpha: 0.08)
                : cardDark,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isInstalled ? primary.withValues(alpha: 0.3) : outline,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isInstalled
                        ? Icons.verified_rounded
                        : Icons.cloud_download_rounded,
                    color: primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Poweramp Viz Pack',
                          style: TextStyle(
                            color: textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          isInstalled
                              ? '${_manager.curatedPresetCount} presets installed'
                              : '400+ presets with textures (< 2 MB)',
                          style: TextStyle(
                            color: textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isDownloading)
                    IconButton(
                      icon: Icon(Icons.cancel_rounded,
                          color: textMuted, size: 20),
                      onPressed: () => _manager.cancelDownload(),
                      tooltip: 'Cancel Download',
                    )
                  else if (isInstalled)
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      icon: const Icon(Icons.refresh_rounded, size: 14),
                      label: const Text('Re-download', style: TextStyle(fontSize: 11)),
                      onPressed: () => _manager.downloadAndInstallCuratedPack(),
                    )
                  else
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primary,
                        foregroundColor: onPrimary,
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(Icons.download_rounded, size: 16),
                      label: const Text(
                        'Download',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: () => _manager.downloadAndInstallCuratedPack(),
                    ),
                ],
              ),
              if (isDownloading) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: status.state == PackDownloadState.extracting
                        ? null
                        : status.progress,
                    backgroundColor: outline,
                    valueColor: AlwaysStoppedAnimation<Color>(primary),
                    minHeight: 4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  status.message,
                  style: TextStyle(color: textMuted, fontSize: 11),
                ),
              ] else if (isError && status.message.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  status.message,
                  style: TextStyle(color: errorColor, fontSize: 11),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildCategoryChips(Color primary) {
    return ValueListenableBuilder<List<ProjectMPreset>>(
      valueListenable: _manager.presetsNotifier,
      builder: (context, _, __) {
        final categories = ['All', ...ProjectMPresetLibrary.categories];

        return SizedBox(
          height: 36,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: categories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (context, i) {
              final cat = categories[i];
              final isSelected = _selectedCategory == cat;

              return ChoiceChip(
                label: Text(cat),
                labelStyle: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected
                      ? Theme.of(context).colorScheme.onPrimary
                      : context.textMuted,
                ),
                selected: isSelected,
                selectedColor: primary,
                backgroundColor: context.cardDark,
                side: BorderSide(
                  color: isSelected ? primary : context.outlineColor,
                ),
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                onSelected: (_) => setState(() => _selectedCategory = cat),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildPresetTile({
    required ProjectMPreset preset,
    required bool isSelected,
    required Color primaryColor,
    required Color cardDark,
    required Color outline,
    required Color textPrimary,
    required Color textMuted,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: isSelected
            ? primaryColor.withValues(alpha: 0.12)
            : cardDark.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSelected ? primaryColor : outline.withValues(alpha: 0.6),
          width: isSelected ? 1.4 : 1.0,
        ),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        leading: Icon(
          Icons.auto_awesome_rounded,
          size: 18,
          color: isSelected ? primaryColor : textMuted,
        ),
        title: Text(
          preset.displayName,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: isSelected ? primaryColor : textPrimary,
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
        subtitle: Text(
          preset.category,
          style: TextStyle(
            color: textMuted,
            fontSize: 11,
          ),
        ),
        trailing: isSelected
            ? Icon(Icons.check_circle_rounded, color: primaryColor, size: 18)
            : null,
        onTap: () {
          setState(() => _activePresetId = preset.id);
          widget.onPresetSelected(preset);
          Navigator.of(context).pop();
        },
      ),
    );
  }

  Future<void> _pickLocalPresets() async {
    final summary = await _manager.pickAndImportFromDisk(
      onStatus: (msg) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg),
              duration: const Duration(seconds: 1),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
    );

    if (mounted && summary.importedPresets.isNotEmpty) {
      final count = summary.importedPresets.length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Imported $count ${count == 1 ? 'preset' : 'presets'}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}
