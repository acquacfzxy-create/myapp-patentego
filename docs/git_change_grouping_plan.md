# Git 变更分组计划

本文件用于把当前大版本级 diff 拆成可审查、可提交的批次。执行原则：

- 不提交真实密钥、keystore、Firebase 本地配置、日志、缓存或构建产物。
- 每一批提交前至少跑对应检查；功能批次提交前跑 `flutter analyze` 和 `flutter test`。
- Android / Firebase / 订阅逻辑优先，iOS / Google Play / App Store 账号相关步骤暂缓。

## Codex 项目重命名与当前状态

| 原批次 | 新项目名 | 当前状态 |
|--------|----------|----------|
| 第 1 批 | 安全底座：仓库卫生与本地密钥隔离 | 已完成最终审查 |
| 第 2 批 | Android/Firebase 底座：包名、签名、规则 | 已完成主要修复，等待后续账号侧验证 |
| 第 3 批 | 权益与同步核心：订阅、VIP、登录、云同步 | 本地代码审查基本完成，等待账号/沙盒端到端验证 |
| 第 4 批 | 学习体验主流程：启动、首页、练习、复盘 | 已完成本地化首屏补齐与模拟器逐语言截图；待练习/复盘深页审查 |
| 第 5 批 | 题库与品牌资产：数据库、题图、App 图标 | 已完成本地资产审查与取舍确认，待 staging |
| 第 6 批 | Apple 平台预备：iOS/macOS 配置与能力 | 已完成本地预备审查，Archive/TestFlight 因账号暂缓 |
| 第 7 批 | 维护工具链：脚本迁移与题库生产线 | 已完成脚本迁移与仓库卫生审查 |

进度估算：

- 本地工程准备：约 92%。
- 完整商店上架：约 50%，主要受 Google Play / Apple Developer 账号、IAP sandbox、TestFlight、商店素材与审核资料影响。

## 第 1 批：安全底座：仓库卫生与本地密钥隔离

目的：先保证仓库可复现、敏感文件不会误入 Git。

建议包含：

- `.gitignore`
- `android/.gitignore`
- `android/gradlew`
- `android/gradlew.bat`
- `android/gradle/wrapper/gradle-wrapper.jar`
- `android/key.properties.example`
- `docs/firebase_local_setup.md`
- `docs/git_change_grouping_plan.md`

提交前检查：

```bash
git check-ignore -v \
  android/key.properties \
  android/release-upload-keystore.jks \
  android/app/google-services.json \
  ios/Runner/GoogleService-Info.plist \
  macos/Runner/GoogleService-Info.plist \
  lib/firebase_options.dart

git diff --check -- .gitignore android/.gitignore docs/firebase_local_setup.md docs/git_change_grouping_plan.md
```

## 第 2 批：Android/Firebase 底座：包名、签名、规则

目的：包名、签名、Firebase 插件、Firestore 规则进入可发布形态。

建议包含：

- `android/app/build.gradle.kts`
- `android/settings.gradle.kts`
- `android/app/src/main/AndroidManifest.xml`
- `android/app/src/main/kotlin/com/patentego/app/MainActivity.kt`
- 删除旧 `android/app/src/main/kotlin/com/example/italy_quiz_app/MainActivity.kt`
- `firebase.json`
- `firestore.rules`
- `lib/services/firebase_status.dart`

提交前检查：

```bash
JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" \
  ./gradlew :app:validateSigningRelease

firebase deploy --only firestore:rules --dry-run --project italy-patente-b
```

## 第 3 批：权益与同步核心：订阅、VIP、登录、云同步

目的：把付费权限、每日限制、restore flow、Firebase 降级、云端同步逻辑作为一个业务批次审查。

当前审查结论：

- 订阅页购买/恢复按钮已防止重复触发购买流程。
- 客户端不再提供 Firestore VIP 写入 helper；VIP 云端权益只应由可信后端/Admin SDK 写入。
- 登录、登出、游客数据合并已补冲突合并逻辑，并增加发布守卫。
- Firestore 进度同步已补 `total_attempts`，恢复时保留或推断答题次数，避免换机后统计缩水。
- 每日免费限制已统一走 `AccessPolicy`，并同步/恢复练习题数、解析次数、模拟考使用状态。
- Firestore rules 已覆盖 VIP 权益写入边界、进度字段、每日用量字段与单步计数递增约束。
- `ru/uk/ur/pa` 已完成账号流程本地化截图复核：登录入口、Firebase 未配置降级提示、游客进度合并弹窗、登出删除云端数据弹窗均无明显溢出或 RTL 错位；真实登录和合并仍待账号环境验证。

