import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:crypto/crypto.dart';
import '../models/user_state.dart';
import '../config/app_strings.dart';
import '../config/app_config.dart';
import '../services/access_policy.dart';
import '../services/database_service.dart';
import '../services/firebase_status.dart';

/// 用户状态管理 Provider
/// 管理全局用户状态：语言、会员状态等
class UserStateProvider extends ChangeNotifier {
  static const String guestUserId = 'guest_user';
  static const String _vipInstallBindingKey = 'vip_install_binding';

  /// 加密存儲（Keychain / Keystore），用於保存敏感狀態（如 VIP、每日刷題數）
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  // 当前用户状态
  UserState _userState = const UserState(
    isVip: false,
    currentLanguage: 'zh',
  );

  // 已掌握的题目总数
  int _masteredCount = 0;

  // 至少做过一次的题目数量（覆盖率统计）
  int _attemptedCount = 0;

  // 错题数量（wrong_count > 0 的题目数）
  int _mistakeCount = 0;

  // 章节统计数据缓存（Map<章节ID, {total, practiced, mastered}>）
  Map<int, Map<String, int>>? _chaptersProgressCache;

  // 是否跳过已掌握题目
  bool _skipMastered = false;

  // VIP状态
  bool _isVip = false;

  // 今日已刷题数
  int _dailyQuizCount = 0;

  // 今日已查看解析次數
  int _dailyExplanationCount = 0;

  // 今日已解鎖解析的題目 ID 集合（避免同一題多次扣費）
  Set<String> _todayUnlockedExplanations = {};

  // 每日免費解析上限（非 VIP）
  static const int maxFreeExplanations = AccessPolicy.maxFreeExplanations;

  // 最后一次模拟考日期（格式：'YYYY-MM-DD'）
  String? _lastExamDate;

  // 今日是否已使用模拟考次数
  bool _isExamUsedToday = false;

  // 当前登录用户 UID（用于后续数据隔离）
  String? _userId;

  // Firebase 登录状态订阅
  StreamSubscription<User?>? _authSubscription;

  /// VIP 進度變更後防抖上傳雲端（換機不丟進度）
  Timer? _cloudSyncDebounce;

  /// 上次同步成功時間（HH:mm），未同步過為 '--'
  String _lastSyncTime = '--';
  String get lastSyncTime => _lastSyncTime;

  /// 是否正在執行雲端同步（設置頁「立即同步」按鈕用）
  bool _isSyncingToCloud = false;
  bool get isSyncingToCloud => _isSyncingToCloud;

  // 获取当前用户状态
  UserState get userState => _userState;

  // 获取当前语言
  String get currentLanguage => _userState.currentLanguage;

  String _localizedError(String key) =>
      AppStrings.getWithLanguage(_userState.currentLanguage, key);

  // 获取已掌握的题目总数
  int get masteredCount => _masteredCount;

  // 获取至少做过一次的题目数量（覆盖率统计）
  int get attemptedCount => _attemptedCount;

  // 获取错题数量
  int get mistakeCount => _mistakeCount;

  // 获取章节统计数据缓存
  Map<int, Map<String, int>>? get chaptersProgressCache =>
      _chaptersProgressCache;

  // 获取是否跳过已掌握题目
  bool get skipMastered => _skipMastered;

  // 获取VIP状态
  bool get isVip => _isVip;

  // 获取今日已刷题数
  int get dailyQuizCount => _dailyQuizCount;

  // 今日剩餘免費解析次數（若為 VIP 則視為無限）
  int get remainingExplanations => AccessPolicy.remainingExplanations(
        isVip: _isVip,
        dailyExplanationCount: _dailyExplanationCount,
      );

  // 获取最后一次模拟考日期
  String? get lastExamDate => _lastExamDate;

  // 获取今日是否已使用模拟考次数
  bool get isExamUsedToday => _isExamUsedToday;

  /// 今日是否已参加模考（与 isExamUsedToday 同义，用于权限 API）
  bool get hasUsedDailyExam => _isExamUsedToday;

  // 获取当前用户 UID（如果未登录则为 null）
  String? get userId => _userId;

  // 获取有效 userId（游客使用默认值）
  String get effectiveUserId => _userId ?? guestUserId;

  /// 考试通过率预测（0～1），-1 表示数据不足冷启动
  static const int totalQuestionsForPrediction = 7139;
  double _passRatePrediction = -1;
  double get passRatePrediction => _passRatePrediction;

  // 较昨天提升（今日与昨日 passRate 差值，0～1 或负值），无数据时为 null
  double? _mockExamImprovement;
  double? get mockExamImprovement => _mockExamImprovement;

  /// 参与当前预测的模拟考次数（用于 UI 显示「预测精度：低」）
  int _mockExamCountForPrediction = 0;
  bool get isPassRatePredictionLowAccuracy => _mockExamCountForPrediction < 3;

  // ─── VIP 权限判定（SubscriptionPage 激活后统一解除下列限制）────────────────
  // 1. 练习：dailyQuizCount 不再拦截  2. 模考：每日 1 次解除
  // 3. 错题/复盘：shouldLockMistake / shouldLockReview 为 false，无遮罩
  // 4. 解析：canViewExplanation 恒 true，无每日 10 次限制

  /// 是否可以继续练习：会员不限次，非会员每日 30 题内
  bool canPractice() => AccessPolicy.canPractice(
        isVip: _isVip,
        dailyQuizCount: _dailyQuizCount,
      );

