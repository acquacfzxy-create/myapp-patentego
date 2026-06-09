# Provider 状态管理重构方案

## 📊 当前问题分析

### 1. 语言切换分散管理
- `AppStrings.currentLanguage` 是静态变量，无法响应式更新
- 各页面需要手动调用 `setState()` 刷新
- `HomeScreen` 使用 `didChangeDependencies()` 监听，不够优雅

### 2. 会员状态分散管理
- `AppConfig.isUserPremium` 是静态变量
- `UserState.isPremium` 存在但未使用
- 两套状态管理系统，容易不同步

### 3. 缺少响应式更新机制
- 无法实现"一处修改，全屏响应"
- 代码耦合度高，难以维护

## ✅ 解决方案：引入 Provider

### 优势
1. ✅ **响应式更新**：一处修改，所有监听者自动更新
2. ✅ **集中管理**：全局状态统一管理，避免分散
3. ✅ **易于测试**：Provider 模式易于单元测试
4. ✅ **代码清晰**：状态管理逻辑集中，职责分明
5. ✅ **已集成**：`pubspec.yaml` 中已包含 `provider: ^6.1.1`

## 📋 重构步骤

### 步骤1：创建 UserStateProvider ✅
- 文件：`lib/providers/user_state_provider.dart`
- 功能：管理用户状态（语言、会员状态）
- 方法：`changeLanguage()`, `setPremium()`

### 步骤2：更新 main.dart
```dart
// 使用 ChangeNotifierProvider 包裹应用
runApp(
  ChangeNotifierProvider(
    create: (_) => UserStateProvider(),
    child: const MyApp(),
  ),
);

// MyApp 使用 Consumer 监听状态变化
class MyApp extends StatelessWidget {
  Widget build(BuildContext context) {
    return Consumer<UserStateProvider>(
      builder: (context, provider, child) {
        // 自动响应语言变化
        return MaterialApp(...);
      },
    );
  }
}
```

### 步骤3：重构 SettingsScreen
```dart
// 使用 Provider 读取和更新状态
class _SettingsScreenState extends State<SettingsScreen> {
  void _changeLanguage(String newLanguage) {
    // 只需要调用 Provider 方法，UI 自动更新
    context.read<UserStateProvider>().changeLanguage(newLanguage);
    Navigator.pop(context);
  }

  Widget build(BuildContext context) {
    return Consumer<UserStateProvider>(
      builder: (context, provider, child) {
        // 自动获取当前语言
        final currentLang = provider.currentLanguage;
        return ListTile(
          title: Text(UserState.languageNames[currentLang] ?? currentLang),
        );
      },
    );
  }
}
```

### 步骤4：重构其他页面
- **HomeScreen**: 使用 `Consumer` 监听语言变化
- **PracticeScreen**: 使用 `Provider.of` 获取当前语言
- **MockTestScreen**: 使用 `Provider.of` 获取当前语言
- **MistakeReviewScreen**: 使用 `Provider.of` 获取当前语言

### 步骤5：整合 AppConfig
- 将会员状态管理迁移到 `UserStateProvider`
- 删除 `AppConfig.isUserPremium` 静态变量
- 使用 `provider.isPremium` 替代

## 🎯 使用示例

### 读取状态
```dart
// 方式1：使用 Consumer（推荐，自动重建）
Consumer<UserStateProvider>(
  builder: (context, provider, child) {
    return Text('当前语言: ${provider.currentLanguage}');
  },
)

// 方式2：使用 Provider.of（仅在需要时读取）
final provider = Provider.of<UserStateProvider>(context);
final lang = provider.currentLanguage;

// 方式3：使用 context.read（只读取，不监听）
final provider = context.read<UserStateProvider>();
```

### 更新状态
```dart
// 切换语言
context.read<UserStateProvider>().changeLanguage('en');

// 设置会员状态
context.read<UserStateProvider>().setPremium(true);
```

## 📝 注意事项

1. **向后兼容**：Provider 会同步更新 `AppStrings`，保持旧代码兼容
2. **持久化存储**：未来可扩展为使用 `SharedPreferences` 保存状态
3. **性能优化**：使用 `Consumer` 时，可以通过 `child` 参数优化性能
4. **测试友好**：Provider 模式易于 Mock 和测试

## ⚠️ 迁移风险

- **低风险**：Provider 已集成，无需额外安装
- **渐进式迁移**：可以逐步迁移，新旧代码可以共存
- **向后兼容**：Provider 会同步更新 `AppStrings`，旧代码仍可工作