建议包含：

- `lib/providers/user_state_provider.dart`
- `lib/services/access_policy.dart`
- `lib/services/iap_service.dart`
- `lib/services/purchase_verification_service.dart`
- `lib/services/database_service.dart`
- `lib/screens/auth_page.dart`
- `lib/screens/subscription_page.dart`
- `lib/screens/settings_screen.dart`
- `test/access_policy_test.dart`
- `test/purchase_verification_service_test.dart`
- `test/user_state_provider_test.dart`
- `test/release_flow_source_test.dart`
- `test/widget_test.dart`

提交前检查：

```bash
flutter analyze
flutter test
firebase deploy --only firestore:rules --dry-run --project italy-patente-b
```

已完成的本地验证：

- `flutter analyze` 通过。
- `flutter test` 通过，当前 42 tests。
- `firebase deploy --only firestore:rules --dry-run --project italy-patente-b` 通过。
- `integration_test/localization_auth_flow_screenshot_test.dart` 在 iPhone 17 模拟器通过，截图留档：`/tmp/patentego-localization/auth-flow-final/contact_sheet.png`。

仍需账号/设备验证：

- Google sign-in 真实登录。
- Apple sign-in 真实登录。
- Google Play / StoreKit sandbox 的购买与恢复。
- 登录后游客进度合并、Firestore 同步、恢复、每日用量恢复的端到端实测。

## 第 4 批：学习体验主流程：启动、首页、练习、复盘

目的：启动页、首页、练习、复盘、错题、收藏、熟练度等体验改动单独审查。

建议包含：

- `lib/main.dart`
- `lib/config/route_observer.dart`
- `lib/screens/splash_bootstrap.dart`
- `lib/screens/splash_screen.dart`
- `lib/screens/home_screen.dart`
- `lib/screens/chapter_selection_screen.dart`
- `lib/screens/practice_screen.dart`
- `lib/screens/mistake_review_screen.dart`
- `lib/screens/favorite_review_screen.dart`
- `lib/screens/exam_review_screen.dart`
- `lib/screens/mastery_report_screen.dart`
- `lib/widgets/circular_progress_card.dart`
- `lib/widgets/empty_state_view.dart`
- `lib/widgets/glass_card.dart`

提交前检查：

```bash
flutter analyze
flutter test
```

当前审查结论：

- `AppStrings` 七个语言包已对齐到 309 keys，`zh/en/ru/uk/ur/pa` 相对英文基准无缺口；非中文语言包无中文残留。
- `ru/uk/ur/pa` 已完成订阅、设置、错题、学习报告页模拟器截图复核；修正订阅页底部链接换行、学习报告 CTA 换行、乌尔都语订阅页关闭按钮 RTL 位置，并补齐 IAP 降级错误本地化。
- `ru/uk/ur/pa` 已完成核心答题路径模拟器截图复核；新增章节选择、练习答题状态、解析弹窗、模拟考试、模拟结果页截图夹具，并修正模拟结果页长评级文案布局。
- `ru/uk/ur/pa` 已完成剩余普通页面截图复核；新增语言选择、考试复盘、收藏空状态、收藏列表、收藏展开翻译截图夹具，并修正乌尔都语选中后的语言选择页 CTA 图标顺序。
- 登录、注册、云端同步等用户可见错误提示已改为本地化 key。
- 主页问候语、会员状态、进度入口已改为本地化读取。
- RTL 方向控制已移入 `MaterialApp.builder`，iPhone 17 模拟器截图确认乌尔都语首屏翻转、旁遮普语保持 LTR。
- 逐语言主页截图留档：`/tmp/patentego-localization/final7/contact_sheet.png`。

最终收口验证：

