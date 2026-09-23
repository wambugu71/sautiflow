import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:material_3_expressive/material_3_expressive.dart';

import '../isolate_player.dart';
import '../models/autoeq_profile.dart';
import '../services/app_theme_service.dart';
import '../services/autoeq_parser.dart';
import '../services/autoeq_service.dart';
import 'app_m3e_widgets.dart';

/// Reusable M3E AutoEQ Profile Selector widget.
/// Suitable for placement in EffectsScreen below the visualizer & profile selector row,
/// and in EqScreen under Graphic/Parametric EQ sections.
class AutoEqSelectorWidget extends StatefulWidget {
  final IsolateAudioPlayer player;
  final VoidCallback? onProfileApplied;
  final bool isCompact;

  const AutoEqSelectorWidget({
    super.key,
    required this.player,
    this.onProfileApplied,
    this.isCompact = false,
  });

  @override
  State<AutoEqSelectorWidget> createState() => _AutoEqSelectorWidgetState();
}

class _AutoEqSelectorWidgetState extends State<AutoEqSelectorWidget> {
  StreamSubscription<AutoEqProfileModel?>? _profileSub;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _initService();
    _profileSub = AutoEqService.instance.onActiveProfileChanged.listen((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _initService() async {
    await AutoEqService.instance.init();
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _profileSub?.cancel();
    super.dispose();
  }

  AutoEqProfileModel? get _activeProfile =>
      AutoEqService.instance.activeProfile;

  List<M3EDropdownItem<String>> _buildDropdownItems() {
    final items = <M3EDropdownItem<String>>[];

    // None / Flat Option
    items.add(const M3EDropdownItem<String>(
      value: '__none__',
      label: 'None',
    ));

    final builtIns = AutoEqService.instance.builtInProfiles;
    final peqs = builtIns.where((p) => p.isParametric).toList();
    final geqs = builtIns.where((p) => p.isGraphic).toList();
    final customs = AutoEqService.instance.customProfiles;

    // 1. Parametric Built-in Section
    if (peqs.isNotEmpty) {
      items.add(const M3EDropdownItem<String>(
        disabled: true,
        value: '__header_peq__',
        label: '— HEADPHONES (PARAMETRIC EQ) —',
      ));
      for (final p in peqs) {
        final preampStr =
            p.preampDb != 0.0 ? ' (${p.preampDb.toStringAsFixed(1)} dB)' : '';
        items.add(M3EDropdownItem<String>(
          value: p.id,
          label: '[PEQ] ${p.modelName}$preampStr',
        ));
      }
    }

    // 2. Graphic Built-in Section
    if (geqs.isNotEmpty) {
      items.add(const M3EDropdownItem<String>(
        disabled: true,
        value: '__header_geq__',
        label: '— HEADPHONES (GRAPHIC EQ) —',
      ));
      for (final p in geqs) {
        final preampStr =
            p.preampDb != 0.0 ? ' (${p.preampDb.toStringAsFixed(1)} dB)' : '';
        items.add(M3EDropdownItem<String>(
          value: p.id,
          label: '[GEQ] ${p.modelName}$preampStr',
        ));
      }
    }

    // 3. User Imported / Custom Profiles
    if (customs.isNotEmpty) {
      items.add(const M3EDropdownItem<String>(
        disabled: true,
        value: '__header_custom__',
        label: '— IMPORTED PROFILES —',
      ));
      for (final p in customs) {
        final badge = p.isParametric ? '[PEQ]' : '[GEQ]';
        final preampStr =
            p.preampDb != 0.0 ? ' (${p.preampDb.toStringAsFixed(1)} dB)' : '';
        items.add(M3EDropdownItem<String>(
          value: p.id,
          label: '$badge ${p.name}$preampStr',
        ));
      }
    }

    return items;
  }

  Future<void> _handleSelection(String? selectedId) async {
    if (selectedId == null || selectedId.startsWith('__header_')) return;

    if (selectedId == '__none__') {
      await AutoEqService.instance.clearActiveProfile(widget.player);
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('AutoEQ disabled'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      widget.onProfileApplied?.call();
      return;
    }

    final profile = AutoEqService.instance.allProfiles
        .cast<AutoEqProfileModel?>()
        .firstWhere(
          (p) => p?.id == selectedId,
          orElse: () => null,
        );

    if (profile != null) {
      await AutoEqService.instance.applyProfile(
        player: widget.player,
        profile: profile,
      );
      if (mounted) {
        setState(() {});
        final typeLabel = profile.isParametric ? 'Parametric EQ' : 'Graphic EQ';
        final preampInfo = profile.preampDb != 0.0
            ? ' • Preamp: ${profile.preampDb.toStringAsFixed(1)} dB'
            : '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  profile.isParametric
                      ? Icons.show_chart_rounded
                      : Icons.equalizer_rounded,
                  color: profile.isParametric
                      ? Colors.cyanAccent
                      : Colors.tealAccent,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Applied ${profile.name} ($typeLabel$preampInfo)',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 3),
            backgroundColor: context.cardDark,
          ),
        );
      }
      widget.onProfileApplied?.call();
    }
  }

  void _showImportDialog() {
    final textController = TextEditingController();
    final nameController = TextEditingController();
    AutoEqResult? previewResult;

    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void updatePreview(String text) {
              if (text.trim().length > 10) {
                try {
                  previewResult = AutoEqParser.parseContent(text.trim());
                } catch (_) {
                  previewResult = null;
                }
              } else {
                previewResult = null;
              }
              setDialogState(() {});
            }

            return AlertDialog(
              backgroundColor: context.cardDark,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Icon(Icons.auto_fix_high_rounded,
                      color: context.primaryColor, size: 22),
                  const SizedBox(width: 8),
                  const Text(
                    'Import AutoEQ Profile',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: math.min(MediaQuery.of(context).size.width * 0.9, 460),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Import in AutoEQ format.',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 12.5,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Pick File Button
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: context.primaryColor,
                            side: BorderSide(
                              color:
                                  context.primaryColor.withValues(alpha: 0.5),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          icon: const Icon(Icons.file_open_rounded, size: 18),
                          label: const Text('Pick (.txt / .csv)'),
                          onPressed: () async {
                            try {
                              final result = await FilePicker.pickFiles(
                                type: FileType.custom,
                                allowedExtensions: ['txt', 'csv'],
                              );
                              if (result != null &&
                                  result.files.single.path != null) {
                                final file = File(result.files.single.path!);
                                final content = await file.readAsString();
                                final defaultName =
                                    result.files.single.name.replaceAll(
                                  RegExp(r'\.(txt|csv)$', caseSensitive: false),
                                  '',
                                );
                                textController.text = content;
                                if (nameController.text.trim().isEmpty) {
                                  nameController.text = defaultName;
                                }
                                updatePreview(content);
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text('Failed to read file: $e')),
                                );
                              }
                            }
                          },
                        ),
                      ),
                      const SizedBox(height: 14),

                      Row(
                        children: [
                          const Expanded(child: Divider(color: Colors.white12)),
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 8.0),
                            child: Text(
                              'OR PASTE TEXT',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.4),
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ),
                          const Expanded(child: Divider(color: Colors.white12)),
                        ],
                      ),
                      const SizedBox(height: 12),

                      TextField(
                        controller: nameController,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'Profile Name (e.g. Moondrop Aria Harman)',
                          hintStyle: TextStyle(
                              color: Colors.white.withValues(alpha: 0.4)),
                          filled: true,
                          fillColor: context.cardDark.withValues(alpha: 0.6),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                                color: Colors.white.withValues(alpha: 0.15)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),

                      TextField(
                        controller: textController,
                        maxLines: 5,
                        onChanged: updatePreview,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11.5,
                          fontFamily: 'monospace',
                        ),
                        decoration: InputDecoration(
                          hintText:
                              'Preamp: -6.0 dB\nFilter 1: ON PK Fc 28 Hz Gain 7.1 dB Q 2.10\nFilter 2: ON LSC Fc 105 Hz Gain 5.5 dB Q 0.70...\nOR GraphicEQ: 20 0; 25 -0.5; 31.5 1.2...',
                          hintStyle: TextStyle(
                              color: Colors.white.withValues(alpha: 0.3)),
                          filled: true,
                          fillColor: context.cardDark.withValues(alpha: 0.6),
                          contentPadding: const EdgeInsets.all(10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                                color: Colors.white.withValues(alpha: 0.15)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Format Auto-Detection Preview
                      if (previewResult != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: previewResult!.isParametric
                                ? Colors.cyan.withValues(alpha: 0.12)
                                : Colors.teal.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: previewResult!.isParametric
                                  ? Colors.cyan.withValues(alpha: 0.35)
                                  : Colors.teal.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                previewResult!.isParametric
                                    ? Icons.show_chart_rounded
                                    : Icons.equalizer_rounded,
                                size: 16,
                                color: previewResult!.isParametric
                                    ? Colors.cyanAccent
                                    : Colors.tealAccent,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  previewResult!.isParametric
                                      ? 'Detected: Parametric EQ (${previewResult!.parametricBands.length} filters, ${previewResult!.preampGainDb.toStringAsFixed(1)} dB preamp)'
                                      : 'Detected: Graphic EQ (31 bands, ${previewResult!.preampGainDb.toStringAsFixed(1)} dB preamp)',
                                  style: TextStyle(
                                    color: previewResult!.isParametric
                                        ? Colors.cyanAccent
                                        : Colors.tealAccent,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: Text(
                    'Cancel',
                    style:
                        TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                  ),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: context.primaryColor),
                  onPressed: () async {
                    final text = textController.text.trim();
                    if (text.isEmpty) return;

                    final name = nameController.text.trim().isNotEmpty
                        ? nameController.text.trim()
                        : 'Custom AutoEQ (${DateTime.now().month}/${DateTime.now().day})';

                    final messenger = ScaffoldMessenger.of(context);
                    final cardDarkColor = context.cardDark;
                    Navigator.of(dialogCtx).pop();

                    final newProfile =
                        await AutoEqService.instance.importFromString(
                      content: text,
                      name: name,
                    );
                    await AutoEqService.instance.applyProfile(
                      player: widget.player,
                      profile: newProfile,
                    );

                    if (mounted) {
                      setState(() {});
                      final typeLabel = newProfile.isParametric
                          ? 'Parametric EQ'
                          : 'Graphic EQ';
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                              'Imported & Applied AutoEQ: "$name" ($typeLabel)'),
                          duration: const Duration(seconds: 3),
                          backgroundColor: cardDarkColor,
                        ),
                      );
                    }
                    widget.onProfileApplied?.call();
                  },
                  child: const Text(
                    'Import & Apply',
                    style: TextStyle(
                        color: Colors.black, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showManageCustomProfilesDialog() {
    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final customs = AutoEqService.instance.customProfiles;
            return AlertDialog(
              backgroundColor: context.cardDark,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.folder_shared_rounded,
                      color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Custom AutoEQ Profiles',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              content: SizedBox(
                width: math.min(MediaQuery.of(context).size.width * 0.85, 420),
                child: customs.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24.0),
                        child: Center(
                          child: Text(
                            'No custom profiles imported yet.\nUse the Import button to add downloaded AutoEQ curves.',
                            textAlign: TextAlign.center,
                            style:
                                TextStyle(color: Colors.white60, fontSize: 12),
                          ),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: customs.length,
                        separatorBuilder: (_, __) =>
                            const Divider(color: Colors.white12, height: 1),
                        itemBuilder: (context, idx) {
                          final item = customs[idx];
                          final isActive = _activeProfile?.id == item.id;
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 2),
                            leading: Icon(
                              item.isParametric
                                  ? Icons.show_chart_rounded
                                  : Icons.equalizer_rounded,
                              color: item.isParametric
                                  ? Colors.cyanAccent
                                  : Colors.tealAccent,
                              size: 20,
                            ),
                            title: Text(
                              item.name,
                              style: TextStyle(
                                color: isActive
                                    ? context.primaryColor
                                    : Colors.white,
                                fontWeight: isActive
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                fontSize: 13,
                              ),
                            ),
                            subtitle: Text(
                              '${item.type.displayName} • Preamp: ${item.preampDb.toStringAsFixed(1)} dB',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.5),
                                fontSize: 11,
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isActive)
                                  AppStatusBadge(
                                    text: 'ACTIVE',
                                    color: context.primaryColor,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                  ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded,
                                      color: Colors.redAccent, size: 18),
                                  tooltip: 'Delete Profile',
                                  onPressed: () async {
                                    await AutoEqService.instance
                                        .deleteCustomProfile(item.id, widget.player);
                                    setDialogState(() {});
                                    if (mounted) setState(() {});
                                  },
                                ),
                              ],
                            ),
                            onTap: () async {
                              final nav = Navigator.of(dialogCtx);
                              await AutoEqService.instance.applyProfile(
                                player: widget.player,
                                profile: item,
                              );
                              nav.pop();
                              if (mounted) setState(() {});
                              widget.onProfileApplied?.call();
                            },
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Close',
                      style: TextStyle(color: Colors.white70)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showProfilePickerModal() {
    final items = _buildDropdownItems();
    final activeId = _activeProfile?.id ?? '__none__';
    final searchCtrl = TextEditingController();
    List<M3EDropdownItem<String>> filteredItems = List.from(items);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.7,
              decoration: BoxDecoration(
                color: context.cardDark,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        const Icon(Icons.auto_fix_high_rounded,
                            color: Color(0xFF38BDF8), size: 20),
                        const SizedBox(width: 8),
                        const Text(
                          'Select AutoEQ Profile',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        if (_activeProfile != null)
                          TextButton(
                            onPressed: () {
                              Navigator.pop(sheetCtx);
                              _handleSelection('__none__');
                            },
                            child: const Text('Bypass / Off',
                                style: TextStyle(
                                    color: Colors.redAccent, fontSize: 13)),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: TextField(
                      controller: searchCtrl,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Search headphones (HD 600, Sony, AirPods)...',
                        hintStyle: TextStyle(
                            color: Colors.white.withValues(alpha: 0.35),
                            fontSize: 13),
                        prefixIcon: const Icon(Icons.search,
                            color: Colors.white54, size: 18),
                        filled: true,
                        fillColor: Colors.black26,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none),
                      ),
                      onChanged: (query) {
                        setSheetState(() {
                          if (query.trim().isEmpty) {
                            filteredItems = List.from(items);
                          } else {
                            final q = query.toLowerCase();
                            filteredItems = items.where((i) {
                              if (i.disabled) return false;
                              return i.label.toLowerCase().contains(q);
                            }).toList();
                          }
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filteredItems.length,
                      itemBuilder: (context, idx) {
                        final item = filteredItems[idx];
                        if (item.disabled) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            child: Text(
                              item.label,
                              style: TextStyle(
                                color: context.primaryColor,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8,
                              ),
                            ),
                          );
                        }
                        final isSelected = item.value == activeId;
                        return ListTile(
                          dense: true,
                          title: Text(
                            item.label,
                            style: TextStyle(
                              color: isSelected
                                  ? const Color(0xFF38BDF8)
                                  : Colors.white,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              fontSize: 13,
                            ),
                          ),
                          trailing: isSelected
                              ? const Icon(Icons.check_rounded,
                                  color: Color(0xFF38BDF8), size: 18)
                              : null,
                          onTap: () {
                            Navigator.pop(sheetCtx);
                            _handleSelection(item.value);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 36,
        child: Center(
            child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }

    final activeLabel = _activeProfile != null
        ? _activeProfile!.name
        : 'None (Flat)';

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0E1724),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Row(
        children: [
          const Text(
            'AutoEq',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: InkWell(
              onTap: _showProfilePickerModal,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF070C14),
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    if (_activeProfile != null) ...[
                      Icon(
                        _activeProfile!.isParametric
                            ? Icons.show_chart_rounded
                            : Icons.equalizer_rounded,
                        color: _activeProfile!.isParametric
                            ? Colors.cyanAccent
                            : Colors.tealAccent,
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Text(
                        activeLabel,
                        style: TextStyle(
                          color: _activeProfile != null
                              ? const Color(0xFF38BDF8)
                              : Colors.white54,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.unfold_more_rounded,
                      color: _activeProfile != null
                          ? const Color(0xFF38BDF8)
                          : Colors.white54,
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_activeProfile != null) ...[
            const SizedBox(width: 6),
            // Reset / Bypass Button (when a profile is active)
            InkWell(
              onTap: () => _handleSelection('__none__'),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFF162232),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.close_rounded,
                  color: Colors.white70,
                  size: 18,
                ),
              ),
            ),
          ],
          const SizedBox(width: 8),
          // Cloud Upload / Import Button
          InkWell(
            onTap: _showImportDialog,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: const Color(0xFF162232),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.cloud_upload_outlined,
                color: Color(0xFF38BDF8),
                size: 18,
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Folder / Manage Custom Button
          InkWell(
            onTap: _showManageCustomProfilesDialog,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: const Color(0xFF162232),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.folder_open_outlined,
                color: Color(0xFFBAE6FD),
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
