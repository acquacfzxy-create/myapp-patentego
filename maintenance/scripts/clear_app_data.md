# 清除应用数据以强制刷新数据库

如果应用仍然显示旧数据，可以手动清除应用数据：

## iOS 模拟器

```bash
# 删除应用数据目录
rm -rf ~/Library/Developer/CoreSimulator/Devices/*/data/Containers/Data/Application/*/Documents/italy_quiz.db
```

或者：
1. 在模拟器中长按应用图标
2. 选择"删除应用"
3. 重新安装并运行应用

## macOS 应用

```bash
# 查找并删除数据库文件
find ~/Library/Containers -name "italy_quiz.db" -delete
```

或者：
1. 完全退出应用
2. 删除应用数据目录中的数据库文件
3. 重新运行应用

## Android 模拟器/设备

```bash
# 通过 adb 清除应用数据
adb shell pm clear com.patentego.app
```

或者：
1. 设置 → 应用 → 找到应用 → 清除数据
2. 重新运行应用

## 验证

清除数据后，重新运行应用，查看控制台日志：
- 应该看到 "📥 [Database] 重新從 assets 複製數據庫文件（包含關鍵詞數據）..."
- 应该看到 "📊 [Database] 檢查關鍵詞數據: XXXX 道題目有關鍵詞"
