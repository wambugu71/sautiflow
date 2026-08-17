import 'package:flutter/material.dart';
import 'package:flutter_m3shapes_extended/flutter_m3shapes_extended.dart';
import 'package:shimmer/shimmer.dart';
import 'services/app_theme_service.dart';

class ShimmerMiniPlayer extends StatelessWidget {
  const ShimmerMiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final cardColor = context.cardDark;
    final outlineColor = context.outlineColor;
    final isDark = context.isDark;
    final artShape = context.albumArtShape;
    final placeholderColor = isDark
        ? Colors.white.withValues(alpha: 0.15)
        : Colors.black.withValues(alpha: 0.12);

    return Container(
      height: 64,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: outlineColor,
          width: 1,
        ),
      ),
      child: Shimmer.fromColors(
        baseColor: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.05),
        highlightColor: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.12),
        child: Row(
          children: [
            // Album Art Placeholder
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 4),
              child: M3EContainer(
                artShape,
                width: 48,
                height: 48,
                clipBehavior: Clip.antiAlias,
                color: placeholderColor,
                child: const SizedBox.shrink(),
              ),
            ),
            const SizedBox(width: 16),
            // Text Placeholders
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 120,
                    height: 14,
                    decoration: BoxDecoration(
                      color: placeholderColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: 80,
                    height: 12,
                    decoration: BoxDecoration(
                      color: placeholderColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
            // Controls Placeholders
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: placeholderColor,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            const SizedBox(width: 16),
            Container(
              width: 24,
              height: 24,
              margin: const EdgeInsets.only(right: 16),
              decoration: BoxDecoration(
                color: placeholderColor,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
