# PatenteGo Release Sprint Checklist

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
- [ ] Test VIP unlock removes practice, mock exam, explanation, review locks.
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
