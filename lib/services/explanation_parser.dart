import 'dart:convert';

class ParsedExplanation {
  const ParsedExplanation({
    required this.detailedDescription,
    required this.keyPoints,
    required this.studyTip,
    required this.isJsonFormat,
  });

  final String detailedDescription;
  final List<Map<String, String>>? keyPoints;
  final String? studyTip;
  final bool isJsonFormat;
}

class ExplanationParser {
  const ExplanationParser._();

  static ParsedExplanation parse(String explanationText) {
    final decoded = _decodeStructuredExplanation(explanationText);

    if (decoded == null) {
      return ParsedExplanation(
        detailedDescription: explanationText,
        keyPoints: null,
        studyTip: null,
        isJsonFormat: false,
      );
    }

    return ParsedExplanation(
      detailedDescription: decoded['detailed_description'] is String
          ? decoded['detailed_description'] as String
          : explanationText,
      keyPoints: _parseKeyPoints(decoded['key_points']),
      studyTip: decoded['study_tip'] is String
          ? decoded['study_tip'] as String
          : null,
      isJsonFormat: true,
    );
  }

  static Map<String, dynamic>? _decodeStructuredExplanation(
    String explanationText,
  ) {
    try {
      final decoded = jsonDecode(explanationText);
      if (decoded is! Map<String, dynamic>) return null;

      final hasKnownSchema = decoded.containsKey('detailed_description') ||
          decoded.containsKey('key_points') ||
          decoded.containsKey('study_tip');

      return hasKnownSchema ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  static List<Map<String, String>>? _parseKeyPoints(Object? keyPointsRaw) {
    if (keyPointsRaw is! List) return null;

    return keyPointsRaw.map((item) {
      if (item is Map) {
        return {
          'title': item['title']?.toString() ?? '',
          'content': item['content']?.toString() ?? '',
        };
      }

      return {'title': '', 'content': ''};
    }).toList();
  }
}
