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

    test('full explanations have no quota gate or subscription redirect', () {
      final source =
          File('lib/widgets/question_widget.dart').readAsStringSync();

      expect(source, isNot(contains('!userStateProvider.canViewExplanation')));
      expect(source, isNot(contains('explanation_limit_reached_message')));
      expect(source, isNot(contains('const SubscriptionPage()')));
    });

    test('IAP service is app-level: the page uses it but never owns it', () {
      final page =
          File('lib/screens/subscription_page.dart').readAsStringSync();
      final main = File('lib/main.dart').readAsStringSync();
      final service = File('lib/services/iap_service.dart').readAsStringSync();

      // 页面从 Provider 取用，不创建、不 dispose，也不自己监听 purchaseStream。
      expect(page, contains('Provider.of<IapService>(context, listen: false)'));
      expect(page, isNot(contains('IapService(')));
      expect(page, isNot(contains('_iapService.dispose')));
      expect(page, isNot(contains('..dispose()')));
      expect(page, isNot(contains('purchaseStream')));
      expect(
          page, contains('_iapService.removeListener(_handleIapStateChanged)'));

      // main.dart 在启动时创建（lazy: false）并 start，生命周期与 App 相同。
      expect(main, contains('ChangeNotifierProvider<IapService>('));
      expect(main, contains('lazy: false'));
      expect(main, contains('service.start('));

      // 购买流只在 App 级服务里监听一次，且仍要求云端验证。
      expect(RegExp(r'_iap\.purchaseStream\.listen').allMatches(service).length,
          1);
      expect(service, contains('_purchaseVerifier.verify(purchase)'));
    });

    test('IAP sync is single-flight + trailing: no fixed throttle, no Timer',
        () {
      final service = File('lib/services/iap_service.dart').readAsStringSync();

      expect(service, isNot(contains('_syncThrottle')));
      expect(service, isNot(contains('_lastSyncAt')));
      // Play 同步路径不用计时器（每次真实的 resume / 登录都查询）。
      final sync = service.substring(
        service.indexOf('Future<void> syncPurchases()'),
        service.indexOf('Future<_QueryResult> _queryOwned()'),
      );
      expect(sync, isNot(contains('Timer')));
      // K1：唯一的计时器是购买流程验证的限次重试（5 / 15 / 45 秒后停止）。
      expect(service,
          contains('_purchaseRetryAttempt >= _purchaseRetryDelays.length'));
      expect(service, contains('Duration(seconds: 45)'));
      expect(service, contains('_syncQueued'));
      // 去重与串行按账号隔离。
      expect(service,
          contains('typedef _PurchaseKey = (String uid, String token);'));
      expect(service, contains('final key = (uid, token);'));
      expect(service, contains('Map<String, Future<void>> _queueTails'));
    });

    test('IAP loadProducts honors the billing switch before touching the store',
        () {
      final service = File('lib/services/iap_service.dart').readAsStringSync();
      final gate =
          service.indexOf('if (!_billingSupported) {\n      // 未启用购买的平台');
      final firstStoreCall =
          service.indexOf('_iap.queryProductDetails(_productIds)');

      expect(gate, isNonNegative);
      expect(gate, lessThan(firstStoreCall));
    });

    test('main.dart does not keep a Provider BuildContext inside IapService',
        () {
      final main = File('lib/main.dart').readAsStringSync();

      expect(main,
          contains('final userState = context.read<UserStateProvider>();'));
      expect(main, contains('userState.activateVipFromVerifiedPurchase'));
      expect(main, isNot(contains('() => context')));
    });

    test(
        'integration/screenshot tests never use the real Billing implementation',
        () {
      final files = Directory('integration_test')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));

      for (final file in files) {
        final source = file.readAsStringSync();
        // 不允许无参（真实）IapService。
        expect(
          RegExp(r'IapService\(\s*\)').hasMatch(source),
          isFalse,
          reason: '${file.path} must not construct a real IapService()',
        );
        // 直接展示订阅页的测试必须显式提供“关闭”或“假” IAP。
        if (source.contains('SubscriptionPage')) {
          expect(source, contains('ChangeNotifierProvider<IapService>'),
              reason: '${file.path} shows SubscriptionPage');
          expect(
            source.contains('billingSupported: false') ||
                RegExp(r'iap:\s*ScreenshotIap\(').hasMatch(source),
            isTrue,
            reason: '${file.path} must use a disabled or fake IAP',
          );
        }
      }
    });

    test('IAP service never grants VIP locally; each store is behind its flag',
        () {
      final service = File('lib/services/iap_service.dart').readAsStringSync();

      expect(service, isNot(contains('setIsVip')));
      expect(service, isNot(contains('updateUserState')));
      expect(service, isNot(contains('isVip')));
      // Play 与 App Store 各自由 build 旗标开启，Web 永远关闭（见 ios_subscription_and_account_deletion_test.dart）。
      expect(
        service,
        contains(
          '(!kIsWeb &&\n'
          '          ((AppConfig.playBillingEnabled &&\n'
          '                  defaultTargetPlatform == TargetPlatform.android) ||\n'
          '              (AppConfig.appStoreBillingEnabled &&\n'
          '                  defaultTargetPlatform == TargetPlatform.iOS)))',
        ),
      );
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
      // clearCloudUserData 遍历 cloudUserDataSubcollections，每个集合都分批删除。
      expect(
          source, contains('for (final name in cloudUserDataSubcollections)'));
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
          'Future<void> buyMonthly() async {\n'
          '    if (_operation != IapOperation.none) {\n'
          '      return;\n'
          '    }\n',
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
      expect(clearCloudUserDataSource, contains('.collection(name)'));
      final listStart = source.indexOf('cloudUserDataSubcollections = [');
      final listSource = source.substring(listStart, clearStart);
      for (final name in [
        'progress',
        'daily_usage',
        'exam_history',
        'exam_sessions',
      ]) {
        expect(listSource, contains("'$name'"));
      }
      expect(listSource, isNot(contains("'playPurchases'")));
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
        isNot(contains("'explanation_count': FieldValue.increment(1)")),
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

    test('daily counters and growth refresh when the app resumes', () {
      final mainSource = File('lib/main.dart').readAsStringSync();
      final reportSource =
          File('lib/screens/mastery_report_screen.dart').readAsStringSync();

      expect(mainSource, contains('with WidgetsBindingObserver'));
      expect(
        mainSource,
        contains('state == AppLifecycleState.resumed'),
      );
      expect(
        mainSource,
        contains('checkAndResetDailyCounters()'),
      );
      expect(reportSource, contains('with WidgetsBindingObserver'));
      expect(reportSource, contains('_refreshAfterResume()'));
      expect(reportSource, contains('if (mounted) await _loadData();'));
    });

    test('fixed chapter practice displays question progress', () {
      final source =
          File('lib/screens/practice_screen.dart').readAsStringSync();

      expect(source, contains("Key('practice_question_counter')"));
      expect(source, contains("'\${_currentIndex + 1}/\$_totalQuestions'"));
      expect(source, contains('widget.chapterId != null'));
    });

    test('daily plan separates new and review work and stays finite', () {
      final providerSource =
          File('lib/providers/user_state_provider.dart').readAsStringSync();
      final databaseSource =
          File('lib/services/database_service.dart').readAsStringSync();
      final homeSource =
          File('lib/screens/home_screen.dart').readAsStringSync();
      final practiceSource =
          File('lib/screens/practice_screen.dart').readAsStringSync();

      expect(providerSource, contains('hasAttemptedQuestion'));
      expect(providerSource, contains('currentDailyPlan'));
      expect(databaseSource, contains('getStudyPlanQuestions'));
      expect(databaseSource, contains('new_question_count'));
      expect(databaseSource, contains('review_question_count'));
      expect(homeSource, contains("Key('start_daily_plan_button')"));
      expect(homeSource, contains('dailyNewQuestionCount'));
      expect(homeSource, contains('dailyReviewQuestionCount'));
      expect(practiceSource, contains('_usesFixedQuestionList'));
    });

    test('daily review plan persists due dates and restores cloud timing', () {
      final providerSource =
          File('lib/providers/user_state_provider.dart').readAsStringSync();
      final databaseSource =
          File('lib/services/database_service.dart').readAsStringSync();
      final homeSource =
          File('lib/screens/home_screen.dart').readAsStringSync();

      expect(databaseSource, contains('version: 10'));
      expect(databaseSource, contains('review_stage INTEGER'));
      expect(databaseSource, contains('next_review_at INTEGER'));
      expect(databaseSource, contains('next_review_at <= ?'));
      expect(databaseSource, contains('getDueReviewCount'));
      expect(providerSource, contains('constrainToDueReviews'));
      expect(providerSource, contains('refreshDueReviewCount'));
      expect(homeSource, contains("Key('spaced_review_status')"));
      expect(databaseSource, contains('nextReviewDateForStage'));
    });

    test('free daily goals preview over quota but save through VIP unlock', () {
      final providerSource =
          File('lib/providers/user_state_provider.dart').readAsStringSync();
      final setupSource =
          File('lib/screens/daily_goal_setup_screen.dart').readAsStringSync();

      expect(providerSource, contains('effectiveDailyStudyGoal'));
      expect(
        providerSource,
        contains('min(normalized, AccessPolicy.freeDailyQuizLimit)'),
      );
      expect(setupSource, contains("'daily_goal_vip_unlock'"));
      expect(setupSource, contains('const SubscriptionPage()'));
      expect(setupSource, contains('if (_exceedsFreeQuota)'));
      expect(setupSource, contains("? _t('unlock_now')"));
    });

    test('practice summary clears Android navigation and mistakes stay gated',
        () {
      final practiceSource =
          File('lib/screens/practice_screen.dart').readAsStringSync();
      final mistakeSource =
          File('lib/screens/mistake_review_screen.dart').readAsStringSync();

      expect(
        practiceSource,
        contains('MediaQuery.viewPaddingOf(sheetContext).bottom'),
      );
      expect(mistakeSource, contains('visibleMistakePreviewCount'));
      expect(mistakeSource, contains('_buildUnlockBanner'));
      expect(mistakeSource, contains('_buildHiddenMistakesPreview'));
      expect(mistakeSource, isNot(contains('_buildLockedCard')));
    });
  });
}
