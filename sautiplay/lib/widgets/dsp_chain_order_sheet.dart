import 'package:material_ui/material_ui.dart';
import 'package:sautiflow/sautiflow.dart';
import 'package:sautiplay/services/app_theme_service.dart';
import 'package:sautiplay/widgets/sauti_icons.dart';

/// Pure helper that moves [oldVisibleIndex] to [newVisibleIndex] within
/// [visibleOrder] and updates [fullOrder] while preserving the relative order
/// of any hidden/inactive modules.
///
/// When [adjustNewIndexForRemoval] is `true` (legacy `onReorder` convention),
/// [newVisibleIndex] is treated as relative to the list before removing
/// [oldVisibleIndex]. When `false` (`onReorderItem` convention),
/// [newVisibleIndex] is already adjusted for removal.
List<DspNodeId> reorderDspChainWithFilter({
  required List<DspNodeId> fullOrder,
  required List<DspNodeId> visibleOrder,
  required int oldVisibleIndex,
  required int newVisibleIndex,
  bool adjustNewIndexForRemoval = true,
}) {
  final normalizedFull = DspNodeId.normalizeOrder(fullOrder);
  final maxNewIndex =
      adjustNewIndexForRemoval ? visibleOrder.length : visibleOrder.length - 1;
  if (visibleOrder.isEmpty ||
      oldVisibleIndex < 0 ||
      oldVisibleIndex >= visibleOrder.length ||
      newVisibleIndex < 0 ||
      newVisibleIndex > maxNewIndex) {
    return normalizedFull;
  }

  var targetVisibleIndex = newVisibleIndex;
  if (adjustNewIndexForRemoval && targetVisibleIndex > oldVisibleIndex) {
    targetVisibleIndex -= 1;
  }
  if (targetVisibleIndex == oldVisibleIndex ||
      targetVisibleIndex < 0 ||
      targetVisibleIndex >= visibleOrder.length) {
    return normalizedFull;
  }

  final moved = visibleOrder[oldVisibleIndex];
  final updated = List<DspNodeId>.from(normalizedFull)..remove(moved);
  final remainingVisible =
      visibleOrder.where((node) => node != moved).toList(growable: false);

  if (remainingVisible.isEmpty) {
    updated.add(moved);
  } else if (targetVisibleIndex >= remainingVisible.length) {
    final afterIdx = updated.indexOf(remainingVisible.last);
    if (afterIdx >= 0) {
      updated.insert(afterIdx + 1, moved);
    } else {
      updated.add(moved);
    }
  } else {
    final anchor = remainingVisible[targetVisibleIndex];
    final anchorIdx = updated.indexOf(anchor);
    if (anchorIdx >= 0) {
      updated.insert(anchorIdx, moved);
    } else {
      updated.add(moved);
    }
  }

  return DspNodeId.normalizeOrder(updated);
}

/// Static display metadata for a reorderable [DspNodeId] module.
class DspChainNodeMeta {
  final String title;
  final String defaultSubtitle;
  final IconData icon;

  const DspChainNodeMeta({
    required this.title,
    required this.defaultSubtitle,
    required this.icon,
  });
}

