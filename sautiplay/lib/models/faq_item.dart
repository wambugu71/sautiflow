class FaqItem {
  final String id;
  final String question;
  final String answer;
  final String category;
  final List<String> tags;

  const FaqItem({
    required this.id,
    required this.question,
    required this.answer,
    required this.category,
    required this.tags,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'question': question,
        'answer': answer,
        'category': category,
        'tags': tags,
      };

  factory FaqItem.fromJson(Map<String, dynamic> json) {
    return FaqItem(
      id: json['id'] as String,
      question: json['question'] as String,
      answer: json['answer'] as String,
      category: json['category'] as String,
      tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? const [],
    );
  }
}
