import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/question.dart';
import 'firebase_status.dart';

class WrongQuestionEntry {
  final Question question;
  final int wrongCount;

  const WrongQuestionEntry({
    required this.question,
    required this.wrongCount,
  });
}

/// 雲端同步結果：success 表示是否成功，isTimeout 表示是否因網絡超時失敗
class SyncResult {
  final bool success;
  final bool isTimeout;
  const SyncResult({required this.success, required this.isTimeout});
}

/// 數據庫服務類
/// 負責數據庫的初始化、題目查詢和用戶進度管理
class DatabaseService {
  static const int _firestoreBatchWriteLimit = 450;

  /// 調試日誌輸出（只在 Debug 模式下輸出，避免 Release 模式性能問題）
  static void _debugLog(String message) {
    if (kDebugMode) {}
  }

  static String _normalizeUserId(String? userId) {
    if (userId == null || userId.isEmpty) {
      return 'guest_user';
    }
    return userId;
  }

  static Future<int> _deleteQuerySnapshotInBatches(
    FirebaseFirestore firestore,
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) async {
    var batch = firestore.batch();
    var pendingWrites = 0;
    var deletedCount = 0;

    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
      pendingWrites++;
      deletedCount++;

      if (pendingWrites >= _firestoreBatchWriteLimit) {
        await batch.commit();
        batch = firestore.batch();
        pendingWrites = 0;
      }
    }

    if (pendingWrites > 0) {
      await batch.commit();
    }