/// Returns display title, icon, and fallback subtitle for [id].
DspChainNodeMeta dspChainNodeMetaFor(DspNodeId id) {
  switch (id) {
    case DspNodeId.preamp:
      return const DspChainNodeMeta(
        title: 'Preamp Gain',
        defaultSubtitle: 'Input headroom trim',
        icon: SautiIcons.preamp,
      );
    case DspNodeId.noiseGate:
      return const DspChainNodeMeta(
        title: 'Noise Gate',
        defaultSubtitle: 'Hysteresis floor gate',
        icon: SautiIcons.noiseGate,
      );
    case DspNodeId.downwardExpander:
      return const DspChainNodeMeta(
        title: 'Expander',
        defaultSubtitle: 'Noise floor reduction',
        icon: SautiIcons.expander,
      );
    case DspNodeId.dynamicEq:
      return const DspChainNodeMeta(
        title: 'Dynamic EQ',
        defaultSubtitle: '6-Band dynamic resonance control',
        icon: SautiIcons.dynamicEq,
      );
    case DspNodeId.deEsser:
      return const DspChainNodeMeta(
        title: 'De-Esser',
        defaultSubtitle: 'Sibilance control',
        icon: SautiIcons.deesser,
      );
    case DspNodeId.harmonicBass:
      return const DspChainNodeMeta(
        title: 'Dynamic Bass',
        defaultSubtitle: 'Low-end & harmonic sub engine',
        icon: SautiIcons.dynamicBass,
      );
    case DspNodeId.dynamicSystem:
      return const DspChainNodeMeta(
        title: 'Dynamic System',
        defaultSubtitle: 'Multiband transducer tuning',
        icon: SautiIcons.dynamicSystem,
      );
    case DspNodeId.analogWarmth:
      return const DspChainNodeMeta(
        title: 'Analog Warmth',
        defaultSubtitle: 'Triode / tape saturation',
        icon: SautiIcons.analogueWarmth,
      );
    case DspNodeId.tapeDrift:
      return const DspChainNodeMeta(
        title: 'Vintage Tape Drift',
        defaultSubtitle: 'Wow & flutter modulation',
        icon: SautiIcons.vintageDrift,
      );
    case DspNodeId.dialogEnhancer:
      return const DspChainNodeMeta(
        title: 'Dialogue Enhancer',
        defaultSubtitle: 'Vocal formant focus',
        icon: SautiIcons.dialogueEnhancer,
      );
    case DspNodeId.clarity:
      return const DspChainNodeMeta(
        title: 'Audio Clarity',
        defaultSubtitle: 'Air shelf & harmonic brilliance',
        icon: SautiIcons.audioClarity,
      );
    case DspNodeId.crystalizer:
      return const DspChainNodeMeta(
        title: 'Crystalizer',
        defaultSubtitle: 'Transient reconstruction',
        icon: SautiIcons.crystallizer,
      );
    case DspNodeId.compressor:
      return const DspChainNodeMeta(
        title: 'Compressor',
        defaultSubtitle: 'Dynamic range control',
        icon: SautiIcons.compressor,
      );
    case DspNodeId.multibandEq:
      return const DspChainNodeMeta(
        title: 'Graphic EQ',
        defaultSubtitle: 'Multi-band ISO equalizer',
        icon: SautiIcons.graphicEq,
      );
    case DspNodeId.multibandFx:
      return const DspChainNodeMeta(
        title: 'Parametric EQ',
        defaultSubtitle: 'Cytomic SVF filter rack',
        icon: SautiIcons.parametricEq,
      );
    case DspNodeId.threeBandEq:
      return const DspChainNodeMeta(
        title: '3-Band EQ',
        defaultSubtitle: 'Legacy L/M/H tuning',
        icon: Icons.equalizer_rounded,
      );
    case DspNodeId.toneCrossover:
      return const DspChainNodeMeta(
        title: 'Tone Controls',
        defaultSubtitle: 'Baxandall, Tilt & LR4 crossover',
        icon: SautiIcons.toneControls,
      );
    case DspNodeId.crossfeed:
      return const DspChainNodeMeta(
        title: 'Crossfeed',
        defaultSubtitle: 'Headphone acoustic virtualization',
        icon: SautiIcons.crossfeed,
      );
    case DspNodeId.surround:
      return const DspChainNodeMeta(
        title: 'Spatial Surround',
        defaultSubtitle: 'HRTF & acoustic stage',
        icon: SautiIcons.spatialSound,
      );
    case DspNodeId.stereoWiden:
      return const DspChainNodeMeta(
        title: 'Stereo Imager',
        defaultSubtitle: 'M/S soundstage width',
        icon: SautiIcons.stereoImager,
      );
    case DspNodeId.stereoEnhancement:
      return const DspChainNodeMeta(
        title: 'Stereo Enhancer',
        defaultSubtitle: 'Stereo presence expansion',
        icon: SautiIcons.stereoWidth,
      );
    case DspNodeId.reverb:
      return const DspChainNodeMeta(
        title: 'Reverb',
        defaultSubtitle: 'Multi-engine acoustic space',
        icon: SautiIcons.reverb,
      );
    case DspNodeId.convolver:
      return const DspChainNodeMeta(
        title: 'Convolver',
        defaultSubtitle: 'FFT impulse response & AutoEQ FIR',
        icon: SautiIcons.convolver,
      );
    case DspNodeId.broadcastLeveller:
      return const DspChainNodeMeta(
        title: 'Auto Gain Control',
        defaultSubtitle: 'EBU R128 broadcast leveller',
        icon: SautiIcons.agcControl,
      );
    case DspNodeId.lookaheadAgc:
      return const DspChainNodeMeta(
        title: 'Lookahead AGC + Limiter',
        defaultSubtitle: '3-band lookahead dynamics',
        icon: Icons.speed_rounded,
      );
    case DspNodeId.bassManagement:
      return const DspChainNodeMeta(
        title: 'Bass Management (5.1/7.1)',
        defaultSubtitle: 'LR4 subwoofer crossover & calibration',
        icon: Icons.speaker_group_rounded,
      );
  }
}

