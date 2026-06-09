import '../services/database_service.dart';

/// 章节分配服务
/// 用于为题目分配章节ID（chapter）
/// 
/// 注意：这是一个工具类，用于初始化或更新题目的章节分配
/// 在生产环境中，可能需要管理员权限或通过其他方式分配
class ChapterAssignmentService {
  /// 为指定题目ID分配章节
  /// [questionIds] 题目ID列表
  /// [chapterId] 章节ID（1-25）
  static Future<bool> assignChapterToQuestions(
    List<String> questionIds,
    int chapterId,
  ) async {
    if (questionIds.isEmpty || chapterId < 1 || chapterId > 25) {
      return false;
    }

    try {
      final db = await DatabaseService.database;
      
      // 构建 UPDATE 语句
      final placeholders = questionIds.map((_) => '?').join(',');
      final result = await db.rawUpdate(
        'UPDATE questions SET chapter = ? WHERE id IN ($placeholders)',
        [chapterId, ...questionIds],
      );

      return result > 0;
    } catch (e) {
      return false;
    }
  }

  /// 为单个题目分配章节
  /// [questionId] 题目ID
  /// [chapterId] 章节ID（1-25）
  static Future<bool> assignChapterToQuestion(
    String questionId,
    int chapterId,
  ) async {
    return await assignChapterToQuestions([questionId], chapterId);
  }

  /// 获取指定章节的题目数量
  /// [chapterId] 章节ID（1-25），如果为 null 则返回所有章节的统计
  static Future<Map<int, int>> getQuestionsCountByChapter({int? chapterId}) async {
    try {
      final db = await DatabaseService.database;
      
      String query = '''
        SELECT chapter, COUNT(*) as count
        FROM questions
      ''';
      
      List<dynamic> args = [];
      if (chapterId != null) {
        query += ' WHERE chapter = ?';
        args.add(chapterId);
      } else {
        query += ' WHERE chapter IS NOT NULL';
      }
      
      query += ' GROUP BY chapter ORDER BY chapter';

      final result = await db.rawQuery(query, args);
      
      final counts = <int, int>{};
      for (final row in result) {
        final cid = row['chapter'] as int?;
        final count = row['count'] as int?;
        if (cid != null && count != null) {
          counts[cid] = count;
        }
      }
      
      return counts;
    } catch (e) {
      return {};
    }
  }

  /// 获取未分配章节的题目数量
  static Future<int> getUnassignedQuestionsCount() async {
    try {
      final db = await DatabaseService.database;
      final result = await db.rawQuery(
        'SELECT COUNT(*) as count FROM questions WHERE chapter IS NULL',
      );
      return (result.first['count'] as int?) ?? 0;
    } catch (e) {
      return 0;
    }
  }

  /// 清空所有题目的章节分配（谨慎使用！）
  static Future<bool> clearAllChapterAssignments() async {
    try {
      final db = await DatabaseService.database;
      await db.rawUpdate('UPDATE questions SET chapter = NULL');
      return true;
    } catch (e) {
      return false;
    }
  }
}
