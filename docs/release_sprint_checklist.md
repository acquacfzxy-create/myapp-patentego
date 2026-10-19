# 2026-10-17 合併版本 1.1.0+12

使用者已明確授權合併另一對話的修改並發布新版；這取代以下歷史記錄中的「尚無發布授權」，不取代真實的帳號／商店門檻。即時交接見 `release_candidates/release_1.1.0_20261017/`。

- DB92：7139/7139 題驗收，49191 詞；發布前另完成 5 題 5 值補正，非題幹／答案改寫。
- 全 Flutter 測試 1038 通過（含 Firestore fixture），範圍 analyze 無 issue，7 項 Firestore emulator 通過；本輪錯題復盤模擬器整合測試通過，3 張畫面已目視。歷史失敗日誌保留，並非刪除／skip 取得全綠。
- Android 最終簽名 AAB 1.1.0（12），包內 DB92 hash 符合，API36、Billing8、arm64 16KB 相容，權限與正式11相同；Play 正式版草稿已建立，最終狀態以本輪發布報告為準。
- Play 三函式及 deleteAccount 已部署，兩 callable 未登入 HTTP401；未刪除任何真實帳號／進行真實購買。Apple IAP 三函式未部署。
- iOS 同源 1.1.0（12）無簽名裝置編譯通過，含 DB92；Apple 內購旗標關閉，不能當可送審成品。舊簽名候選 DB82 保留，不冒稱新 DB92。
- Apple 登入本輪已過期，待使用者登入；案件22926042本輪仍僅有受理信。銀行／稅務／DSA沒有本輪登入後的即時確認，不能冒用舊值。
- 隱私草稿必以新 `IOS_SDK_PRIVACY_AUDIT.json`／`IOS_DISCLOSURE_RESOLUTION.md` 為準：GoogleSignIn 與 Firebase 實際清單包含舊稿漏列的項目；BoringSSL 亦不能稱純 OS 加密。尚未代填虛構稅務／內容權利／法國加密聲明。
- 詞彙自動化保持 PAUSED。Web 內容包未同步／未部署，母語確認、真實商店購買與真帳號刪除仍為明示邊界。

---

# LinguaPatente Release Sprint Checklist

## Pending Next Version — 2026-10-17

- [x] Remove daily limits and quota consumption for full explanations across practice, favorites, mistake review, exam review, session review, and Web. Remove remaining-count hints and explanation VIP badges. Update all seven subscription-page languages to state that full explanations are free and unlimited for everyone. Include this change in the same next-version release after the question-bank batch completes. See [verification record](../outputs/session_mistake_review_20261017/free_explanations/完成紀錄.md).

- [x] Preserve the local fast-practice update: session mistake review, summary review, and optional inline extra explanation. See [implementation record](../outputs/session_mistake_review_20261017/完成紀錄.md) and [extra explanation verification](../outputs/session_mistake_review_20261017/expanded_details/完成紀錄.md).
- [ ] Wait for the current question-bank batch to finish, then verify its completion logs and resulting data quality.
- [ ] Validate the finished question bank and this feature together; increment `kStaticDbVersion` when bundling an updated database, confirm the next app version/build, and complete release checks before packaging.
- Release timing confirmed by the maintainer: include this feature with the completed question bank in the next version; do not release it separately.

## Every Update - Non-negotiable Gates

- [ ] Run `flutter test test/app_theme_test.dart`; every Material text style must use the bundled language-specific Noto family.
- [ ] New UI text inherits `AppTheme`; do not add literal `fontFamily` values or raw `RichText` widgets that bypass `DefaultTextStyle`.
- [ ] Smoke-check Chinese home, settings, question, explanation, dialog, and button text on Android; no serif Chinese is accepted for release.
- [ ] Run full `flutter analyze`, `flutter test`, and `git diff --check` before handing off an update.

## Day 1 - Baseline