/// Live UI descriptor for a node inside [DspChainOrderSheet].
class DspChainNodeInfo {
  final DspNodeId id;
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isEnabled;
  final ValueChanged<bool>? onToggle;
  final VoidCallback? onOpenDetail;

  const DspChainNodeInfo({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isEnabled,
    this.onToggle,
    this.onOpenDetail,
  });

  DspChainNodeInfo copyWith({
    bool? isEnabled,
    String? subtitle,
  }) {
    return DspChainNodeInfo(
      id: id,
      title: title,
      subtitle: subtitle ?? this.subtitle,
      icon: icon,
      isEnabled: isEnabled ?? this.isEnabled,
      onToggle: onToggle,
      onOpenDetail: onOpenDetail,
    );
  }
}

/// Opens the live, drag-and-drop reorderable DSP Signal Chain bottom sheet.
Future<void> showDspChainOrderSheet({
  required BuildContext context,
  required List<DspNodeId> initialOrder,
  required List<DspChainNodeInfo> nodes,
  required ValueChanged<List<DspNodeId>> onOrderChanged,
  VoidCallback? onResetOrder,
}) {
  final isDark = context.isDark;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: isDark ? 0.65 : 0.35),
    builder: (ctx) => Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: DspChainOrderSheet(
          initialOrder: initialOrder,
          nodes: nodes,
          onOrderChanged: onOrderChanged,
          onResetOrder: onResetOrder,
        ),
      ),
    ),
  );
}

/// Interactive drag-and-drop bottom sheet for inspecting and reordering the
/// live DSP signal chain.
class DspChainOrderSheet extends StatefulWidget {
  final List<DspNodeId> initialOrder;
  final List<DspChainNodeInfo> nodes;
  final ValueChanged<List<DspNodeId>> onOrderChanged;
  final VoidCallback? onResetOrder;

  const DspChainOrderSheet({
    super.key,
    required this.initialOrder,
    required this.nodes,
    required this.onOrderChanged,
    this.onResetOrder,
  });

  @override
  State<DspChainOrderSheet> createState() => _DspChainOrderSheetState();
}

class _DspChainOrderSheetState extends State<DspChainOrderSheet> {
  late List<DspNodeId> _order;
  late Map<DspNodeId, DspChainNodeInfo> _nodeMap;
  late bool _activeOnly;

  @override
  void initState() {
    super.initState();
    _order = DspNodeId.normalizeOrder(widget.initialOrder);
    _nodeMap = _buildNodeMap(widget.nodes);
    final activeCount = _nodeMap.values.where((n) => n.isEnabled).length;
    _activeOnly = activeCount >= 2;
  }