- 2026-06-02：`git diff --check` 通过，检查范围覆盖第 4 批页面、组件、截图测试、`AppStrings`、`pubspec` 与相关文档。
- 2026-06-02：第 4 批敏感扫描未发现真实密钥；命中项仅为“不应提交文件清单”中的本地配置文件名示例。
- 2026-06-02：`flutter analyze` 通过。
- 2026-06-02：`flutter test` 通过，当前 42 tests。
- 2026-06-02：四个 iPhone 17 模拟器截图回归测试全部通过：深页、核心答题路径、账号流程、剩余普通页面。

第 4 批建议一起提交：

- `lib/config/app_strings.dart`
- `lib/main.dart`
- `lib/config/route_observer.dart`
- `lib/screens/splash_bootstrap.dart`
- `lib/screens/splash_screen.dart`
- `lib/screens/home_screen.dart`
- `lib/screens/chapter_selection_screen.dart`
- `lib/screens/practice_screen.dart`
- `lib/screens/mistake_review_screen.dart`
- `lib/screens/favorite_review_screen.dart`
- `lib/screens/exam_review_screen.dart`
- `lib/screens/mastery_report_screen.dart`
- `lib/screens/mock_test_screen.dart`
- `lib/screens/mock_test_result_screen.dart`
- `lib/screens/language_selection_screen.dart`
- `lib/screens/settings_screen.dart`
- `lib/screens/subscription_page.dart`
- `lib/widgets/question_widget.dart`
- `lib/widgets/circular_progress_card.dart`
- `lib/widgets/empty_state_view.dart`
- `lib/widgets/glass_card.dart`
- `integration_test/localization_deep_pages_screenshot_test.dart`
- `integration_test/localization_core_flow_screenshot_test.dart`
- `integration_test/localization_auth_flow_screenshot_test.dart`
- `integration_test/localization_remaining_pages_screenshot_test.dart`
- `test/widget_test.dart`
- `pubspec.yaml`
- `pubspec.lock`
- `docs/多语言补全报告.md`
- `docs/release_sprint_checklist.md`
- `docs/git_change_grouping_plan.md`

第 4 批不应混入：

- Android / Firebase / Firestore 配置与规则。
- 题库数据库、路标图、App icon 等资产。
- iOS / macOS 原生工程配置。
- 维护脚本迁移与题库生产线脚本。

## 第 5 批：题库与品牌资产：数据库、题图、App 图标

目的：题库、路标图片、App icon 等大资产单独确认，避免业务代码审查被二进制 diff 淹没。

建议包含：

- `assets/italy_quiz.db`
- 删除根目录旧 `italy_quiz.db`
- `images/img_sign/*.png`
- `images/img_sign/109.png`
- `images/img_sign/968.png`
- `assets/images/app_icon.png`
- `android/app/src/main/res/drawable-*/ic_launcher_foreground.png`
- `android/app/src/main/res/mipmap-*/launcher_icon.png`
- `android/app/src/main/res/mipmap-anydpi-v26/launcher_icon.xml`
- `android/app/src/main/res/values/colors.xml`
- `pubspec.yaml` 中的数据库 assets 路径、`assets/images/` 和 launcher icon 配置（该文件也包含其他批次依赖变更，拆提交时需统一协调）

提交前检查：

```bash
flutter test
```

确认点：

- `DatabaseService.kStaticDbVersion` 已随内置题库更新递增。
- 确认 `assets/italy_quiz.db` 是最终要打包的数据库。
- 确认根目录旧 `italy_quiz.db` 删除是预期迁移。

当前审查结论：

- 当前 `assets/italy_quiz.db` 完整性检查通过，`PRAGMA integrity_check = ok`。
- 当前题库仍为 7139 题；`questions` 新增 `keywords_json` 字段，7139 条 `keywords_json` 均可 JSON 解析。
- `zh/en/ru/uk/pa/ur` 六个目标语言均有 7139 条题干翻译与 7139 条解析；目标语言解析 JSON 均可解析，未发现缺失 `detailed_description`、`key_points`、`study_tip` 的记录。
- 翻译表无孤儿记录、无重复 `(question_id, lang, type)` 记录、无空题干或空目标语言解析。
- 数据库引用的 413 个去重图片路径全部存在；新增 `images/img_sign/109.png` 被 7 题引用，`images/img_sign/968.png` 被 1 题引用。
- 413 个题图文件、1 个 App icon 源图与 12 个 Android launcher icon 资源均已确认存在；`assets/images/app_icon.png` 为 1024x1024 RGB，符合 launcher/source icon 用途。
- `DatabaseService.kStaticDbVersion = 10`，已随内置题库更新；旧 HEAD 中根目录 `italy_quiz.db` 与旧 `assets/italy_quiz.db` hash 相同，因此删除根目录旧库并改为打包 `assets/italy_quiz.db` 是一致迁移。