    return deletedCount;
  }

  static Future<bool> hasUserProgress({required String userId}) async {
    final db = await userProgressDatabase;
    final normalizedUserId = _normalizeUserId(userId);
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM user_progress WHERE user_id = ?',
      [normalizedUserId],
    );
    final count = (result.first['count'] as int?) ?? 0;
    return count > 0;
  }

  static Future<void> mergeGuestDataToAccount(String targetUid) async {
    final db = await userProgressDatabase;
    final normalizedTargetUid = _normalizeUserId(targetUid);
    if (normalizedTargetUid == 'guest_user') {
      return;
    }

    await db.transaction((txn) async {
      await txn.rawInsert('''
        INSERT INTO user_progress (
          question_id,
          user_id,
          is_favorite,
          error_count,
          wrong_count,
          is_mastered,
          correct_streak,
          total_attempts,
          last_practiced,
          created_at
        )
        SELECT
          question_id,
          ?,
          is_favorite,
          error_count,
          wrong_count,
          is_mastered,
          correct_streak,
          total_attempts,
          last_practiced,
          created_at
        FROM user_progress
        WHERE user_id = ?
        ON CONFLICT(question_id, user_id) DO UPDATE SET
          is_favorite = CASE
            WHEN user_progress.is_favorite = 1 OR excluded.is_favorite = 1
            THEN 1
            ELSE 0
          END,
          error_count = user_progress.error_count + excluded.error_count,
          wrong_count = user_progress.wrong_count + excluded.wrong_count,
          total_attempts = user_progress.total_attempts + excluded.total_attempts,
          correct_streak = CASE
            WHEN COALESCE(excluded.last_practiced, 0) >= COALESCE(user_progress.last_practiced, 0)
            THEN excluded.correct_streak
            ELSE user_progress.correct_streak
          END,
          is_mastered = CASE
            WHEN COALESCE(excluded.last_practiced, 0) >= COALESCE(user_progress.last_practiced, 0)
            THEN excluded.is_mastered
            ELSE user_progress.is_mastered
          END,
          last_practiced = CASE
            WHEN user_progress.last_practiced IS NULL THEN excluded.last_practiced
            WHEN excluded.last_practiced IS NULL THEN user_progress.last_practiced
            WHEN excluded.last_practiced > user_progress.last_practiced THEN excluded.last_practiced
            ELSE user_progress.last_practiced
          END,
          created_at = CASE
            WHEN excluded.created_at < user_progress.created_at
            THEN excluded.created_at
            ELSE user_progress.created_at
          END
      ''', [normalizedTargetUid, 'guest_user']);

      await txn.update(
        'mock_exam_results',
        {'user_id': normalizedTargetUid},
        where: 'user_id = ?',
        whereArgs: ['guest_user'],
      );

      await txn.delete(
        'user_progress',
        where: 'user_id = ?',
        whereArgs: ['guest_user'],
      );
    });
  }

  // 靜態數據庫實例（單例模式）
  static Database? _database;
  static Database? _userProgressDatabase;

  // 數據庫配置
  static const String _databaseName = 'assets/italy_quiz.db';
  static const String _userProgressDbName = 'user_progress.db';

  // 靜態數據庫版本號（用於強制更新）
  static const int kStaticDbVersion = 10;
  static const String _lastCopiedDbVersionKey = 'last_copied_db_version';

  // 初始化錯誤信息（如果初始化失敗，保存錯誤信息）
  static String? initError;
  static bool _isWebPreviewMode = false;

  static bool get isWebPreviewMode => _isWebPreviewMode;

  /// 獲取主數據庫實例（只讀，包含題目數據）
  static Future<Database> get database async {
    if (_database != null) {
      // 強制檢查數據庫是否有章節數據，如果沒有則重新初始化
      try {
        final countResult = await _database!.rawQuery(
            'SELECT COUNT(*) as count FROM questions WHERE chapter IS NOT NULL');
        final count = countResult.first['count'] as int? ?? 0;
        if (count == 0) {
          _debugLog('⚠️ [Database] 檢測到已打開的數據庫沒有章節數據，重新初始化...');
          await _database!.close();
          _database = null;
          _database = await _initDatabase();
        }
      } catch (e) {
        _debugLog('⚠️ [Database] 檢查已打開的數據庫時出錯，重新初始化: $e');
        try {
          await _database?.close();
        } catch (_) {}
        _database = null;
        _database = await _initDatabase();
      }
      return _database!;
    }
    _database = await _initDatabase();
    return _database!;
  }

  /// 獲取用戶進度數據庫實例（可讀寫，用於記錄用戶學習進度）
  static Future<Database> get userProgressDatabase async {
    if (_userProgressDatabase != null) return _userProgressDatabase!;
    _userProgressDatabase = await _initUserProgressDatabase();
    return _userProgressDatabase!;
  }

  /// 從 assets 複製數據庫文件到設備目錄
  static Future<void> _copyDatabaseFromAssets(File file, String path) async {
    try {
      // 🔍 強制修復：在拷貝邏輯之前，強制刪除舊文件
      _debugLog('🗑️ [Database] 強制刪除舊數據庫文件（如果存在）...');
      if (await file.exists()) {
        try {
          await file.delete();
          _debugLog('✅ [Database] 舊文件已強制刪除');
        } catch (e) {
          _debugLog('⚠️ [Database] 刪除舊文件時出錯（可能文件不存在）: $e');
        }
      } else {
        _debugLog('ℹ️ [Database] 舊文件不存在，無需刪除');
      }

      _debugLog('📁 [Database] 創建目錄結構...');
      await Directory(dirname(path)).create(recursive: true);

      _debugLog('📦 [Database] 從 assets 加載數據庫文件...');
      final ByteData data = await rootBundle.load(_databaseName);
      final int dataSize = data.lengthInBytes;
      _debugLog(
          '📦 [Database] 數據庫文件大小（從 assets）: ${(dataSize / 1024 / 1024).toStringAsFixed(2)} MB');

      _debugLog('💾 [Database] 開始寫入數據庫文件到設備...');
      final List<int> bytes =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

      // 直接寫入文件（對於 20MB 的文件，直接寫入通常沒問題）
      // 如果遇到內存問題，可以考慮分批寫入
      await file.writeAsBytes(bytes, flush: true);

      // 🔍 強制修復：拷貝完成後，驗證文件大小
      final copiedFile = File(path);
      if (await copiedFile.exists()) {
        final fileSize = copiedFile.lengthSync();
        _debugLog('✅ [Database] 數據庫文件複製完成');
        _debugLog(
            '📊 [Database] 拷貝後文件大小: ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB ($fileSize bytes)');
        _debugLog(
            '📊 [Database] 原始文件大小: ${(dataSize / 1024 / 1024).toStringAsFixed(2)} MB ($dataSize bytes)');

        if (fileSize == dataSize) {
          _debugLog('✅ [Database] 文件大小驗證通過：拷貝完整');
        } else {
          _debugLog(
              '⚠️ [Database] 文件大小驗證失敗：拷貝可能不完整（差異: ${fileSize - dataSize} bytes）');
        }
      } else {
        _debugLog('❌ [Database] 錯誤：拷貝後文件不存在！');
      }
    } catch (e, stackTrace) {
      _debugLog('❌ [Database] 複製數據庫文件失敗: $e');
      _debugLog('📋 [Database] 錯誤堆棧: $stackTrace');
      throw Exception('Failed to copy database from assets: $e');
    }
  }

  /// 初始化主數據庫（從 assets 複製到設備目錄）
  static Future<Database> _initDatabase() async {
    _debugLog('📁 [Database] 開始初始化主數據庫...');

    // 獲取應用文檔目錄
    _debugLog('📂 [Database] 獲取應用文檔目錄...');
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = join(documentsDirectory.path, _databaseName);
    _debugLog('📂 [Database] 數據庫路徑: $path');

    // 檢查數據庫文件是否存在
    _debugLog('🔍 [Database] 檢查數據庫文件是否存在...');
    final file = File(path);
    var exists = await file.exists();
    _debugLog('🔍 [Database] 文件存在: $exists');

    // 版本檢查邏輯（在 openDatabase 之前執行）
    final prefs = await SharedPreferences.getInstance();
    final lastCopiedVersion = prefs.getInt(_lastCopiedDbVersionKey) ?? 0;
    _debugLog('📋 [Database] 當前數據庫版本: $kStaticDbVersion');
    _debugLog('📋 [Database] 已拷貝的數據庫版本: $lastCopiedVersion');

    // 僅在文件不存在或靜態版本升級時才覆蓋拷貝
    if (!exists || lastCopiedVersion < kStaticDbVersion) {
      if (exists) {
        _debugLog('⚠️ [Database] 檢測到數據庫版本更新，正在覆蓋舊文件...');
        _debugLog(
            '⚠️ [Database] 舊版本: $lastCopiedVersion, 新版本: $kStaticDbVersion');
        _debugLog('🗑️ [Database] 刪除舊數據庫文件...');
        try {
          await file.delete();
          _debugLog('✅ [Database] 舊文件已刪除');
          exists = false;
        } catch (e) {
          _debugLog('⚠️ [Database] 刪除舊文件時出錯: $e');
        }
      } else {
        _debugLog('📥 [Database] 數據庫文件不存在，開始從 assets 複製...');
      }

      // 從 assets 複製新文件
      _debugLog('📥 [Database] 正在從 assets 複製最新版本的數據庫文件...');
      await _copyDatabaseFromAssets(file, path);

      // 🔍 強制修復：拷貝完成後，打印文件大小
      if (await File(path).exists()) {
        final fileSize = File(path).lengthSync();
        _debugLog(
            '✅ [Database] 成功拷貝新數據庫，大小為: $fileSize 字節 (${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB)');
      } else {
        _debugLog('❌ [Database] 錯誤：拷貝後文件不存在！');
      }

      // 更新版本記錄
      await prefs.setInt(_lastCopiedDbVersionKey, kStaticDbVersion);
      _debugLog('✅ [Database] 數據庫文件已更新，版本號已記錄: $kStaticDbVersion');
    } else {
      _debugLog('✅ [Database] 數據庫版本已是最新（版本 $lastCopiedVersion），跳過更新');
    }

    // 確保文件存在（版本檢查後應該已經存在）
    final fileExists = await file.exists();
    if (!fileExists) {
      _debugLog('❌ [Database] 錯誤：數據庫文件不存在，即使已執行版本檢查');
      throw Exception('Database file does not exist after version check');
    }

    // 繼續原有的檢查邏輯（用於向後兼容和額外驗證，但簡化處理）
    // 注意：由於版本檢查已確保數據庫是最新的，這裡的檢查主要是驗證
    Database? tempDb;
    try {
      _debugLog('✅ [Database] 數據庫文件已存在，開始驗證數據完整性...');

      // 驗證數據庫完整性（版本檢查已確保是最新版本，這裡主要是驗證）
      _debugLog('🔍 [Database] 打開臨時數據庫連接驗證數據完整性...');
      tempDb = await openDatabase(path,
          version: 1, readOnly: false, singleInstance: false);

      // 驗證章節數據
      final countResult = await tempDb.rawQuery(
          'SELECT COUNT(*) as count FROM questions WHERE chapter IS NOT NULL');
      final count = countResult.first['count'] as int? ?? 0;
      _debugLog('📊 [Database] 驗證章節數據: $count 道題目有章節信息');

      // 驗證關鍵詞數據
      try {
        final keywordsCheck =
            await tempDb.rawQuery('PRAGMA table_info(questions)');
        final hasKeywordsColumn =
            keywordsCheck.any((column) => column['name'] == 'keywords_json');
        _debugLog('📋 [Database] 驗證 keywords_json 字段: $hasKeywordsColumn');

        if (hasKeywordsColumn) {
          final keywordsCountResult = await tempDb.rawQuery('''
            SELECT COUNT(*) as count
            FROM questions
            WHERE keywords_json IS NOT NULL
            AND keywords_json != ''
            AND keywords_json != '[]'
          ''');
          final keywordsCount = keywordsCountResult.first['count'] as int? ?? 0;
          _debugLog('📊 [Database] 驗證關鍵詞數據: $keywordsCount 道題目有關鍵詞');

          if (keywordsCount >= 100) {
            _debugLog('✅ [Database] 數據庫驗證通過：章節數據和關鍵詞數據正常');
          } else {
            _debugLog(
                '⚠️ [Database] 驗證警告：關鍵詞數據不足（$keywordsCount 題），但版本檢查已通過，繼續使用');
          }
        } else {
          _debugLog('⚠️ [Database] 驗證警告：缺少 keywords_json 字段，但版本檢查已通過，繼續使用');
        }
      } catch (e) {
        _debugLog('⚠️ [Database] 驗證關鍵詞數據時出錯: $e');
      }
    } catch (e, stackTrace) {
      _debugLog('⚠️ [Database] 驗證數據庫完整性時出錯: $e');
      _debugLog('📋 [Database] 錯誤堆棧: $stackTrace');
      if (tempDb != null) {
        try {
          await tempDb.close();
        } catch (_) {}
      }
      // 驗證失敗時，由於版本檢查已確保是最新版本，這裡只記錄警告
      _debugLog('⚠️ [Database] 驗證失敗，但版本檢查已通過，繼續使用數據庫');
    } finally {
      if (tempDb != null) {
        try {
          await tempDb.close();
        } catch (_) {}
      }
    }

    // 確保文件可寫（如果不是，刪除並重新複製）
    try {
      // 嘗試設置文件權限為可寫（如果平台支持）
      if (await file.exists()) {
        await file.stat();
        _debugLog('📝 [Database] 數據庫文件權限檢查完成');
      }
    } catch (e) {
      _debugLog('⚠️ [Database] 無法檢查文件權限: $e');
    }

    // 打開數據庫連接
    // 注意：雖然我們不應該修改這個數據庫，但 SQLite 需要寫權限來創建臨時文件和執行 PRAGMA 命令
    // 我們通過不在代碼中執行寫操作來保護數據，而不是使用 readOnly 模式
    _debugLog('🔓 [Database] 打開數據庫連接...');
    Database? db;
    int retryCount = 0;
    const maxRetries = 3;

    while (retryCount < maxRetries) {
      try {
        // 如果之前有連接，先關閉它
        if (db != null) {
          try {
            await db.close();
          } catch (_) {}
          db = null;
        }

        // 如果重試，先等待一小段時間
        if (retryCount > 0) {
          _debugLog('⏳ [Database] 等待 ${retryCount * 500}ms 後重試...');
          await Future.delayed(Duration(milliseconds: retryCount * 500));

          // 檢查文件是否存在且可讀
          if (!await file.exists()) {
            _debugLog('❌ [Database] 數據庫文件不存在，重新複製...');
            await _copyDatabaseFromAssets(file, path);
          }
        }

        db = await openDatabase(
          path,
          version: 1,
          readOnly: false, // 必須為 false，因為 SQLite 需要寫權限來創建臨時文件和執行 PRAGMA 命令
          singleInstance: true, // 使用單例模式，避免多個連接
          // 我們通過只執行 SELECT 查詢來保護數據，不執行 INSERT/UPDATE/DELETE
        );
        _debugLog('✅ [Database] 數據庫連接打開成功');
        break; // 成功打開，跳出重試循環
      } catch (e) {
        retryCount++;
        final errorStr = e.toString();
        _debugLog('⚠️ [Database] 打開數據庫連接失敗（嘗試 $retryCount/$maxRetries）: $e');

        // 檢查是否為磁盤 I/O 錯誤
        final isDiskIOError = errorStr.contains('disk I/O error') ||
            errorStr.contains('Code=6922') ||
            errorStr.contains('BEGIN EXCLUSIVE');

        if (isDiskIOError && retryCount < maxRetries) {
          _debugLog('🔄 [Database] 檢測到磁盤 I/O 錯誤，嘗試關閉並重新打開...');
          // 嘗試關閉可能存在的舊連接
          if (_database != null) {
            try {
              await _database!.close();
              _database = null;
              _debugLog('✅ [Database] 已關閉舊數據庫連接');
            } catch (_) {}
          }
          // 繼續重試
          continue;
        }

        if (retryCount >= maxRetries) {
          // 最後一次重試失敗，嘗試刪除並重新複製數據庫
          _debugLog('🔄 [Database] 所有重試失敗，嘗試刪除並重新複製數據庫文件...');
          try {
            // 確保關閉所有連接
            if (_database != null) {
              try {
                await _database!.close();
                _database = null;
              } catch (_) {}
            }
            if (db != null) {
              try {
                await db.close();
                db = null;
              } catch (_) {}
            }

            // 等待一小段時間，確保文件解鎖
            await Future.delayed(const Duration(milliseconds: 500));

            if (await file.exists()) {
              await file.delete();
              _debugLog('🗑️ [Database] 已刪除損壞的數據庫文件');
            }
            await _copyDatabaseFromAssets(file, path);
            _debugLog('📥 [Database] 已重新複製數據庫文件，嘗試最後一次打開...');

            // 最後一次嘗試打開
            db = await openDatabase(
              path,
              version: 1,
              readOnly: false,
              singleInstance: true,
            );
            _debugLog('✅ [Database] 重新複製後數據庫連接打開成功');
            break;
          } catch (finalError) {
            _debugLog('❌ [Database] 重新複製後仍然失敗: $finalError');
            throw Exception(
                'Failed to open database after retries: $finalError');
          }
        }
      }
    }

    if (db == null) {
      throw Exception(
          'Unable to open database connection after $maxRetries attempts');
    }

    final finalDb = db;

    // 🔍 強力調試：打印表結構，檢查 keywords_json 字段是否存在
    try {
      final tableInfo = await finalDb.rawQuery('PRAGMA table_info(questions)');
      _debugLog('📋 [Database] ========== 表結構檢查 ==========');
      _debugLog('📋 [Database] questions 表共有 ${tableInfo.length} 個字段:');
      bool hasKeywordsJson = false;
      for (final column in tableInfo) {
        final columnName = column['name'] as String?;
        final columnType = column['type'] as String?;
        if (columnName == 'keywords_json') {
          hasKeywordsJson = true;
          _debugLog(
              '✅ [Database] 找到 keywords_json 字段: $columnName ($columnType)');
        } else {
          _debugLog('   - $columnName ($columnType)');
        }
      }
      if (!hasKeywordsJson) {
        _debugLog('❌ [Database] ⚠️⚠️⚠️ 警告：questions 表中沒有 keywords_json 字段！');
      }
      _debugLog('📋 [Database] =================================');
    } catch (e) {
      _debugLog('⚠️ [Database] 檢查表結構時出錯: $e');
    }

    // 創建索引以優化查詢性能
    await _createIndexes(finalDb);

    return finalDb;
  }

  /// 創建數據庫索引以優化查詢性能
  static Future<void> _createIndexes(Database db) async {
    try {
      _debugLog('📊 [Database] 開始創建數據庫索引...');

      // 為 chapter 字段創建索引，優化章節查詢性能
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_chapter ON questions (chapter)');
      _debugLog('✅ [Database] 索引 idx_chapter 創建成功（或已存在）');

      // 為 translations 表創建複合索引，優化最常見的查詢模式
      // 優化：WHERE question_id = ? AND lang = ? AND type = ?
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_translations_lookup ON translations(question_id, lang, type)');
      _debugLog('✅ [Database] 索引 idx_translations_lookup 創建成功（或已存在）');

      // 優化：WHERE type = ? AND lang = ? 查詢
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_translations_type_lang ON translations(type, lang)');
      _debugLog('✅ [Database] 索引 idx_translations_type_lang 創建成功（或已存在）');

      // 驗證索引是否存在
      final indexInfo = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='index' AND name IN ('idx_chapter', 'idx_translations_lookup', 'idx_translations_type_lang')");
      if (indexInfo.length >= 3) {
        _debugLog('✅ [Database] 所有索引驗證成功');
      }
    } catch (e, stackTrace) {
      _debugLog('⚠️ [Database] 創建索引失敗: $e');
      _debugLog('📋 [Database] 錯誤堆棧: $stackTrace');
      // 索引創建失敗不影響應用運行，只是查詢可能較慢
    }
  }

  /// 為用戶進度數據庫創建索引（優化掌握度統計查詢）
  static Future<void> _createUserProgressIndexes(Database db) async {
    try {
      _debugLog('📊 [UserProgress] 開始創建用戶進度數據庫索引...');

      // 以 user_id 為核心的索引（多用戶隔離）
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_user_id ON user_progress (user_id)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_user_question ON user_progress (user_id, question_id)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_user_mastered ON user_progress (user_id, is_mastered)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_user_last_practiced ON user_progress (user_id, last_practiced)');

      // 保留原索引（兼容舊查詢/統計）
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_is_mastered ON user_progress (is_mastered)');
      _debugLog('✅ [UserProgress] 索引 idx_is_mastered 創建成功（或已存在）');

      try {
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_question_id ON user_progress (question_id)');
        _debugLog('✅ [UserProgress] 索引 idx_question_id 創建成功（或已存在）');
      } catch (e) {
        _debugLog('ℹ️ [UserProgress] question_id 索引可能已存在（PRIMARY KEY）');
      }
    } catch (e, stackTrace) {
      _debugLog('⚠️ [UserProgress] 創建索引失敗: $e');
      _debugLog('📋 [UserProgress] 錯誤堆棧: $stackTrace');
      // 索引創建失敗不影響應用運行，只是查詢可能較慢
    }
  }

  /// 執行數據庫遷移（添加 chapter 和 keywords_json 字段）
  static Future<void> _migrateDatabase() async {
    try {
      final db = await database;

      // 獲取表結構信息（只需查詢一次）
      final tableInfo = await db.rawQuery('PRAGMA table_info(questions)');

      // 檢查 chapter 字段是否存在
      final hasChapter = tableInfo.any((column) => column['name'] == 'chapter');
      _debugLog('📋 [Migration] 檢查 chapter 字段是否存在: $hasChapter');

      // 如果字段不存在，則添加
      if (!hasChapter) {
        _debugLog('📝 [Migration] 開始添加 chapter 字段...');
        await db.execute('ALTER TABLE questions ADD COLUMN chapter INTEGER');
        _debugLog('✅ [Migration] 數據庫遷移完成：已添加 chapter 字段');
      } else {
        _debugLog('ℹ️ [Migration] chapter 字段已存在，跳過添加');

        // 檢查是否有數據
        final countResult = await db.rawQuery(
            'SELECT COUNT(*) as count FROM questions WHERE chapter IS NOT NULL');
        final count = countResult.first['count'] as int? ?? 0;
        _debugLog('📊 [Migration] 數據庫中有章節信息的題目數量: $count');

        if (count == 0) {
          _debugLog('⚠️ [Migration] 警告：chapter 字段存在但所有題目的 chapter 值都是 NULL！');
          _debugLog('⚠️ [Migration] 這可能意味著：');
          _debugLog('   1. assets/italy_quiz.db 文件中的數據沒有 chapter 信息');
          _debugLog('   2. 需要更新 assets/italy_quiz.db 文件以包含章節數據');
          _debugLog('   3. 或者需要運行腳本為題目分配章節');
        }
      }

      // 檢查 keywords_json 字段是否存在
      final hasKeywordsJson =
          tableInfo.any((column) => column['name'] == 'keywords_json');
      _debugLog('📋 [Migration] 檢查 keywords_json 字段是否存在: $hasKeywordsJson');

      // 如果字段不存在，則添加
      if (!hasKeywordsJson) {
        _debugLog('📝 [Migration] 開始添加 keywords_json 字段...');
        await db.execute('ALTER TABLE questions ADD COLUMN keywords_json TEXT');
        _debugLog('✅ [Migration] 數據庫遷移完成：已添加 keywords_json 字段');
      } else {
        _debugLog('ℹ️ [Migration] keywords_json 字段已存在，跳過添加');
      }
    } catch (e, stackTrace) {
      _debugLog('⚠️ [Migration] 數據庫遷移失敗：$e');
      _debugLog('📋 [Migration] 錯誤堆棧: $stackTrace');
      // 遷移失敗不影響應用運行，只是相關功能不可用
    }
  }

  /// 初始化用戶進度數據庫（用於記錄用戶學習進度）
  /// 這個數據庫會在設備上創建，不會影響原始題庫
  static Future<Database> _initUserProgressDatabase() async {
    _debugLog('📁 [UserProgress] 開始初始化用戶進度數據庫...');

    try {
      final documentsDirectory = await getApplicationDocumentsDirectory();
      final path = join(documentsDirectory.path, _userProgressDbName);
      _debugLog('📂 [UserProgress] 用戶進度數據庫路徑: $path');

      final db = await openDatabase(
        path,
        version: 7, // 7: 新增 mock_exam_results 表
        onCreate: (db, version) async {
          _debugLog('📝 [UserProgress] 創建用戶進度表結構...');
          await db.execute('''
            CREATE TABLE user_progress (
              question_id TEXT NOT NULL,
              user_id TEXT NOT NULL DEFAULT 'guest_user',
              is_favorite INTEGER DEFAULT 0,
              error_count INTEGER DEFAULT 0,
              wrong_count INTEGER DEFAULT 0,
              is_mastered INTEGER DEFAULT 0,
              correct_streak INTEGER DEFAULT 0,
              total_attempts INTEGER DEFAULT 0,
              last_practiced INTEGER,
              created_at INTEGER DEFAULT (strftime('%s', 'now')),
              PRIMARY KEY (question_id, user_id)
            )
          ''');
          _debugLog('✅ [UserProgress] 用戶進度表創建成功');
          await db.execute('''
            CREATE TABLE mock_exam_results (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              user_id TEXT NOT NULL,
              correct_count INTEGER NOT NULL,
              wrong_count INTEGER NOT NULL,
              total_questions INTEGER NOT NULL,
              time_used_seconds INTEGER,
              taken_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
            )
          ''');
          _debugLog('✅ [UserProgress] mock_exam_results 表創建成功');
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          _debugLog('🔄 [UserProgress] 數據庫升級: $oldVersion -> $newVersion');

          // 版本2：添加 is_mastered 字段
          if (oldVersion < 2) {
            try {
              await db.execute(
                  'ALTER TABLE user_progress ADD COLUMN is_mastered INTEGER DEFAULT 0');
              _debugLog('✅ [UserProgress] 已添加 is_mastered 字段');
            } catch (e) {
              // 如果字段已存在，忽略錯誤
              _debugLog('ℹ️ [UserProgress] is_mastered 字段可能已存在: $e');
            }
          }

          // 版本3：添加 correct_streak 字段
          if (oldVersion < 3) {
            try {
              await db.execute(
                  'ALTER TABLE user_progress ADD COLUMN correct_streak INTEGER DEFAULT 0');
              _debugLog('✅ [UserProgress] 已添加 correct_streak 字段');
            } catch (e) {
              // 如果字段已存在，忽略錯誤
              _debugLog('ℹ️ [UserProgress] correct_streak 字段可能已存在: $e');
            }
          }

          // 版本4：添加 wrong_count 字段（記錄累計做錯總次數）
          if (oldVersion < 4) {
            try {
              // 添加 wrong_count 字段
              await db.execute(
                  'ALTER TABLE user_progress ADD COLUMN wrong_count INTEGER DEFAULT 0');
              _debugLog('✅ [UserProgress] 已添加 wrong_count 字段');

              // 將現有的 error_count 數據遷移到 wrong_count（保持向後兼容）
              await db.execute('''
                UPDATE user_progress
                SET wrong_count = error_count
                WHERE error_count > 0
              ''');
              _debugLog('✅ [UserProgress] 已將 error_count 數據遷移到 wrong_count');
            } catch (e) {
              // 如果字段已存在，忽略錯誤
              _debugLog('ℹ️ [UserProgress] wrong_count 字段可能已存在: $e');
            }
          }

          // 版本5：添加 total_attempts 字段（記錄題目被做的總次數，用於追踪覆盖率）
          if (oldVersion < 5) {
            try {
              // 添加 total_attempts 字段
              await db.execute(
                  'ALTER TABLE user_progress ADD COLUMN total_attempts INTEGER DEFAULT 0');
              _debugLog('✅ [UserProgress] 已添加 total_attempts 字段');

              // 初始化：將現有記錄的 total_attempts 設為 error_count + correct_streak（估算）
              // 注意：這只是一個估算，因為我們無法知道之前的準確嘗試次數
              await db.execute('''
                UPDATE user_progress
                SET total_attempts = error_count + correct_streak
                WHERE error_count > 0 OR correct_streak > 0
              ''');
              _debugLog('✅ [UserProgress] 已初始化 total_attempts 字段（估算值）');
            } catch (e) {
              // 如果字段已存在，忽略錯誤
              _debugLog('ℹ️ [UserProgress] total_attempts 字段可能已存在: $e');
            }
          }

          // 版本6：引入 user_id 欄位並改為複合主鍵（question_id + user_id）
          if (oldVersion < 6) {
            try {
              _debugLog('🔄 [UserProgress] 開始遷移 user_id 與複合主鍵...');
              await db.execute('''
                CREATE TABLE user_progress_new (
                  question_id TEXT NOT NULL,
                  user_id TEXT NOT NULL DEFAULT 'guest_user',
                  is_favorite INTEGER DEFAULT 0,
                  error_count INTEGER DEFAULT 0,
                  wrong_count INTEGER DEFAULT 0,
                  is_mastered INTEGER DEFAULT 0,
                  correct_streak INTEGER DEFAULT 0,
                  total_attempts INTEGER DEFAULT 0,
                  last_practiced INTEGER,
                  created_at INTEGER DEFAULT (strftime('%s', 'now')),
                  PRIMARY KEY (question_id, user_id)
                )
              ''');
              await db.execute('''
                INSERT INTO user_progress_new (
                  question_id,
                  user_id,
                  is_favorite,
                  error_count,
                  wrong_count,
                  is_mastered,
                  correct_streak,
                  total_attempts,
                  last_practiced,
                  created_at
                )
                SELECT
                  question_id,
                  'guest_user',
                  is_favorite,
                  error_count,
                  wrong_count,
                  is_mastered,
                  correct_streak,
                  total_attempts,
                  last_practiced,
                  created_at
                FROM user_progress
              ''');
              await db.execute('DROP TABLE user_progress');
              await db.execute(
                  'ALTER TABLE user_progress_new RENAME TO user_progress');
              _debugLog('✅ [UserProgress] user_id 遷移完成');
            } catch (e) {
              _debugLog('⚠️ [UserProgress] user_id 遷移失敗: $e');
            }
          }

          // 版本7：模擬考結果表
          if (oldVersion < 7) {
            try {
              await db.execute('''
                CREATE TABLE IF NOT EXISTS mock_exam_results (
                  id INTEGER PRIMARY KEY AUTOINCREMENT,
                  user_id TEXT NOT NULL,
                  correct_count INTEGER NOT NULL,
                  wrong_count INTEGER NOT NULL,
                  total_questions INTEGER NOT NULL,
                  time_used_seconds INTEGER,
                  taken_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
                )
              ''');
              _debugLog('✅ [UserProgress] mock_exam_results 表創建成功');
            } catch (e) {
              _debugLog('⚠️ [UserProgress] mock_exam_results 表創建失敗: $e');
            }
          }
        },
      );

      // 確保索引已創建（即使表已存在）
      await _createUserProgressIndexes(db);

      _debugLog('✅ [UserProgress] 用戶進度數據庫初始化成功');
      return db;
    } catch (e, stackTrace) {
      _debugLog('❌ [UserProgress] 用戶進度數據庫初始化失敗: $e');
      _debugLog('📋 [UserProgress] 錯誤堆棧: $stackTrace');
      throw Exception('Failed to initialize user progress database: $e');
    }
  }

  /// 初始化數據庫服務（應在應用啟動時調用）
  static Future<void> init() async {
    _debugLog('🚀 [DatabaseService] 開始初始化數據庫服務...');

    if (kIsWeb) {
      // sqflite/path_provider 目前只用於行動與桌面端；Web 預覽不初始化本機 SQLite。
      _isWebPreviewMode = true;
      initError = null;
      _debugLog('🌐 [DatabaseService] Web 預覽模式：跳過本機 SQLite 初始化');
      return;
    }

    try {
      // 確保清除舊的數據庫實例
      if (_database != null) {
        _debugLog('🔄 [DatabaseService] 關閉舊的數據庫連接...');
        try {
          await _database!.close();
        } catch (e) {
          _debugLog('⚠️ [DatabaseService] 關閉舊數據庫連接時出錯: $e');
        }
        _database = null;
      }

      _debugLog('📊 [DatabaseService] 步驟 1/3: 初始化主數據庫...');
      final db = await database;
      _debugLog('✅ [DatabaseService] 主數據庫初始化完成');

      // 驗證數據庫是否有章節數據和關鍵詞數據
      _debugLog('🔍 [DatabaseService] 驗證數據庫數據完整性...');
      final countResult = await db.rawQuery(
          'SELECT COUNT(*) as count FROM questions WHERE chapter IS NOT NULL');
      final count = countResult.first['count'] as int? ?? 0;
      _debugLog('📊 [DatabaseService] 數據庫中有 $count 道題目有章節信息');

      // 檢查關鍵詞數據
      try {
        final keywordsCountResult = await db.rawQuery('''
          SELECT COUNT(*) as count
          FROM questions
          WHERE keywords_json IS NOT NULL
          AND keywords_json != ''
          AND keywords_json != '[]'
        ''');
        final keywordsCount = keywordsCountResult.first['count'] as int? ?? 0;
        _debugLog('📊 [DatabaseService] 數據庫中有 $keywordsCount 道題目有關鍵詞數據');

        if (keywordsCount < 100) {
          _debugLog('⚠️ [DatabaseService] 警告：關鍵詞數據不足（$keywordsCount 題）！');
          _debugLog('🔄 [DatabaseService] 嘗試強制重新加載數據庫...');
          await forceReloadDatabase();
          // 重新獲取數據庫實例
          final newDb = await database;
          final retryKeywordsResult = await newDb.rawQuery('''
            SELECT COUNT(*) as count
            FROM questions
            WHERE keywords_json IS NOT NULL
            AND keywords_json != ''
            AND keywords_json != '[]'
          ''');
          final retryKeywordsCount =
              retryKeywordsResult.first['count'] as int? ?? 0;
          _debugLog(
              '📊 [DatabaseService] 重新加載後，數據庫中有 $retryKeywordsCount 道題目有關鍵詞數據');
        }
      } catch (e) {
        _debugLog('⚠️ [DatabaseService] 檢查關鍵詞數據時出錯: $e');
      }

      if (count == 0) {
        _debugLog('❌ [DatabaseService] 警告：數據庫沒有章節數據！');
        _debugLog('❌ [DatabaseService] 這將導致章節練習功能無法使用');
        _debugLog('🔄 [DatabaseService] 嘗試強制重新加載數據庫...');
        await forceReloadDatabase();
        // 再次檢查
        final retryCountResult = await _database!.rawQuery(
            'SELECT COUNT(*) as count FROM questions WHERE chapter IS NOT NULL');
        final retryCount = retryCountResult.first['count'] as int? ?? 0;
        _debugLog('📊 [DatabaseService] 重新加載後，數據庫中有 $retryCount 道題目有章節信息');
      }

      _debugLog('📊 [DatabaseService] 步驟 2/3: 初始化用戶進度數據庫...');
      await userProgressDatabase;
      _debugLog('✅ [DatabaseService] 用戶進度數據庫初始化完成');

      _debugLog('📊 [DatabaseService] 步驟 3/3: 執行數據庫遷移...');
      await _migrateDatabase();
      _debugLog('✅ [DatabaseService] 數據庫遷移完成');

      _debugLog('🎉 [DatabaseService] 所有數據庫初始化完成！');
      // 初始化成功，清除之前的錯誤信息
      initError = null;
    } catch (e, stackTrace) {
      _debugLog('❌ [DatabaseService] 數據庫服務初始化失敗: $e');
      _debugLog('📋 [DatabaseService] 錯誤堆棧: $stackTrace');
      initError = e.toString();
      rethrow; // 重新拋出錯誤，讓調用者知道初始化失敗
    }
  }

  /// 強制重新加載數據庫（刪除舊文件並從assets重新複製）
  /// 同時檢查並更新關鍵詞數據
  static Future<void> forceReloadDatabase() async {
    _debugLog('🔄 [DatabaseService] 強制重新加載數據庫...');
    if (_database != null) {
      try {
        await _database!.close();
      } catch (e) {
        _debugLog('⚠️ [DatabaseService] 關閉數據庫時出錯: $e');
      }
      _database = null;
    }

    // 刪除設備上的數據庫文件
    try {
      final documentsDirectory = await getApplicationDocumentsDirectory();
      final path = join(documentsDirectory.path, _databaseName);
      final file = File(path);
      if (await file.exists()) {
        _debugLog('🗑️ [DatabaseService] 刪除舊數據庫文件: $path');
        await file.delete();
      }
    } catch (e) {
      _debugLog('⚠️ [DatabaseService] 刪除舊數據庫文件時出錯: $e');
    }

    // 重新初始化
    _database = await _initDatabase();
    _debugLog('✅ [DatabaseService] 數據庫重新加載完成');
  }

  /// 檢查數據庫是否已成功初始化
  static bool get isInitialized {
    // 如果兩個數據庫實例都存在，認為已初始化成功
    // initError 只在初始化失敗時設置，成功時會被清除
    final isReady = _database != null && _userProgressDatabase != null;
    if (isReady && initError != null) {
      // 如果數據庫已就緒但還有錯誤標記，清除錯誤標記（可能是之前的錯誤已被修復）
      initError = null;
    }
    return isReady;
  }

  /// 獲取題目列表
  /// [lang] 語言代碼（如 'zh', 'it', 'en'），默認為 'zh'
  /// [limit] 限制返回的題目數量，null 表示不限制
  /// [chapter] 章節ID，null 表示所有章節
  /// [skipMastered] 是否跳過已掌握的題目（is_mastered = 1），默認為 false
  /// 注意：由於 questions 表和 user_progress 表在不同的數據庫中，無法使用 SQL 跨數據庫查詢，
  /// 因此採用先查詢題目ID，再從 user_progress 數據庫查詢已掌握題目ID，最後在內存中過濾的方式
  static Future<List<Question>> getQuestions({
    String lang = 'zh',
    int? limit,
    int? chapter,
    bool skipMastered = false,
    String? userId,
  }) async {
    final db = await database;
    final normalizedUserId = _normalizeUserId(userId);

    // 如果需要跳過已掌握的題目，先查詢所有題目ID
    Set<String> masteredQuestionIds = {};
    if (skipMastered) {
      // 構建查詢所有題目ID的SQL
      String idQuery = 'SELECT id FROM questions';
      List<dynamic> idQueryArgs = [];

      if (chapter != null) {
        idQuery += ' WHERE chapter = ?';
        idQueryArgs.add(chapter);
      }

      final List<Map<String, dynamic>> questionIds =
          await db.rawQuery(idQuery, idQueryArgs);

      if (questionIds.isNotEmpty) {
        // 從 user_progress 數據庫查詢已掌握的題目ID
        final userProgressDb = await userProgressDatabase;
        final placeholders = questionIds.map((_) => '?').join(',');
        final ids = questionIds.map((row) => row['id'] as String).toList();

        final masteredResults = await userProgressDb.rawQuery('''
          SELECT question_id
          FROM user_progress
          WHERE question_id IN ($placeholders) AND is_mastered = 1 AND user_id = ?
        ''', [...ids, normalizedUserId]);

        masteredQuestionIds =
            masteredResults.map((row) => row['question_id'] as String).toSet();
      }
    }

    // 構建 SQL 查詢
    String query = '''
      SELECT
        q.id,
        q.img,
        q.answer,
        q.chapter,
        q.keywords_json,
        t_q.content as question,
        t_e.content as explanation
      FROM questions q
      LEFT JOIN translations t_q ON q.id = t_q.question_id AND t_q.lang = ? AND t_q.type = 'q'
      LEFT JOIN translations t_e ON q.id = t_e.question_id AND t_e.lang = ? AND t_e.type = 'e'
    ''';

    List<dynamic> queryArgs = [lang, lang];

    // 添加章節過濾（如果提供）
    if (chapter != null) {
      query += ' WHERE q.chapter = ?';
      queryArgs.add(chapter);
    }

    // 🔍 強力調試：打印 SQL 語句
    _debugLog('🔍 [Database] ========== SQL 查詢調試 ==========');
    _debugLog('🔍 [Database] SQL 語句: $query');
    _debugLog('🔍 [Database] 查詢參數: $queryArgs');
    _debugLog(
        '🔍 [Database] 是否包含 keywords_json: ${query.contains('keywords_json')}');
    _debugLog('🔍 [Database] =================================');

    final List<Map<String, dynamic>> maps = await db.rawQuery(query, queryArgs);

    // 🔍 強力調試：打印原始查詢結果
    _debugLog('🔍 [Database] ========== 原始查詢結果調試 ==========');
    _debugLog('🔍 [Database] 查詢返回記錄數: ${maps.length}');
    if (maps.isNotEmpty) {
      final firstMap = maps.first;
      _debugLog('🔍 [Database] DEBUG RAW MAP (第一條記錄): $firstMap');
      _debugLog('🔍 [Database] 第一條記錄的所有鍵: ${firstMap.keys.toList()}');

      // 檢查 keywords_json 字段
      if (firstMap.containsKey('keywords_json')) {
        _debugLog('✅ [Database] 查詢結果包含 keywords_json 字段');
        final keywordsJson = firstMap['keywords_json'];
        _debugLog(
            '🔍 [Database] keywords_json 的類型: ${keywordsJson.runtimeType}');
        _debugLog('🔍 [Database] keywords_json 的值: $keywordsJson');
        if (keywordsJson != null &&
            keywordsJson is String &&
            keywordsJson.isNotEmpty) {
          _debugLog(
              '✅ [Database] 第一題 keywords_json 不為空，長度: ${keywordsJson.length}');
          _debugLog(
              '✅ [Database] 第一題 keywords_json 內容（前200字符）: ${keywordsJson.substring(0, keywordsJson.length > 200 ? 200 : keywordsJson.length)}${keywordsJson.length > 200 ? '...' : ''}');
        } else {
          _debugLog('ℹ️ [Database] 第一題 keywords_json 為空或 null');
        }
      } else {
        _debugLog('❌ [Database] ⚠️⚠️⚠️ 查詢結果不包含 keywords_json 字段！');
        _debugLog('❌ [Database] 可用字段: ${firstMap.keys.join(', ')}');
        _debugLog('❌ [Database] 這表示 SQL 查詢沒有返回 keywords_json 列！');
      }
    } else {
      _debugLog('⚠️ [Database] 查詢結果為空，沒有記錄');
    }
    _debugLog('🔍 [Database] =================================');

    // 過濾掉已掌握的題目（如果 skipMastered 為 true）
    final filteredMaps = skipMastered
        ? maps.where((map) {
            final questionId = map['id'] as String;
            return !masteredQuestionIds.contains(questionId);
          }).toList()
        : maps;

    // 應用限制（在過濾後）
    final finalMaps = limit != null && limit < filteredMaps.length
        ? filteredMaps.take(limit).toList()
        : filteredMaps;

    final questions =
        finalMaps.map((map) => Question.fromMap(map, lang)).toList();

    // 調試：檢查解析後的 Question 對象
    if (questions.isNotEmpty) {
      final firstQuestion = questions.first;
      _debugLog(
          '🔍 [Database] 第一題解析後: id=${firstQuestion.id}, keywordsJson=${firstQuestion.keywordsJson?.substring(0, firstQuestion.keywordsJson!.length > 50 ? 50 : firstQuestion.keywordsJson!.length) ?? "null"}');
      _debugLog(
          '🔍 [Database] 第一題 keyWords.length: ${firstQuestion.keyWords.length}');
    }

    return questions;
  }

  /// 隨機獲取一道題目
  static Future<Question?> getRandomQuestion(
      {String lang = 'zh', int? chapter}) async {
    final questions =
        await getQuestions(lang: lang, limit: 1, chapter: chapter);
    if (questions.isEmpty) return null;

    // 由於 SQLite 的 RANDOM() 在 sqflite 中可能不可用，我們先獲取所有題目再隨機選擇
    final allQuestions = await getQuestions(lang: lang, chapter: chapter);
    if (allQuestions.isEmpty) return null;

    allQuestions.shuffle();
    return allQuestions.first;
  }

  /// 隨機獲取一道題目，同時包含意大利語和指定語言的翻譯（用於練習模式）
  /// [translationLang] 翻譯語言代碼（默認為當前語言）
  /// [chapter] 章節ID（可選）
  static Future<Question?> getRandomQuestionWithTranslation(
      {String translationLang = 'zh', int? chapter}) async {
    final db = await database;

    // 先獲取所有題目的ID（隨機選擇）
    List<Map<String, dynamic>> questionIds;
    if (chapter != null) {
      questionIds = await db.rawQuery('''
        SELECT id FROM questions WHERE chapter = ?
      ''', [chapter]);
    } else {
      questionIds = await db.rawQuery('SELECT id FROM questions');
    }

    if (questionIds.isEmpty) return null;

    // 隨機選擇一個題目ID
    questionIds.shuffle();
    final randomId = questionIds.first['id'] as String;

    // 獲取包含翻譯的題目
    return await getQuestionWithTranslation(randomId,
        translationLang: translationLang);
  }

  /// 獲取多道隨機題目（用於模擬考試）
  static Future<List<Question>> getRandomQuestions(int count,
      {String lang = 'zh', int? chapter}) async {
    final allQuestions = await getQuestions(lang: lang, chapter: chapter);
    if (allQuestions.isEmpty) return [];

    allQuestions.shuffle();
    return allQuestions.take(count).toList();
  }

  /// 獲取多道隨機題目，同時包含意大利語和指定語言的翻譯（用於模擬考試）
  /// [count] 需要獲取的題目數量
  /// [translationLang] 翻譯語言代碼（默認為當前語言）
  /// [chapter] 章節ID（可選）
  static Future<List<Question>> getRandomQuestionsWithTranslation(int count,
      {String translationLang = 'zh', int? chapter}) async {
    final db = await database;

    // 先獲取所有題目的ID（隨機選擇）
    List<Map<String, dynamic>> questionIds;
    if (chapter != null) {
      questionIds = await db.rawQuery('''
        SELECT id FROM questions WHERE chapter = ?
      ''', [chapter]);
    } else {
      questionIds = await db.rawQuery('SELECT id FROM questions');
    }

    if (questionIds.isEmpty) return [];

    // 隨機選擇指定數量的題目ID
    questionIds.shuffle();
    final selectedIds =
        questionIds.take(count).map((map) => map['id'] as String).toList();

    // 獲取包含翻譯的題目列表
    final questions = <Question>[];
    for (final id in selectedIds) {
      final question = await getQuestionWithTranslation(id,
          translationLang: translationLang);
      if (question != null) {
        questions.add(question);
      }
    }

    return questions;
  }

  /// 批量獲取隨機題目（優化版本：使用批量JOIN查詢，支持skipMastered和excludeIds）
  /// [count] 需要獲取的題目數量
  /// [translationLang] 翻譯語言代碼（默認為當前語言）
  /// [skipMastered] 是否跳過已掌握的題目（is_mastered = 1），默認為 false
  /// [userId] 用戶ID（用於過濾已掌握的題目）
  /// [excludeIds] 需要排除的題目ID集合（避免重複）
  static Future<List<Question>> getRandomQuestionsBatch({
    required int count,
    String translationLang = 'zh',
    bool skipMastered = false,
    String? userId,
    Set<String> excludeIds = const {},
  }) async {
    final db = await database;
    final normalizedUserId = _normalizeUserId(userId);

    // 步驟1：如果需要跳過已掌握的題目，先從 user_progress 數據庫查詢已掌握的題目ID
    Set<String> masteredQuestionIds = {};
    if (skipMastered) {
      final userProgressDb = await userProgressDatabase;
      final masteredResults = await userProgressDb.rawQuery('''
        SELECT question_id
        FROM user_progress
        WHERE is_mastered = 1 AND user_id = ?
      ''', [normalizedUserId]);

      masteredQuestionIds =
          masteredResults.map((row) => row['question_id'] as String).toSet();
    }

    // 步驟2：構建真隨機SQL查詢
    // 使用子查詢：先從所有題目中隨機抽取ID，再查詢完整數據
    // 這樣既保證了真隨機，又保證了性能（只查一次庫）
    String idQuery = 'SELECT id FROM questions';
    List<dynamic> idQueryArgs = [];
    List<String> whereConditions = [];

    // 添加排除已掌握題目的條件（如果提供）
    if (skipMastered && masteredQuestionIds.isNotEmpty) {
      final masteredPlaceholders =
          masteredQuestionIds.map((_) => '?').join(',');
      whereConditions.add('id NOT IN ($masteredPlaceholders)');
      idQueryArgs.addAll(masteredQuestionIds);
    }

    // 添加排除已加載題目的條件（如果提供）
    if (excludeIds.isNotEmpty) {
      final excludePlaceholders = excludeIds.map((_) => '?').join(',');
      whereConditions.add('id NOT IN ($excludePlaceholders)');
      idQueryArgs.addAll(excludeIds);
    }

    // 組合 WHERE 條件
    if (whereConditions.isNotEmpty) {
      idQuery += ' WHERE ${whereConditions.join(' AND ')}';
    }

    // **關鍵：使用 ORDER BY RANDOM() 實現真隨機**
    // 獲取 count * 2 個隨機ID（預留空間，因為可能有些題目在後續步驟中被過濾）
    idQuery += ' ORDER BY RANDOM() LIMIT ?';
    idQueryArgs.add(count * 2);

    // 執行查詢，只獲取ID列表（快速）
    final questionIds = await db.rawQuery(idQuery, idQueryArgs);

    if (questionIds.isEmpty) return [];

    // 步驟3：提取ID列表並再次過濾（雙重保險）
    final ids = questionIds
        .map((row) => row['id'] as String)
        .where((id) =>
            !excludeIds.contains(id) && !masteredQuestionIds.contains(id))
        .toList();

    // **雙重保險：在Dart層面再次打亂，確保完全隨機**
    ids.shuffle();
    final selectedIds = ids.take(count).toList();

    if (selectedIds.isEmpty) return [];

    // 步驟4：批量獲取題目（使用批量JOIN查詢，一次性獲取所有題目的完整數據）
    final placeholders = selectedIds.map((_) => '?').join(',');
    final questionsMap = await db.rawQuery('''
      SELECT
        q.id,
        q.img,
        q.answer,
        q.chapter,
        q.keywords_json,
        -- 意大利語題目和解析
        it_q.content as question_it,
        it_e.content as explanation_it,
        -- 翻譯語言題目和解析
        trans_q.content as question_trans,
        trans_e.content as explanation_trans
      FROM questions q
      LEFT JOIN translations it_q ON q.id = it_q.question_id AND it_q.lang = 'it' AND it_q.type = 'q'
      LEFT JOIN translations it_e ON q.id = it_e.question_id AND it_e.lang = 'it' AND it_e.type = 'e'
      LEFT JOIN translations trans_q ON q.id = trans_q.question_id AND trans_q.lang = ? AND trans_q.type = 'q'
      LEFT JOIN translations trans_e ON q.id = trans_e.question_id AND trans_e.lang = ? AND trans_e.type = 'e'
      WHERE q.id IN ($placeholders)
      -- 注意：這裡不排序，保持隨機順序
    ''', [translationLang, translationLang, ...selectedIds]);

    // 步驟5：構建 Question 對象列表
    final questions = <Question>[];
    for (final row in questionsMap) {
      try {
        final questionMap = {
          'id': row['id'],
          'img': row['img'],
          'answer': row['answer'],
          'question': row['question_it'], // 意大利語題目
          'explanation': row['explanation_it'], // 意大利語解析
          'question_trans': row['question_trans'], // 翻譯語言題目
          'explanation_trans': row['explanation_trans'], // 翻譯語言解析
          'chapter': row['chapter'],
          'keywords_json': row['keywords_json'],
        };

        final question =
            Question.fromMapWithTranslation(questionMap, 'it', translationLang);
        questions.add(question);
      } catch (e) {
        _debugLog('⚠️ [DatabaseService] 構建題目對象失敗: ${row['id']}, 錯誤: $e');
      }
    }

    // **雙重保險：在返回前再次打亂，確保完全隨機分佈**
    questions.shuffle();

    return questions;
  }

  /// 從指定章節獲取題目列表
  /// [chapterId] 章節ID（1-25）
  /// [skipMastered] 是否跳過已掌握的題目（is_mastered = 1），默認為 false
  /// [translationLang] 翻譯語言代碼（默認為當前語言）
  ///
  /// 注意：此方法用於章節練習模式，支持過濾已掌握的題目。
  /// 如果 skipMastered 為 true，則只返回未掌握的題目。
  static Future<List<Question>> getQuestionsByChapter(
    int chapterId, {
    bool skipMastered = false,
    String translationLang = 'zh',
    String? userId,
  }) async {
    _debugLog(
        '🔍 [DatabaseService] 正在查詢章節 ID: $chapterId, skipMastered: $skipMastered, translationLang: $translationLang');

    final db = await database;
    final normalizedUserId = _normalizeUserId(userId);

    // 查詢該章節的所有題目ID
    _debugLog(
        '📝 [DatabaseService] 執行 SQL 查詢: SELECT id FROM questions WHERE chapter = $chapterId AND chapter IS NOT NULL');
    final List<Map<String, dynamic>> questionIds = await db.rawQuery('''
      SELECT id FROM questions WHERE chapter = ? AND chapter IS NOT NULL
    ''', [chapterId]);

    _debugLog('📊 [DatabaseService] 查詢結果：找到 ${questionIds.length} 道題目');
    if (questionIds.isEmpty) {
      _debugLog('⚠️ [DatabaseService] 章節 $chapterId 沒有找到任何題目！');
      // 調試：檢查是否有其他章節有題目
      final debugResult = await db.rawQuery(
          'SELECT COUNT(*) as count FROM questions WHERE chapter IS NOT NULL');
      final totalWithChapter = debugResult.first['count'] as int? ?? 0;
      _debugLog('📊 [DatabaseService] 數據庫中總共有 $totalWithChapter 道題目有章節信息');

      // 檢查章節字段是否存在
      final tableInfo = await db.rawQuery('PRAGMA table_info(questions)');
      final hasChapterField =
          tableInfo.any((column) => column['name'] == 'chapter');
      _debugLog(
          '📋 [DatabaseService] questions 表是否有 chapter 字段: $hasChapterField');

      // 檢查該章節的所有可能值
      if (totalWithChapter > 0) {
        final sampleResult = await db.rawQuery(
            'SELECT DISTINCT chapter FROM questions WHERE chapter IS NOT NULL ORDER BY chapter LIMIT 10');
        final sampleChapters =
            sampleResult.map((row) => row['chapter']).toList();
        _debugLog('📋 [DatabaseService] 數據庫中的章節範例: $sampleChapters');
      }

      return [];
    }

    // 如果需要跳過已掌握的題目，查詢 user_progress 表
    Set<String> masteredQuestionIds = {};
    if (skipMastered) {
      final userProgressDb = await userProgressDatabase;
      final placeholders = questionIds.map((_) => '?').join(',');
      final ids = questionIds.map((row) => row['id'] as String).toList();

      final masteredResults = await userProgressDb.rawQuery('''
        SELECT question_id
        FROM user_progress
        WHERE question_id IN ($placeholders) AND is_mastered = 1 AND user_id = ?
      ''', [...ids, normalizedUserId]);

      masteredQuestionIds =
          masteredResults.map((row) => row['question_id'] as String).toSet();
    }

    // 優化：如果跳過已掌握，先過濾 ID 列表，減少後續查詢量
    final filteredQuestionIds = skipMastered
        ? questionIds
            .map((row) => row['id'] as String)
            .where((id) => !masteredQuestionIds.contains(id))
            .toList()
        : questionIds.map((row) => row['id'] as String).toList();

    if (filteredQuestionIds.isEmpty) {
      _debugLog('✅ [DatabaseService] 章節 $chapterId 所有題目都已掌握，返回空列表');
      return [];
    }

    // 使用批量 JOIN 查詢一次性獲取所有題目的翻譯（優化性能）
    // 避免在循環中逐個查詢，減少數據庫往返次數
    final placeholders = filteredQuestionIds.map((_) => '?').join(',');
    _debugLog(
        '📝 [DatabaseService] 執行批量查詢，獲取 ${filteredQuestionIds.length} 道題目的翻譯...');

    final questionsMap = await db.rawQuery('''
      SELECT
        q.id,
        q.img,
        q.answer,
        q.chapter,
        q.keywords_json,
        -- 意大利語題目和解析
        it_q.content as question_it,
        it_e.content as explanation_it,
        -- 翻譯語言題目和解析
        trans_q.content as question_trans,
        trans_e.content as explanation_trans
      FROM questions q
      LEFT JOIN translations it_q ON q.id = it_q.question_id AND it_q.lang = 'it' AND it_q.type = 'q'
      LEFT JOIN translations it_e ON q.id = it_e.question_id AND it_e.lang = 'it' AND it_e.type = 'e'
      LEFT JOIN translations trans_q ON q.id = trans_q.question_id AND trans_q.lang = ? AND trans_q.type = 'q'
      LEFT JOIN translations trans_e ON q.id = trans_e.question_id AND trans_e.lang = ? AND trans_e.type = 'e'
      WHERE q.id IN ($placeholders) AND q.chapter = ?
      ORDER BY q.id
    ''', [translationLang, translationLang, ...filteredQuestionIds, chapterId]);

    _debugLog('📊 [DatabaseService] 批量查詢完成，獲取 ${questionsMap.length} 道題目的數據');

    // 構建 Question 對象列表
    final questions = <Question>[];
    for (final row in questionsMap) {
      try {
        final questionMap = {
          'id': row['id'],
          'img': row['img'],
          'answer': row['answer'],
          'question': row['question_it'], // 意大利語題目
          'explanation': row['explanation_it'], // 意大利語解析
          'question_trans': row['question_trans'], // 翻譯語言題目
          'explanation_trans': row['explanation_trans'], // 翻譯語言解析
          'chapter': row['chapter'],
          'keywords_json': row['keywords_json'], // 重點詞彙 JSON 數據
        };

        final question = Question.fromMapWithTranslation(
          questionMap,
          'it',
          translationLang,
        );
        questions.add(question);
      } catch (e) {
        _debugLog('⚠️ [DatabaseService] 解析題目失敗: ${row['id']}, 錯誤: $e');
      }
    }

    final skippedCount =
        skipMastered ? questionIds.length - filteredQuestionIds.length : 0;
    _debugLog(
        '✅ [DatabaseService] 章節 $chapterId 最終返回 ${questions.length} 道題目 (跳過已掌握: $skippedCount, 加載失敗: ${filteredQuestionIds.length - questions.length})');
    return questions;
  }

  /// 從指定章節隨機獲取一道題目（包含意大利語和翻譯）
  /// [chapterId] 章節ID（1-25）
  /// [skipMastered] 是否跳過已掌握的題目（is_mastered = 1），默認為 false
  /// [translationLang] 翻譯語言代碼（默認為當前語言）
  static Future<Question?> getRandomQuestionFromChapter(
    int chapterId, {
    bool skipMastered = false,
    String translationLang = 'zh',
    String? userId,
  }) async {
    _debugLog('🎲 [DatabaseService] 從章節 $chapterId 隨機獲取一道題目');

    final questions = await getQuestionsByChapter(
      chapterId,
      skipMastered: skipMastered,
      translationLang: translationLang,
      userId: userId,
    );

    if (questions.isEmpty) {
      _debugLog('❌ [DatabaseService] 章節 $chapterId 沒有可用題目');
      return null;
    }

    // 隨機選擇一道題目
    questions.shuffle();
    final selectedQuestion = questions.first;
    _debugLog('✅ [DatabaseService] 成功選中題目 ID: ${selectedQuestion.id}');
    return selectedQuestion;
  }

  /// 獲取模擬考試題目（嚴格執行意大利交通部30題抽題規則）
  /// 算法邏輯：
  /// 1. 全覆蓋步：從1-25章節各隨機抽取1題（共25題）
  /// 2. 權重加權步：從1-15重點章節中隨機選5個不同章節，每個章節再隨機抽取1題（共5題）
  /// 3. 去重處理：如果第二步抽取的題目在第一步中已抽取，自動重新抽取
  /// 4. 組合與打亂：將30題組合並隨機打亂順序
  /// 重要：禁止使用 chapter IS NULL 的題目
  /// [translationLang] 翻譯語言代碼（默認為當前語言）
  /// 返回值：始終返回30題（如果題庫足夠），如果題庫不足30題則返回所有可用題目
  static Future<List<Question>> getMockTestQuestions(
      {String translationLang = 'zh'}) async {
    const int targetQuestionCount = 30;
    final db = await database;
    final selectedQuestionIds = <String>[]; // 最終選中的題目ID列表
    final usedQuestionIds = <String>{}; // 已使用的題目ID集合（用於去重）

    try {
      // ========== 步驟1：全覆蓋步（從1-25章節各抽取1題） ==========
      // 一次性查詢所有章節的題目ID（排除 chapter IS NULL）
      final List<Map<String, dynamic>> allChapterQuestions =
          await db.rawQuery('''
        SELECT id, chapter
        FROM questions
        WHERE chapter IS NOT NULL AND chapter BETWEEN 1 AND 25
        ORDER BY chapter, id
      ''');

      // 按章節分組題目ID
      final Map<int, List<String>> questionsByChapter = {};
      for (final row in allChapterQuestions) {
        final chapterId = row['chapter'] as int;
        final questionId = row['id'] as String;
        questionsByChapter.putIfAbsent(chapterId, () => []).add(questionId);
      }

      // 從每個章節（1-25）隨機抽取1題
      for (int chapterId = 1; chapterId <= 25; chapterId++) {
        final chapterQuestions = questionsByChapter[chapterId];
        if (chapterQuestions != null && chapterQuestions.isNotEmpty) {
          // 過濾掉已使用的題目ID
          final availableQuestions = chapterQuestions
              .where((id) => !usedQuestionIds.contains(id))
              .toList();

          if (availableQuestions.isNotEmpty) {
            // 隨機選擇一道題目
            availableQuestions.shuffle();
            final selectedId = availableQuestions.first;
            selectedQuestionIds.add(selectedId);
            usedQuestionIds.add(selectedId);
          }
        }
      }

      // ========== 步驟2：權重加權步（從1-15重點章節中選5個，每個再抽1題） ==========
      // 創建1-15的重點章節列表
      final principalChapters = List.generate(15, (index) => index + 1);

      // 隨機打亂並選取5個不同的重點章節
      principalChapters.shuffle();
      final selectedChapters = principalChapters.take(5).toList();

      // 從這5個章節中各抽取1題（確保不重複）
      for (final chapterId in selectedChapters) {
        final chapterQuestions = questionsByChapter[chapterId];
        if (chapterQuestions != null && chapterQuestions.isNotEmpty) {
          // 過濾掉已使用的題目ID
          final availableQuestions = chapterQuestions
              .where((id) => !usedQuestionIds.contains(id))
              .toList();

          // 如果該章節還有可用題目，隨機選擇一道
          if (availableQuestions.isNotEmpty) {
            availableQuestions.shuffle();
            final selectedId = availableQuestions.first;
            selectedQuestionIds.add(selectedId);
            usedQuestionIds.add(selectedId);
          }
        }
      }

      // ========== 步驟3：驗證題目數量 ==========
      if (selectedQuestionIds.length < targetQuestionCount) {
        _debugLog(
            '⚠️ [DatabaseService] 無法獲取足夠的題目：僅獲取到 ${selectedQuestionIds.length} 題（目標：$targetQuestionCount 題）');
        // 如果題庫不足，返回已獲取的題目
      }

      // ========== 步驟4：批量獲取題目完整信息（包含翻譯） ==========
      // 使用 getQuestionsByIds 批量獲取題目（但這個方法只支持單語言，需要改用其他方式）
      // 為了支持雙語言（意大利語+翻譯語言），我們使用 getQuestionWithTranslation
      final questions = <Question>[];
      for (final questionId in selectedQuestionIds) {
        final question = await getQuestionWithTranslation(questionId,
            translationLang: translationLang);
        if (question != null) {
          questions.add(question);
        }
      }

      // ========== 步驟5：組合與打亂 ==========
      // 隨機打亂所有題目的順序，確保用戶不會發現題目是按章節排列的
      questions.shuffle();

      // ========== 步驟6：輸出日誌 ==========
      final weightedChaptersList = selectedChapters.toList()..sort();
      _debugLog(
          '✅ [DatabaseService] 考試生成成功：覆蓋了 25 個章節，加權了章節 $weightedChaptersList');

      return questions;
    } catch (e) {
      _debugLog('❌ [DatabaseService] getMockTestQuestions 出錯: $e');
      // 如果出現錯誤，返回空列表（調用方應該檢查並處理）
      return [];
    }
  }

  /// 根據題目ID獲取題目
  static Future<Question?> getQuestionById(String id,
      {String lang = 'zh'}) async {
    final db = await database;

    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT
        q.id,
        q.img,
        q.answer,
        q.keywords_json,
        t_q.content as question,
        t_e.content as explanation
      FROM questions q
      LEFT JOIN translations t_q ON q.id = t_q.question_id AND t_q.lang = ? AND t_q.type = 'q'
      LEFT JOIN translations t_e ON q.id = t_e.question_id AND t_e.lang = ? AND t_e.type = 'e'
      WHERE q.id = ?
    ''', [lang, lang, id]);

    if (maps.isEmpty) return null;
    return Question.fromMap(maps.first, lang);
  }

  /// 根據題目ID獲取題目，同時包含意大利語和指定語言的翻譯
  /// [id] 題目ID
  /// [translationLang] 翻譯語言代碼（默認為當前語言）
  static Future<Question?> getQuestionWithTranslation(String id,
      {String translationLang = 'zh'}) async {
    final db = await database;

    // 查詢意大利語內容
    final List<Map<String, dynamic>> itMaps = await db.rawQuery('''
      SELECT
        q.id,
        q.img,
        q.answer,
        q.chapter,
        t_q.content as question_it,
        t_e.content as explanation_it
      FROM questions q
      LEFT JOIN translations t_q ON q.id = t_q.question_id AND t_q.lang = 'it' AND t_q.type = 'q'
      LEFT JOIN translations t_e ON q.id = t_e.question_id AND t_e.lang = 'it' AND t_e.type = 'e'
      WHERE q.id = ?
    ''', [id]);

    if (itMaps.isEmpty) return null;

    final itMap = itMaps.first;

    // 如果翻譯語言是意大利語，直接返回意大利語內容
    if (translationLang == 'it') {
      return Question.fromMap({
        'id': itMap['id'],
        'img': itMap['img'],
        'answer': itMap['answer'],
        'question': itMap['question_it'] ?? '',
        'explanation': itMap['explanation_it'] ?? '',
        'chapter': itMap['chapter'],
      }, 'it');
    }

    // 查詢翻譯語言的內容
    final List<Map<String, dynamic>> translationMaps = await db.rawQuery('''
      SELECT
        t_q.content as question_trans,
        t_e.content as explanation_trans
      FROM questions q
      LEFT JOIN translations t_q ON q.id = t_q.question_id AND t_q.lang = ? AND t_q.type = 'q'
      LEFT JOIN translations t_e ON q.id = t_e.question_id AND t_e.lang = ? AND t_e.type = 'e'
      WHERE q.id = ?
    ''', [translationLang, translationLang, id]);

    final translationMap =
        translationMaps.isNotEmpty ? translationMaps.first : null;

    // 構建包含兩種語言的 Question 對象
    final questionMap = <String, dynamic>{
      'id': itMap['id'],
      'img': itMap['img'],
      'answer': itMap['answer'],
      'question': itMap['question_it'] ?? '', // 意大利語題目
      'explanation': itMap['explanation_it'] ?? '', // 意大利語解析
      'question_trans': translationMap?['question_trans'], // 翻譯語言題目
      'explanation_trans': translationMap?['explanation_trans'], // 翻譯語言解析
      'chapter': itMap['chapter'], // 章節ID
    };

    return Question.fromMapWithTranslation(questionMap, 'it', translationLang);
  }

  // ========== 用戶進度相關方法 ==========

  /// 更新題目進度（統一方法）
  /// [questionId] 題目ID（String類型）
  /// [isCorrect] 是否答對
  ///
  /// 邏輯：
  /// - 如果答對：correct_streak + 1，如果達到 3 則設置 is_mastered = 1
  /// - 如果答錯：correct_streak 重置為 0，is_mastered 設為 0，wrong_count + 1
  ///
  /// 返回：是否剛剛達成掌握（is_mastered 從 0 變為 1）
  /// 使用事務確保操作的原子性
  static Future<bool> updateQuestionProgress(
    String questionId,
    bool isCorrect, {
    required String userId,
  }) async {
    final db = await userProgressDatabase;
    final normalizedUserId = _normalizeUserId(userId);

    bool newlyMastered = false;

    // 使用事務確保操作的原子性
    await db.transaction((txn) async {
      // 1. 首先查詢當前的 correct_streak、is_mastered 和 wrong_count
      final result = await txn.query(
        'user_progress',
        columns: ['correct_streak', 'is_mastered', 'wrong_count'],
        where: 'question_id = ? AND user_id = ?',
        whereArgs: [questionId, normalizedUserId],
      );

      final currentStreak =
          result.isEmpty ? 0 : (result.first['correct_streak'] as int? ?? 0);
      final currentIsMastered =
          result.isEmpty ? 0 : (result.first['is_mastered'] as int? ?? 0);
      final currentWrongCount =
          result.isEmpty ? 0 : (result.first['wrong_count'] as int? ?? 0);

      if (isCorrect) {
        // 2. 答對了：correct_streak + 1，total_attempts + 1
        final newStreak = currentStreak + 1;
        // 如果達到 3，設置 is_mastered = 1
        final shouldMaster = newStreak >= 3;
        // 如果從未掌握變為掌握，標記為剛剛達成掌握
        newlyMastered = shouldMaster && currentIsMastered == 0;

        // 🔄 統一邏輯：如果 wrong_count > 0，自動減少 1
        final newWrongCount = currentWrongCount > 0 ? currentWrongCount - 1 : 0;

        await txn.rawInsert('''
          INSERT INTO user_progress (question_id, user_id, correct_streak, is_mastered, wrong_count, total_attempts, last_practiced)
          VALUES (?, ?, ?, ?, ?, 1, strftime('%s', 'now'))
          ON CONFLICT(question_id, user_id) DO UPDATE SET
            correct_streak = ?,
            is_mastered = ?,
            wrong_count = CASE
              WHEN wrong_count > 0 THEN wrong_count - 1
              ELSE 0
            END,
            total_attempts = total_attempts + 1,
            last_practiced = strftime('%s', 'now')
        ''', [
          questionId,
          normalizedUserId,
          newStreak,
          shouldMaster ? 1 : 0,
          newWrongCount,
          newStreak,
          shouldMaster ? 1 : 0
        ]);
      } else {
        // 3. 答錯了：correct_streak 重置為 0，is_mastered 設為 0，wrong_count + 1，total_attempts + 1
        await txn.rawInsert('''
          INSERT INTO user_progress (question_id, user_id, error_count, wrong_count, correct_streak, is_mastered, total_attempts, last_practiced)
          VALUES (?, ?, 1, 1, 0, 0, 1, strftime('%s', 'now'))
          ON CONFLICT(question_id, user_id) DO UPDATE SET
            error_count = error_count + 1,
            wrong_count = wrong_count + 1,
            correct_streak = 0,
            is_mastered = 0,
            total_attempts = total_attempts + 1,
            last_practiced = strftime('%s', 'now')
        ''', [questionId, normalizedUserId]);
        newlyMastered = false;
      }
    });

    return newlyMastered;
  }

  /// 記錄題目正確（練習模式）
  /// [questionId] 題目ID
  /// 增加 correct_streak，如果 >= 3 則自動標記為已掌握
  static Future<void> recordCorrectAnswer(String questionId,
      {required String userId}) async {
    final db = await userProgressDatabase;
    final normalizedUserId = _normalizeUserId(userId);

    // 先查詢當前的 correct_streak
    final result = await db.query(
      'user_progress',
      columns: ['correct_streak'],
      where: 'question_id = ? AND user_id = ?',
      whereArgs: [questionId, normalizedUserId],
    );

    final currentStreak =
        result.isEmpty ? 0 : (result.first['correct_streak'] as int? ?? 0);
    final newStreak = currentStreak + 1;

    // 如果連續答對 >= 3 次，標記為已掌握
    final shouldMaster = newStreak >= 3;

    await db.rawInsert('''
      INSERT INTO user_progress (question_id, user_id, correct_streak, is_mastered, last_practiced)
      VALUES (?, ?, ?, ?, strftime('%s', 'now'))
      ON CONFLICT(question_id, user_id) DO UPDATE SET
        correct_streak = ?,
        is_mastered = ?,
        last_practiced = strftime('%s', 'now')
    ''', [
      questionId,
      normalizedUserId,
      newStreak,
      shouldMaster ? 1 : 0,
      newStreak,
      shouldMaster ? 1 : 0
    ]);
  }

  /// 記錄題目錯誤（練習模式）
  /// [questionId] 題目ID
  /// correct_streak 歸零，取消已掌握標記，增加錯誤計數和錯題計數
  static Future<void> recordError(String questionId,
      {required String userId}) async {
    final db = await userProgressDatabase;
    final normalizedUserId = _normalizeUserId(userId);

    await db.rawInsert('''
      INSERT INTO user_progress (question_id, user_id, error_count, wrong_count, correct_streak, is_mastered, last_practiced)
      VALUES (?, ?, 1, 1, 0, 0, strftime('%s', 'now'))
      ON CONFLICT(question_id, user_id) DO UPDATE SET
        error_count = error_count + 1,
        wrong_count = wrong_count + 1,
        correct_streak = 0,
        is_mastered = 0,
        last_practiced = strftime('%s', 'now')
    ''', [questionId, normalizedUserId]);
  }

  /// 記錄題目錯誤（模擬考試模式）
  /// [questionId] 題目ID
  /// 只記錄錯誤計數和錯題計數，不影響 correct_streak（因為考試是檢測，不是學習）
  static Future<void> recordErrorInExam(String questionId,
      {required String userId}) async {
    final db = await userProgressDatabase;
    final normalizedUserId = _normalizeUserId(userId);

    await db.rawInsert('''
      INSERT INTO user_progress (question_id, user_id, error_count, wrong_count, last_practiced)
      VALUES (?, ?, 1, 1, strftime('%s', 'now'))
      ON CONFLICT(question_id, user_id) DO UPDATE SET
        error_count = error_count + 1,
        wrong_count = wrong_count + 1,
        last_practiced = strftime('%s', 'now')
    ''', [questionId, normalizedUserId]);
  }

  /// 更新練習進度（記錄用戶完成一道題）
  /// [questionId] 題目ID
  /// 異步更新 last_practiced 字段
  static Future<void> updatePracticeProgress(String questionId,
      {required String userId}) async {
    final db = await userProgressDatabase;
    final normalizedUserId = _normalizeUserId(userId);

    // 異步更新 last_practiced 字段，如果記錄不存在則創建
    await db.rawInsert('''
      INSERT INTO user_progress (question_id, user_id, last_practiced)
      VALUES (?, ?, strftime('%s', 'now'))
      ON CONFLICT(question_id, user_id) DO UPDATE SET
        last_practiced = strftime('%s', 'now')
    ''', [questionId, normalizedUserId]);
  }

  /// 標記題目為已掌握
  /// [questionId] 題目ID
  static Future<void> markAsMastered(String questionId,
      {required String userId}) async {
    final db = await userProgressDatabase;
    final normalizedUserId = _normalizeUserId(userId);

    await db.rawInsert('''
      INSERT INTO user_progress (question_id, user_id, is_mastered, last_practiced)
      VALUES (?, ?, 1, strftime('%s', 'now'))
      ON CONFLICT(question_id, user_id) DO UPDATE SET
        is_mastered = 1,
        last_practiced = strftime('%s', 'now')
    ''', [questionId, normalizedUserId]);
  }

  /// 檢查題目是否已經精通
  /// [questionId] 題目ID
  /// [userId] 用戶ID
  /// 返回 true 表示該題目已經精通（is_mastered = 1）
  static Future<bool> isQuestionMastered(String questionId,
      {required String userId}) async {
    final db = await userProgressDatabase;
    final normalizedUserId = _normalizeUserId(userId);

    final result = await db.query(
      'user_progress',
      columns: ['is_mastered'],
      where: 'question_id = ? AND user_id = ?',
      whereArgs: [questionId, normalizedUserId],
    );

    if (result.isEmpty) {
      return false; // 沒有記錄，表示未精通
    }

    final isMastered = result.first['is_mastered'] as int? ?? 0;
    return isMastered == 1;
  }

  /// 取消題目的已掌握標記
  /// [questionId] 題目ID
  static Future<void> unmarkAsMastered(String questionId,
      {required String userId}) async {
    final db = await userProgressDatabase;
    final normalizedUserId = _normalizeUserId(userId);

    await db.update(
      'user_progress',
      {'is_mastered': 0},
      where: 'question_id = ? AND user_id = ?',
      whereArgs: [questionId, normalizedUserId],
    );
  }

  /// 切換收藏狀態
  static Future<void> toggleFavorite(String questionId,
      {required String userId}) async {
    final db = await userProgressDatabase;
    final normalizedUserId = _normalizeUserId(userId);

    // 先查詢當前狀態
    final result = await db.query(
      'user_progress',
      where: 'question_id = ? AND user_id = ?',
      whereArgs: [questionId, normalizedUserId],
    );

    final newFavoriteStatus =
        result.isEmpty || (result.first['is_favorite'] as int) == 0 ? 1 : 0;

    await db.rawInsert('''
      INSERT INTO user_progress (question_id, user_id, is_favorite, last_practiced)
      VALUES (?, ?, ?, strftime('%s', 'now'))
      ON CONFLICT(question_id, user_id) DO UPDATE SET
        is_favorite = ?,
        last_practiced = strftime('%s', 'now')
    ''', [questionId, normalizedUserId, newFavoriteStatus, newFavoriteStatus]);
  }

  /// 獲取題目的收藏狀態
  static Future<bool> isFavorite(String questionId,
      {required String userId}) async {
    final db = await userProgressDatabase;
    final normalizedUserId = _normalizeUserId(userId);

    final result = await db.query(
      'user_progress',
      columns: ['is_favorite'],
      where: 'question_id = ? AND user_id = ?',
      whereArgs: [questionId, normalizedUserId],
    );

    if (result.isEmpty) return false;
    return (result.first['is_favorite'] as int) == 1;
  }

  /// 獲取題目的錯誤次數
  static Future<int> getErrorCount(String questionId,
      {required String userId}) async {
    final db = await userProgressDatabase;
    final normalizedUserId = _normalizeUserId(userId);

    final result = await db.query(
      'user_progress',
      columns: ['error_count'],
      where: 'question_id = ? AND user_id = ?',
      whereArgs: [questionId, normalizedUserId],
    );

    if (result.isEmpty) return 0;
    return result.first['error_count'] as int;
  }

  /// 獲取所有收藏的題目ID列表
  static Future<List<String>> getFavoriteQuestionIds(
      {required String userId}) async {
    final db = await userProgressDatabase;
    final normalizedUserId = _normalizeUserId(userId);

    final result = await db.query(
      'user_progress',
      columns: ['question_id'],
      where: 'is_favorite = ? AND user_id = ?',
      whereArgs: [1, normalizedUserId],
    );

    return result.map((row) => row['question_id'] as String).toList();
  }

  /// 獲取總題目數
  static Future<int> getTotalQuestionsCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM questions');
    return (result.first['count'] as int?) ?? 0;
  }

  /// 獲取已練習過的題目數（有記錄的題目）
  static Future<int> getAnsweredQuestionsCount({required String userId}) async {
    final db = await userProgressDatabase;
    final normalizedUserId = _normalizeUserId(userId);
    final result = await db.rawQuery(
      'SELECT COUNT(DISTINCT question_id) as count FROM user_progress WHERE last_practiced IS NOT NULL AND user_id = ?',
      [normalizedUserId],
    );
    return (result.first['count'] as int?) ?? 0;
  }

  /// 獲取模擬考試最好成績（最少錯誤次數）
  /// 返回最少錯誤次數，如果沒有成績則返回 null
  static Future<int?> getBestMockTestScore() async {
    // 注意：目前數據庫中沒有專門存儲模擬考試成績的表
    // 這裡可以通過 user_progress 表中的 error_count 來估算
    // 或者未來可以添加一個專門的 mock_test_results 表
    // 暫時返回 null，表示還沒有成績記錄
    return null;
  }

  /// 獲取錯誤題目的章節分布統計
  /// [errorQuestionIds] 錯誤題目的ID列表
  /// 返回 Map<章節ID, 錯誤數量>
  static Future<Map<int, int>> getChapterErrorDistribution(
      List<String> errorQuestionIds) async {
    if (errorQuestionIds.isEmpty) return {};

    final db = await database;

    // 構建 IN 查詢條件
    final placeholders = errorQuestionIds.map((_) => '?').join(',');

    final result = await db.rawQuery('''
      SELECT
        chapter,
        COUNT(*) as error_count
      FROM questions
      WHERE id IN ($placeholders) AND chapter IS NOT NULL
      GROUP BY chapter
      ORDER BY error_count DESC
    ''', errorQuestionIds);

    final distribution = <int, int>{};
    for (final row in result) {
      final chapterId = row['chapter'] as int?;
      final count = row['error_count'] as int?;
      if (chapterId != null && count != null) {
        distribution[chapterId] = count;
      }
    }

    return distribution;
  }

  /// 統計 25 個章節的掌握度數據
  /// 返回 Map<章節ID, {total, attempted, accuracy}>
  /// - total: 該章節總題數
  /// - attempted: 至少做過一次的題目數（total_attempts > 0）
  /// - accuracy: 正確率（所有題目的正確次數總和 / 嘗試次數總和），範圍 0.0 - 1.0
  static Future<Map<int, Map<String, dynamic>>> getChapterMasteryStats({
    required String userId,
  }) async {
    final db = await database;
    final userProgressDb = await userProgressDatabase;
    final normalizedUserId = _normalizeUserId(userId);

    // 1. 從主題庫獲取所有帶章節的題目，建立 questionId -> chapter 映射
    final questionRows = await db.rawQuery(
      'SELECT id, chapter FROM questions WHERE chapter IS NOT NULL',
    );

    final Map<String, int> questionChapter = {};
    final Map<int, int> chapterTotal = {};

    for (final row in questionRows) {
      final idValue = row['id'];
      final chapterValue = row['chapter'] as int?;
      if (idValue == null || chapterValue == null) continue;
      final questionId = idValue.toString();
      questionChapter[questionId] = chapterValue;
      chapterTotal[chapterValue] = (chapterTotal[chapterValue] ?? 0) + 1;
    }

    if (questionChapter.isEmpty) {
      return {};
    }

    // 2. 從用戶進度庫獲取當前用戶所有有嘗試記錄的題目
    final progressRows = await userProgressDb.rawQuery('''
      SELECT question_id, total_attempts, wrong_count
      FROM user_progress
      WHERE user_id = ? AND total_attempts > 0
    ''', [normalizedUserId]);

    final Map<int, int> chapterAttempted = {};
    final Map<int, int> chapterTotalAttempts = {};
    final Map<int, int> chapterCorrectAttempts = {};

    for (final row in progressRows) {
      final questionId = row['question_id'] as String?;
      if (questionId == null) continue;
      final chapterId = questionChapter[questionId];
      if (chapterId == null) continue; // 可能是已刪除或無章節信息的題目

      final totalAttempts = (row['total_attempts'] as int?) ?? 0;
      final wrongCount = (row['wrong_count'] as int?) ?? 0;
      if (totalAttempts <= 0) continue;

      chapterAttempted[chapterId] = (chapterAttempted[chapterId] ?? 0) + 1;
      chapterTotalAttempts[chapterId] =
          (chapterTotalAttempts[chapterId] ?? 0) + totalAttempts;

      var correctAttempts = totalAttempts - wrongCount;
      if (correctAttempts < 0) {
        correctAttempts = 0;
      }
      chapterCorrectAttempts[chapterId] =
          (chapterCorrectAttempts[chapterId] ?? 0) + correctAttempts;
    }

    // 3. 彙總為結果結構
    final Map<int, Map<String, dynamic>> result = {};
    chapterTotal.forEach((chapterId, total) {
      final attempted = chapterAttempted[chapterId] ?? 0;
      final totalAttempts = chapterTotalAttempts[chapterId] ?? 0;
      final correctAttempts = chapterCorrectAttempts[chapterId] ?? 0;

      double accuracy = 0.0;
      if (totalAttempts > 0) {
        accuracy = correctAttempts / totalAttempts;
      }

      result[chapterId] = {
        'total': total,
        'attempted': attempted,
        'accuracy': accuracy,
      };
    });

    return result;
  }

  /// 保存本次模擬考結果到 mock_exam_results 表
  /// [userId] 當前用戶 ID
  /// [correctCount] 正確題數
  /// [wrongCount] 錯誤題數
  /// [totalQuestions] 總題數
  /// [timeUsedSeconds] 用時（秒），可選
  static Future<void> saveMockTestResult({
    required String userId,
    required int correctCount,
    required int wrongCount,
    required int totalQuestions,
    int? timeUsedSeconds,
  }) async {
    final db = await userProgressDatabase;
    final normalizedUserId = _normalizeUserId(userId);
    await db.insert(
      'mock_exam_results',
      {
        'user_id': normalizedUserId,
        'correct_count': correctCount,
        'wrong_count': wrongCount,
        'total_questions': totalQuestions,
        'time_used_seconds': timeUsedSeconds,
        'taken_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      },
    );
  }

  /// 獲取最近 10 次模擬考成績（按時間倒序）
  /// 返回列表元素包含：correct, wrong, total, timestamp（UNIX 秒）
  static Future<List<Map<String, dynamic>>> getMockExamHistory({
    required String userId,
  }) async {
    final db = await userProgressDatabase;
    final normalizedUserId = _normalizeUserId(userId);

    try {
      final rows = await db.rawQuery('''
        SELECT correct_count, wrong_count, total_questions, taken_at
        FROM mock_exam_results
        WHERE user_id = ?
        ORDER BY taken_at DESC
        LIMIT 10
      ''', [normalizedUserId]);

      return rows.map((row) {
        final correct = (row['correct_count'] as int?) ?? 0;
        final wrong = (row['wrong_count'] as int?) ?? 0;
        final total = (row['total_questions'] as int?) ?? (correct + wrong);
        return {
          'correct': correct,
          'wrong': wrong,
          'total': total,
          'timestamp': row['taken_at'],
        };
      }).toList();
    } catch (e, stackTrace) {
      _debugLog('⚠️ [DatabaseService] 讀取模擬考歷史失敗: $e');
      _debugLog('📋 [DatabaseService] 讀取模擬考歷史堆棧: $stackTrace');
      // 表不存在或其他錯誤時，返回空列表以避免影響主流程
      return [];
    }
  }

  /// 今日與昨日模擬考平均正確率（0.0～1.0），用於「較昨天提升」計算
  /// 若某日無數據，該日為 0.0
  static Future<Map<String, double>> getTodayYesterdayMockAccuracy({
    required String userId,
  }) async {
    final db = await userProgressDatabase;
    final normalizedUserId = _normalizeUserId(userId);
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final yesterdayStart = todayStart.subtract(const Duration(days: 1));
    final todayStartSec = todayStart.millisecondsSinceEpoch ~/ 1000;
    final yesterdayEndSec = todayStartSec - 1;
    final yesterdayStartSec = yesterdayStart.millisecondsSinceEpoch ~/ 1000;

    try {
      final rows = await db.rawQuery('''
        SELECT correct_count, total_questions, taken_at
        FROM mock_exam_results
        WHERE user_id = ? AND taken_at >= ?
        ORDER BY taken_at ASC
      ''', [normalizedUserId, yesterdayStartSec]);

      double todaySum = 0.0;
      int todayCount = 0;
      double yesterdaySum = 0.0;
      int yesterdayCount = 0;

      for (final row in rows) {
        final takenAt = row['taken_at'] as int?;
        if (takenAt == null) continue;
        final total = (row['total_questions'] as int?) ?? 0;
        if (total <= 0) continue;
        final correct = (row['correct_count'] as int?) ?? 0;
        final rate = correct / total;

        if (takenAt >= todayStartSec) {
          todaySum += rate;
          todayCount++;
        } else if (takenAt >= yesterdayStartSec && takenAt <= yesterdayEndSec) {
          yesterdaySum += rate;
          yesterdayCount++;
        }
      }

      return {
        'today': todayCount > 0 ? todaySum / todayCount : 0.0,
        'yesterday': yesterdayCount > 0 ? yesterdaySum / yesterdayCount : 0.0,
      };
    } catch (e) {
      _debugLog('⚠️ [DatabaseService] getTodayYesterdayMockAccuracy 失敗: $e');
      return {'today': 0.0, 'yesterday': 0.0};
    }
  }

  /// 今日與昨日模擬考平均錯題數（用於通過率預測公式中的 S）
  /// 某日無考試時該日為 null
  static Future<Map<String, double?>> getTodayYesterdayAverageWrong({
    required String userId,
  }) async {
    final db = await userProgressDatabase;
    final normalizedUserId = _normalizeUserId(userId);
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final yesterdayStart = todayStart.subtract(const Duration(days: 1));
    final todayStartSec = todayStart.millisecondsSinceEpoch ~/ 1000;
    final yesterdayEndSec = todayStartSec - 1;
    final yesterdayStartSec = yesterdayStart.millisecondsSinceEpoch ~/ 1000;

    try {
      final rows = await db.rawQuery('''
        SELECT wrong_count, taken_at
        FROM mock_exam_results
        WHERE user_id = ? AND taken_at >= ?
        ORDER BY taken_at ASC
      ''', [normalizedUserId, yesterdayStartSec]);

      double todaySum = 0.0;
      int todayCount = 0;
      double yesterdaySum = 0.0;
      int yesterdayCount = 0;

      for (final row in rows) {
        final takenAt = row['taken_at'] as int?;
        if (takenAt == null) continue;
        final wrong = (row['wrong_count'] as int?) ?? 0;

        if (takenAt >= todayStartSec) {
          todaySum += wrong;
          todayCount++;
        } else if (takenAt >= yesterdayStartSec && takenAt <= yesterdayEndSec) {
          yesterdaySum += wrong;
          yesterdayCount++;
        }
      }

      return {
        'today': todayCount > 0 ? todaySum / todayCount : null,
        'yesterday': yesterdayCount > 0 ? yesterdaySum / yesterdayCount : null,
      };
    } catch (e) {
      _debugLog('⚠️ [DatabaseService] getTodayYesterdayAverageWrong 失敗: $e');
      return {'today': null, 'yesterday': null};
    }
  }

  /// 找出錯題數量最多的前 N 個章節（默認 3 個）
  /// 返回列表元素包含：chapter（章節號）、errors（錯題數量）
  static Future<List<Map<String, int>>> getTopWeakChapters({
    required String userId,
    int limit = 3,
  }) async {
    // 先獲取當前用戶所有錯題ID
    final errorQuestionIds = await getErrorQuestionIds(userId: userId);
    if (errorQuestionIds.isEmpty) {
      return [];
    }

    // 使用現有的章節錯誤分佈工具方法
    final distribution = await getChapterErrorDistribution(errorQuestionIds);
    if (distribution.isEmpty) {
      return [];
    }

    final entries = distribution.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final top = entries.take(limit);
    return top.map((e) => {'chapter': e.key, 'errors': e.value}).toList();
  }

  /// 根據題目ID列表獲取題目列表（包含章節信息）
  /// [questionIds] 題目ID列表
  /// [lang] 語言代碼，默認為當前語言
  static Future<List<Question>> getQuestionsByIds(List<String> questionIds,
      {String lang = 'zh'}) async {
    if (questionIds.isEmpty) return [];

    final db = await database;

    // 構建 IN 查詢條件
    final placeholders = questionIds.map((_) => '?').join(',');

    final maps = await db.rawQuery('''
      SELECT
        q.id,
        q.img,
        q.answer,
        q.chapter,
        q.keywords_json,
        t_q.content as question,
        t_e.content as explanation
      FROM questions q
      LEFT JOIN translations t_q ON q.id = t_q.question_id AND t_q.lang = ? AND t_q.type = 'q'
      LEFT JOIN translations t_e ON q.id = t_e.question_id AND t_e.lang = ? AND t_e.type = 'e'
      WHERE q.id IN ($placeholders)
    ''', [lang, lang, ...questionIds]);

    return maps.map((map) => Question.fromMap(map, lang)).toList();
  }

  /// 獲取所有錯題的ID列表（error_count > 0）
  static Future<List<String>> getErrorQuestionIds(
      {required String userId}) async {
    final db = await userProgressDatabase;
    final normalizedUserId = _normalizeUserId(userId);

    final result = await db.query(
      'user_progress',
      columns: ['question_id'],
      where: '(error_count > ? OR wrong_count > ?) AND user_id = ?',
      whereArgs: [0, 0, normalizedUserId],
      orderBy: 'wrong_count DESC, error_count DESC, last_practiced DESC',
    );

    return result.map((row) => row['question_id'] as String).toList();
  }

  /// 獲取錯題列表（包含題目內容與錯誤次數）
  /// [lang] 語言代碼，默認為意大利語
  static Future<List<WrongQuestionEntry>> getWrongQuestions(
    String userId, {
    String lang = 'it',
  }) async {
    final db = await database;
    final userProgressDb = await userProgressDatabase;
    final normalizedUserId = _normalizeUserId(userId);

    // 先從用戶進度庫取出錯題ID與錯誤次數
    final progressRows = await userProgressDb.rawQuery('''
      SELECT question_id, wrong_count
      FROM user_progress
      WHERE user_id = ? AND wrong_count > 0
      ORDER BY wrong_count DESC, last_practiced DESC
    ''', [normalizedUserId]);

    if (progressRows.isEmpty) return [];

    final idList =
        progressRows.map((row) => row['question_id'] as String).toList();
    final wrongCountMap = <String, int>{
      for (final row in progressRows)
        row['question_id'] as String: (row['wrong_count'] as int?) ?? 0
    };

    final placeholders = idList.map((_) => '?').join(',');
    final questionRows = await db.rawQuery('''
      SELECT
        q.id,
        q.img,
        q.answer,
        q.chapter,
        q.keywords_json,
        it_q.content AS it_text,
        t_q.content AS question,
        t_e.content AS explanation
      FROM questions q
      LEFT JOIN translations it_q ON q.id = it_q.question_id AND it_q.lang = 'it' AND it_q.type = 'q'
      LEFT JOIN translations t_q ON q.id = t_q.question_id AND t_q.lang = ? AND t_q.type = 'q'
      LEFT JOIN translations t_e ON q.id = t_e.question_id AND t_e.lang = ? AND t_e.type = 'e'
      WHERE q.id IN ($placeholders)
    ''', [lang, lang, ...idList]);

    final questionMap = <String, Question>{
      for (final row in questionRows)
        row['id'] as String: Question.fromMap(row, lang),
    };

    final results = <WrongQuestionEntry>[];
    for (final id in idList) {
      final question = questionMap[id];
      if (question == null) continue;
      results.add(
        WrongQuestionEntry(
          question: question,
          wrongCount: wrongCountMap[id] ?? 0,
        ),
      );
    }

    return results;
  }

  /// 清除題目的錯誤計數（當用戶在錯題回顧中答對時調用）
  /// [questionId] 題目ID
  static Future<void> clearErrorCount(String questionId,
      {required String userId}) async {
    final db = await userProgressDatabase;
    final normalizedUserId = _normalizeUserId(userId);

    // 將 error_count 設置為 0
    await db.update(
      'user_progress',
      {'error_count': 0},
      where: 'question_id = ? AND user_id = ?',
      whereArgs: [questionId, normalizedUserId],
    );
  }

  /// 從錯題列表中移除題目（將 wrong_count 設置為 0）
  /// [questionId] 題目ID
  /// [userId] 用戶ID
  static Future<void> removeQuestionFromMistakes(String questionId,
      {required String userId}) async {
    final db = await userProgressDatabase;
    final normalizedUserId = _normalizeUserId(userId);

    // 將 wrong_count 設置為 0
    await db.update(
      'user_progress',
      {'wrong_count': 0},
      where: 'question_id = ? AND user_id = ?',
      whereArgs: [questionId, normalizedUserId],
    );
  }

  /// 減少題目的錯誤計數（可選：如果答對一次就減少錯誤計數，而不是直接清零）
  /// [questionId] 題目ID
  static Future<int> decreaseErrorCount(String questionId,
      {required String userId}) async {
    final db = await userProgressDatabase;
    final normalizedUserId = _normalizeUserId(userId);

    // 先獲取當前錯誤計數
    final result = await db.query(
      'user_progress',
      columns: ['error_count', 'wrong_count'],
      where: 'question_id = ? AND user_id = ?',
      whereArgs: [questionId, normalizedUserId],
    );

    if (result.isNotEmpty) {
      final currentError = result.first['error_count'] as int;
      final currentWrong = result.first['wrong_count'] as int? ?? 0;
      if (currentError > 0 || currentWrong > 0) {
        await db.update(
          'user_progress',
          {
            'error_count': currentError > 0 ? currentError - 1 : 0,
            'wrong_count': currentWrong > 0 ? currentWrong - 1 : 0,
          },
          where: 'question_id = ? AND user_id = ?',
          whereArgs: [questionId, normalizedUserId],
        );
      }
    }
    final updated = await db.query(
      'user_progress',
      columns: ['wrong_count'],
      where: 'question_id = ? AND user_id = ?',
      whereArgs: [questionId, normalizedUserId],
    );
    if (updated.isEmpty) return 0;
    return updated.first['wrong_count'] as int? ?? 0;
  }

  static Future<int> getWrongCount(String questionId,
      {required String userId}) async {
    final db = await userProgressDatabase;
    final normalizedUserId = _normalizeUserId(userId);
    final result = await db.query(
      'user_progress',
      columns: ['wrong_count'],
      where: 'question_id = ? AND user_id = ?',
      whereArgs: [questionId, normalizedUserId],
    );
    if (result.isEmpty) return 0;
    return result.first['wrong_count'] as int? ?? 0;
  }

  /// 獲取章節練習進度統計
  /// [chapterId] 章節ID（1-25）
  /// 返回包含以下信息的 Map：
  ///   - 'total': 該章節的總題數
  ///   - 'practiced': 已做過的題數（last_practiced IS NOT NULL）
  ///   - 'mastered': 已掌握的題數（is_mastered = 1）
  static Future<Map<String, int>> getChapterProgress(int chapterId,
      {required String userId}) async {
    final db = await database;
    final userProgressDb = await userProgressDatabase;
    final normalizedUserId = _normalizeUserId(userId);

    // 獲取該章節的總題數
    final totalResult = await db.rawQuery('''
      SELECT COUNT(*) as count
      FROM questions
      WHERE chapter = ? AND chapter IS NOT NULL
    ''', [chapterId]);
    final total = (totalResult.first['count'] as int?) ?? 0;

    // 獲取該章節所有題目的ID
    final questionIdsResult = await db.rawQuery('''
      SELECT id
      FROM questions
      WHERE chapter = ? AND chapter IS NOT NULL
    ''', [chapterId]);
    final questionIds =
        questionIdsResult.map((row) => row['id'] as String).toList();

    if (questionIds.isEmpty) {
      return {
        'total': 0,
        'practiced': 0,
        'mastered': 0,
      };
    }

    // 獲取已做過的題數（last_practiced IS NOT NULL）
    final placeholders = questionIds.map((_) => '?').join(',');
    final practicedResult = await userProgressDb.rawQuery('''
      SELECT COUNT(DISTINCT question_id) as count
      FROM user_progress
      WHERE question_id IN ($placeholders) AND last_practiced IS NOT NULL AND user_id = ?
    ''', [...questionIds, normalizedUserId]);
    final practiced = (practicedResult.first['count'] as int?) ?? 0;

    // 獲取已掌握的題數（is_mastered = 1）
    final masteredResult = await userProgressDb.rawQuery('''
      SELECT COUNT(DISTINCT question_id) as count
      FROM user_progress
      WHERE question_id IN ($placeholders) AND is_mastered = 1 AND user_id = ?
    ''', [...questionIds, normalizedUserId]);
    final mastered = (masteredResult.first['count'] as int?) ?? 0;

    return {
      'total': total,
      'practiced': practiced,
      'mastered': mastered,
    };
  }

  /// 批量獲取多個章節的統計數據（並行處理，提升性能）
  /// [chapterIds] 章節ID列表
  /// [userId] 用戶ID
  /// 返回 Map<章節ID, 統計數據>
  static Future<Map<int, Map<String, int>>> getChaptersProgress(
    List<int> chapterIds, {
    required String userId,
  }) async {
    if (chapterIds.isEmpty) return {};

    // 使用 Future.wait 並行處理所有章節
    final futures = chapterIds.map((chapterId) async {
      final progress = await getChapterProgress(chapterId, userId: userId);
      return MapEntry(chapterId, progress);
    });

    final results = await Future.wait(futures);
    return Map.fromEntries(results);
  }

  /// 獲取已掌握的題目總數
  /// 返回當前用戶已掌握的題目數量（is_mastered = 1）
  /// [userId] 預留參數：用於未來多用戶數據隔離（目前本地 SQLite 未分表）
  static Future<int> getMasteredCount({String? userId}) async {
    final userProgressDb = await userProgressDatabase;
    final normalizedUserId = _normalizeUserId(userId);

    // 獲取已掌握的題目數
    final masteredResult = await userProgressDb.rawQuery('''
      SELECT COUNT(DISTINCT question_id) as count
      FROM user_progress
      WHERE is_mastered = 1 AND user_id = ?
    ''', [normalizedUserId]);
    final mastered = (masteredResult.first['count'] as int?) ?? 0;

    return mastered;
  }

  /// 獲取已嘗試的題目總數（覆盖率統計）
  /// 返回當前用戶至少做過一次的題目數量（total_attempts > 0）
  /// [userId] 預留參數：用於未來多用戶數據隔離（目前本地 SQLite 未分表）
  static Future<int> getTotalAttemptedCount({String? userId}) async {
    final userProgressDb = await userProgressDatabase;
    final normalizedUserId = _normalizeUserId(userId);

    // 獲取已嘗試的題目數（total_attempts > 0）
    final attemptedResult = await userProgressDb.rawQuery('''
      SELECT COUNT(DISTINCT question_id) as count
      FROM user_progress
      WHERE total_attempts > 0 AND user_id = ?
    ''', [normalizedUserId]);
    final attempted = (attemptedResult.first['count'] as int?) ?? 0;

    return attempted;
  }

  /// 獲取截至某時間點之前的已嘗試題目數（用於昨日通過率對比）
  /// [asOfTimestampSec] Unix 秒，只統計 last_practiced <= asOfTimestampSec 且 total_attempts > 0 的記錄
  static Future<int> getTotalAttemptedCountAsOf({
    required String userId,
    required int asOfTimestampSec,
  }) async {
    final userProgressDb = await userProgressDatabase;
    final normalizedUserId = _normalizeUserId(userId);
    final result = await userProgressDb.rawQuery('''
      SELECT COUNT(DISTINCT question_id) as count
      FROM user_progress
      WHERE user_id = ? AND total_attempts > 0
        AND last_practiced IS NOT NULL AND last_practiced <= ?
    ''', [normalizedUserId, asOfTimestampSec]);
    return (result.first['count'] as int?) ?? 0;
  }

  /// 獲取全局掌握百分比
  /// 返回已掌握題目數 / 總題目數的百分比（0.0 - 1.0）
  /// [userId] 預留參數：用於未來多用戶數據隔離（目前本地 SQLite 未分表）
  static Future<double> getTotalMasteryPercentage({String? userId}) async {
    final db = await database;
    final userProgressDb = await userProgressDatabase;
    final normalizedUserId = _normalizeUserId(userId);

    // 獲取總題目數
    final totalResult = await db.rawQuery(
        'SELECT COUNT(*) as count FROM questions WHERE chapter IS NOT NULL');
    final total = (totalResult.first['count'] as int?) ?? 0;

    if (total == 0) return 0.0;

    // 獲取已掌握的題目數
    final masteredResult = await userProgressDb.rawQuery('''
      SELECT COUNT(DISTINCT question_id) as count
      FROM user_progress
      WHERE is_mastered = 1 AND user_id = ?
    ''', [normalizedUserId]);
    final mastered = (masteredResult.first['count'] as int?) ?? 0;

    return mastered / total;
  }

  /// 計算當前用戶的全局正確率（基於 total_attempts / wrong_count）
  /// 返回範圍 0.0 - 1.0，如果沒有練習記錄則返回 0.0
  static Future<double> getGlobalAccuracy({String? userId}) async {
    final userProgressDb = await userProgressDatabase;
    final normalizedUserId = _normalizeUserId(userId);

    final rows = await userProgressDb.rawQuery('''
      SELECT
        SUM(total_attempts) as total_attempts,
        SUM(wrong_count) as wrong_attempts
      FROM user_progress
      WHERE user_id = ?
    ''', [normalizedUserId]);

    if (rows.isEmpty) return 0.0;

    final row = rows.first;
    final totalAttempts = (row['total_attempts'] as int?) ?? 0;
    final wrongAttempts = (row['wrong_attempts'] as int?) ?? 0;

    if (totalAttempts <= 0) return 0.0;

    final correctAttempts =
        (totalAttempts - wrongAttempts).clamp(0, totalAttempts);
    return correctAttempts / totalAttempts;
  }

  /// 重置所有用戶進度
  /// 物理刪除指定 user_id 的所有進度與模擬考記錄（本地完全清空）
  /// 返回 true 表示操作成功，false 表示操作失敗
  static Future<bool> resetAllUserProgress({required String userId}) async {
    try {
      _debugLog('🔄 [DatabaseService] 開始重置所有用戶進度...');

      final db = await userProgressDatabase;
      final normalizedUserId = _normalizeUserId(userId);

      // 物理刪除 user_progress 中該用戶的所有記錄
      final deletedProgress = await db.delete(
        'user_progress',
        where: 'user_id = ?',
        whereArgs: [normalizedUserId],
      );

      // 同時刪除模擬考結果表 mock_exam_results 中該用戶的所有記錄
      final deletedMock = await db.delete(
        'mock_exam_results',
        where: 'user_id = ?',
        whereArgs: [normalizedUserId],
      );

      _debugLog(
          '✅ [DatabaseService] 已刪除用戶進度記錄 $deletedProgress 條、模擬考記錄 $deletedMock 條');
      return true;
    } catch (e, stackTrace) {
      _debugLog('❌ [DatabaseService] 重置用戶進度失敗: $e');
      _debugLog('📋 [DatabaseService] 錯誤堆棧: $stackTrace');
      return false;
    }
  }

  /// 關閉數據庫連接（應用退出時調用）
  static Future<void> close() async {
    await _database?.close();
    await _userProgressDatabase?.close();
    _database = null;
    _userProgressDatabase = null;
  }

  /// 臨時測試方法：為 id 1-5 的題目填充 keywords_json 字段（用於驗證邏輯）
  /// 注意：這是臨時方法，僅用於測試，實際應用中應該從數據源獲取關鍵詞數據
  static Future<void> fillTestKeywordsData() async {
    try {
      final db = await database;

      // 檢查 keywords_json 字段是否存在
      final tableInfo = await db.rawQuery('PRAGMA table_info(questions)');
      final hasKeywordsJson =
          tableInfo.any((column) => column['name'] == 'keywords_json');

      if (!hasKeywordsJson) {
        _debugLog('⚠️ [TestKeywords] keywords_json 字段不存在，無法填充測試數據');
        return;
      }

      // 測試數據：為 id 1-5 的題目設置關鍵詞 JSON
      final testData = [
        {
          'id': 1,
          'keywords': [
            {'it': 'Carreggiata', 'zh': '行车道'},
            {'it': 'Banchina', 'zh': '路肩'},
          ],
        },
        {
          'id': 2,
          'keywords': [
            {'it': 'Sospensione', 'zh': '吊销/暂停'},
            {'it': 'Patente', 'zh': '驾照'},
          ],
        },
        {
          'id': 3,
          'keywords': [
            {'it': 'Ovvero', 'zh': '或者/即'},
            {'it': 'Sempre', 'zh': '总是'},
          ],
        },
        {
          'id': 4,
          'keywords': [
            {'it': 'Divieto', 'zh': '禁止'},
            {'it': 'Obbligo', 'zh': '义务'},
          ],
        },
        {
          'id': 5,
          'keywords': [
            {'it': 'Precedenza', 'zh': '优先权'},
            {'it': 'Strada', 'zh': '道路'},
          ],
        },
      ];

      int updatedCount = 0;

      for (final item in testData) {
        final id = item['id'] as int;
        final keywords = item['keywords'] as List<Map<String, String>>;

        // 將關鍵詞列表轉換為 JSON 字符串
        final keywordsJson = jsonEncode(keywords);

        // 更新數據庫
        final result = await db.update(
          'questions',
          {'keywords_json': keywordsJson},
          where: 'id = ?',
          whereArgs: [id],
        );

        if (result > 0) {
          updatedCount++;
          _debugLog('✅ [TestKeywords] 已為題目 id=$id 填充關鍵詞數據');
        } else {
          _debugLog('⚠️ [TestKeywords] 題目 id=$id 不存在或更新失敗');
        }
      }

      _debugLog('📊 [TestKeywords] 測試數據填充完成：成功更新 $updatedCount 條記錄');
    } catch (e, stackTrace) {
      _debugLog('❌ [TestKeywords] 填充測試關鍵詞數據失敗：$e');
      _debugLog('📋 [TestKeywords] 錯誤堆棧: $stackTrace');
    }
  }

  /// 將本地 user_progress 表中有變動的數據批量寫入 Firestore（Sync Down to Up）
  /// 文檔路徑：users/{userId}/progress/{questionId}，字段：correct_streak, wrong_count, total_attempts, is_mastered, is_favorite, last_practiced
  /// 僅在 isVip 時由 Provider 觸發；網絡異常時不拋錯，返回 SyncResult，避免 App 卡死。
  static Future<SyncResult> syncLocalToCloud({required String userId}) async {
    final currentUser = FirebaseStatus.auth?.currentUser;
    if (currentUser == null || currentUser.uid != userId) {
      _debugLog('❌ [CloudSync] 用戶未登入或 UID 不匹配，無法同步');
      return const SyncResult(success: false, isTimeout: false);
    }

    try {
      final ok = await syncLocalToCloudImpl(userId)
          .timeout(const Duration(seconds: 30), onTimeout: () {
        _debugLog('❌ [CloudSync] 同步超時');
        throw TimeoutException('Cloud sync');
      });
      return SyncResult(success: ok, isTimeout: false);
    } on TimeoutException {
      return const SyncResult(success: false, isTimeout: true);
    } catch (e, stackTrace) {
      _debugLog('❌ [CloudSync] 同步到雲端失敗: $e');
      if (kDebugMode) _debugLog('📋 [CloudSync] 錯誤堆棧: $stackTrace');
      return const SyncResult(success: false, isTimeout: false);
    }
  }

  static Future<bool> syncLocalToCloudImpl(String userId) async {
    _debugLog('🔄 [CloudSync] 開始同步用戶進度到雲端...');
    final db = await userProgressDatabase;
    final firestore = FirebaseStatus.firestore;
    if (firestore == null) return false;

    final progressRows = await db.query(
      'user_progress',
      where: 'user_id = ? AND (total_attempts > 0 OR is_favorite = 1)',
      whereArgs: [userId],
    );

    if (progressRows.isEmpty) {
      _debugLog('ℹ️ [CloudSync] 沒有需要同步的記錄');
      return true;
    }

    _debugLog('📊 [CloudSync] 找到 ${progressRows.length} 條需要同步的記錄');

    var batch = firestore.batch();
    var pendingWrites = 0;
    var committedBatches = 0;
    int successCount = 0;
    int errorCount = 0;

    for (final row in progressRows) {
      try {
        final questionId = row['question_id'] as String;
        final progressRef = firestore
            .collection('users')
            .doc(userId)
            .collection('progress')
            .doc(questionId);

        final lastPracticedSec = row['last_practiced'] as int?;
        final lastPracticedTimestamp =
            lastPracticedSec != null && lastPracticedSec > 0
                ? Timestamp.fromMillisecondsSinceEpoch(lastPracticedSec * 1000)
                : null;

        final progressData = {
          'correct_streak': row['correct_streak'] as int? ?? 0,
          'wrong_count': row['wrong_count'] as int? ?? 0,
          'total_attempts': row['total_attempts'] as int? ?? 0,
          'is_mastered': (row['is_mastered'] as int? ?? 0) == 1,
          'is_favorite': (row['is_favorite'] as int? ?? 0) == 1,
          if (lastPracticedTimestamp != null)
            'last_practiced': lastPracticedTimestamp,
        };

        batch.set(progressRef, progressData, SetOptions(merge: true));
        pendingWrites++;
        successCount++;

        if (pendingWrites >= _firestoreBatchWriteLimit) {
          await batch.commit();
          committedBatches++;
          batch = firestore.batch();
          pendingWrites = 0;
        }
      } catch (e) {
        _debugLog('⚠️ [CloudSync] 處理記錄失敗: $e');
        errorCount++;
      }
    }

    if (pendingWrites > 0) {
      await batch.commit();
      committedBatches++;
    }
    _debugLog(
        '✅ [CloudSync] 同步完成：成功 $successCount 條，失敗 $errorCount 條，提交 $committedBatches 批');
    return errorCount == 0;
  }

  /// 同步用戶進度到 Firestore 雲端（對外入口，內部調用 syncLocalToCloud）
  static Future<SyncResult> syncProgressToCloud(
      {required String userId}) async {
    return syncLocalToCloud(userId: userId);
  }

  /// 刪除 Firestore 中指定用戶的所有進度文檔，防止本地重置後又從雲端恢復舊數據
  /// 路徑：users/{userId}/progress/*
  static Future<void> clearCloudProgress({required String userId}) async {
    try {
      final firestore = FirebaseStatus.firestore;
      if (firestore == null) return;
      final progressCollection =
          firestore.collection('users').doc(userId).collection('progress');
      final snapshot = await progressCollection.get();
      if (snapshot.docs.isEmpty) {
        _debugLog('ℹ️ [CloudSync] 雲端無進度可清空');
        return;
      }
      final deletedCount =
          await _deleteQuerySnapshotInBatches(firestore, snapshot);
      _debugLog('✅ [CloudSync] 已清空雲端進度，共刪除 $deletedCount 條記錄');
    } catch (e, stackTrace) {
      _debugLog('⚠️ [CloudSync] 清空雲端進度失敗: $e');
      if (kDebugMode) _debugLog('📋 [CloudSync] 錯誤堆棧: $stackTrace');
    }
  }

  /// 刪除用戶在 Firestore 的學習數據（progress + daily_usage）
  /// 用於帳號登出前的資料刪除確認流程（審核合規）
  static Future<void> clearCloudUserData({required String userId}) async {
    try {
      final firestore = FirebaseStatus.firestore;
      if (firestore == null) return;
      final progressSnapshot = await firestore
          .collection('users')
          .doc(userId)
          .collection('progress')
          .get();
      final deletedProgress =
          await _deleteQuerySnapshotInBatches(firestore, progressSnapshot);

      final usageSnapshot = await firestore
          .collection('users')
          .doc(userId)
          .collection('daily_usage')
          .get();
      final deletedUsage =
          await _deleteQuerySnapshotInBatches(firestore, usageSnapshot);

      _debugLog(
          '✅ [CloudSync] 已刪除雲端學習數據：progress=$deletedProgress, daily_usage=$deletedUsage');
    } catch (e, stackTrace) {
      _debugLog('⚠️ [CloudSync] 刪除雲端學習數據失敗: $e');
      if (kDebugMode) _debugLog('📋 [CloudSync] 錯誤堆棧: $stackTrace');
    }
  }

  /// 從 Firestore 讀取進度並覆蓋/更新到本地 SQLite（Sync Up to Down）
  /// 登入成功且為 VIP 時調用，確保換設備後進度可恢復；網絡異常時不拋錯，返回 false。
  static Future<bool> syncCloudToLocal({required String userId}) async {
    final currentUser = FirebaseStatus.auth?.currentUser;
    if (currentUser == null || currentUser.uid != userId) {
      _debugLog('❌ [CloudSync] 用戶未登入或 UID 不匹配，無法恢復');
      return false;
    }
    try {
      return await syncCloudToLocalImpl(userId)
          .timeout(const Duration(seconds: 45), onTimeout: () {
        _debugLog('❌ [CloudSync] 從雲端恢復超時');
        return false;
      });
    } catch (e, stackTrace) {
      _debugLog('❌ [CloudSync] 從雲端恢復失敗: $e');
      if (kDebugMode) _debugLog('📋 [CloudSync] 錯誤堆棧: $stackTrace');
      return false;
    }
  }

  static int _cloudInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is bool) return value ? 1 : 0;
    return 0;
  }

  static int _cloudTotalAttempts(
    Map<String, dynamic> data, {
    required int wrongCount,
    required int correctStreak,
  }) {
    final totalAttempts = data['total_attempts'];
    if (totalAttempts != null) {
      return _cloudInt(totalAttempts);
    }
    final inferredAttempts = wrongCount + correctStreak;
    return inferredAttempts > 0 ? inferredAttempts : 0;
  }

  static Future<bool> syncCloudToLocalImpl(String userId) async {
    _debugLog('🔄 [CloudSync] 開始從雲端恢復用戶進度...');
    final db = await userProgressDatabase;
    final firestore = FirebaseStatus.firestore;
    if (firestore == null) return false;

    final progressSnapshot = await firestore
        .collection('users')
        .doc(userId)
        .collection('progress')
        .get();

    if (progressSnapshot.docs.isEmpty) {
      _debugLog('ℹ️ [CloudSync] 雲端沒有進度數據');
      return true;
    }

    _debugLog('📊 [CloudSync] 從雲端獲取到 ${progressSnapshot.docs.length} 條記錄');

    int mergedCount = 0;
    int skippedCount = 0;

    await db.transaction((txn) async {
      for (final doc in progressSnapshot.docs) {
        try {
          final data = doc.data();
          final questionId = data['question_id'] as String? ?? doc.id;
          final cloudLastPracticed = data['last_practiced'] as Timestamp?;
          final cloudLastPracticedSeconds = cloudLastPracticed?.seconds ?? 0;
          final cloudIsFavorite = _cloudInt(data['is_favorite']);
          final cloudIsMastered = _cloudInt(data['is_mastered']);
          final cloudCorrectStreak = _cloudInt(data['correct_streak']);
          final cloudWrongCount = _cloudInt(data['wrong_count']);
          final cloudErrorCount = data['error_count'] != null
              ? _cloudInt(data['error_count'])
              : cloudWrongCount;
          final cloudTotalAttempts = _cloudTotalAttempts(
            data,
            wrongCount: cloudWrongCount,
            correctStreak: cloudCorrectStreak,
          );

          final localResult = await txn.query(
            'user_progress',
            where: 'question_id = ? AND user_id = ?',
            whereArgs: [questionId, userId],
          );

          if (localResult.isNotEmpty) {
            final localRow = localResult.first;
            final localLastPracticed = localRow['last_practiced'] as int? ?? 0;
            final localIsFavorite = localRow['is_favorite'] as int? ?? 0;
            final localTotalAttempts = localRow['total_attempts'] as int? ?? 0;
            final mergedTotalAttempts = cloudTotalAttempts > localTotalAttempts
                ? cloudTotalAttempts
                : localTotalAttempts;

            if (cloudLastPracticedSeconds > localLastPracticed) {
              final mergedIsFavorite =
                  (localIsFavorite == 1 || cloudIsFavorite == 1) ? 1 : 0;
              await txn.rawInsert('''
                INSERT INTO user_progress (
                  question_id, user_id, is_favorite, error_count, wrong_count,
                  is_mastered, correct_streak, total_attempts, last_practiced
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(question_id, user_id) DO UPDATE SET
                  is_favorite = ?,
                  error_count = ?,
                  wrong_count = ?,
                  is_mastered = ?,
                  correct_streak = ?,
                  total_attempts = CASE
                    WHEN ? > total_attempts THEN ?
                    ELSE total_attempts
                  END,
                  last_practiced = ?
              ''', [
                questionId,
                userId,
                mergedIsFavorite,
                cloudErrorCount,
                cloudWrongCount,
                cloudIsMastered,
                cloudCorrectStreak,
                mergedTotalAttempts,
                cloudLastPracticedSeconds,
                mergedIsFavorite,
                cloudErrorCount,
                cloudWrongCount,
                cloudIsMastered,
                cloudCorrectStreak,
                mergedTotalAttempts,
                mergedTotalAttempts,
                cloudLastPracticedSeconds,
              ]);
              mergedCount++;
            } else {
              final mergedIsFavorite =
                  (localIsFavorite == 1 || cloudIsFavorite == 1) ? 1 : 0;
              if (mergedIsFavorite != localIsFavorite) {
                await txn.update(
                  'user_progress',
                  {'is_favorite': mergedIsFavorite},
                  where: 'question_id = ? AND user_id = ?',
                  whereArgs: [questionId, userId],
                );
                mergedCount++;
              } else {
                skippedCount++;
              }
            }
          } else {
            await txn.rawInsert('''
              INSERT INTO user_progress (
                question_id, user_id, is_favorite, error_count, wrong_count,
                is_mastered, correct_streak, total_attempts, last_practiced
              )
              VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ''', [
              questionId,
              userId,
              cloudIsFavorite,
              cloudErrorCount,
              cloudWrongCount,
              cloudIsMastered,
              cloudCorrectStreak,
              cloudTotalAttempts,
              cloudLastPracticedSeconds,
            ]);
            mergedCount++;
          }
        } catch (e) {
          _debugLog('⚠️ [CloudSync] 處理記錄失敗: $e');
        }
      }
    });

    _debugLog('✅ [CloudSync] 恢復完成：合併 $mergedCount 條，跳過 $skippedCount 條');
    return true;
  }

  /// 從 Firestore 雲端恢復用戶進度到本地 SQLite（對外入口，內部調用 syncCloudToLocal）
  static Future<bool> restoreProgressFromCloud({required String userId}) async {
    return syncCloudToLocal(userId: userId);
  }

  /// 檢查 Firestore users/{userId} 是否標記為 isVip: true（用於恢復購買）。
  /// isVip 僅應由可信後端 / Admin SDK 寫入；客戶端只讀取雲端權益。
  /// 返回 true/false 表示有記錄且為 VIP/非 VIP；null 表示未找到或網絡錯誤。
  static Future<bool?> checkUserVipInFirestore(String userId) async {
    try {
      final firestore = FirebaseStatus.firestore;
      if (firestore == null) return null;

      final doc = await firestore
          .collection('users')
          .doc(userId)
          .get()
          .timeout(const Duration(seconds: 15));
      if (!doc.exists) return null;
      final isVip = doc.data()?['isVip'];
      if (isVip is bool) return isVip;
      if (isVip is int) return isVip != 0;
      return false;
    } catch (e) {
      _debugLog('⚠️ [CloudSync] 檢查 Firestore VIP 狀態失敗: $e');
      return null;
    }
  }
}