  @override
  void didUpdateWidget(covariant DspChainOrderSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nodes != widget.nodes) {
      _nodeMap = _buildNodeMap(widget.nodes);
    }
  }

  Map<DspNodeId, DspChainNodeInfo> _buildNodeMap(List<DspChainNodeInfo> nodes) {
    final map = <DspNodeId, DspChainNodeInfo>{};
    for (final node in nodes) {
      map[node.id] = node;
    }
    return map;
  }

  DspChainNodeInfo _infoFor(DspNodeId id) {
    final existing = _nodeMap[id];
    if (existing != null) return existing;
    final meta = dspChainNodeMetaFor(id);
    return DspChainNodeInfo(
      id: id,
      title: meta.title,
      subtitle: meta.defaultSubtitle,
      icon: meta.icon,
      isEnabled: false,
    );
  }

  List<DspNodeId> get _allDisplayIds {
    // Keep legacy threeBandEq hidden unless explicitly active or supplied
    // in widget.nodes so the rack stays focused on active/user-facing modules.
    return _order.where((id) {
      if (id != DspNodeId.threeBandEq) return true;
      final info = _nodeMap[id];
      return info != null && info.isEnabled;
    }).toList(growable: false);
  }

  List<DspNodeId> get _visibleIds {
    final all = _allDisplayIds;
    if (!_activeOnly) return all;
    return all
        .where((id) => _infoFor(id).isEnabled)
        .toList(growable: false);
  }

  void _handleReorder(int oldVisibleIndex, int newVisibleIndex) {
    final visible = _visibleIds;
    final updated = reorderDspChainWithFilter(
      fullOrder: _order,
      visibleOrder: visible,
      oldVisibleIndex: oldVisibleIndex,
      newVisibleIndex: newVisibleIndex,
      adjustNewIndexForRemoval: false,
    );
    setState(() => _order = updated);
    widget.onOrderChanged(updated);
  }

  void _handleReset() {
    final def = DspNodeId.defaultOrder;
    setState(() => _order = def);
    widget.onResetOrder?.call();
    widget.onOrderChanged(def);
  }

  void _toggleNode(DspChainNodeInfo info, bool value) {
    final cb = info.onToggle;
    if (cb == null) return;
    cb(value);
    setState(() {
      _nodeMap[info.id] = info.copyWith(
        isEnabled: value,
        subtitle: value ? info.subtitle : 'Disabled',
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final appTheme = context.appTheme;
    final isDark = context.isDark;
    final primary = appTheme.primary;
    final textPrimary = context.textPrimary;
    final textMuted = context.textMuted;
    final outlineColor = context.outlineColor;
    final surfaceColor = isDark
        ? (appTheme.id == AppThemeId.amoledBlack
            ? const Color(0xFF0A0A0A)
            : appTheme.cardDark)
        : appTheme.cardDark;

    final allIds = _allDisplayIds;
    final visibleIds = _visibleIds;
    final activeCount =
        allIds.where((id) => _infoFor(id).isEnabled).length;
    final isDefault = DspNodeId.isDefaultOrder(_order);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.88,
      ),
      decoration: BoxDecoration(
        color: surfaceColor.withValues(alpha: isDark ? 0.97 : 0.99),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(
          color: isDark ? primary.withValues(alpha: 0.25) : outlineColor,
          width: 1.2,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 42,
              height: 5,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black26,
                borderRadius: BorderRadius.circular(2.5),
              ),
            ),
          ),
          _ChainSheetHeader(
            isDefault: isDefault,
            primary: primary,
            textPrimary: textPrimary,
            textMuted: textMuted,
            isDark: isDark,
            onReset: isDefault ? null : _handleReset,
            onClose: () => Navigator.of(context).pop(),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 10),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _FilterPill(
                  label: 'Active Only ($activeCount)',
                  selected: _activeOnly,
                  primary: primary,
                  textPrimary: textPrimary,
                  outlineColor: outlineColor,
                  onTap: () => setState(() => _activeOnly = true),
                ),
                _FilterPill(
                  label: 'All Modules (${allIds.length})',
                  selected: !_activeOnly,
                  primary: primary,
                  textPrimary: textPrimary,
                  outlineColor: outlineColor,
                  onTap: () => setState(() => _activeOnly = false),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: outlineColor),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 6),
                  child: _PinnedBoundaryBanner(
                    title: 'INPUT STAGE (PINNED)',
                    detail:
                        'Source → ReplayGain / Normalizer → Subsonic Protection',
                    icon: Icons.lock_outline_rounded,
                    primary: primary,
                    textPrimary: textPrimary,
                    textMuted: textMuted,
                    outlineColor: outlineColor,
                    isDark: isDark,
                  ),
                ),
                Expanded(
                  child: visibleIds.isEmpty
                      ? _EmptyActiveRackState(
                          textPrimary: textPrimary,
                          textMuted: textMuted,
                          primary: primary,
                          onShowAll: () => setState(() => _activeOnly = false),
                        )
                      : ReorderableListView.builder(
                          buildDefaultDragHandles: false,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          itemCount: visibleIds.length,
                          onReorderItem: _handleReorder,
                          proxyDecorator: (child, index, animation) {
                            return Material(
                              color: Colors.transparent,
                              elevation: 6,
                              shadowColor:
                                  Colors.black.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(14),
                              child: child,
                            );
                          },
                          itemBuilder: (context, visibleIndex) {
                            final id = visibleIds[visibleIndex];
                            final info = _infoFor(id);
                            final stepNumber = allIds.indexOf(id) + 1;
                            return _ReorderableRackTile(
                              key: ValueKey(id.key),
                              visibleIndex: visibleIndex,
                              stepNumber: stepNumber,
                              info: info,
                              primary: primary,
                              textPrimary: textPrimary,
                              textMuted: textMuted,
                              outlineColor: outlineColor,
                              isDark: isDark,
                              onToggle: info.onToggle == null
                                  ? null
                                  : (v) => _toggleNode(info, v),
                              onTapDetail: info.onOpenDetail == null
                                  ? null
                                  : () {
                                      Navigator.of(context).pop();
                                      info.onOpenDetail?.call();
                                    },
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 6, 16, 16),
                  child: _PinnedBoundaryBanner(
                    title: 'OUTPUT PROTECTION (PINNED)',
                    detail:
                        'Master Volume → Dynamic Loudness → Brickwall Limiter → DAC',
                    icon: Icons.shield_outlined,
                    primary: primary,
                    textPrimary: textPrimary,
                    textMuted: textMuted,
                    outlineColor: outlineColor,
                    isDark: isDark,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChainSheetHeader extends StatelessWidget {
  final bool isDefault;
  final Color primary;
  final Color textPrimary;
  final Color textMuted;
  final bool isDark;
  final VoidCallback? onReset;
  final VoidCallback onClose;

  const _ChainSheetHeader({
    required this.isDefault,
    required this.primary,
    required this.textPrimary,
    required this.textMuted,
    required this.isDark,
    required this.onReset,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 4, 12, 8),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: primary.withValues(alpha: 0.28)),
            ),
            child: Icon(Icons.reorder_rounded, color: primary, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'DSP Signal Chain',
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  isDefault
                      ? 'Default audiophile order · Drag to reorder'
                      : 'Custom signal routing · Active live',
                  style: TextStyle(
                    color: isDefault ? textMuted : primary,
                    fontSize: 11.5,
                    fontWeight: isDefault ? FontWeight.w400 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: onReset,
            icon: const Icon(Icons.restart_alt_rounded, size: 17),
            label: const Text('Reset'),
            style: TextButton.styleFrom(
              foregroundColor: onReset != null ? primary : textMuted,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: onClose,
            icon: Icon(
              Icons.close_rounded,
              color: textPrimary.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  final String label;
  final bool selected;
  final Color primary;
  final Color textPrimary;
  final Color outlineColor;
  final VoidCallback onTap;

  const _FilterPill({
    required this.label,
    required this.selected,
    required this.primary,
    required this.textPrimary,
    required this.outlineColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected
                ? primary.withValues(alpha: 0.16)
                : textPrimary.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? primary.withValues(alpha: 0.55) : outlineColor,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? primary : textPrimary.withValues(alpha: 0.8),
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _PinnedBoundaryBanner extends StatelessWidget {
  final String title;
  final String detail;
  final IconData icon;
  final Color primary;
  final Color textPrimary;
  final Color textMuted;
  final Color outlineColor;
  final bool isDark;

  const _PinnedBoundaryBanner({
    required this.title,
    required this.detail,
    required this.icon,
    required this.primary,
    required this.textPrimary,
    required this.textMuted,
    required this.outlineColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: (isDark ? Colors.white : Colors.black)
            .withValues(alpha: isDark ? 0.04 : 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: outlineColor.withValues(alpha: 0.7)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: textMuted,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  detail,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: textPrimary.withValues(alpha: 0.82),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyActiveRackState extends StatelessWidget {
  final Color textPrimary;
  final Color textMuted;
  final Color primary;
  final VoidCallback onShowAll;

  const _EmptyActiveRackState({
    required this.textPrimary,
    required this.textMuted,
    required this.primary,
    required this.onShowAll,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.tune_rounded, size: 32, color: textMuted),
            const SizedBox(height: 10),
            Text(
              'No active DSP modules in the rack',
              style: TextStyle(
                color: textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Switch to All Modules to pre-order effects before enabling them.',
              textAlign: TextAlign.center,
              style: TextStyle(color: textMuted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onShowAll,
              style: OutlinedButton.styleFrom(
                foregroundColor: primary,
                side: BorderSide(color: primary.withValues(alpha: 0.5)),
              ),
              child: const Text('Show All Modules'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReorderableRackTile extends StatelessWidget {
  final int visibleIndex;
  final int stepNumber;
  final DspChainNodeInfo info;
  final Color primary;
  final Color textPrimary;
  final Color textMuted;
  final Color outlineColor;
  final bool isDark;
  final ValueChanged<bool>? onToggle;
  final VoidCallback? onTapDetail;

  const _ReorderableRackTile({
    super.key,
    required this.visibleIndex,
    required this.stepNumber,
    required this.info,
    required this.primary,
    required this.textPrimary,
    required this.textMuted,
    required this.outlineColor,
    required this.isDark,
    this.onToggle,
    this.onTapDetail,
  });

  @override
  Widget build(BuildContext context) {
    final stepText = stepNumber.toString().padLeft(2, '0');
    final activeBorder = info.isEnabled
        ? primary.withValues(alpha: isDark ? 0.35 : 0.45)
        : outlineColor.withValues(alpha: 0.7);
    final tileBg = info.isEnabled
        ? primary.withValues(alpha: isDark ? 0.08 : 0.06)
        : (isDark ? Colors.white : Colors.black)
            .withValues(alpha: isDark ? 0.03 : 0.02);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: tileBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: activeBorder),
        ),
        child: InkWell(
          onTap: onTapDetail,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 4, 8),
            child: Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: info.isEnabled
                        ? primary.withValues(alpha: 0.16)
                        : textMuted.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    stepText,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: info.isEnabled ? primary : textMuted,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: info.isEnabled
                        ? primary.withValues(alpha: 0.14)
                        : textPrimary.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    info.icon,
                    size: 18,
                    color: info.isEnabled ? primary : textMuted,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        info.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: info.isEnabled
                              ? textPrimary
                              : textPrimary.withValues(alpha: 0.72),
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        info.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onToggle != null)
                  Transform.scale(
                    scale: 0.82,
                    child: Switch(
                      value: info.isEnabled,
                      onChanged: onToggle,
                      activeThumbColor: primary,
                    ),
                  ),
                Semantics(
                  button: true,
                  label: 'Drag to reorder ${info.title}',
                  child: ReorderableDragStartListener(
                    index: visibleIndex,
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Icon(
                        Icons.drag_handle_rounded,
                        color: info.isEnabled
                            ? textPrimary.withValues(alpha: 0.75)
                            : textMuted,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