当前风险 / 待决定：

- `assets/italy_quiz.db` 从约 18 MB 增至约 75 MB，主要来自多语言解析、关键词等内容；功能正确，但会增加包体。
- 49 张已替换路标图总大小从约 0.32 MB 增至约 1.75 MB，增量约 1.43 MB；部分图片从调色板 PNG 变为 RGB PNG。若要压包体，可在不损失画质的前提下再做 PNG 压缩。
- `assets/images/app_icon.png` 是唯一保留的 App icon 源图；重复的根目录 `images/app_icon.png` 已移除，不放入正式提交。
- Android Manifest 已引用 `@mipmap/launcher_icon`；对应 Android launcher icon 资源应随本批次一起提交。
- 升级后旧设备文档目录中可能残留旧路径 `Documents/italy_quiz.db`，新版本实际使用 `Documents/assets/italy_quiz.db`；这是存储残留风险，不影响新库加载。

## 第 6 批：Apple 平台预备：iOS/macOS 配置与能力

目的：Apple 开发者账号完成前只保留准备工作，不推进 Archive / TestFlight。

建议包含：

- `ios/Podfile`
- `ios/Podfile.lock`
- `ios/Runner.xcodeproj/project.pbxproj`
- `ios/Runner/Info.plist`
- `ios/Runner/Runner.entitlements`
- `ios/Flutter/Profile.xcconfig`
- iOS AppIcon 图片
- `macos/Podfile.lock`
- `macos/Runner.xcodeproj/project.pbxproj`
- `macos/Runner/Configs/AppInfo.xcconfig`

提交前检查：

```bash
pod install
flutter build ios --simulator --debug
```

确认点：

- `GoogleService-Info.plist` 保持本地忽略，不提交。
- Apple Sign In entitlement 是否等 Apple Developer 账号完成后再最终确认。
- iOS / macOS bundle id 与 Firebase 配置一致。

当前审查结论：

- iOS 主 App bundle id 为 `com.patentego.app`，RunnerTests 为 `com.patentego.app.RunnerTests`；macOS `PRODUCT_BUNDLE_IDENTIFIER` 也为 `com.patentego.app`。
- iOS `Runner.entitlements` 已包含 Sign in with Apple capability；仍需等 Apple Developer 账号完成后在 Apple Developer / Xcode Signing 中最终确认。
- iOS / macOS 工程均引用本地 `GoogleService-Info.plist`；对应文件已被 `.gitignore` 忽略，不应提交。新机器需按 `docs/firebase_local_setup.md` 生成本地 Firebase 配置后再构建。
- iOS AppIcon 尺寸全部匹配 `Contents.json`，未发现 alpha 通道；源图 `assets/images/app_icon.png` 为 1024x1024 RGB。
- 已修正 Runner 的 Profile build configuration：Debug / Release / Profile 分别指向 `Debug.xcconfig`、`Release.xcconfig`、`Profile.xcconfig`，避免 Release 配置混入 Profile Pods 配置。
- 已修正 macOS `PRODUCT_COPYRIGHT` 中旧 `com.example` 占位。
- `pod install` 通过，且不再出现 CocoaPods base configuration 警告。
- `flutter build ios --simulator --debug` 通过，产物为 `build/ios/iphonesimulator/Runner.app`。
- iOS / macOS `.xcodeproj` 均可解析；相关 plist / entitlements 语法校验通过。

当前风险 / 待决定：

