# 题目章节匹配指南

## 当前匹配情况

- **JSON题目总数**: 7139
- **数据库题目总数**: 7139
- **已匹配题目**: ~4000-5000 道（约 56-70%）
- **未匹配题目**: ~2000-3000 道（约 30-44%）

## 未匹配的主要原因

### 1. 多个候选题目 (multiple_matches) - **最主要问题**

同一张图片在数据库中对应多道不同的题目（不同的问题文本，相同的图片）。

**原因**: 
- 意大利驾照考试中，很多题目使用相同的交通标志图片
- 每道题目问的是关于这张图片的不同方面

**解决方案**:
- ✅ 已实现：使用题目内容相似度匹配（SequenceMatcher）
- ✅ 已实现：标准化图片路径匹配
- ⚠️ 需要：提高内容匹配的精确度

### 2. 空图片路径

部分题目在JSON中没有图片路径（img字段为空）。

**解决方案**:
- 完全依赖题目内容匹配
- 可以使用相似度算法查找最接近的题目

## 改进的匹配策略

### 策略1: 图片路径标准化匹配
- 统一路径格式（去除前导/，统一使用正斜杠）
- 大小写不敏感匹配

### 策略2: 题目内容相似度匹配
- 使用 `SequenceMatcher` 计算相似度
- 相似度阈值：0.8（精确匹配）或 0.6（模糊匹配）
- 标准化文本（去除标点符号，统一空格）

### 策略3: 答案匹配
- 确保答案（True/False）与数据库中的（1/0）一致

## 使用方法

### 方法1: 使用改进的匹配脚本（推荐）

```bash
# 运行改进的匹配脚本
python3 scripts/improved_matching_v2.py

# 查看生成的SQL脚本
cat scripts/assign_chapters_v2.sql

# 备份数据库后执行
cp assets/italy_quiz.db assets/italy_quiz.db.backup
sqlite3 assets/italy_quiz.db < scripts/assign_chapters_v2.sql
```

### 方法2: 手动匹配未匹配的题目

1. 查看未匹配题目列表：
   ```bash
   cat scripts/unmatched_v2.json
   ```

2. 手动检查并分配章节

3. 使用 `ChapterAssignmentService` 在代码中分配：
   ```dart
   await ChapterAssignmentService.assignChapterToQuestion('question_id', chapter_id);
   ```

### 方法3: 调整匹配参数

如果匹配率仍然不理想，可以调整 `improved_matching_v2.py` 中的参数：

```python
# 在 match_questions_v2 函数中
similarity_threshold=0.8  # 降低到0.6-0.7以提高匹配率（但可能增加误匹配）
```

## 分配优先级建议

1. **先分配已匹配的题目** (~4000-5000题)
   - 这些题目的匹配度较高，可以立即使用
   - 使用生成的SQL脚本批量分配

2. **手动处理关键章节**
   - 对于重点章节（1-15），优先确保题目分配完整
   - 可以手动检查部分题目，确保准确性

3. **未匹配题目的处理**
   - 可以先不分配，留待后续处理
   - 或者使用较低的相似度阈值尝试匹配（需要人工验证）

## 验证分配结果

```sql
-- 查看各章节的题目数量
SELECT chapter_id, COUNT(*) as count 
FROM questions 
WHERE chapter_id IS NOT NULL 
GROUP BY chapter_id 
ORDER BY chapter_id;

-- 查看未分配的题目数量
SELECT COUNT(*) as unassigned 
FROM questions 
WHERE chapter_id IS NULL;

-- 查看某个章节的题目示例
SELECT id, img 
FROM questions 
WHERE chapter_id = 1 
LIMIT 10;
```

## 注意事项

⚠️ **执行SQL脚本前务必备份数据库！**

⚠️ **如果匹配结果不理想，可以：**
- 调整匹配算法参数
- 手动检查部分题目
- 分批处理（先处理匹配度高的，再处理未匹配的）

⚠️ **建议先在小范围测试**：
- 可以先只分配一个章节，验证结果正确后再批量分配

