import 'package:material_ui/material_ui.dart';
import 'package:sautiplay/services/app_theme_service.dart';
import 'package:sautiplay/widgets/signal_path.dart';

class SignalPathCard extends StatefulWidget {
  final SignalPathResult path;
  final Color cardBg;
  final Color outlineColor;
  final bool isDark;
  final Color textPrimary;
  final Color textMuted;
  final VoidCallback? onEditChainOrder;

  const SignalPathCard({
    super.key,
    required this.path,
    required this.cardBg,
    required this.outlineColor,
    required this.isDark,
    required this.textPrimary,
    required this.textMuted,
    this.onEditChainOrder,
  });

  @override
  State<SignalPathCard> createState() => _SignalPathCardState();
}

class _SignalPathCardState extends State<SignalPathCard> {
  bool _showInactive = false;
  final Set<String> _expandedNodeKeys = <String>{};

  void _toggleNode(String key) {
    setState(() {
      if (_expandedNodeKeys.contains(key)) {
        _expandedNodeKeys.remove(key);
      } else {
        _expandedNodeKeys.add(key);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final primary = context.appTheme.primary;
    final successColor =
        widget.isDark ? const Color(0xFF4ADE80) : const Color(0xFF16A34A);
    final warningColor =
        widget.isDark ? Colors.amberAccent : const Color(0xFFD97706);

    final totalMs = widget.path.totalMeasuredLatencyMs;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: widget.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: widget.isDark
              ? widget.textPrimary.withValues(alpha: 0.08)
              : widget.outlineColor,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Signal Path',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        color: widget.textPrimary.withValues(alpha: 0.85),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.4,
                      ),
                    ),
                    Text(
                      'TAP NODE FOR LIVE DATA',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        color: widget.textMuted.withValues(alpha: 0.7),
                        fontSize: 8.5,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.onEditChainOrder != null) ...[
                Semantics(
                  button: true,
                  label: 'Reorder DSP signal chain',
                  child: InkWell(
                    onTap: widget.onEditChainOrder,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: widget.isDark ? 0.14 : 0.09),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: primary.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.reorder_rounded, size: 12, color: primary),
                          const SizedBox(width: 4),
                          Text(
                            'REORDER',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                              color: primary,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              if (totalMs != null)
                Text(
                  '${totalMs.toStringAsFixed(2)} ms',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    color: successColor,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Divider(
            color: widget.isDark
                ? widget.textPrimary.withValues(alpha: 0.08)
                : widget.outlineColor,
            height: 1,
          ),
          const SizedBox(height: 12),
          for (int i = 0; i < widget.path.nodes.length; i++) ...[
            Builder(builder: (context) {
              final node = widget.path.nodes[i];
              final key = node.id ?? '${node.kind.name}_${node.title}_$i';
              return _ChainNodeTile(
                node: node,
                isExpanded: _expandedNodeKeys.contains(key),
                onTap: node.liveParams.isNotEmpty ? () => _toggleNode(key) : null,
                isDark: widget.isDark,
                primary: primary,
                warningColor: warningColor,
                textPrimary: widget.textPrimary,
                textMuted: widget.textMuted,
              );
            }),
            if (widget.path.nodes[i].outgoingArrow != null &&
                i < widget.path.nodes.length - 1)
              _ChainArrow(
                arrow: widget.path.nodes[i].outgoingArrow!,
                isDark: widget.isDark,
                primary: primary,
                warningColor: warningColor,
                textMuted: widget.textMuted,
              ),
          ],
          if (widget.path.inactiveStageCount > 0) ...[
            const SizedBox(height: 10),
            InkWell(
              onTap: () => setState(() => _showInactive = !_showInactive),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                child: Row(
                  children: [
                    Icon(
                      _showInactive
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 16,
                      color: widget.textMuted,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${widget.path.inactiveStageCount} inactive stages',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: widget.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_showInactive)
              Padding(
                padding: const EdgeInsets.only(left: 22, top: 4),
                child: Text(
                  widget.path.inactiveStageNames.join(' · '),
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10.5,
                    color: widget.textMuted.withValues(alpha: 0.75),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _ChainNodeTile extends StatelessWidget {
  final SignalPathNode node;
  final bool isExpanded;
  final VoidCallback? onTap;
  final bool isDark;
  final Color primary;
  final Color warningColor;
  final Color textPrimary;
  final Color textMuted;

  const _ChainNodeTile({
    required this.node,
    required this.isExpanded,
    required this.onTap,
    required this.isDark,
    required this.primary,
    required this.warningColor,
    required this.textPrimary,
    required this.textMuted,
  });

  @override
  Widget build(BuildContext context) {
    final Color markerColor;
    if (node.isWarning) {
      markerColor = warningColor;
    } else if (node.isBypassed) {
      markerColor = textMuted.withValues(alpha: 0.5);
    } else if (node.kind == ChainNodeKind.output ||
        node.kind == ChainNodeKind.source) {
      markerColor = primary;
    } else {
      markerColor = isDark ? const Color(0xFF4ADE80) : const Color(0xFF16A34A);
    }

    final latencyText = node.latencyMs != null
        ? '${node.isEstimatedLatency ? "≈" : ""}${node.latencyMs!.toStringAsFixed(2)} ms'
        : null;
    final bool hasParams = node.liveParams.isNotEmpty;

    return Semantics(
      button: hasParams,
      label: '${node.title}: ${node.detail}'
          '${latencyText != null ? ", latency $latencyText" : ""}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: node.isWarning
                        ? Icon(Icons.warning_amber_rounded,
                            size: 13, color: warningColor)
                        : Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.symmetric(horizontal: 2.5),
                            decoration: BoxDecoration(
                              color: markerColor,
                              shape: node.kind == ChainNodeKind.output
                                  ? BoxShape.rectangle
                                  : BoxShape.circle,
                              borderRadius: node.kind == ChainNodeKind.output
                                  ? BorderRadius.circular(2)
                                  : null,
                            ),
                          ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (node.badge != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: (node.isWarning
                                          ? warningColor
                                          : primary)
                                      .withValues(alpha: isDark ? 0.16 : 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  node.badge!,
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                    color:
                                        node.isWarning ? warningColor : primary,
                                  ),
                                ),
                              ),
                            Text(
                              node.title,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color:
                                    node.isBypassed ? textMuted : textPrimary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          node.detail,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: node.isBypassed
                                ? textMuted.withValues(alpha: 0.75)
                                : textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (latencyText != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      latencyText,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 10.5,
                        color: warningColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                  if (hasParams) ...[
                    const SizedBox(width: 4),
                    Icon(
                      isExpanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 16,
                      color: textMuted.withValues(alpha: 0.75),
                    ),
                  ],
                ],
              ),
              if (isExpanded && hasParams) ...[
                const SizedBox(height: 8),
                Container(
                  margin: const EdgeInsets.only(left: 20),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: (isDark ? Colors.white : Colors.black)
                        .withValues(alpha: isDark ? 0.04 : 0.03),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: (node.isWarning ? warningColor : primary)
                          .withValues(alpha: isDark ? 0.22 : 0.16),
                      width: 0.8,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final entry in node.liveParams.entries)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 5,
                                child: Text(
                                  entry.key,
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 10,
                                    color: textMuted,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 7,
                                child: Text(
                                  entry.value,
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                    color: entry.key.contains('Warning')
                                        ? warningColor
                                        : textPrimary.withValues(alpha: 0.92),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ChainArrow extends StatelessWidget {
  final SignalPathArrow arrow;
  final bool isDark;
  final Color primary;
  final Color warningColor;
  final Color textMuted;

  const _ChainArrow({
    required this.arrow,
    required this.isDark,
    required this.primary,
    required this.warningColor,
    required this.textMuted,
  });

  @override
  Widget build(BuildContext context) {
    final bool isConversion = arrow.conversionKind != FormatConversionKind.none;
    final bool isDowncast =
        arrow.conversionKind == FormatConversionKind.downcast;
    final Color badgeColor = isDowncast
        ? warningColor
        : (isConversion ? primary : textMuted);

    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.only(left: 5.5, top: 2, bottom: 2),
        child: Row(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 1.5,
                  height: 8,
                  color: badgeColor.withValues(alpha: 0.55),
                ),
                Icon(
                  Icons.arrow_drop_down_rounded,
                  size: 14,
                  color: badgeColor.withValues(alpha: 0.85),
                ),
              ],
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
              decoration: BoxDecoration(
                color: isConversion
                    ? badgeColor.withValues(alpha: isDark ? 0.14 : 0.09)
                    : textMuted.withValues(alpha: isDark ? 0.08 : 0.06),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: badgeColor.withValues(alpha: isConversion ? 0.35 : 0.15),
                  width: 0.7,
                ),
              ),
              child: Text(
                arrow.note != null
                    ? '${arrow.formatLabel} · ${arrow.note}'
                    : arrow.formatLabel,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 9.5,
                  fontWeight: isConversion ? FontWeight.bold : FontWeight.normal,
                  color: badgeColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