- Apple Developer 账号未完成，因此未做真机签名、Archive、TestFlight、App Store Connect capability 校验。
- `GoogleService-Info.plist` 不提交是正确的，但 Xcode 工程引用它；新机器缺本地文件时原生构建会失败，需要先做 Firebase 本地配置。
- `ios/Runner.xcworkspace/xcshareddata/IDEWorkspaceChecks.plist` 与 `WorkspaceSettings.xcsettings` 已恢复，保留 Flutter/Xcode 模板共享元数据。
- macOS 已更新 bundle id 和 Pods，但当前项目主目标是移动端；macOS 上架/签名能力未做端到端验证。

第 6 批不应混入：

- 本地 `GoogleService-Info.plist`、`lib/firebase_options.dart` 或任何 Apple/商店账号凭据。
- Android / Google Play 配置。
- 题库数据库和路标图片资产。
- 维护脚本迁移。

## 第 7 批：维护工具链：脚本迁移与题库生产线

目的：把旧 `scripts/` 迁移到 `maintenance/` 的变更从 App 运行逻辑中拆出来。

建议包含：

- 删除旧 `scripts/*.py`
- 删除旧 `scripts/*.md`
- 删除旧 `scripts/*.sql`
- 删除旧 `scripts/*.txt`
- 删除旧 `scripts/*.json`
- 新增 `maintenance/scripts/*`
- 新增 `maintenance/reports/*`
- 保留 `scripts/generate_global_explanations.py` 作为转发入口
- `check_watermark.py`
- `remove_watermark.py`
- `scripts/rebuild_ios_appicons.py`

提交前检查：

```bash
python3 -m py_compile \
  scripts/generate_global_explanations.py \
  scripts/rebuild_ios_appicons.py \
  check_watermark.py \
  remove_watermark.py \
  $(find maintenance/scripts -maxdepth 1 -name '*.py' | sort)

bash -n \
  maintenance/scripts/check_status.sh \
  maintenance/scripts/monitor_progress.sh \
  maintenance/scripts/run_auto_explanations.sh
```

当前审查结论：

- 旧 `scripts/` 下的维护脚本、SQL、说明文档已迁移到 `maintenance/scripts/`；根目录 `scripts/generate_global_explanations.py` 保留为兼容转发入口。
- 可执行维护脚本已移除个人绝对路径，改为从脚本位置推导项目根目录；缺少题库文件时会明确退出。
- `generate_keywords_with_gemini.py`、关键词覆盖统计、关键词写入测试、中文解析规范化、全库解析生成等脚本不再回退到个人机器路径。
- `test_update_keywords.py` 已改为复制正式题库到临时数据库后测试写入，并在进程退出时清理临时目录，避免误改 `assets/italy_quiz.db`。
- `test_gemini_api.py` 已移除旧 Pro 测试模型，改为 Flash 候选模型；API key 仍只从环境变量读取。
- 关键词覆盖烟测通过：7139 题均有 `keywords_json`，覆盖率 100%。
- `__pycache__`、`*.log`、`failed_ids.txt`、`firepit-log.txt` 等运行产物已被忽略，不应提交。
- 第 7 批敏感扫描未发现真实密钥；命中项为环境变量名、占位说明或第三方参考代码中的普通字符串。

当前风险 / 待决定：

- `maintenance/reports/*` 当前包含多份历史报告与说明；若希望提交更轻，可只保留真正要长期使用的报告文档。
- `maintenance/reports/watermark_report.txt` 是水印检查脚本生成结果，已移除；水印工具依赖文件改放在 `maintenance/scripts/requirements_watermark.txt`。
- 部分旧章节分配脚本 / 历史 SQL 仍提到旧字段名 `chapter_id`，当前题库字段是 `chapter`；它们应视为历史迁移资料，不应在正式题库上直接运行。当前可用的章节重分配入口应优先使用 `maintenance/scripts/reassign_chapters.py` 或已确认使用 `chapter` 字段的 SQL。

第 7 批不应混入：

- `maintenance/scripts/__pycache__/`
- `scripts/__pycache__/`
- `maintenance/scripts/*.log`
- `scripts/*.log`
- `maintenance/reports/firepit-log.txt`
- `failed_ids.txt`
- `maintenance/reports/watermark_report.txt`
- 任何本地 API key、Firebase 配置、keystore 或商店账号凭据。

## 发布前总闸门审查

目的：在真正提交前，把 7 个批次从一个大 diff 收束成可审查、可交接、可继续上架的状态。

