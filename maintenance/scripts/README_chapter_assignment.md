# 章节分配指南

## 问题说明

目前数据库中的所有题目的 `chapter_id` 都是 NULL，导致章节练习功能无法正常工作。

## 解决方案

有两种方式为题目分配章节ID：

### 方法1：使用 SQL 脚本（推荐）

1. **准备数据**：确定每道题目应该属于哪个章节（1-25）
2. **修改脚本**：编辑 `scripts/assign_chapters.sql`，填入题目ID和章节对应关系
3. **执行脚本**：
   ```bash
   sqlite3 assets/italy_quiz.db < scripts/assign_chapters.sql
   ```

**示例**：
```sql
-- 为题目分配章节
UPDATE questions SET chapter_id = 1 WHERE id IN ('10', '100', '1000');
UPDATE questions SET chapter_id = 2 WHERE id IN ('20', '200', '2000');
-- ... 依此类推
```

### 方法2：使用 Dart 服务类

在代码中调用 `ChapterAssignmentService`：

```dart
import 'package:your_app/services/chapter_assignment_service.dart';

// 为多道题目分配章节
await ChapterAssignmentService.assignChapterToQuestions(
  ['10', '100', '1000'],  // 题目ID列表
  1,  // 章节ID（1-25）
);

// 为单道题目分配章节
await ChapterAssignmentService.assignChapterToQuestion('10', 1);

// 查看分配统计
final counts = await ChapterAssignmentService.getQuestionsCountByChapter();
print('各章节题目数量: $counts');

// 查看未分配题目数量
final unassigned = await ChapterAssignmentService.getUnassignedQuestionsCount();
print('未分配题目数: $unassigned');
```

## 如何确定题目与章节的对应关系？

这需要根据您的业务需求来决定：

1. **如果有官方分类数据**：直接导入对应的章节ID
2. **如果没有分类数据**：
   - 查看题目内容，根据题目内容判断所属章节
   - 例如：关于"交通标志"的题目 → 章节1
   - 关于"优先权"的题目 → 章节2
   - 等等...

## 章节列表（参考）

章节配置在 `lib/config/chapter_config.dart` 中定义，包括：

**重点章节（1-15）**：
1. Segnaletica stradale (交通標誌)
2. Precedenza (優先通行權)
3. Sosta e fermata (停車與停止)
... 等等

**次要章节（16-25）**：
16. Guida ecologica (生態駕駛)
... 等等

## 注意事项

- 章节ID范围是 1-25
- 一道题目只能属于一个章节
- 建议在分配前备份数据库
- 分配完成后，章节练习功能即可正常使用

