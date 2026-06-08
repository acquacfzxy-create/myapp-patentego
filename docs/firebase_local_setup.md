# Firebase 本地配置说明

本项目的 Firebase 配置文件只放在本机，不提交到 Git。新机器或干净 checkout 后，需要先生成这些文件，再运行包含登录、Firestore 同步或发布构建的流程。

## 需要生成的本地文件

- `lib/firebase_options.dart`
- `android/app/google-services.json`
- `ios/Runner/GoogleService-Info.plist`
- `macos/Runner/GoogleService-Info.plist`

这些文件已经被 `.gitignore` 忽略，不要 commit。

## 前置条件

- 有 Firebase 项目访问权限。
- 本机已安装 Firebase CLI。
- 本机已安装 FlutterFire CLI。

```bash
dart pub global activate flutterfire_cli
firebase login
```

## 生成配置

在仓库根目录执行：

```bash
cd /path/to/assets
flutterfire configure \
  --project italy-patente-b \
  --platforms android,ios,macos \
  --android-package-name com.patentego.app \
  --ios-bundle-id com.patentego.app \
  --macos-bundle-id com.patentego.app \
  --out lib/firebase_options.dart
```

完成后确认文件存在：

```bash
test -f lib/firebase_options.dart
test -f android/app/google-services.json
test -f ios/Runner/GoogleService-Info.plist
test -f macos/Runner/GoogleService-Info.plist
```

Android 配置必须包含当前包名 `com.patentego.app`。iOS 和 macOS 配置的 bundle id 也应为 `com.patentego.app`。

## Firestore 规则校验

只做 dry-run，不发布：

```bash
firebase deploy --only firestore:rules --dry-run --project italy-patente-b
```

真正发布规则前需要维护者明确确认。

## 降级行为

App 启动时会尝试初始化 Firebase。若运行环境的 Firebase 配置异常，离线题库和本地学习进度仍应可用；登录、云端同步、Firestore VIP 恢复等功能会跳过或提示不可用。

注意：如果 `lib/firebase_options.dart` 完全不存在，Dart 编译会失败。新机器首次运行前必须先生成本文件。