建议提交顺序：

1. 第 1 批：安全底座，先提交 `.gitignore`、Gradle wrapper、Android key 示例、Firebase 本地配置说明和本分组计划。
2. 第 2 批：Android/Firebase 底座，再提交 Android 包名/签名配置、Firebase 配置入口、Firestore rules 和 Firebase 状态降级逻辑。
3. 第 3 批：权益与同步核心，提交订阅、VIP、登录、云端同步、每日限制和对应测试。
4. 第 4 批：学习体验主流程，提交启动、首页、练习、复盘、错题、收藏、学习报告、本地化 UI 和截图测试。
5. 第 5 批：题库与品牌资产，提交内置题库、路标图片、App icon 和相关资源配置；这是大文件批次，应单独审查包体。
6. 第 6 批：Apple 平台预备，提交 iOS/macOS 工程配置、Profile xcconfig、entitlements、Podfile/Podfile.lock 和 AppIcon。
7. 第 7 批：维护工具链，最后提交 `scripts/` 到 `maintenance/` 的迁移、维护报告、兼容转发脚本和水印/AppIcon 工具。

总闸门检查结果：

- 2026-06-02：全仓 `git status` 已复核，当前 diff 覆盖 7 个计划批次；尚未 stage、commit 或 push。
- 2026-06-02：本地密钥与配置文件存在于机器上，但已被 Git 忽略：Android `key.properties`、Android keystore、`google-services.json`、iOS/macOS `GoogleService-Info.plist`、`lib/firebase_options.dart`。
- 2026-06-02：敏感扫描未发现真实密钥；命中项为环境变量名、占位说明或维护脚本文档。
- 2026-06-02：`git diff --check` 初次发现 `lib/models/question.dart` 行尾空格，已机械清理；复查通过。
- 2026-06-02：`flutter analyze` 通过。
- 2026-06-02：`flutter test` 通过，当前 42 tests。

提交前取舍收口：

- `maintenance/reports/*.md` 保留为历史交接资料；生成型 `maintenance/reports/watermark_report.txt` 不提交。
- `maintenance/reports/requirements.txt` 已移除，水印工具依赖改为 `maintenance/scripts/requirements_watermark.txt`。
- 重复的根目录 `images/app_icon.png` 已移除，只保留被运行时和图标生成脚本引用的 `assets/images/app_icon.png`。
- `ios/Runner.xcworkspace/xcshareddata/IDEWorkspaceChecks.plist` 与 `WorkspaceSettings.xcsettings` 已恢复，减少 Xcode 模板元数据噪音。
- `analysis_options.yaml` 保留当前 lint 降级作为临时发布策略；尝试收窄后会暴露 148 个 info，主要是 `withOpacity` 弃用与少量 const 提示，不适合混入本次提交前取舍收口。

总闸门仍需人工决定：

- Google Play / Apple Developer 账号尚未完成，真实登录、IAP sandbox、Archive/TestFlight、商店上传仍是上架阻塞项。
- 后续可单独开一批“Flutter 新版 lint 清理”，集中替换 `withOpacity`、处理 const 提示，再移除 `analysis_options.yaml` 中的临时降级。

## 不应提交

以下内容只允许本机存在：

- `android/key.properties`
- `android/release-upload-keystore.jks`
- `android/app/google-services.json`
- `ios/Runner/GoogleService-Info.plist`
- `macos/Runner/GoogleService-Info.plist`
- `lib/firebase_options.dart`
- `*.log`
- `__pycache__/`
- `failed_ids.txt`
- `firepit-log.txt`
- `.DS_Store`
- `.dart_tool/`
- `.cache/`
- `.config/`
- `.python_packages/`
- `build/`
- `ios/Pods/`
- `macos/Pods/`
- `*.code-workspace`

## 当前保留风险

- `firestore.rules` 当前允许用户删除自己的 `daily_usage` 文档，便于资料删除流程，但不能作为强防绕过限制；若要强限制，应改用可信后端。
- `analysis_options.yaml` 新增了较多 lint 降级规则，需要在最终提交前确认这是长期策略还是临时压警告。
- iOS / macOS 配置依赖本地 Firebase plist，新机器必须先按 `docs/firebase_local_setup.md` 生成配置。
