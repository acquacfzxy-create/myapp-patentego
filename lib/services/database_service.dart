import 'dart:io';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import '../models/question.dart';

/// 數據庫服務類
/// 負責數據庫的初始化、題目查詢和用戶進度管理
class DatabaseService {
  /// 調試日誌輸出（只在 Debug 模式下輸出，避免 Release 模式性能問題）
  static void _debugLog(String message) {
    if (kDebugMode) {
      _debugLog(message);
    }
  }
  // 靜態數據庫實例（單例模式）
  static Database? _database;
  static Database? _userProgressDatabase;
  
  // 數據庫配置
  static const String _databaseName = 'italy_quiz.db';
  static const String _userProgressDbName = 'user_progress.db';
  static const int _databaseVersion = 1;
  
  // 初始化錯誤信息（如果初始化失敗，保存錯誤信息）
  static String? initError;

  /// 獲取主數據庫實例（只讀，包含題目數據）
  static Future<Database> get database async {
    if (_database != null) {
      // 強制檢查數據庫是否有章節數據，如果沒有則重新初始化
      try {
        final countResult = await _database!.rawQuery('SELECT COUNT(*) as count FROM questions WHERE chapter IS NOT NULL');
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
      _debugLog('📁 [Database] 創建目錄結構...');
      await Directory(dirname(path)).create(recursive: true);
      
      _debugLog('📦 [Database] 從 assets 加載數據庫文件...');
      final ByteData data = await rootBundle.load(_databaseName);
      final int dataSize = data.lengthInBytes;
      _debugLog('📦 [Database] 數據庫文件大小: ${(dataSize / 1024 / 1024).toStringAsFixed(2)} MB');
      
      _debugLog('💾 [Database] 開始寫入數據庫文件到設備...');
      final List<int> bytes =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      
      // 直接寫入文件（對於 20MB 的文件，直接寫入通常沒問題）
      // 如果遇到內存問題，可以考慮分批寫入
      await file.writeAsBytes(bytes, flush: true);
      
      _debugLog('✅ [Database] 數據庫文件複製完成 (${(bytes.length / 1024 / 1024).toStringAsFixed(2)} MB)');
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
    final exists = await file.exists();
    _debugLog('🔍 [Database] 文件存在: $exists');

    if (!exists) {
      // 如果不存在，從 assets 複製
      _debugLog('📥 [Database] 數據庫文件不存在，開始從 assets 複製...');
      await _copyDatabaseFromAssets(file, path);
    } else {
      _debugLog('✅ [Database] 數據庫文件已存在');
      
      // 檢查數據庫是否有章節數據，如果沒有則重新複製
      Database? tempDb;
      try {
        _debugLog('🔍 [Database] 打開臨時數據庫連接檢查章節數據...');
        tempDb = await openDatabase(path, version: 1, readOnly: false, singleInstance: false);
        final countResult = await tempDb.rawQuery('SELECT COUNT(*) as count FROM questions WHERE chapter IS NOT NULL');
        final count = countResult.first['count'] as int? ?? 0;
        _debugLog('📊 [Database] 檢查數據庫章節數據: $count 道題目有章節信息');
        
        if (count == 0) {
          _debugLog('⚠️ [Database] 檢測到數據庫沒有章節數據，可能是舊版本');
          _debugLog('🔄 [Database] 關閉數據庫連接...');
          await tempDb.close();
          tempDb = null;
          
          _debugLog('🗑️ [Database] 刪除舊數據庫文件...');
          await file.delete();
          _debugLog('📥 [Database] 重新從 assets 複製數據庫文件...');
          await _copyDatabaseFromAssets(file, path);
          _debugLog('✅ [Database] 數據庫文件已更新');
        } else {
          _debugLog('✅ [Database] 數據庫章節數據正常（$count 道題目有章節信息），跳過複製');
        }
      } catch (e, stackTrace) {
        _debugLog('⚠️ [Database] 檢查數據庫章節數據時出錯: $e');
        _debugLog('📋 [Database] 錯誤堆棧: $stackTrace');
        if (tempDb != null) {
          try {
            await tempDb.close();
          } catch (_) {}
        }
        _debugLog('🔄 [Database] 嘗試重新複製數據庫文件...');
        try {
          if (await file.exists()) {
            await file.delete();
          }
          await _copyDatabaseFromAssets(file, path);
          _debugLog('✅ [Database] 數據庫文件已重新複製');
        } catch (copyError) {
          _debugLog('❌ [Database] 重新複製失敗: $copyError');
        }
      } finally {
        if (tempDb != null) {
          try {
            await tempDb.close();
          } catch (_) {}
        }
      }
    }

    // 確保文件可寫（如果不是，刪除並重新複製）
    try {
      // 嘗試設置文件權限為可寫（如果平台支持）
      if (await file.exists()) {
        final stat = await file.stat();
        _debugLog('📝 [Database] 數據庫文件權限檢查完成');
      }
    } catch (e) {
      _debugLog('⚠️ [Database] 無法檢查文件權限: $e');
    }

    // 打開數據庫連接
    // 注意：雖然我們不應該修改這個數據庫，但 SQLite 需要寫權限來創建臨時文件和執行 PRAGMA 命令
    // 我們通過不在代碼中執行寫操作來保護數據，而不是使用 readOnly 模式
    _debugLog('🔓 [Database] 打開數據庫連接...');
    try {
      final db = await openDatabase(
        path,
        version: 1,
        readOnly: false, // 必須為 false，因為 SQLite 需要寫權限來創建臨時文件和執行 PRAGMA 命令
        singleInstance: true, // 使用單例模式，避免多個連接
        // 我們通過只執行 SELECT 查詢來保護數據，不執行 INSERT/UPDATE/DELETE
      );
      _debugLog('✅ [Database] 數據庫連接打開成功');
      
      // 創建索引以優化查詢性能
      await _createIndexes(db);
      
      return db;
    } catch (e, stackTrace) {
      _debugLog('❌ [Database] 打開數據庫連接失敗: $e');
      _debugLog('📋 [Database] 錯誤堆棧: $stackTrace');
      
      // 如果打開失敗且錯誤與只讀相關，嘗試刪除並重新複製數據庫
      if (e.toString().contains('read-only') || e.toString().contains('readonly')) {
        _debugLog('🔄 [Database] 檢測到只讀錯誤，嘗試刪除並重新複製數據庫...');
        try {
          final file = File(path);
          if (await file.exists()) {
            await file.delete();
            _debugLog('🗑️ [Database] 已刪除舊數據庫文件');
            
            // 重新複製數據庫
            final ByteData data = await rootBundle.load(_databaseName);
            final List<int> bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
            await file.writeAsBytes(bytes, flush: true);
            _debugLog('✅ [Database] 數據庫文件重新複製完成');
            
            // 再次嘗試打開
            final db = await openDatabase(
              path,
              version: 1,
              readOnly: false,
              singleInstance: true,
            );
            _debugLog('✅ [Database] 數據庫連接打開成功（重新複製後）');
            return db;
          }
        } catch (retryError) {
          _debugLog('❌ [Database] 重新複製數據庫失敗: $retryError');
        }
      }
      
      throw Exception('Failed to open database: $e');
    }
  }

  /// 創建數據庫索引以優化查詢性能
  static Future<void> _createIndexes(Database db) async {
    try {
      _debugLog('📊 [Database] 開始創建數據庫索引...');
      
      // 為 chapter 字段創建索引，優化章節查詢性能
      await db.execute('CREATE INDEX IF NOT EXISTS idx_chapter ON questions (chapter)');
      _debugLog('✅ [Database] 索引 idx_chapter 創建成功（或已存在）');
      
      // 驗證索引是否存在
      final indexInfo = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_chapter'"
      );
      if (indexInfo.isNotEmpty) {
        _debugLog('✅ [Database] 索引 idx_chapter 驗證成功');
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
      
      // 為 is_mastered 字段創建索引，優化掌握度統計查詢
      await db.execute('CREATE INDEX IF NOT EXISTS idx_is_mastered ON user_progress (is_mastered)');
      _debugLog('✅ [UserProgress] 索引 idx_is_mastered 創建成功（或已存在）');
      
      // 為 question_id 創建索引（通常已經有 PRIMARY KEY，但為了完整性還是創建）
      try {
        await db.execute('CREATE INDEX IF NOT EXISTS idx_question_id ON user_progress (question_id)');
        _debugLog('✅ [UserProgress] 索引 idx_question_id 創建成功（或已存在）');
      } catch (e) {
        // PRIMARY KEY 已經自動創建索引，忽略錯誤
        _debugLog('ℹ️ [UserProgress] question_id 索引可能已存在（PRIMARY KEY）');
      }
      
    } catch (e, stackTrace) {
      _debugLog('⚠️ [UserProgress] 創建索引失敗: $e');
      _debugLog('📋 [UserProgress] 錯誤堆棧: $stackTrace');
      // 索引創建失敗不影響應用運行，只是查詢可能較慢
    }
  }

  /// 執行數據庫遷移（添加 chapter 字段）
  static Future<void> _migrateDatabase() async {
    try {
      final db = await database;
      
      // 檢查 chapter 字段是否存在
      final tableInfo = await db.rawQuery('PRAGMA table_info(questions)');
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
        final countResult = await db.rawQuery('SELECT COUNT(*) as count FROM questions WHERE chapter IS NOT NULL');
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
    } catch (e, stackTrace) {
      _debugLog('⚠️ [Migration] 數據庫遷移失敗：$e');
      _debugLog('📋 [Migration] 錯誤堆棧: $stackTrace');
      // 遷移失敗不影響應用運行，只是 chapter 功能不可用
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
        version: 4, // 升級版本號以支持 wrong_count 字段
        onCreate: (db, version) async {
          _debugLog('📝 [UserProgress] 創建用戶進度表結構...');
          // 創建用戶進度表
          await db.execute('''
            CREATE TABLE user_progress (
              question_id TEXT PRIMARY KEY,
              is_favorite INTEGER DEFAULT 0,
              error_count INTEGER DEFAULT 0,
              wrong_count INTEGER DEFAULT 0,
              is_mastered INTEGER DEFAULT 0,
              correct_streak INTEGER DEFAULT 0,
              last_practiced INTEGER,
              created_at INTEGER DEFAULT (strftime('%s', 'now'))
            )
          ''');
          _debugLog('✅ [UserProgress] 用戶進度表創建成功');
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          _debugLog('🔄 [UserProgress] 數據庫升級: $oldVersion -> $newVersion');
          
          // 版本2：添加 is_mastered 字段
          if (oldVersion < 2) {
            try {
              await db.execute('ALTER TABLE user_progress ADD COLUMN is_mastered INTEGER DEFAULT 0');
              _debugLog('✅ [UserProgress] 已添加 is_mastered 字段');
            } catch (e) {
              // 如果字段已存在，忽略錯誤
              _debugLog('ℹ️ [UserProgress] is_mastered 字段可能已存在: $e');
            }
          }
          
          // 版本3：添加 correct_streak 字段
          if (oldVersion < 3) {
            try {
              await db.execute('ALTER TABLE user_progress ADD COLUMN correct_streak INTEGER DEFAULT 0');
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
              await db.execute('ALTER TABLE user_progress ADD COLUMN wrong_count INTEGER DEFAULT 0');
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
      
      // 驗證數據庫是否有章節數據
      _debugLog('🔍 [DatabaseService] 驗證數據庫章節數據...');
      final countResult = await db.rawQuery('SELECT COUNT(*) as count FROM questions WHERE chapter IS NOT NULL');
      final count = countResult.first['count'] as int? ?? 0;
      _debugLog('📊 [DatabaseService] 數據庫中有 $count 道題目有章節信息');
      
      if (count == 0) {
        _debugLog('❌ [DatabaseService] 警告：數據庫沒有章節數據！');
        _debugLog('❌ [DatabaseService] 這將導致章節練習功能無法使用');
        _debugLog('🔄 [DatabaseService] 嘗試強制重新加載數據庫...');
        await forceReloadDatabase();
        // 再次檢查
        final retryCountResult = await _database!.rawQuery('SELECT COUNT(*) as count FROM questions WHERE chapter IS NOT NULL');
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
  }) async {
    final db = await database;
    
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
      
      final List<Map<String, dynamic>> questionIds = await db.rawQuery(idQuery, idQueryArgs);
      
      if (questionIds.isNotEmpty) {
        // 從 user_progress 數據庫查詢已掌握的題目ID
        final userProgressDb = await userProgressDatabase;
        final placeholders = questionIds.map((_) => '?').join(',');
        final ids = questionIds.map((row) => row['id'] as String).toList();
        
        final masteredResults = await userProgressDb.rawQuery('''
          SELECT question_id
          FROM user_progress
          WHERE question_id IN ($placeholders) AND is_mastered = 1
        ''', ids);
        
        masteredQuestionIds = masteredResults
            .map((row) => row['question_id'] as String)
            .toSet();
      }
    }
    
    // 構建 SQL 查詢
    String query = '''
      SELECT 
        q.id,
        q.img,
        q.answer,
        q.chapter,
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

    final List<Map<String, dynamic>> maps = await db.rawQuery(query, queryArgs);
    
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

    return finalMaps.map((map) => Question.fromMap(map, lang)).toList();
  }

  /// 隨機獲取一道題目
  static Future<Question?> getRandomQuestion({String lang = 'zh', int? chapter}) async {
    final questions = await getQuestions(lang: lang, limit: 1, chapter: chapter);
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
  static Future<Question?> getRandomQuestionWithTranslation({String translationLang = 'zh', int? chapter}) async {
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
    return await getQuestionWithTranslation(randomId, translationLang: translationLang);
  }

  /// 獲取多道隨機題目（用於模擬考試）
  static Future<List<Question>> getRandomQuestions(int count, {String lang = 'zh', int? chapter}) async {
    final allQuestions = await getQuestions(lang: lang, chapter: chapter);
    if (allQuestions.isEmpty) return [];
    
    allQuestions.shuffle();
    return allQuestions.take(count).toList();
  }

  /// 獲取多道隨機題目，同時包含意大利語和指定語言的翻譯（用於模擬考試）
  /// [count] 需要獲取的題目數量
  /// [translationLang] 翻譯語言代碼（默認為當前語言）
  /// [chapter] 章節ID（可選）
  static Future<List<Question>> getRandomQuestionsWithTranslation(int count, {String translationLang = 'zh', int? chapter}) async {
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
    final selectedIds = questionIds.take(count).map((map) => map['id'] as String).toList();
    
    // 獲取包含翻譯的題目列表
    final questions = <Question>[];
    for (final id in selectedIds) {
      final question = await getQuestionWithTranslation(id, translationLang: translationLang);
      if (question != null) {
        questions.add(question);
      }
    }
    
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
  }) async {
    _debugLog('🔍 [DatabaseService] 正在查詢章節 ID: $chapterId, skipMastered: $skipMastered, translationLang: $translationLang');
    
    final db = await database;
    
    // 查詢該章節的所有題目ID
    _debugLog('📝 [DatabaseService] 執行 SQL 查詢: SELECT id FROM questions WHERE chapter = $chapterId AND chapter IS NOT NULL');
    final List<Map<String, dynamic>> questionIds = await db.rawQuery('''
      SELECT id FROM questions WHERE chapter = ? AND chapter IS NOT NULL
    ''', [chapterId]);
    
    _debugLog('📊 [DatabaseService] 查詢結果：找到 ${questionIds.length} 道題目');
    if (questionIds.isEmpty) {
      _debugLog('⚠️ [DatabaseService] 章節 $chapterId 沒有找到任何題目！');
      // 調試：檢查是否有其他章節有題目
      final debugResult = await db.rawQuery('SELECT COUNT(*) as count FROM questions WHERE chapter IS NOT NULL');
      final totalWithChapter = debugResult.first['count'] as int? ?? 0;
      _debugLog('📊 [DatabaseService] 數據庫中總共有 $totalWithChapter 道題目有章節信息');
      
      // 檢查章節字段是否存在
      final tableInfo = await db.rawQuery('PRAGMA table_info(questions)');
      final hasChapterField = tableInfo.any((column) => column['name'] == 'chapter');
      _debugLog('📋 [DatabaseService] questions 表是否有 chapter 字段: $hasChapterField');
      
      // 檢查該章節的所有可能值
      if (totalWithChapter > 0) {
        final sampleResult = await db.rawQuery('SELECT DISTINCT chapter FROM questions WHERE chapter IS NOT NULL ORDER BY chapter LIMIT 10');
        final sampleChapters = sampleResult.map((row) => row['chapter']).toList();
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
        WHERE question_id IN ($placeholders) AND is_mastered = 1
      ''', ids);
      
      masteredQuestionIds = masteredResults
          .map((row) => row['question_id'] as String)
          .toSet();
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
    _debugLog('📝 [DatabaseService] 執行批量查詢，獲取 ${filteredQuestionIds.length} 道題目的翻譯...');
    
    final questionsMap = await db.rawQuery('''
      SELECT 
        q.id,
        q.img,
        q.answer,
        q.chapter,
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
    
    final skippedCount = skipMastered ? questionIds.length - filteredQuestionIds.length : 0;
    _debugLog('✅ [DatabaseService] 章節 $chapterId 最終返回 ${questions.length} 道題目 (跳過已掌握: $skippedCount, 加載失敗: ${filteredQuestionIds.length - questions.length})');
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
  }) async {
    _debugLog('🎲 [DatabaseService] 從章節 $chapterId 隨機獲取一道題目');
    
    final questions = await getQuestionsByChapter(
      chapterId,
      skipMastered: skipMastered,
      translationLang: translationLang,
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
  static Future<List<Question>> getMockTestQuestions({String translationLang = 'zh'}) async {
    const int targetQuestionCount = 30;
    final db = await database;
    final selectedQuestionIds = <String>[]; // 最終選中的題目ID列表
    final usedQuestionIds = <String>{}; // 已使用的題目ID集合（用於去重）
    
    try {
      // ========== 步驟1：全覆蓋步（從1-25章節各抽取1題） ==========
      // 一次性查詢所有章節的題目ID（排除 chapter IS NULL）
      final List<Map<String, dynamic>> allChapterQuestions = await db.rawQuery('''
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
          final availableQuestions = chapterQuestions.where((id) => !usedQuestionIds.contains(id)).toList();
          
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
          final availableQuestions = chapterQuestions.where((id) => !usedQuestionIds.contains(id)).toList();
          
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
        _debugLog('⚠️ [DatabaseService] 無法獲取足夠的題目：僅獲取到 ${selectedQuestionIds.length} 題（目標：$targetQuestionCount 題）');
        // 如果題庫不足，返回已獲取的題目
      }
      
      // ========== 步驟4：批量獲取題目完整信息（包含翻譯） ==========
      // 使用 getQuestionsByIds 批量獲取題目（但這個方法只支持單語言，需要改用其他方式）
      // 為了支持雙語言（意大利語+翻譯語言），我們使用 getQuestionWithTranslation
      final questions = <Question>[];
      for (final questionId in selectedQuestionIds) {
        final question = await getQuestionWithTranslation(questionId, translationLang: translationLang);
        if (question != null) {
          questions.add(question);
        }
      }
      
      // ========== 步驟5：組合與打亂 ==========
      // 隨機打亂所有題目的順序，確保用戶不會發現題目是按章節排列的
      questions.shuffle();
      
      // ========== 步驟6：輸出日誌 ==========
      final weightedChaptersList = selectedChapters.toList()..sort();
      _debugLog('✅ [DatabaseService] 考試生成成功：覆蓋了 25 個章節，加權了章節 $weightedChaptersList');
      
      return questions;
    } catch (e) {
      _debugLog('❌ [DatabaseService] getMockTestQuestions 出錯: $e');
      // 如果出現錯誤，返回空列表（調用方應該檢查並處理）
      return [];
    }
  }

  /// 從總題庫隨機獲取指定數量的題目（保底邏輯輔助方法）
  /// [count] 需要的題目數量
  /// [excludeIds] 需要排除的題目ID集合（避免重複）
  /// [translationLang] 翻譯語言代碼
  /// 注意：返回的題目包含意大利語和翻譯語言的內容（使用 getQuestionWithTranslation）
  static Future<List<Question>> _getRandomQuestionsFromAll({
    required int count,
    required Set<String> excludeIds,
    String translationLang = 'zh',
  }) async {
    final db = await database;
    final questions = <Question>[];
    
    try {
      // 構建排除條件
      String excludeCondition = '';
      List<dynamic> queryArgs = [];
      
      if (excludeIds.isNotEmpty) {
        final placeholders = excludeIds.map((_) => '?').join(',');
        excludeCondition = ' WHERE q.id NOT IN ($placeholders)';
        queryArgs.addAll(excludeIds);
      }
      
      // 從總題庫獲取題目ID（不限制章節，獲取更多以便後續隨機選擇）
      final List<Map<String, dynamic>> questionIdMaps = await db.rawQuery('''
        SELECT q.id
        FROM questions q
        $excludeCondition
        LIMIT ?
      ''', [...queryArgs, count * 3]); // 獲取更多ID以便後續隨機選擇
      
      if (questionIdMaps.isEmpty) {
        _debugLog('⚠️ [DatabaseService] _getRandomQuestionsFromAll: 數據庫中沒有可用題目');
        return [];
      }
      
      // 提取題目ID列表
      final questionIds = questionIdMaps
          .map((map) => map['id'] as String)
          .where((id) => !excludeIds.contains(id))
          .toList();
      
      if (questionIds.isEmpty) {
        _debugLog('⚠️ [DatabaseService] _getRandomQuestionsFromAll: 所有題目都被排除了');
        return [];
      }
      
      // 隨機打亂ID列表
      questionIds.shuffle();
      final selectedIds = questionIds.take(count).toList();
      
      // 使用 getQuestionWithTranslation 獲取每個題目（包含意大利語和翻譯）
      for (final id in selectedIds) {
        try {
          final question = await getQuestionWithTranslation(id, translationLang: translationLang);
          if (question != null && !excludeIds.contains(question.id)) {
            questions.add(question);
          }
        } catch (e) {
          // 跳過解析失敗的題目，繼續處理下一個
          _debugLog('⚠️ [DatabaseService] _getRandomQuestionsFromAll 題目解析失敗: $id, 錯誤: $e');
        }
      }
    } catch (e) {
      _debugLog('❌ [DatabaseService] _getRandomQuestionsFromAll 出錯: $e');
    }
    
    return questions;
  }

  /// 根據題目ID獲取題目
  static Future<Question?> getQuestionById(String id, {String lang = 'zh'}) async {
    final db = await database;
    
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT 
        q.id,
        q.img,
        q.answer,
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
  static Future<Question?> getQuestionWithTranslation(String id, {String translationLang = 'zh'}) async {
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

    final translationMap = translationMaps.isNotEmpty ? translationMaps.first : null;
    
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
  static Future<bool> updateQuestionProgress(String questionId, bool isCorrect) async {
    final db = await userProgressDatabase;
    
    bool newlyMastered = false;
    
    // 使用事務確保操作的原子性
    await db.transaction((txn) async {
      // 1. 首先查詢當前的 correct_streak 和 is_mastered
      final result = await txn.query(
        'user_progress',
        columns: ['correct_streak', 'is_mastered'],
        where: 'question_id = ?',
        whereArgs: [questionId],
      );
      
      final currentStreak = result.isEmpty ? 0 : (result.first['correct_streak'] as int? ?? 0);
      final currentIsMastered = result.isEmpty ? 0 : (result.first['is_mastered'] as int? ?? 0);
      
      if (isCorrect) {
        // 2. 答對了：correct_streak + 1
        final newStreak = currentStreak + 1;
        // 如果達到 3，設置 is_mastered = 1
        final shouldMaster = newStreak >= 3;
        // 如果從未掌握變為掌握，標記為剛剛達成掌握
        newlyMastered = shouldMaster && currentIsMastered == 0;
        
        await txn.rawInsert('''
          INSERT INTO user_progress (question_id, correct_streak, is_mastered, last_practiced)
          VALUES (?, ?, ?, strftime('%s', 'now'))
          ON CONFLICT(question_id) DO UPDATE SET
            correct_streak = ?,
            is_mastered = ?,
            last_practiced = strftime('%s', 'now')
        ''', [questionId, newStreak, shouldMaster ? 1 : 0, newStreak, shouldMaster ? 1 : 0]);
      } else {
        // 3. 答錯了：correct_streak 重置為 0，is_mastered 設為 0，wrong_count + 1
        await txn.rawInsert('''
          INSERT INTO user_progress (question_id, error_count, wrong_count, correct_streak, is_mastered, last_practiced)
          VALUES (?, 1, 1, 0, 0, strftime('%s', 'now'))
          ON CONFLICT(question_id) DO UPDATE SET
            error_count = error_count + 1,
            wrong_count = wrong_count + 1,
            correct_streak = 0,
            is_mastered = 0,
            last_practiced = strftime('%s', 'now')
        ''', [questionId]);
        newlyMastered = false;
      }
    });
    
    return newlyMastered;
  }

  /// 記錄題目正確（練習模式）
  /// [questionId] 題目ID
  /// 增加 correct_streak，如果 >= 3 則自動標記為已掌握
  static Future<void> recordCorrectAnswer(String questionId) async {
    final db = await userProgressDatabase;
    
    // 先查詢當前的 correct_streak
    final result = await db.query(
      'user_progress',
      columns: ['correct_streak'],
      where: 'question_id = ?',
      whereArgs: [questionId],
    );
    
    final currentStreak = result.isEmpty ? 0 : (result.first['correct_streak'] as int? ?? 0);
    final newStreak = currentStreak + 1;
    
    // 如果連續答對 >= 3 次，標記為已掌握
    final shouldMaster = newStreak >= 3;
    
    await db.rawInsert('''
      INSERT INTO user_progress (question_id, correct_streak, is_mastered, last_practiced)
      VALUES (?, ?, ?, strftime('%s', 'now'))
      ON CONFLICT(question_id) DO UPDATE SET
        correct_streak = ?,
        is_mastered = ?,
        last_practiced = strftime('%s', 'now')
    ''', [questionId, newStreak, shouldMaster ? 1 : 0, newStreak, shouldMaster ? 1 : 0]);
  }

  /// 記錄題目錯誤（練習模式）
  /// [questionId] 題目ID
  /// correct_streak 歸零，取消已掌握標記，增加錯誤計數和錯題計數
  static Future<void> recordError(String questionId) async {
    final db = await userProgressDatabase;
    
    await db.rawInsert('''
      INSERT INTO user_progress (question_id, error_count, wrong_count, correct_streak, is_mastered, last_practiced)
      VALUES (?, 1, 1, 0, 0, strftime('%s', 'now'))
      ON CONFLICT(question_id) DO UPDATE SET
        error_count = error_count + 1,
        wrong_count = wrong_count + 1,
        correct_streak = 0,
        is_mastered = 0,
        last_practiced = strftime('%s', 'now')
    ''', [questionId]);
  }

  /// 記錄題目錯誤（模擬考試模式）
  /// [questionId] 題目ID
  /// 只記錄錯誤計數和錯題計數，不影響 correct_streak（因為考試是檢測，不是學習）
  static Future<void> recordErrorInExam(String questionId) async {
    final db = await userProgressDatabase;
    
    await db.rawInsert('''
      INSERT INTO user_progress (question_id, error_count, wrong_count, last_practiced)
      VALUES (?, 1, 1, strftime('%s', 'now'))
      ON CONFLICT(question_id) DO UPDATE SET
        error_count = error_count + 1,
        wrong_count = wrong_count + 1,
        last_practiced = strftime('%s', 'now')
    ''', [questionId]);
  }

  /// 更新練習進度（記錄用戶完成一道題）
  /// [questionId] 題目ID
  /// 異步更新 last_practiced 字段
  static Future<void> updatePracticeProgress(String questionId) async {
    final db = await userProgressDatabase;
    
    // 異步更新 last_practiced 字段，如果記錄不存在則創建
    await db.rawInsert('''
      INSERT INTO user_progress (question_id, last_practiced)
      VALUES (?, strftime('%s', 'now'))
      ON CONFLICT(question_id) DO UPDATE SET
        last_practiced = strftime('%s', 'now')
    ''', [questionId]);
  }

  /// 標記題目為已掌握
  /// [questionId] 題目ID
  static Future<void> markAsMastered(String questionId) async {
    final db = await userProgressDatabase;
    
    await db.rawInsert('''
      INSERT INTO user_progress (question_id, is_mastered, last_practiced)
      VALUES (?, 1, strftime('%s', 'now'))
      ON CONFLICT(question_id) DO UPDATE SET
        is_mastered = 1,
        last_practiced = strftime('%s', 'now')
    ''', [questionId]);
  }

  /// 取消題目的已掌握標記
  /// [questionId] 題目ID
  static Future<void> unmarkAsMastered(String questionId) async {
    final db = await userProgressDatabase;
    
    await db.update(
      'user_progress',
      {'is_mastered': 0},
      where: 'question_id = ?',
      whereArgs: [questionId],
    );
  }

  /// 切換收藏狀態
  static Future<void> toggleFavorite(String questionId) async {
    final db = await userProgressDatabase;
    
    // 先查詢當前狀態
    final result = await db.query(
      'user_progress',
      where: 'question_id = ?',
      whereArgs: [questionId],
    );

    final newFavoriteStatus = result.isEmpty || (result.first['is_favorite'] as int) == 0 ? 1 : 0;

    await db.rawInsert('''
      INSERT INTO user_progress (question_id, is_favorite, last_practiced)
      VALUES (?, ?, strftime('%s', 'now'))
      ON CONFLICT(question_id) DO UPDATE SET
        is_favorite = ?,
        last_practiced = strftime('%s', 'now')
    ''', [questionId, newFavoriteStatus, newFavoriteStatus]);
  }

  /// 獲取題目的收藏狀態
  static Future<bool> isFavorite(String questionId) async {
    final db = await userProgressDatabase;
    
    final result = await db.query(
      'user_progress',
      columns: ['is_favorite'],
      where: 'question_id = ?',
      whereArgs: [questionId],
    );

    if (result.isEmpty) return false;
    return (result.first['is_favorite'] as int) == 1;
  }

  /// 獲取題目的錯誤次數
  static Future<int> getErrorCount(String questionId) async {
    final db = await userProgressDatabase;
    
    final result = await db.query(
      'user_progress',
      columns: ['error_count'],
      where: 'question_id = ?',
      whereArgs: [questionId],
    );

    if (result.isEmpty) return 0;
    return result.first['error_count'] as int;
  }

  /// 獲取所有收藏的題目ID列表
  static Future<List<String>> getFavoriteQuestionIds() async {
    final db = await userProgressDatabase;
    
    final result = await db.query(
      'user_progress',
      columns: ['question_id'],
      where: 'is_favorite = ?',
      whereArgs: [1],
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
  static Future<int> getAnsweredQuestionsCount() async {
    final db = await userProgressDatabase;
    final result = await db.rawQuery('SELECT COUNT(DISTINCT question_id) as count FROM user_progress WHERE last_practiced IS NOT NULL');
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
  static Future<Map<int, int>> getChapterErrorDistribution(List<String> errorQuestionIds) async {
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

  /// 根據題目ID列表獲取題目列表（包含章節信息）
  /// [questionIds] 題目ID列表
  /// [lang] 語言代碼，默認為當前語言
  static Future<List<Question>> getQuestionsByIds(List<String> questionIds, {String lang = 'zh'}) async {
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
  static Future<List<String>> getErrorQuestionIds() async {
    final db = await userProgressDatabase;
    
    final result = await db.query(
      'user_progress',
      columns: ['question_id'],
      where: 'error_count > ?',
      whereArgs: [0],
      orderBy: 'error_count DESC, last_practiced DESC', // 按錯誤次數和最近練習時間排序
    );

    return result.map((row) => row['question_id'] as String).toList();
  }

  /// 獲取錯題列表（包含題目內容）
  /// [lang] 語言代碼，默認為當前語言
  static Future<List<Question>> getErrorQuestions({String lang = 'zh'}) async {
    final errorIds = await getErrorQuestionIds();
    if (errorIds.isEmpty) return [];
    
    final questions = <Question>[];
    for (final id in errorIds) {
      // 獲取意大利語題目
      final questionIt = await getQuestionById(id, lang: 'it');
      if (questionIt == null) continue;
      
      // 如果指定語言不是意大利語，獲取翻譯並合併
      if (lang != 'it') {
        final questionTrans = await getQuestionById(id, lang: lang);
        if (questionTrans != null) {
          questions.add(questionIt.mergeLanguages(questionTrans));
        } else {
          questions.add(questionIt);
        }
      } else {
        questions.add(questionIt);
      }
    }
    
    return questions;
  }

  /// 獲取錯題列表（包含題目內容）
  /// 這是 getErrorQuestions() 的別名方法，為了保持API一致性
  /// [lang] 語言代碼，默認為當前語言
  static Future<List<Question>> getWrongQuestions({String lang = 'zh'}) async {
    return getErrorQuestions(lang: lang);
  }

  /// 清除題目的錯誤計數（當用戶在錯題回顧中答對時調用）
  /// [questionId] 題目ID
  static Future<void> clearErrorCount(String questionId) async {
    final db = await userProgressDatabase;
    
    // 將 error_count 設置為 0
    await db.update(
      'user_progress',
      {'error_count': 0},
      where: 'question_id = ?',
      whereArgs: [questionId],
    );
  }

  /// 減少題目的錯誤計數（可選：如果答對一次就減少錯誤計數，而不是直接清零）
  /// [questionId] 題目ID
  static Future<void> decreaseErrorCount(String questionId) async {
    final db = await userProgressDatabase;
    
    // 先獲取當前錯誤計數
    final result = await db.query(
      'user_progress',
      columns: ['error_count'],
      where: 'question_id = ?',
      whereArgs: [questionId],
    );

    if (result.isNotEmpty) {
      final currentCount = result.first['error_count'] as int;
      if (currentCount > 0) {
        await db.update(
          'user_progress',
          {'error_count': currentCount - 1},
          where: 'question_id = ?',
          whereArgs: [questionId],
        );
      }
    }
  }

  /// 獲取章節練習進度統計
  /// [chapterId] 章節ID（1-25）
  /// 返回包含以下信息的 Map：
  ///   - 'total': 該章節的總題數
  ///   - 'practiced': 已做過的題數（last_practiced IS NOT NULL）
  ///   - 'mastered': 已掌握的題數（is_mastered = 1）
  static Future<Map<String, int>> getChapterProgress(int chapterId) async {
    final db = await database;
    final userProgressDb = await userProgressDatabase;
    
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
    final questionIds = questionIdsResult.map((row) => row['id'] as String).toList();
    
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
      WHERE question_id IN ($placeholders) AND last_practiced IS NOT NULL
    ''', questionIds);
    final practiced = (practicedResult.first['count'] as int?) ?? 0;
    
    // 獲取已掌握的題數（is_mastered = 1）
    final masteredResult = await userProgressDb.rawQuery('''
      SELECT COUNT(DISTINCT question_id) as count
      FROM user_progress
      WHERE question_id IN ($placeholders) AND is_mastered = 1
    ''', questionIds);
    final mastered = (masteredResult.first['count'] as int?) ?? 0;
    
    return {
      'total': total,
      'practiced': practiced,
      'mastered': mastered,
    };
  }

  /// 獲取已掌握的題目總數
  /// 返回當前用戶已掌握的題目數量（is_mastered = 1）
  static Future<int> getMasteredCount() async {
    final userProgressDb = await userProgressDatabase;
    
    // 獲取已掌握的題目數
    final masteredResult = await userProgressDb.rawQuery('''
      SELECT COUNT(DISTINCT question_id) as count
      FROM user_progress
      WHERE is_mastered = 1
    ''');
    final mastered = (masteredResult.first['count'] as int?) ?? 0;
    
    return mastered;
  }

  /// 獲取全局掌握百分比
  /// 返回已掌握題目數 / 總題目數的百分比（0.0 - 1.0）
  static Future<double> getTotalMasteryPercentage() async {
    final db = await database;
    final userProgressDb = await userProgressDatabase;
    
    // 獲取總題目數
    final totalResult = await db.rawQuery('SELECT COUNT(*) as count FROM questions WHERE chapter IS NOT NULL');
    final total = (totalResult.first['count'] as int?) ?? 0;
    
    if (total == 0) return 0.0;
    
    // 獲取已掌握的題目數
    final masteredResult = await userProgressDb.rawQuery('''
      SELECT COUNT(DISTINCT question_id) as count
      FROM user_progress
      WHERE is_mastered = 1
    ''');
    final mastered = (masteredResult.first['count'] as int?) ?? 0;
    
    return mastered / total;
  }

  /// 關閉數據庫連接（應用退出時調用）
  static Future<void> close() async {
    await _database?.close();
    await _userProgressDatabase?.close();
    _database = null;
    _userProgressDatabase = null;
  }
}
