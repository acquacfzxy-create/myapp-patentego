-- 数据库迁移脚本：添加 chapter_id 字段
-- 执行方式：sqlite3 italy_quiz.db < add_chapter_id.sql

-- 添加 chapter_id 字段（允许 NULL，默认值为 NULL）
ALTER TABLE questions ADD COLUMN chapter_id INTEGER;

-- 注意：这里只是添加字段，不填充数据
-- 数据的填充需要根据业务逻辑进行
-- 例如：根据题目ID的规则、或者手动分配等

