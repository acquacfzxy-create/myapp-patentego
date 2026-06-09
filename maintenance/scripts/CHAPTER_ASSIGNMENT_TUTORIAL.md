# 数据库章节分配 - 保姆级教程

## 📋 准备工作

### 方法1：使用命令行 sqlite3（推荐，macOS 自带）

macOS 系统自带 `sqlite3` 工具，无需安装。

### 方法2：使用图形化工具 DB Browser for SQLite（可选）

如果不想用命令行，可以下载安装：
- 下载地址：https://sqlitebrowser.org/dl/
- 下载 macOS 版本，安装后打开数据库文件

---

## 🚀 方法1：使用命令行（推荐）

### 步骤1：打开终端

1. 按 `Command + Space` 打开 Spotlight
2. 输入 "Terminal" 或 "终端"
3. 回车打开终端

### 步骤2：进入项目目录

```bash
cd /path/to/assets
```

### 步骤3：备份数据库（重要！）

在执行任何修改之前，先备份数据库：

```bash
cp assets/italy_quiz.db assets/italy_quiz.db.backup
```

### 步骤4：检查数据库当前状态

```bash
sqlite3 assets/italy_quiz.db "PRAGMA table_info(questions);"
```

这会显示 `questions` 表的所有字段。查看是否有 `chapter` 字段。

### 步骤5：添加 chapter 字段（如果还没有）

```bash
sqlite3 assets/italy_quiz.db "ALTER TABLE questions ADD COLUMN chapter INTEGER;"
```

### 步骤6：验证字段已添加

```bash
sqlite3 assets/italy_quiz.db "PRAGMA table_info(questions);"
```

现在应该能看到 `chapter` 字段了。

### 步骤7：执行章节分配 SQL

执行修复后的 SQL 脚本：

```bash
sqlite3 assets/italy_quiz.db < maintenance/scripts/assign_chapters_fixed.sql
```

**注意**：这可能需要几秒钟时间，因为要更新约 5000 道题目。

### 步骤8：验证分配结果

#### 8.1 查看每个章节的题目数量

```bash
sqlite3 assets/italy_quiz.db "SELECT chapter, COUNT(*) as count FROM questions WHERE chapter IS NOT NULL GROUP BY chapter ORDER BY chapter;"
```

你应该看到 1-25 章节的题目分布。

#### 8.2 查看未分配的题目数量

```bash
sqlite3 assets/italy_quiz.db "SELECT COUNT(*) as unassigned FROM questions WHERE chapter IS NULL;"
```

理想情况下应该是 0，或至少是很少的数字（< 100）。

#### 8.3 查看总题目数

```bash
sqlite3 assets/italy_quiz.db "SELECT COUNT(*) as total FROM questions;"
```

### 步骤9：验证分配结果（详细查看）

查看每个章节的题目数量分布：

```bash
sqlite3 assets/italy_quiz.db "SELECT chapter, COUNT(*) as count FROM questions WHERE chapter IS NOT NULL GROUP BY chapter ORDER BY chapter;" | cat
```

查看具体某个章节的题目 ID 示例（例如查看章节 1 的前 10 个题目）：

```bash
sqlite3 assets/italy_quiz.db "SELECT id FROM questions WHERE chapter = 1 LIMIT 10;" | cat
```

---

## 🖥️ 方法2：使用 DB Browser for SQLite（图形化工具）

### 步骤1：下载安装

1. 访问：https://sqlitebrowser.org/dl/
2. 下载 macOS 版本（.dmg 文件）
3. 安装并打开应用

### 步骤2：打开数据库

1. 点击 "打开数据库" 按钮
2. 导航到项目内的 `assets/italy_quiz.db`
3. 选择并打开

### 步骤3：备份数据库（重要！）

1. 菜单栏：文件 → 另存为
2. 保存为 `italy_quiz.db.backup`

### 步骤4：执行 SQL

1. 点击顶部标签 "执行 SQL"
2. 在 SQL 编辑器中，先执行添加字段的 SQL：

