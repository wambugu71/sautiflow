import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:sautiplay/data/faq_data.dart';
import 'package:sautiplay/faq_screen.dart';
import 'package:sautiplay/models/faq_item.dart';
import 'package:sautiplay/services/app_theme_service.dart';

Widget _hostFaqScreen() {
  final themeData = AppThemeService.themes.first;
  return AppThemeProvider(
    themeData: themeData,
    child: M3EMaterialApp(
      data: themeData.toM3EThemeData(),
      home: const FaqScreen(),
    ),
  );
}

void main() {
  group('FAQ Data and Model Tests', () {
    test('sautiplayFaqItems has exactly 10 questions derived from site', () {
      expect(sautiplayFaqItems.length, 10);
    });

    test('All FAQ items have complete fields', () {
      for (final item in sautiplayFaqItems) {
        expect(item.id.isNotEmpty, isTrue, reason: 'id must not be empty');
        expect(item.question.isNotEmpty, isTrue,
            reason: 'question must not be empty');
        expect(item.answer.isNotEmpty, isTrue,
            reason: 'answer must not be empty');
        expect(item.category.isNotEmpty, isTrue,
            reason: 'category must not be empty');
        expect(item.tags.isNotEmpty, isTrue, reason: 'tags must not be empty');
      }
    });

    test('FaqItem JSON serialization round-trips properly', () {
      final sample = sautiplayFaqItems.first;
      final jsonMap = sample.toJson();
      final restored = FaqItem.fromJson(jsonMap);

      expect(restored.id, sample.id);
      expect(restored.question, sample.question);
      expect(restored.answer, sample.answer);
      expect(restored.category, sample.category);
      expect(restored.tags, sample.tags);
    });

    test('Contains key audiophile topics from site owner\'s manual', () {
      final questions =
          sautiplayFaqItems.map((e) => e.question.toLowerCase()).toList();

      expect(
          questions.any((q) => q.contains('exclusive mode') || q.contains('hardware declined')),
          isTrue);
      expect(
          questions.any((q) => q.contains('when bit-perfect is enabled') || q.contains('actually bit-perfect')),
          isTrue);
      expect(questions.any((q) => q.contains('auto-rate matching')), isTrue);
      expect(questions.any((q) => q.contains('oem equalizers') || q.contains('dolby atmos')),
          isTrue);
      expect(questions.any((q) => q.contains('resampler')), isTrue);
      expect(questions.any((q) => q.contains('streaming tracks')), isTrue);
      expect(questions.any((q) => q.contains('64-bit float')), isTrue);
      expect(questions.any((q) => q.contains('autoeq')), isTrue);
      expect(questions.any((q) => q.contains('dlna')), isTrue);
      expect(questions.any((q) => q.contains('ads')), isTrue);
    });
  });

  group('FaqScreen Widget Tests with M3E CardList and Expanders', () {
    testWidgets('FaqScreen renders M3ECardList and M3ECardListItem with question items',
        (tester) async {
      await tester.pumpWidget(_hostFaqScreen());
      await tester.pumpAndSettle();

      expect(find.byType(M3ECardList), findsAtLeastNWidgets(1));
      expect(find.byType(M3ECardListItem), findsAtLeastNWidgets(1));
      expect(find.text('FAQ\'s'), findsOneWidget);
      expect(find.text(sautiplayFaqItems.first.question), findsOneWidget);
    });

    testWidgets('Tapping FAQ item expands and reveals answer',
        (tester) async {
      await tester.pumpWidget(_hostFaqScreen());
      await tester.pumpAndSettle();

      final firstFaq = sautiplayFaqItems.first;
      final questionFinder = find.text(firstFaq.question);
      expect(questionFinder, findsOneWidget);

      await tester.tap(questionFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final firstParagraph = firstFaq.answer.split('\n\n').first;
      expect(find.text(firstParagraph), findsOneWidget);
      expect(find.byTooltip('Copy FAQ'), findsAtLeastNWidgets(1));
    });

    testWidgets('Category chip filtering updates the list',
        (tester) async {
      await tester.pumpWidget(_hostFaqScreen());
      await tester.pumpAndSettle();

      // Tap on a specific category chip if available
      final categoryChip = find.widgetWithText(ChoiceChip, 'Hardware & Bit-Perfect');
      if (categoryChip.evaluate().isNotEmpty) {
        await tester.ensureVisible(categoryChip);
        await tester.tap(categoryChip);
        await tester.pumpAndSettle();

        expect(find.text(sautiplayFaqItems.first.question), findsOneWidget);
      }
    });
  });
}
