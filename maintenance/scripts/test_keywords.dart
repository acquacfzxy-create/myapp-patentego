import 'dart:io';
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

void main() async {
  // 获取数据库路径
  final documentsDirectory = await getApplicationDocumentsDirectory();
  final dbPath = join(documentsDirectory.path, 'italy_quiz.db');

  print('📂 数据库路径: $dbPath');

  // 检查文件是否存在
  final file = File(dbPath);
  if (!await file.exists()) {
    print('❌ 数据库文件不存在: $dbPath');
    print('💡 提示：应用可能还没有初始化数据库');
    return;
  }

  // 打开数据库
  final db = await openDatabase(dbPath);

  // 查询一道有关键词的题目
  final result = await db.rawQuery('''
    SELECT
      q.id,
      q.keywords_json,
      t.content as question_text
    FROM questions q
    LEFT JOIN translations t ON q.id = t.question_id AND t.lang = 'it' AND t.type = 'q'
    WHERE q.keywords_json IS NOT NULL
    AND q.keywords_json != ''
    AND q.keywords_json != '[]'
    LIMIT 1
  ''');

  if (result.isEmpty) {
    print('❌ 没有找到有关键词的题目');
    print('💡 提示：数据库可能还没有更新');
  } else {
    final row = result.first;
    final id = row['id'];
    final keywordsJson = row['keywords_json'] as String?;
    final questionText = row['question_text'];

    print('✅ 找到题目 ID: $id');
    print('📝 题目文本: $questionText');
    print('📦 keywords_json: $keywordsJson');

    // 尝试解析 JSON
    if (keywordsJson != null && keywordsJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(keywordsJson) as List;
        print('✅ JSON 解析成功');
        print('📊 关键词数量: ${decoded.length}');
        for (var i = 0; i < decoded.length; i++) {
          final keyword = decoded[i] as Map;
          print('   ${i + 1}. ${keyword['it']} → ${keyword['zh']}');
        }
      } catch (e) {
        print('❌ JSON 解析失败: $e');
      }
    }
  }

  // 统计
  final countResult = await db.rawQuery('''
    SELECT COUNT(*) as count
    FROM questions
    WHERE keywords_json IS NOT NULL
    AND keywords_json != ''
    AND keywords_json != '[]'
  ''');
  final count = countResult.first['count'] as int? ?? 0;
  print('\n📊 统计: $count 道题目有关键词数据');

  await db.close();
}
