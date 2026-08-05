import 'package:flutter/material.dart';
import 'package:showcaseview/showcaseview.dart';
import '../services/app_theme_service.dart';

class AppShowcase extends StatelessWidget {
  final GlobalKey showcaseKey;
  final String title;
  final String description;
  final Widget child;
  final int currentStep;
  final int totalSteps;
  final VoidCallback? onNext;
  final VoidCallback? onPrev;

  const AppShowcase({
    super.key,
    required this.showcaseKey,
    required this.title,
    required this.description,
    required this.child,
    required this.currentStep,
    required this.totalSteps,
    this.onNext,
    this.onPrev,
  });

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeService.instance.currentData;
    final primary = theme.primary;
    final cardDark = theme.cardDark;

    return Showcase.withWidget(
      key: showcaseKey,
      height: 190,
      width: 290,
      targetPadding: const EdgeInsets.all(8),
      overlayColor: Colors.black,
      overlayOpacity: 0.75,
      container: Container(
        width: 290,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardDark,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: primary.withValues(alpha: 0.5),
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: primary,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: primary.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    '$currentStep/$totalSteps',
                    style: TextStyle(
                      color: primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (currentStep > 1)
                  TextButton.icon(
                    onPressed: () {
                      onPrev?.call();
                      ShowCaseWidget.of(context).previous();
                    },
                    icon: const Icon(Icons.arrow_back_rounded, size: 14),
                    label: const Text('Prev', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white70,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  )
                else
                  TextButton(
                    onPressed: () {
                      ShowCaseWidget.of(context).dismiss();
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Skip',
                        style:
                            TextStyle(color: Colors.white38, fontSize: 12)),
                  ),
                ElevatedButton.icon(
                  onPressed: () {
                    if (currentStep < totalSteps) {
                      onNext?.call();
                      ShowCaseWidget.of(context).next();
                    } else {
                      ShowCaseWidget.of(context).dismiss();
                    }
                  },
                  icon: Icon(
                    currentStep < totalSteps
                        ? Icons.arrow_forward_rounded
                        : Icons.check_rounded,
                    size: 14,
                  ),
                  label: Text(
                    currentStep < totalSteps ? 'Next' : 'Done',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      child: child,
    );
  }
}