- [x] Verify built-in database integrity.
- [x] Verify Chinese question/explanation content is Simplified Chinese.
- [x] Verify explanation JSON parses and required fields are present.
- [x] Make Dart analyzer pass for app code.
- [x] Remove Firestore custom-claim dependency from progress sync rules.
- [x] Replace Android debug release signing with release keystore config.
- [x] Add GitHub Pages workflow for legal pages.
- [x] Verify legal pages return HTTP 200 from a local static server.
- [x] Run `flutter analyze` from a normal terminal.
- [x] Run Android Gradle/Flutter build from a normal terminal.
- [x] Run `flutter build ios --release --no-codesign` from a normal terminal.
- [ ] Run iOS archive/TestFlight build from a normal terminal.
- [x] Deploy legal pages and confirm privacy/terms URLs return HTTP 200.

## Day 2 - Android

- [x] Create Android upload keystore outside git.
- [x] Create `android/key.properties` outside git using `android/key.properties.example`.
- [x] Build `flutter build appbundle --release`.
- [x] Create/connect Android API 35 Google Play emulator and run clean first-launch smoke flow.
- [ ] Upload to Play Console internal testing.
- [ ] Complete Play Data Safety and content rating.

## Day 3 - iOS

- [ ] Confirm Apple Developer team and bundle id `com.patentego.app`.
- [ ] Confirm Sign in with Apple capability.
- [ ] Confirm IAP product `patentego_vip_monthly`.
- [ ] Archive and upload to TestFlight.
- [ ] Install TestFlight build on a real device.

## Day 4 - Payments And Entitlements

- [ ] Test monthly purchase in sandbox.
- [ ] Test restore purchase after reinstall with StoreKit/TestFlight sandbox.
- [ ] Test VIP unlock removes practice, mock exam, and review locks; full explanations remain free for everyone.
- [x] Guard local VIP cache against stale iOS Keychain data after reinstall.
- [ ] Decide whether first release ships with platform purchase stream validation or a backend receipt verifier.

## Day 5 - QA

- [x] Guest clean first launch shows language selection after app data and iOS Keychain reset.
- [x] Clean free-user home shows `免费用户` and zero progress.
- [x] Chapter lock source/UI guard routes locked chapters to the subscription entry.
- [x] Explanation limit source guard routes exhausted free users to the subscription entry.
- [x] Run `flutter test` and `flutter analyze` after release-flow guards.
- [ ] Google sign-in.
- [ ] Apple sign-in.
- [ ] Guest progress merge into account.
- [ ] Firestore progress sync and restore.
- [x] Free daily limits.
- [ ] DB upgrade for existing installs via `kStaticDbVersion`.
- [x] Multilingual display smoke test.

## Day 6 - Store Assets

- [ ] App screenshots.
- [ ] App description and keywords.
- [ ] Support URL. Online `support.html` still needs deployment; in-app Support currently uses mailto.
- [x] Privacy URL.
- [x] Terms URL.
- [ ] Review notes and demo account.
- [ ] Third-party notices/license review.

## Day 7 - Submission

- [ ] Final Android build upload.
- [ ] Final iOS build upload.
- [ ] Submit App Store review.
- [ ] Submit Play Store review.

## Latest Local Smoke Results