  /// 是否可以开始模拟考试：会员不限次，非会员每日 1 次
  bool canStartExam() => AccessPolicy.canStartExam(
        isVip: _isVip,
        isExamUsedToday: _isExamUsedToday,
      );

  /// 是否可以查看解析：會員不限次；非會員若當天已解鎖過該題或仍有剩餘次數也允許
  bool canViewExplanation(String questionId) => AccessPolicy.canViewExplanation(
        isVip: _isVip,
        isUnlockedToday: _todayUnlockedExplanations.contains(questionId),
        dailyExplanationCount: _dailyExplanationCount,
      );

  /// 當天該題是否已解鎖解析（避免重複扣費）
  bool isExplanationUnlockedToday(String questionId) =>
      _todayUnlockedExplanations.contains(questionId);

  /// 查看试卷（考试回顾）是否锁定：非会员仅可查看前 10 条，index 从 0 起
  bool shouldLockReview(int index) => AccessPolicy.shouldLockPreviewItem(
        isVip: _isVip,
        index: index,
      );

  /// 错题回顾是否锁定：非会员仅可查看前 10 条，index 从 0 起
  bool shouldLockMistake(int index) => AccessPolicy.shouldLockPreviewItem(
        isVip: _isVip,
        index: index,
      );

  /// 熟练度 S：averageWrong<=3 则 S=1，否则 S=(30-averageWrong)/30，结果限制在 [0, 1]
  static double _proficiencyFromAverageWrong(double averageWrong) {
    if (averageWrong <= 3) return 1.0;
    if (averageWrong >= 30) return 0.0;
    return ((30 - averageWrong) / 30).clamp(0.0, 1.0);
  }

  /// 加载通过率预测：C=覆盖率，S=熟练度，passRate=(C*0.6+S*0.4)；冷启动返回 -1
  Future<void> loadPassRatePrediction() async {
    final uid = effectiveUserId;
    final attempted = _attemptedCount;
    final history = await DatabaseService.getMockExamHistory(userId: uid);
    final recent5 = history.take(5).toList();
    final mockCount = recent5.length;

    if (attempted < 50 && mockCount == 0) {
      _mockExamCountForPrediction = 0;
      if (_passRatePrediction != -1) {
        _passRatePrediction = -1;
        notifyListeners();
      }
      return;
    }

    double averageWrong = 0.0;
    if (recent5.isNotEmpty) {
      double sum = 0;
      for (final e in recent5) {
        sum += (e['wrong'] as num?)?.toDouble() ?? 0;
      }
      averageWrong = sum / recent5.length;
    }

    _mockExamCountForPrediction = mockCount;
    final C = (attempted / totalQuestionsForPrediction).clamp(0.0, 1.0);
    final S = _proficiencyFromAverageWrong(averageWrong).clamp(0.0, 1.0);
    final passRate = (C * 0.6 + S * 0.4).clamp(0.0, 1.0);
    if (_passRatePrediction != passRate) {
      _passRatePrediction = passRate;
      notifyListeners();
    }
  }

  /// 加载「较昨天提升」：今日与昨日 passRate 差值（同公式 C*0.6+S*0.4）
  /// 昨日 passRate 使用截至昨天 23:59 的做题数 C_yesterday，今日用当前 C，保证提升反映「多刷题+考更高」两方面
  Future<void> loadMockExamImprovement() async {
    final uid = effectiveUserId;
    final attemptedToday = _attemptedCount;
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final yesterdayEndSec = (todayStart.millisecondsSinceEpoch ~/ 1000) - 1;

    final attemptedYesterday = await DatabaseService.getTotalAttemptedCountAsOf(
      userId: uid,
      asOfTimestampSec: yesterdayEndSec,
    );
    final result =
        await DatabaseService.getTodayYesterdayAverageWrong(userId: uid);
    final avgWrongToday = result['today'];
    final avgWrongYesterday = result['yesterday'];

    if (avgWrongToday == null || avgWrongYesterday == null) {
      if (_mockExamImprovement != null) {
        _mockExamImprovement = null;
        notifyListeners();
      }
      return;
    }

    final cToday =
        (attemptedToday / totalQuestionsForPrediction).clamp(0.0, 1.0);
    final cYesterday =
        (attemptedYesterday / totalQuestionsForPrediction).clamp(0.0, 1.0);
    final sToday = _proficiencyFromAverageWrong(avgWrongToday);
    final sYesterday = _proficiencyFromAverageWrong(avgWrongYesterday);
    final passRateToday = (cToday * 0.6 + sToday * 0.4).clamp(0.0, 1.0);
    final passRateYesterday =
        (cYesterday * 0.6 + sYesterday * 0.4).clamp(0.0, 1.0);
    final improvement = passRateToday - passRateYesterday;
    if (_mockExamImprovement != improvement) {
      _mockExamImprovement = improvement;
      notifyListeners();
    }
  }

  /// 构造函数：从持久化存储加载初始状态
  UserStateProvider() {
    _loadUserState();
    _initAuthListener();
  }

