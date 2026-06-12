import 'package:flutter_test/flutter_test.dart';
import 'package:italy_quiz_app/services/explanation_parser.dart';

void main() {
  group('ExplanationParser', () {
    test('parses structured explanation JSON', () {
      final parsed = ExplanationParser.parse('''
{
  "detailed_description": "Stop means stop.",
  "key_points": [
    {"title": "STOP", "content": "Always stop fully."}
  ],
  "study_tip": "Look for the red sign."
}
''');

      expect(parsed.isJsonFormat, isTrue);
      expect(parsed.detailedDescription, 'Stop means stop.');
      expect(parsed.keyPoints, [
        {'title': 'STOP', 'content': 'Always stop fully.'},
      ]);
      expect(parsed.studyTip, 'Look for the red sign.');
    });

    test('keeps plain text explanations unchanged', () {
      const text = 'This is a normal explanation.';

      final parsed = ExplanationParser.parse(text);

      expect(parsed.isJsonFormat, isFalse);
      expect(parsed.detailedDescription, text);
      expect(parsed.keyPoints, isNull);
      expect(parsed.studyTip, isNull);
    });

    test('falls back to plain text for malformed JSON', () {
      const text = '{"detailed_description": "missing quote}';

      final parsed = ExplanationParser.parse(text);

      expect(parsed.isJsonFormat, isFalse);
      expect(parsed.detailedDescription, text);
      expect(parsed.keyPoints, isNull);
      expect(parsed.studyTip, isNull);
    });

    test('ignores JSON without the expected explanation schema', () {
      const text = '{"message": "not an explanation"}';

      final parsed = ExplanationParser.parse(text);

      expect(parsed.isJsonFormat, isFalse);
      expect(parsed.detailedDescription, text);
    });

    test('normalizes unusual key point entries', () {
      final parsed = ExplanationParser.parse('''
{
  "detailed_description": "Description.",
  "key_points": [
    {"title": 123, "content": true},
    "not a map"
  ]
}
''');

      expect(parsed.isJsonFormat, isTrue);
      expect(parsed.keyPoints, [
        {'title': '123', 'content': 'true'},
        {'title': '', 'content': ''},
      ]);
    });
  });
}
