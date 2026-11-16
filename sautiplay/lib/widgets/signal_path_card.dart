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

  const SignalPathCard({
    super.key,
    required this.path,
    required this.cardBg,
    required this.outlineColor,
    required this.isDark,
    required this.textPrimary,
    required this.textMuted,
  });

  @override
  State<SignalPathCard> createState() => _SignalPathCardState();
}

class _SignalPathCardState extends State<SignalPathCard> {
  bool _showInactive = false;

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
            _ChainNodeTile(
              node: widget.path.nodes[i],
              isDark: widget.isDark,
              primary: primary,
              warningColor: warningColor,
              textPrimary: widget.textPrimary,
              textMuted: widget.textMuted,
            ),
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
  final bool isDark;
  final Color primary;
  final Color warningColor;
  final Color textPrimary;
  final Color textMuted;

  const _ChainNodeTile({
    required this.node,
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

    return Semantics(
      label: '${node.title}: ${node.detail}'
          '${latencyText != null ? ", latency $latencyText" : ""}',
      child: Row(
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
                          color: primary.withValues(alpha: isDark ? 0.16 : 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          node.badge!,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                            color: primary,
                          ),
                        ),
                      ),
                    Text(
                      node.title,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: node.isBypassed ? textMuted : textPrimary,
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
        ],
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
