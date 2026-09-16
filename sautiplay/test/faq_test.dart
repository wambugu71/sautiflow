import 'package:flutter_test/flutter_test.dart';
import 'package:sautiplay/data/faq_data.dart';
import 'package:sautiplay/models/faq_item.dart';

void main() {
  group('FAQ Data and Model Tests', () {
    test('sautiplayFaqItems has exactly 9 questions derived from site', () {
      expect(sautiplayFaqItems.length, 9);
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
}