```sql
ALTER TABLE questions ADD COLUMN chapter INTEGER;
```

3. 点击 "执行 SQL" 按钮（或按 F5）

4. 然后打开 `maintenance/scripts/assign_chapters_fixed.sql` 文件，复制所有内容
5. 粘贴到 SQL 编辑器中
6. 点击 "执行 SQL" 按钮

### 步骤5：验证结果

1. 点击顶部标签 "浏览数据"
2. 选择表 `questions`
3. 查看是否有 `chapter` 列
4. 点击 "执行 SQL" 标签，执行验证查询：

```sql
SELECT chapter, COUNT(*) as count
FROM questions
WHERE chapter IS NOT NULL
GROUP BY chapter
ORDER BY chapter;
```

---

## ✅ 验证步骤（两种方法都需要）

执行以下 SQL 来验证分配结果：

### 1. 查看章节分布

```sql
SELECT chapter, COUNT(*) as count
FROM questions
WHERE chapter IS NOT NULL
GROUP BY chapter
ORDER BY chapter;
```

应该看到 1-25 章节，每个章节都有题目。

### 2. 查看未分配的题目

```sql
SELECT COUNT(*) as unassigned
FROM questions
WHERE chapter IS NULL;
```

应该接近 0（可能有一些题目无法匹配）。

### 3. 查看总题目数

```sql
SELECT COUNT(*) as total FROM questions;
```

应该看到总题目数（约 7000+）。

---

## ⚠️ 常见问题

### Q1：提示 "no such column: chapter"

**原因**：字段还没有添加。

**解决**：先执行 `ALTER TABLE questions ADD COLUMN chapter INTEGER;`

### Q2：执行 SQL 时提示语法错误

**原因**：SQL 脚本可能有格式问题。

**解决**：
1. 确保使用的是 `maintenance/scripts/assign_chapters_fixed.sql`（不是 `assign_chapters_v2.sql`）
2. 检查 SQL 文件是否完整
3. 如果使用命令行，确保命令正确：`sqlite3 assets/italy_quiz.db < maintenance/scripts/assign_chapters_fixed.sql`

### Q3：如何撤销更改

如果你有备份文件：

```bash
cp assets/italy_quiz.db.backup assets/italy_quiz.db
```

### Q4：章节分配后，App 中还是不显示章节

**原因**：App 启动时可能会重新复制数据库文件。

**解决**：
1. 确保修改的是 `assets/italy_quiz.db`（源文件）
2. 删除 App 数据，重新安装 App
3. 或者确保 App 的数据库初始化逻辑不会覆盖已修改的数据库

---

## 📝 快速命令参考（命令行方法）

```bash
# 1. 进入项目目录
cd /path/to/assets

# 2. 备份数据库
cp assets/italy_quiz.db assets/italy_quiz.db.backup

# 3. 添加 chapter 字段
sqlite3 assets/italy_quiz.db "ALTER TABLE questions ADD COLUMN chapter INTEGER;"

# 4. 执行章节分配
sqlite3 assets/italy_quiz.db < maintenance/scripts/assign_chapters_fixed.sql

# 5. 验证结果
sqlite3 assets/italy_quiz.db "SELECT chapter, COUNT(*) as count FROM questions WHERE chapter IS NOT NULL GROUP BY chapter ORDER BY chapter;"
```

---

## 🎉 完成后的下一步

章节分配完成后，你需要：

1. **测试 App**：运行 Flutter App，确保章节功能正常工作
2. **恢复模拟考试的章节抽取功能**：修改 `MockTestScreen` 使用 `getMockTestQuestions` 方法

---

## 📞 需要帮助？

如果遇到问题，可以：

1. 检查终端输出的错误信息
2. 验证 SQL 文件是否存在：`ls -l maintenance/scripts/assign_chapters_fixed.sql`
3. 检查数据库文件是否存在：`ls -lh assets/italy_quiz.db`