  /// 监听 Firebase 登录状态，捕获 UID 并初始化用户进度
  void _initAuthListener() {
    final auth = FirebaseStatus.auth;
    if (auth == null) return;

    try {
      _authSubscription = auth.authStateChanges().listen((user) {
        final newUid = user?.uid;
        if (newUid != _userId) {
          _userId = newUid;
          notifyListeners();

          // 登入成功：同步 VIP 狀態 → 若為 VIP 則從 Firestore 拉取進度並合併到本地（新設備登入不丟進度）
          if (_userId != null) {
            updateMasteryStats();
            if (user != null) {
              _syncVipFromFirebase(user).then((_) {
                if (_isVip) _restoreProgressFromCloud();
              });
            }
            // 登入後從雲端恢復當日已用每日配額（綁定 UID，換機/重裝不丟每日限制）
            _syncDailyUsageFromCloud();
          }
        }
      });
    } catch (_) {
      // Firebase 不可用時保留離線題庫與本地進度功能。
    }
  }

  /// 从 Firebase Custom Claims 同步 VIP 状态到本地
  Future<void> _syncVipFromFirebase(User user) async {
    try {
      final tokenResult = await user.getIdTokenResult(true);
      final claims = tokenResult.claims ?? {};
      var vip = _extractVipFromClaims(claims);
      vip ??= await DatabaseService.checkUserVipInFirestore(user.uid);

      if (vip != null && vip != _isVip) {
        await setIsVip(vip);
      }
    } catch (_) {
      // 無法讀取 claims 時保留本地 VIP 狀態，避免登入流程被中斷。
    }
  }

  /// 从 Firebase Custom Claims 中提取 VIP 状态
  /// 支持多种可能的键名：vip, isVip, is_vip, isPremium, premium
  bool? _extractVipFromClaims(Map<String, dynamic> claims) {
    const keys = ['vip', 'isVip', 'is_vip', 'isPremium', 'premium'];
    for (final key in keys) {
      if (!claims.containsKey(key)) continue;
      final value = claims[key];
      if (value is bool) return value;
      if (value is int) return value != 0;
      if (value is String) {
        final normalized = value.toLowerCase();
        if (normalized == 'true' || normalized == '1') return true;
        if (normalized == 'false' || normalized == '0') return false;
      }
    }
    return null;
  }

  Future<bool> hasGuestProgress() async {
    return DatabaseService.hasUserProgress(userId: guestUserId);
  }

  Future<void> mergeGuestProgressToCurrentUser() async {
    final uid = FirebaseStatus.currentUserUid;
    if (uid == null) return;

    _userId = uid;
    await DatabaseService.mergeGuestDataToAccount(uid);
    await updateMasteryStats();
    await refreshMistakeCount();
    await refreshChaptersProgress();
    await loadPassRatePrediction();
    await loadMockExamImprovement();
    if (_isVip) _scheduleCloudSync();
  }

