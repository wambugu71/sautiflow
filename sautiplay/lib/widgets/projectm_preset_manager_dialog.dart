import 'package:flutter/material.dart';
import 'package:projectm_visualizer/projectm_visualizer.dart';

import '../services/app_theme_service.dart';
import '../services/projectm_preset_manager.dart';

/// Interactive modal sheet/dialog allowing users to:
/// - Download the Poweramp Curated Milkdrop Viz Sets APK in the background.
/// - Pick custom `.milk` presets, `.zip` archives, or `.apk` packs from disk.
/// - Search, preview, and apply presets with zero UI stutter.
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
    final cardDark = context.cardDark;
    final outline = context.outlineColor;
    final textPrimary = context.textPrimary;
    final textMuted = context.textMuted;
    final maxSheetHeight = MediaQuery.of(context).size.height * 0.85;

    return Container(
      constraints: BoxConstraints(maxHeight: maxSheetHeight),
      decoration: BoxDecoration(
        color: const Color(0xFF0F111A).withValues(alpha: 0.98),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: outline),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 28,
            offset: const Offset(0, -6),
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
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
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
                        'Milkdrop Presets Library',
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
                            '${presets.length} presets available',
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

          const Divider(height: 1, color: Colors.white10),

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
                          'No presets match "$_searchQuery"',
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
    return ValueListenableBuilder<ProjectMPackStatus>(
      valueListenable: _manager.statusNotifier,
      builder: (context, status, _) {
        final isDownloading =
            status.state == PackDownloadState.downloading ||
            status.state == PackDownloadState.extracting;
        final isInstalled = _manager.isCuratedPackDownloaded;

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isInstalled
                ? primary.withValues(alpha: 0.08)
                : const Color(0xFF141724),
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
                        const Text(
                          'Poweramp Curated Viz Sets (Milkdrop)',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          isInstalled
                              ? '${_manager.curatedPresetCount} community presets installed'
                              : '400+ curated presets with textures (~30 MB)',
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isDownloading)
                    IconButton(
                      icon: const Icon(Icons.cancel_rounded,
                          color: Colors.white60, size: 20),
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
                        foregroundColor: Colors.black,
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
                    backgroundColor: Colors.white12,
                    valueColor: AlwaysStoppedAnimation<Color>(primary),
                    minHeight: 4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  status.message,
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
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
                  color: isSelected ? Colors.black : Colors.white70,
                ),
                selected: isSelected,
                selectedColor: primary,
                backgroundColor: const Color(0xFF141724),
                side: BorderSide(
                  color: isSelected ? primary : Colors.white12,
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Imported ${summary.importedPresets.length} presets successfully!',
          ),
          backgroundColor: const Color(0xFF00E5FF),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}
