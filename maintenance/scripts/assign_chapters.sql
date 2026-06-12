-- 为题目分配章节ID的SQL脚本
-- 使用方法：sqlite3 italy_quiz.db < assign_chapters.sql
--
-- 注意：这是一个模板脚本，您需要根据实际的题目分布情况来分配章节
-- 目前所有题目的 chapter_id 都是 NULL，需要根据业务逻辑进行分配

-- 示例：为部分题目分配章节ID（请根据实际情况修改）
-- UPDATE questions SET chapter_id = 1 WHERE id IN ('10', '100', '1000', ...);
-- UPDATE questions SET chapter_id = 2 WHERE id IN ('20', '200', '2000', ...);
-- ... 依此类推

-- 如果您有题目ID和章节的对应关系，可以使用以下格式批量更新：
-- UPDATE questions SET chapter_id = ? WHERE id IN (?, ?, ?, ...);

-- 或者，如果您想为所有题目随机分配章节（仅用于测试）：
-- UPDATE questions SET chapter_id = (ABS(RANDOM()) % 25) + 1;

-- 检查分配结果：
-- SELECT chapter_id, COUNT(*) as count FROM questions GROUP BY chapter_id ORDER BY chapter_id;