  /// 從 Firestore 讀取當日每日限額使用情況並與本地合併（取較大值），確保卸載重裝後仍能續用當日配額
  Future<void> _syncDailyUsageFromCloud() async {
    final uid = _userId;
    if (uid == null) return;

    try {
      final today = _getCurrentDateString();
      final firestore = FirebaseStatus.firestore;
      if (firestore == null) return;

      final doc = await firestore
          .collection('users')
          .doc(uid)
          .collection('daily_usage')
          .doc(today)
          .get();

      if (!doc.exists) return;
      final data = doc.data();
      final cloudCount = (data?['quiz_count'] as int?) ?? 0;
      final cloudExplanationCount = (data?['explanation_count'] as int?) ?? 0;
      final cloudExamUsed = data?['exam_used'] == true;

      // 與本地合併：保留較大的那個，避免本地已比雲端多時被覆蓋
      final newCount =
          cloudCount > _dailyQuizCount ? cloudCount : _dailyQuizCount;
      final newExplanationCount = cloudExplanationCount > _dailyExplanationCount
          ? cloudExplanationCount.clamp(0, maxFreeExplanations)
          : _dailyExplanationCount;
      final newExamUsed = _isExamUsedToday || cloudExamUsed;
      if (newCount == _dailyQuizCount &&
          newExplanationCount == _dailyExplanationCount &&
          newExamUsed == _isExamUsedToday) {
        return;
      }

      _dailyQuizCount = newCount;
      _dailyExplanationCount = newExplanationCount;
      _isExamUsedToday = newExamUsed;
      if (newExamUsed) {
        _lastExamDate = today;
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('daily_quiz_count', _dailyQuizCount);
      await prefs.setInt('daily_explanation_count', _dailyExplanationCount);
      await prefs.setBool('is_exam_used_today', _isExamUsedToday);
      if (_isExamUsedToday) {
        await prefs.setString('last_exam_date', today);
      }
      await prefs.setString('last_access_date', today);
      await prefs.setString('last_quiz_date', today);
      await _secureStorage.write(
        key: 'daily_quiz_count',
        value: _dailyQuizCount.toString(),
      );

      notifyListeners();
    } catch (_) {
      // 語言偏好保存失敗不影響當前會話中的語言切換。
      if (kDebugMode) {}
    }
  }

  void _writeDailyUsageToCloud(Map<String, Object> data) {
    final uid = _userId;
    final firestore = FirebaseStatus.firestore;
    if (uid == null || firestore == null) return;

    final today = _getCurrentDateString();
    firestore
        .collection('users')
        .doc(uid)
        .collection('daily_usage')
        .doc(today)
        .set(
      {
        ...data,
        'updated_at': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    ).catchError((_) {
      if (kDebugMode) {}
    });
  }

  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)])
        .join();
  }

  String _sha256OfString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Google 登录
  Future<UserCredential> signInWithGoogle() async {
    final auth = FirebaseStatus.auth;
    if (auth == null) {
      throw Exception(_localizedError('auth_error_firebase_unavailable'));
    }

    final googleSignIn = GoogleSignIn();
    final googleUser = await googleSignIn.signIn();
    if (googleUser == null) {
      throw Exception(_localizedError('auth_error_google_cancelled'));
    }

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    return auth.signInWithCredential(credential);
  }

  /// Apple 登录
  Future<UserCredential> signInWithApple() async {
    final auth = FirebaseStatus.auth;
    if (auth == null) {
      throw Exception(_localizedError('auth_error_firebase_unavailable'));
    }

    final rawNonce = _generateNonce();
    final nonce = _sha256OfString(rawNonce);

    final appleCredential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: nonce,
    );

    final idToken = appleCredential.identityToken;
    if (idToken == null) {
      throw Exception(_localizedError('auth_error_apple_identity_missing'));
    }

    final oauthCredential = OAuthProvider('apple.com').credential(
      idToken: idToken,
      rawNonce: rawNonce,
    );

    return auth.signInWithCredential(oauthCredential);
  }

  /// 邮箱登录
  /// [email] 邮箱地址
  /// [password] 密码
  Future<UserCredential> signInWithEmail(String email, String password) async {
    final auth = FirebaseStatus.auth;
    if (auth == null) {
      throw Exception(_localizedError('auth_error_firebase_unavailable'));
    }

    try {
      final credential = await auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      return credential;
    } on FirebaseAuthException catch (e) {
      // 转换 Firebase 错误为更友好的中文提示
      String errorMessage;
      switch (e.code) {
        case 'user-not-found':
          errorMessage = _localizedError('auth_error_user_not_found');
          break;
        case 'wrong-password':
          errorMessage = _localizedError('auth_error_wrong_password');
          break;
        case 'invalid-email':
          errorMessage = _localizedError('auth_error_invalid_email');
          break;
        case 'user-disabled':
          errorMessage = _localizedError('auth_error_user_disabled');
          break;
        case 'too-many-requests':
          errorMessage = _localizedError('auth_error_too_many_requests');
          break;
        case 'network-request-failed':
          errorMessage = _localizedError('auth_error_network_failed');
          break;
        default:
          errorMessage =
              '${_localizedError('auth_error_login_failed_prefix')}${e.message ?? e.code}';
      }
      throw Exception(errorMessage);
    } catch (e) {
      // 跳過已掌握偏好保存失敗不影響當前會話。
      throw Exception(
          '${_localizedError('auth_error_login_failed_prefix')}${e.toString()}');
    }
  }

  /// 邮箱注册
  /// [email] 邮箱地址
  /// [password] 密码
  Future<UserCredential> signUpWithEmail(String email, String password) async {
    // 验证密码长度
    if (password.length < 6) {
      throw Exception(_localizedError('auth_error_password_too_short'));
    }

    final auth = FirebaseStatus.auth;
    if (auth == null) {
      throw Exception(_localizedError('auth_error_register_unavailable'));
    }

    try {
      final credential = await auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      return credential;
    } on FirebaseAuthException catch (e) {
      // 转换 Firebase 错误为更友好的中文提示
      String errorMessage;
      switch (e.code) {
        case 'email-already-in-use':
          errorMessage = _localizedError('auth_error_email_in_use');
          break;
        case 'invalid-email':
          errorMessage = _localizedError('auth_error_invalid_email');
          break;
        case 'weak-password':
          errorMessage = _localizedError('auth_error_weak_password');
          break;
        case 'operation-not-allowed':
          errorMessage = _localizedError('auth_error_email_register_disabled');
          break;
        case 'network-request-failed':
          errorMessage = _localizedError('auth_error_network_failed');
          break;
        default:
          errorMessage =
              '${_localizedError('auth_error_register_failed_prefix')}${e.message ?? e.code}';
      }
      throw Exception(errorMessage);
    } catch (e) {
      // 本地偏好保存失敗時仍保留內存中的最新狀態。
      throw Exception(
          '${_localizedError('auth_error_register_failed_prefix')}${e.toString()}');
    }
  }

  /// 获取当前日期字符串（格式：'YYYY-MM-DD'）
  String _getCurrentDateString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  @visibleForTesting
  static bool resolveVipFromLocalCache({
    required bool? secureVip,
    required bool? sharedVip,
    required bool? legacyPremium,
    required bool hasVipInstallBinding,
  }) {
    final trustedSecureVip = hasVipInstallBinding ? secureVip : null;
    return trustedSecureVip ?? sharedVip ?? legacyPremium ?? false;
  }

  /// 从本地存储加载用户状态
  Future<void> _loadUserState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // 優先從加密存儲讀取敏感狀態，若不存在則回退到 SharedPreferences（並做一次遷移）
      String? secureVipRaw;
      String? secureDailyQuizRaw;
      try {
        secureVipRaw = await _secureStorage.read(key: 'is_vip');
      } catch (_) {}
      try {
        secureDailyQuizRaw = await _secureStorage.read(key: 'daily_quiz_count');
      } catch (_) {}

      // 初始化时先检查是否需要重置每日计数器；失败不应影响语言偏好加载。
      try {
        await checkAndResetDailyCounters(prefs: prefs);
      } catch (_) {}

      // 从 SharedPreferences 加载语言（兼容舊版本的 it 配置）
      final savedLanguage = prefs.getString('current_language');

      // 從 SharedPreferences 加載 VIP 狀態（兼容舊的 is_premium），僅作為遷移來源。
      // iOS Keychain 會跨卸載保留，secureVip 只有在本次安裝也有綁定標記時才可信。
      final vipValue = prefs.getBool('is_vip');
      final legacyPremium = prefs.getBool('is_premium');
      final hasVipInstallBinding = prefs.getBool(_vipInstallBindingKey) == true;
      bool? secureVip;
      if (secureVipRaw != null) {
        final v = secureVipRaw.toLowerCase();
        if (v == '1' || v == 'true') {
          secureVip = true;
        } else if (v == '0' || v == 'false') {
          secureVip = false;
        }
      }
      final effectiveVip = resolveVipFromLocalCache(
        secureVip: secureVip,
        sharedVip: vipValue,
        legacyPremium: legacyPremium,
        hasVipInstallBinding: hasVipInstallBinding,
      );

      // 从 SharedPreferences 加载跳过已掌握题目设置
      final skipMastered = prefs.getBool('skip_mastered') ?? false;

      // 从 SharedPreferences 加载最后一次模拟考日期
      final lastExamDate = prefs.getString('last_exam_date');

      // 從加密存儲 / SharedPreferences 加載日消耗記錄（每日刷題數）
      int dailyQuizCount;
      if (secureDailyQuizRaw != null) {
        dailyQuizCount = int.tryParse(secureDailyQuizRaw) ?? 0;
      } else {
        dailyQuizCount = prefs.getInt('daily_quiz_count') ?? 0;
      }
      final isExamUsedToday = prefs.getBool('is_exam_used_today') ?? false;
      final dailyExplanationCount =
          prefs.getInt('daily_explanation_count') ?? 0;
      final unlockedExplanations =
          prefs.getStringList('today_unlocked_explanations') ??
              const <String>[];

      // 如果保存了语言，使用保存的语言；否则使用默认值
      // 舊用戶若曾選擇過 'it'，現在已不再提供作為 UI 語言，統一回退為中文
      String currentLang;
      if (savedLanguage == null) {
        currentLang = 'zh';
      } else if (savedLanguage == 'it') {
        // 將舊的義大利語 UI 配置回退為中文（可按需改為 'en'）
        currentLang = 'zh';
        await prefs.setString('current_language', currentLang);
      } else if (!UserState.supportedLanguages.contains(savedLanguage)) {
        // 任意未知語言代碼一律回退為中文
        currentLang = 'zh';
        await prefs.setString('current_language', currentLang);
      } else {
        currentLang = savedLanguage;
      }

      // 設置 VIP 狀態（唯一真理來源）
      _isVip = effectiveVip;

      _userState = _userState.copyWith(
        currentLanguage: currentLang,
        isVip: _isVip,
      );

      // 同步更新 AppStrings（向后兼容）
      AppStrings.setLanguage(currentLang);

      // 先落地会直接影响 UI 的本地状态；统计刷新即使失败也不应让语言回退。
      _skipMastered = skipMastered;
      _dailyQuizCount = dailyQuizCount;
      _lastExamDate = lastExamDate;
      _isExamUsedToday = isExamUsedToday;
      _dailyExplanationCount = dailyExplanationCount;
      _todayUnlockedExplanations = unlockedExplanations.toSet();
      notifyListeners();

      // 兼容迁移：若只有旧 key，写回新 key 并删除旧 key
      if (vipValue == null && legacyPremium != null) {
        await prefs.setBool('is_vip', legacyPremium);
        await prefs.remove('is_premium');
      }

      // 初始化统计数据；失败时保留已加载的语言和本地状态。
      try {
        await refreshMasteryStats();
      } catch (_) {}
      try {
        await refreshMistakeCount();
      } catch (_) {}
      try {
        await refreshChaptersProgress();
      } catch (_) {}

      // 若是從 SharedPreferences 遷移到加密存儲，寫回一份加密值
      if (secureVipRaw == null && (vipValue != null || legacyPremium != null)) {
        try {
          await _secureStorage.write(
            key: 'is_vip',
            value: effectiveVip ? '1' : '0',
          );
        } catch (_) {}
      }
      if (vipValue != null || legacyPremium != null || hasVipInstallBinding) {
        await prefs.setBool(_vipInstallBindingKey, true);
      }
      if (secureDailyQuizRaw == null &&
          (prefs.containsKey('daily_quiz_count'))) {
        try {
          await _secureStorage.write(
            key: 'daily_quiz_count',
            value: dailyQuizCount.toString(),
          );
        } catch (_) {}
      }
    } catch (_) {
      // 語言偏好保存失敗不影響當前會話中的語言切換。
      // 如果加载失败，使用默认值
      _isVip = false;
      _userState = _userState.copyWith(
        currentLanguage: 'zh',
        isVip: false,
      );
      _masteredCount = 0;
      _attemptedCount = 0;
      _mistakeCount = 0;
      _skipMastered = false;
      _dailyQuizCount = 0;
      _lastExamDate = null;
      _isExamUsedToday = false;
    }
  }

  /// 每日重置计数器（比较 lastAccessDate）
  Future<void> checkAndResetDailyCounters({SharedPreferences? prefs}) async {
    final sharedPrefs = prefs ?? await SharedPreferences.getInstance();
    final currentDate = _getCurrentDateString();

    // 兼容旧字段：如果没有 last_access_date，则尝试读取 last_quiz_date
    final lastAccessDate = sharedPrefs.getString('last_access_date') ??
        sharedPrefs.getString('last_quiz_date');

    if (lastAccessDate != currentDate) {
      _dailyQuizCount = 0;
      _dailyExplanationCount = 0;
      _todayUnlockedExplanations.clear();
      _isExamUsedToday = false;
      _lastExamDate = null;

      await sharedPrefs.setInt('daily_quiz_count', 0);
      await sharedPrefs.setInt('daily_explanation_count', 0);
      await sharedPrefs.setStringList('today_unlocked_explanations', const []);
      await sharedPrefs.setString('last_access_date', currentDate);
      await sharedPrefs.setString('last_quiz_date', currentDate);
      await sharedPrefs.remove('last_exam_date');

      // 同步重置加密存儲中的每日刷題數
      try {
        await _secureStorage.write(key: 'daily_quiz_count', value: '0');
      } catch (_) {}

      notifyListeners();
    }
  }

  /// 检查是否已经选择过语言（是否首次启动）
  static Future<bool> hasSelectedLanguage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.containsKey('current_language');
    } catch (_) {
      // 跳過已掌握偏好保存失敗不影響當前會話。
      return false;
    }
  }

  /// 切换语言
  /// [language] 新的语言代码
  Future<void> changeLanguage(String language) async {
    if (!UserState.supportedLanguages.contains(language)) {
      return;
    }

    // 更新用户状态
    _userState = _userState.copyWith(currentLanguage: language);

    // 同步更新 AppStrings（保持兼容性）
    AppStrings.setLanguage(language);

    // 保存到本地存储
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('current_language', language);
    } catch (_) {
      // 本地偏好保存失敗時仍保留內存中的最新狀態。
    }

    // 通知所有监听者（触发 UI 更新）
    notifyListeners();
  }

  /// 设置是否跳过已掌握题目
  /// [skipMastered] 是否跳过已掌握题目
  Future<void> setSkipMastered(bool skipMastered) async {
    _skipMastered = skipMastered;

    // 保存到本地存储
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('skip_mastered', skipMastered);
    } catch (_) {
      // 跳過已掌握偏好保存失敗不影響當前會話。
    }

    // 通知所有监听者
    notifyListeners();
  }

  /// 检查章节是否被锁定（需要付费）
  /// [chapterNumber] 章节编号（从1开始）
  /// 返回 true 表示该章节被锁定，需要付费才能访问
  bool isChapterLocked(int chapterNumber) {
    // 如果章节数 > 免费限制 且 用户不是 VIP 会员，则锁定
    return AppConfig.isChapterLocked(chapterNumber, isVip: _isVip);
  }

  /// 刷新掌握度统计（从数据库查询已掌握的总题数和已尝试的总题数）
  /// 调用此方法会更新 _masteredCount 和 _attemptedCount 并触发 notifyListeners()
  Future<void> refreshMasteryStats() async {
    try {
      // 同时查询 masteredCount 和 attemptedCount
      _masteredCount =
          await DatabaseService.getMasteredCount(userId: effectiveUserId);
      _attemptedCount =
          await DatabaseService.getTotalAttemptedCount(userId: effectiveUserId);
      notifyListeners();
    } catch (_) {
      // 本地偏好保存失敗時仍保留內存中的最新狀態。
      // 如果查询失败，保持当前值不变
    }
  }

  /// 刷新錯題數量統計（從數據庫查詢 wrong_count > 0 的題目數）
  /// 調用此方法會更新 _mistakeCount 並觸發 notifyListeners()
  Future<void> refreshMistakeCount() async {
    try {
      final wrongQuestions = await DatabaseService.getWrongQuestions(
        effectiveUserId,
        lang: 'it',
      );
      _mistakeCount = wrongQuestions.length;
      notifyListeners();
    } catch (_) {
      // 模擬考使用狀態保存失敗不阻塞當前會話。
      // 如果查詢失敗，保持當前值不變
    }
  }

  /// 刷新章节统计数据（使用 Future.wait 并行处理，避免滑动掉帧）
  /// 数据缓存在 Provider 中，多个页面可以共享
  Future<void> refreshChaptersProgress() async {
    try {
      // 获取所有章节ID（1-25）
      final allChapterIds = List.generate(25, (index) => index + 1);

      // 使用 Future.wait 并行处理所有章节统计
      final progress = await DatabaseService.getChaptersProgress(
        allChapterIds,
        userId: effectiveUserId,
      );

      _chaptersProgressCache = progress;
      notifyListeners();
    } catch (e) {
      // 如果查询失败，保持当前缓存不变
    }
  }

  /// 更新掌握度统计（从数据库查询已掌握的总题数和已尝试的总题数）
  /// 调用此方法会重新查询数据库中 is_mastered = 1 的总数和 total_attempts > 0 的总数
  /// 并更新 masteredCount 和 attemptedCount 变量
  /// 在方法末尾会调用 notifyListeners() 通知所有监听者
  Future<void> updateMasteryStats() async {
    try {
      // 同时查询 masteredCount 和 attemptedCount
      _masteredCount =
          await DatabaseService.getMasteredCount(userId: effectiveUserId);
      _attemptedCount =
          await DatabaseService.getTotalAttemptedCount(userId: effectiveUserId);
      notifyListeners();
    } catch (e) {
      // 如果查询失败，保持当前值不变
    }
  }

  /// 獲取全局掌握百分比
  /// 返回當前用戶對整個題庫的總掌握百分比（0.0 - 1.0）
  Future<double> getTotalMasteryPercentage() async {
    return await DatabaseService.getTotalMasteryPercentage(
        userId: effectiveUserId);
  }

  /// 更新用户状态（批量更新）
  Future<void> updateUserState({
    bool? isVip,
    String? currentLanguage,
  }) async {
    if (isVip != null) {
      _isVip = isVip;
    }

    _userState = _userState.copyWith(
      isVip: isVip ?? _userState.isVip,
      currentLanguage: currentLanguage,
    );

    // 如果语言改变，同步更新 AppStrings
    if (currentLanguage != null) {
      AppStrings.setLanguage(currentLanguage);
    }

    // 保存到本地存储（非敏感用 SharedPreferences，VIP 使用加密存储）
    try {
      final prefs = await SharedPreferences.getInstance();
      if (currentLanguage != null) {
        await prefs.setString('current_language', currentLanguage);
      }
      if (isVip != null) {
        await _secureStorage.write(
          key: 'is_vip',
          value: isVip ? '1' : '0',
        );
        await prefs.remove('is_premium'); // 清理旧 key
      }
    } catch (_) {
      // 本地偏好保存失敗時仍保留內存中的最新狀態。
    }

    notifyListeners();
  }

  /// 重置所有用户进度
  /// 调用数据库服务重置进度，并更新内存中的掌握度统计
  Future<bool> handleResetProgress() async {
    try {
      // 调用数据库服务重置所有用户进度
      final success =
          await DatabaseService.resetAllUserProgress(userId: effectiveUserId);

      if (success) {
        // 如果為已登入的 VIP，用戶，清空雲端進度，避免重置後又被恢復
        if (_isVip && _userId != null) {
          await DatabaseService.clearCloudProgress(userId: _userId!);
        }

        // 重置內存中的統計與每日刷題數
        _masteredCount = 0;
        _attemptedCount = 0;
        _dailyQuizCount = 0;
        _mistakeCount = 0;

        // 更新本地每日計數持久化（SharedPreferences + secure storage）
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt('daily_quiz_count', 0);
          await prefs.setString('last_access_date', _getCurrentDateString());
          await prefs.setString('last_quiz_date', _getCurrentDateString());
          await _secureStorage.write(key: 'daily_quiz_count', value: '0');
        } catch (_) {
          // 重置後的持久化狀態可在下次每日檢查時重新校正。
        }

        // 通知首頁等 UI 立刻重繪
        notifyListeners();

        // 重新查询数据库中的掌握度统计（应该为 0）
        await updateMasteryStats();

        return true;
      } else {
        return false;
      }
    } catch (_) {
      // VIP 狀態保存失敗時仍保留內存狀態，避免購買完成後 UI 不更新。
      return false;
    }
  }

  /// 设置VIP状态（唯一真理来源）
  /// [isVip] 是否为VIP
  Future<void> setIsVip(bool isVip) async {
    _isVip = isVip;
    _userState = _userState.copyWith(isVip: isVip);

    // 保存到本地存儲（VIP 狀態寫入加密存儲，並清理舊 key）
    try {
      final prefs = await SharedPreferences.getInstance();
      await _secureStorage.write(
        key: 'is_vip',
        value: isVip ? '1' : '0',
      );
      await prefs.setBool(_vipInstallBindingKey, true);
      await prefs.remove('is_premium'); // 清理旧 key
    } catch (_) {
      // VIP 狀態保存失敗時仍保留內存狀態，避免購買完成後 UI 不更新。
    }

    // 通知所有监听者
    notifyListeners();
  }

  /// 增加今日已刷题数
  /// 返回更新后的刷题数
  Future<int> incrementDailyQuizCount() async {
    // 确保每日计数器已按日期重置
    await checkAndResetDailyCounters();

    final currentDate = _getCurrentDateString();

    try {
      final prefs = await SharedPreferences.getInstance();
      _dailyQuizCount = (_dailyQuizCount) + 1;
      await prefs.setInt('daily_quiz_count', _dailyQuizCount);
      await prefs.setString('last_access_date', currentDate);
      await prefs.setString('last_quiz_date', currentDate);
      await _secureStorage.write(
        key: 'daily_quiz_count',
        value: _dailyQuizCount.toString(),
      );

      // 綁定 UID 的雲端計數：若已登入，將今日使用量寫入 Firestore（非阻塞，失敗忽略）
      _writeDailyUsageToCloud({'quiz_count': FieldValue.increment(1)});

      // 通知所有监听者
      notifyListeners();

      return _dailyQuizCount;
    } catch (_) {
      // 模擬考使用狀態保存失敗不阻塞當前會話。
      return _dailyQuizCount;
    }
  }

  /// 增加今日已查看解析次數（僅對非 VIP 生效）
  Future<int> incrementExplanationCount(String questionId) async {
    // 確保每日計數器已按日期重置
    await checkAndResetDailyCounters();

    if (_isVip) {
      return maxFreeExplanations;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      // 如果當天已經對該題解鎖過解析，不再重複扣費
      if (_todayUnlockedExplanations.contains(questionId)) {
        return _dailyExplanationCount;
      }
      if (_dailyExplanationCount >= maxFreeExplanations) {
        return _dailyExplanationCount;
      }

      _dailyExplanationCount =
          (_dailyExplanationCount + 1).clamp(0, maxFreeExplanations);
      _todayUnlockedExplanations.add(questionId);

      await prefs.setInt('daily_explanation_count', _dailyExplanationCount);
      await prefs.setStringList(
        'today_unlocked_explanations',
        _todayUnlockedExplanations.toList(),
      );
      _writeDailyUsageToCloud({
        'explanation_count': FieldValue.increment(1),
      });
      return _dailyExplanationCount;
    } catch (_) {
      // 模擬考日期保存失敗不阻塞本次權限狀態更新。
      return _dailyExplanationCount;
    }
  }

  /// 记录最后一次模拟考日期
  /// [date] 日期字符串（格式：'YYYY-MM-DD'），如果为null则使用当前日期
  Future<void> setLastExamDate([String? date]) async {
    final examDate = date ?? _getCurrentDateString();
    _lastExamDate = examDate;
    _isExamUsedToday = true;

    // 保存到本地存储
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_exam_date', examDate);
      await prefs.setBool('is_exam_used_today', true);
      await prefs.setString('last_access_date', examDate);
      _writeDailyUsageToCloud({'exam_used': true});
    } catch (_) {
      // 模擬考使用狀態保存失敗不阻塞當前會話。
    }

    // 通知所有监听者
    notifyListeners();
  }

  /// 标记今日是否已使用模拟考次数
  Future<void> setExamUsedToday([bool used = true]) async {
    final currentDate = _getCurrentDateString();
    _isExamUsedToday = used;
    if (used) {
      _lastExamDate = currentDate;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_exam_used_today', used);
      await prefs.setString('last_access_date', currentDate);
      if (used) {
        await prefs.setString('last_exam_date', currentDate);
        _writeDailyUsageToCloud({'exam_used': true});
      }
    } catch (_) {
      // 模擬考使用狀態保存失敗不阻塞當前會話。
    }

    notifyListeners();
  }

  /// 統一更新題目進度（含本地計數器）
  /// VIP 且已登入時會防抖上傳進度到雲端，換機可恢復。
  Future<bool> updateQuestionProgress(String questionId, bool isCorrect) async {
    final newlyMastered = await DatabaseService.updateQuestionProgress(
      questionId,
      isCorrect,
      userId: effectiveUserId,
    );
    await incrementDailyQuizCount();
    await refreshMistakeCount();
    await refreshChaptersProgress();
    if (_isVip && _userId != null) _scheduleCloudSync();
    return newlyMastered;
  }

  void _scheduleCloudSync() {
    _cloudSyncDebounce?.cancel();
    _cloudSyncDebounce = Timer(const Duration(seconds: 3), () async {
      _cloudSyncDebounce = null;
      if (!_isVip || _userId == null) return;
      try {
        await syncProgressToCloud();
      } catch (_) {}
    });
  }

  /// 從 Firestore 拉取進度並合併到本地 SQLite（僅 VIP、新設備登入後自動觸發；非 VIP 不執行）
  Future<void> _restoreProgressFromCloud() async {
    if (!_isVip || _userId == null) return;

    try {
      await DatabaseService.restoreProgressFromCloud(userId: _userId!);
      // 恢復後刷新統計
      await updateMasteryStats();
      await refreshMistakeCount();
    } catch (e) {
      // 不拋出異常，避免影響登入流程
    }
  }

  /// 同步用戶進度到雲端（僅 VIP 用戶，否則拋錯）。成功時更新 lastSyncTime。
  Future<SyncResult> syncProgressToCloud() async {
    if (!_isVip || _userId == null) {
      throw Exception(_localizedError('sync_vip_required'));
    }

    _isSyncingToCloud = true;
    notifyListeners();
    try {
      final result =
          await DatabaseService.syncProgressToCloud(userId: _userId!);
      if (result.success) {
        final now = DateTime.now();
        _lastSyncTime =
            '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      }
      return result;
    } catch (_) {
      rethrow;
    } finally {
      _isSyncingToCloud = false;
      notifyListeners();
    }
  }

  /// 若為 VIP 且已登入則將 user_progress 變動上傳至 Firestore；非 VIP 不執行、不拋錯。
  /// 用於完成一組練習或模擬考後自動同步，安全可隨意調用。
  Future<void> syncProgressToCloudIfVip() async {
    if (!_isVip || _userId == null) return;
    try {
      await syncProgressToCloud();
    } catch (_) {}
  }

  /// 清空当前内存中的学习统计（用于注销）
  void clearProgressStats() {
    _masteredCount = 0;
    _attemptedCount = 0;
    _mistakeCount = 0;
    notifyListeners();
  }

  /// 商店訂閱交易驗證成功後激活本機 VIP。
  /// 正式上架前應由可信後端驗證交易，並下發雲端 VIP 權益。
  Future<void> activateVipFromVerifiedPurchase() async {
    await setIsVip(true);
    if (_userId != null) {
      try {
        await syncProgressToCloud();
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _cloudSyncDebounce?.cancel();
    super.dispose();
  }
}
