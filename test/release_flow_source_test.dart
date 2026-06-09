import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Release flow source guards', () {
    test('chapter practice enforces VIP chapter locks before navigation', () {
      final source =
          File('lib/screens/chapter_selection_screen.dart').readAsStringSync();

      expect(source, contains('userStateProvider.isChapterLocked(chapterId)'));
      expect(source, contains('chapter_locked_title'));
      expect(source, contains('chapter_locked_message'));
      expect(source, contains('const SubscriptionPage()'));
    });

    test('explanation limit routes free users to the subscription page', () {
      final source =
          File('lib/widgets/question_widget.dart').readAsStringSync();

      expect(source, contains('!userStateProvider.canViewExplanation'));
      expect(source, contains('explanation_limit_reached_message'));
      expect(source, contains('const SubscriptionPage()'));
    });

    test('subscription page assigns IAP service before synchronous init events',
        () {
      final source =
          File('lib/screens/subscription_page.dart').readAsStringSync();

      final createIndex = source.indexOf('final iapService = IapService();');
      final assignIndex = source.indexOf('_iapService = iapService;');
      final listenerIndex =
          source.indexOf('..addListener(_handleIapStateChanged)');
      final initIndex = source
          .indexOf('..init(onEntitlementActive: _activateVipFromPurchase)');

      expect(createIndex, isNonNegative);
      expect(assignIndex, greaterThan(createIndex));
      expect(listenerIndex, greaterThan(assignIndex));
      expect(initIndex, greaterThan(listenerIndex));
      expect(source, isNot(contains('_iapService = IapService()')));
    });

    test('Firebase startup can degrade to offline mode', () {
      final mainSource = File('lib/main.dart').readAsStringSync();
      final providerSource =
          File('lib/providers/user_state_provider.dart').readAsStringSync();

      expect(mainSource, contains('FirebaseStatus.markInitialized()'));
      expect(mainSource, contains('FirebaseStatus.markUnavailable(e)'));
      expect(providerSource, contains('final auth = FirebaseStatus.auth;'));
      expect(
        providerSource,
        isNot(contains('FirebaseAuth.instance.authStateChanges()')),
      );
    });

    test('Firestore cloud sync commits writes in bounded batches', () {
      final source =
          File('lib/services/database_service.dart').readAsStringSync();

      expect(source, contains('_firestoreBatchWriteLimit = 450'));
      expect(source, contains('_deleteQuerySnapshotInBatches'));
      expect(source, contains('pendingWrites >= _firestoreBatchWriteLimit'));
      expect(source, contains('committedBatches++'));
      expect(source, contains("'total_attempts': row['total_attempts']"));
      expect(source, contains('static int _cloudTotalAttempts'));
      expect(source, contains('wrongCount + correctStreak'));
      expect(source, contains('mergedTotalAttempts'));
      expect(source, contains('WHEN ? > total_attempts THEN ?'));
      expect(
          source,
          contains(
            'await _deleteQuerySnapshotInBatches(firestore, snapshot)',
          ));
      expect(
          source,
          contains(
            'await _deleteQuerySnapshotInBatches(firestore, progressSnapshot)',
          ));
      expect(
          source,
          contains(
            'await _deleteQuerySnapshotInBatches(firestore, usageSnapshot)',
          ));
    });

    test('Firestore rules allow complete progress sync fields only', () {
      final source = File('firestore.rules').readAsStringSync();

      expect(source, contains("'correct_streak'"));
      expect(source, contains("'wrong_count'"));
      expect(source, contains("'total_attempts'"));
      expect(source, contains("'is_mastered'"));
      expect(source, contains("'is_favorite'"));
      expect(source, contains("'last_practiced'"));
      expect(source, contains('request.resource.data.total_attempts is int'));
      expect(source, contains('request.resource.data.total_attempts >= 0'));
      expect(source, contains('request.resource.data.total_attempts <= 10000'));
      expect(source, isNot(contains("'error_count'")));
    });

    test('subscription purchase CTA stays locked while IAP is active', () {
      final source =
          File('lib/screens/subscription_page.dart').readAsStringSync();

      expect(
        source,
        contains(
          'final isPurchaseInProgress = _isSubscribing || '
          '_iapService.isPurchasing;',
        ),
      );
      expect(source, contains('child: isPurchaseInProgress'));
      expect(
        source,
        contains(
          'onPressed: _iapService.isPurchasing ? null : '
          '_handleRestorePurchase',
        ),
      );
      expect(source, contains('Future<void> _handleSubscribeButtonPressed()'));
      expect(source, contains('_isSubscribing = true;'));
      expect(
        source,
        isNot(
          contains(
            'finally {\n'
            '      if (mounted) {\n'
            '        setState(() {\n'
            '          _isSubscribing = false;',
          ),
        ),
      );
    });

    test('IAP service ignores duplicate purchase starts', () {
      final source = File('lib/services/iap_service.dart').readAsStringSync();

      expect(
        source,
        contains(
          'if (_operation != IapOperation.none) {\n'
          '      return;\n'
          '    }\n\n'
          '    final product = _monthlyProduct;',
        ),
      );
    });

    test('client code does not write Firestore VIP entitlements', () {
      final source =
          File('lib/services/database_service.dart').readAsStringSync();

      expect(source, contains('checkUserVipInFirestore'));
      expect(source, contains('Admin SDK'));
      expect(source, contains('客戶端只讀取雲端權益'));
      expect(source, isNot(contains('setUserVipInFirestore')));
      expect(source, isNot(contains(".set({'isVip'")));
      expect(source, isNot(contains(".update({'isVip'")));
      expect(source, isNot(contains(".set({'vip'")));
      expect(source, isNot(contains(".update({'vip'")));
    });

    test('guest progress merge preserves existing account data', () {
      final databaseSource =
          File('lib/services/database_service.dart').readAsStringSync();
      final providerSource =
          File('lib/providers/user_state_provider.dart').readAsStringSync();

      expect(databaseSource, contains('mergeGuestDataToAccount'));
      expect(databaseSource,
          isNot(contains('INSERT OR IGNORE INTO user_progress')));
      expect(databaseSource,
          contains('ON CONFLICT(question_id, user_id) DO UPDATE SET'));
      expect(
        databaseSource,
        contains('user_progress.error_count + excluded.error_count'),
      );
      expect(
        databaseSource,
        contains('user_progress.wrong_count + excluded.wrong_count'),
      );
      expect(
        databaseSource,
        contains('user_progress.total_attempts + excluded.total_attempts'),
      );
      expect(databaseSource, contains("'mock_exam_results'"));
      expect(databaseSource, contains("{'user_id': normalizedTargetUid}"));
      expect(providerSource, contains('_userId = uid;'));
      expect(providerSource, contains('await refreshMistakeCount();'));
      expect(providerSource, contains('await refreshChaptersProgress();'));
      expect(providerSource, contains('await loadPassRatePrediction();'));
    });

    test('sign-out cloud deletion only removes learning data', () {
      final source =
          File('lib/services/database_service.dart').readAsStringSync();
      final clearStart =
          source.indexOf('static Future<void> clearCloudUserData');
      final vipReadStart =
          source.indexOf('static Future<bool?> checkUserVipInFirestore');

      expect(clearStart, isNonNegative);
      expect(vipReadStart, greaterThan(clearStart));

      final clearCloudUserDataSource =
          source.substring(clearStart, vipReadStart);
      expect(clearCloudUserDataSource, contains(".collection('progress')"));
      expect(clearCloudUserDataSource, contains(".collection('daily_usage')"));
      expect(clearCloudUserDataSource, isNot(contains(".doc(userId).delete")));
      expect(clearCloudUserDataSource, isNot(contains("'isVip'")));
    });

    test('daily free limits use AccessPolicy and sync cloud usage', () {
      final providerSource =
          File('lib/providers/user_state_provider.dart').readAsStringSync();
      final practiceSource =
          File('lib/screens/practice_screen.dart').readAsStringSync();
      final rulesSource = File('firestore.rules').readAsStringSync();

      expect(providerSource, contains('AccessPolicy.canPractice'));
      expect(providerSource, contains('AccessPolicy.canStartExam'));
      expect(providerSource, contains('AccessPolicy.canViewExplanation'));
      expect(providerSource, contains("_writeDailyUsageToCloud"));
      expect(providerSource, contains("'quiz_count': FieldValue.increment(1)"));
      expect(
        providerSource,
        contains("'explanation_count': FieldValue.increment(1)"),
      );
      expect(providerSource, contains("'exam_used': true"));
      expect(providerSource, contains("data?['explanation_count']"));
      expect(providerSource, contains("data?['exam_used'] == true"));

      expect(practiceSource, isNot(contains('dailyQuizCount >= 30')));
      expect(practiceSource, contains('userStateProvider.canPractice()'));

      expect(rulesSource, contains('function dailyUsageFields()'));
      expect(rulesSource, contains("'explanation_count'"));
      expect(rulesSource, contains("'exam_used'"));
      expect(rulesSource, contains('incrementsByOne'));
      expect(rulesSource, contains('request.resource.data.exam_used == true'));
    });

    test('saved language loads before optional statistics refresh', () {
      final providerSource =
          File('lib/providers/user_state_provider.dart').readAsStringSync();
      final languageIndex = providerSource.indexOf(
        "_userState = _userState.copyWith(\n"
        "        currentLanguage: currentLang,",
      );
      final notifyIndex =
          providerSource.indexOf('notifyListeners();', languageIndex);
      final masteryRefreshIndex =
          providerSource.indexOf('await refreshMasteryStats();');

      expect(languageIndex, isNonNegative);
      expect(notifyIndex, greaterThan(languageIndex));
      expect(masteryRefreshIndex, greaterThan(notifyIndex));
      expect(providerSource,
          contains('try {\n        await refreshMasteryStats();'));
      expect(providerSource,
          contains('try {\n        await refreshMistakeCount();'));
      expect(providerSource,
          contains('try {\n        await refreshChaptersProgress();'));
      expect(
          providerSource, contains('secureVipRaw = await _secureStorage.read'));
      expect(providerSource, contains('secureDailyQuizRaw ='));
      expect(providerSource,
          contains('await checkAndResetDailyCounters(prefs: prefs);'));
      expect(
        providerSource,
        contains(
            "await _secureStorage.write(key: 'daily_quiz_count', value: '0');"),
      );
    });
  });
}
