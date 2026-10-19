import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Web learning suite source guards', () {
    late String screen;

    setUpAll(() {
      screen = File('lib/screens/web_app_screen.dart').readAsStringSync();
    });

    test('exposes the ordered learning and review areas', () {
      for (final area in <String>[
        'favoriteReview',
        'settings',
        'masteryReport',
        'dailyPlan',
        'examResult',
        'examReview',
      ]) {
        expect(screen, contains(area));
      }
      expect(screen, contains('WebExamHistoryRepository'));
      expect(screen, contains('resetWebLearningCounters'));
    });

    test('keeps payment out of the Web learning flow', () {
      expect(screen, isNot(contains('SubscriptionPage')));
      expect(screen, isNot(contains('IapService')));
    });

    test('Web Apple login uses a Firebase popup', () {
      final provider =
          File('lib/providers/user_state_provider.dart').readAsStringSync();
      expect(provider, contains("OAuthProvider('apple.com')"));
      expect(provider, contains("addScope('email')"));
      expect(provider, contains('auth.signInWithPopup(provider)'));
      expect(screen, contains('signInWithApple'));
    });

    test('exam history and active session have owner-only rule sections', () {
      final rules = File('firestore.rules').readAsStringSync();
      expect(rules, contains('match /exam_history/{attemptId}'));
      expect(rules, contains('match /exam_sessions/{sessionId}'));
      expect(rules, contains("sessionId == 'current'"));
      expect(rules, contains('request.resource.data.session.actor_id == uid'));
    });
  });
}