- 2026-08-31: Subscription release-readiness pass completed. `flutter analyze` passed; 53 focused subscription, entitlement, access-policy, provider, and release-flow tests passed. Android release AAB `1.0.3+4` built successfully, its signature verified, and the merged manifest contains `com.android.vending.BILLING` with target SDK 36. iOS release device build also succeeded with codesigning disabled. Real store purchase/restore remains blocked on Play Console/App Store Connect account access and store-distributed sandbox builds. Full `flutter test` had 175 passing tests and one unrelated failure because the current worktree has `web/index.html` deleted.
- 2026-06-02: Pre-submit gate review completed. Full Git status was reviewed against the 7 planned batches, local secret/config files are present but ignored, sensitive scanning found no real secrets, `git diff --check` passed after trimming whitespace in `lib/models/question.dart`, `flutter analyze` passed, and full `flutter test` passed with 42 tests. Remaining submission blockers are still account-side: Google Play, Apple Developer, sandbox IAP, real sign-in, Archive/TestFlight, and store upload metadata.
- 2026-06-02: Pre-submit file selection closure completed. Removed duplicate root `images/app_icon.png`, restored iOS workspace shared metadata files, moved watermark tool requirements to `maintenance/scripts/requirements_watermark.txt`, and removed generated `maintenance/reports/watermark_report.txt`. `analysis_options.yaml` lint downgrades remain as a temporary release strategy because narrowing them currently exposes 148 analyzer info items, mostly Flutter `withOpacity` deprecations. Follow-up `git diff --check`, `flutter analyze`, and `flutter test` with 42 tests passed.
- 2026-06-02: Batch 7 maintenance toolchain migration review completed. Personal absolute paths were removed from migrated scripts/docs, Gemini smoke tooling now uses Flash candidates and env-only keys, keyword write testing uses and cleans a temporary DB copy, Python scripts compiled, shell scripts passed syntax checks, `git diff --check` passed, keyword coverage is 7139/7139, and sensitive scanning found no real secrets. Remaining risk: some historical chapter-mapping SQL/docs still reference old `chapter_id` and should not be run against the current DB without review.
- 2026-06-02: Batch 6 Apple platform prep review completed. iOS/macOS project files parse, plist/entitlements lint passed, Firebase plist files remain local/ignored, iOS AppIcon dimensions and alpha status are valid, `pod install` passed without base-config warnings, and `flutter build ios --simulator --debug` produced `build/ios/iphonesimulator/Runner.app`. Archive/TestFlight remain paused until Apple Developer account access is ready.
- 2026-06-02: Batch 5 database and brand-asset review completed. `assets/italy_quiz.db` integrity passed, 7139 questions are present, six target-language explanations are complete and valid JSON, all DB-referenced image files exist, app icon source is 1024x1024 RGB, and duplicate root `images/app_icon.png` was removed. Remaining asset risk: database/package size growth.
- 2026-06-02: Batch 4 final closure completed. `git diff --check`, sensitive scan, `flutter analyze`, `flutter test` with 42 tests, and all four iPhone 17 localization screenshot integration tests passed: deep pages, core answer flow, auth/account flow, and remaining ordinary pages.
- 2026-06-02: Remaining ordinary-page localization simulator review completed for `ru/uk/ur/pa`: language selection, exam review, exam-review translation expansion, favorite empty state, favorite list, and favorite translation expansion. Fixed the Urdu-selected language CTA icon order and reset the language-selection title letter spacing to 0. Final screenshots are under `/tmp/patentego-localization/remaining-pages-final/`.
- 2026-06-02: Auth/account localization simulator review completed for `ru/uk/ur/pa`: auth entry page, Firebase-unavailable sign-in snackbar, guest-progress merge dialog, and sign-out/delete-cloud-data dialog. Final screenshots are under `/tmp/patentego-localization/auth-flow-final/`; real Google/Apple sign-in and account merge remain blocked on Firebase/developer-account environments.
- 2026-06-02: Final verification after core answer-flow localization fixes: `git diff --check` passed for touched files, `flutter analyze` passed, full `flutter test` passed with 42 tests, and the core-flow simulator screenshot integration test passed on iPhone 17.
- 2026-06-02: Core answer-flow localization simulator review completed for `ru/uk/ur/pa`: chapter selection, practice unanswered/correct/wrong, explanation sheet, mock exam, and mock result. Fixed mock-result stats layout for long rating text and stabilized rich-explanation bottom-sheet context usage. Final screenshots are under `/tmp/patentego-localization/core-flow-final/`.
- 2026-06-02: Final verification after deep-page localization fixes: `git diff --check` passed for touched files, `flutter analyze` passed, and full `flutter test` passed with 42 tests. The simulator screenshot integration test also passed on iPhone 17.
- 2026-06-02: Deep-page localization simulator review completed for `ru/uk/ur/pa` on subscription, settings, mistakes, and mastery report pages. Fixed subscription footer wrapping, mastery CTA wrapping, Urdu subscription close-button RTL placement, and localized common IAP fallback errors. Final screenshots are under `/tmp/patentego-localization/deep-pages-final/`.
- 2026-06-02: Non-Chinese language review completed for `en/ru/uk/ur/pa` and legacy `it`. AppStrings now has 309 keys per language, no Chinese residue in non-Chinese maps, and auth/sync/IAP user-facing errors use localized keys.
- 2026-06-01: Chinese page-copy review started. Fixed hardcoded Chinese in the home subscription dialog and mock-test image/error paths; adjusted mastery report chapter title format; added a source guard for reviewed Chinese hardcoded strings.
- 2026-06-01: Multilingual AppStrings coverage completed for `zh/en/ru/uk/ur/pa` with 0 missing vs English baseline. iPhone 17 simulator clean-install screenshots saved under `/tmp/patentego-localization/final7/`; Urdu RTL and Punjabi LTR were visually checked on the home screen.
- 2026-06-01: Local localization engineering review completed. Critical UI language keys now have source guards; Urdu remains RTL, Punjabi Gurmukhi is LTR.
- 2026-05-31: `flutter test` passed with 35 tests after daily-limit guards.
- 2026-05-31: `flutter analyze` passed with no issues.
- 2026-05-31: Firestore rules dry-run compiled successfully for project `italy-patente-b`.
- 2026-05-31: Subscription CTA now stays locked while IAP purchase/restore is active; duplicate purchase starts are guarded in `IapService`.
- 2026-05-31: Client-side Firestore VIP write helper removed; App now only reads cloud VIP entitlement written by a trusted backend/Admin SDK.
- 2026-05-31: Firestore cloud sync and cloud delete paths now commit writes in bounded batches.
- 2026-05-31: Firestore progress sync now includes `total_attempts`, and restore keeps/infer attempts so coverage and pass-rate stats survive device changes.
- 2026-05-31: Daily free limits now route through `AccessPolicy`; signed-in daily usage restores quiz, explanation, and mock-exam usage from Firestore. Firestore rules now validate daily usage fields and one-step counter increments.
- 2026-05-31: Remaining account-dependent QA still requires real Firebase sign-in environments and store sandbox access; local source guards are in place, but Google/Apple login and IAP restore flows remain unverified end to end.
- 2026-05-24: `flutter test` passed with 26 tests.
- 2026-05-24: `flutter analyze` passed with no issues.
- 2026-05-24: iOS simulator clean launch verified on iPhone 17 / iOS 26.2.
- 2026-05-24: Android emulator verified on `Pixel_8_API_35_Play` / Android 15 (API 35): clean first launch, chapter lock, explanation-limit subscription routing, and subscription page entry.
- 2026-05-24: Android subscription page emits the expected local emulator billing warning (`In-app purchases are not available on this device.`); real purchase/restore still requires Google Play internal testing or another Play Billing-capable test environment.
- 2026-05-24: Rebuilt latest Android release AAB after subscription-page initialization fix: `build/app/outputs/bundle/release/app-release.aab` (69.1 MB).
- 2026-05-24: Prepared Play internal testing upload notes at `docs/google_play_internal_testing_upload.md`; Play Console upload still requires account access.
- 2026-05-24: Clean first-launch screenshot saved at `/tmp/patentego-smoke/keychain_clean_language.png`.
- 2026-05-24: Clean free-user home screenshot saved at `/tmp/patentego-smoke/keychain_clean_free_home.png`.
- Note: simulator tap automation was unavailable locally, so the language-selection transition was advanced by setting the Flutter language preference before relaunch.
