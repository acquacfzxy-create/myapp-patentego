# Google Play Internal Testing Upload Notes

Date: 2026-08-31

## Build Artifact

- Package: `com.patentego.app`
- Version: `1.0.3+4`
- AAB: `build/app/outputs/bundle/release/app-release.aab`
- Size: 131.2 MB
- SHA-256: `4c2429cf44018667cdb5ac0b35c5c72669a9fba5ffe5e3de773624385d99b434`

## Release Notes

```text
Internal QA build: refreshed subscription page, Android clean launch, chapter lock, explanation limit, and subscription entry validation.
```

## Internal Test Focus

- Fresh install opens language selection.
- Free-user home shows zero progress.
- Chapter practice locks paid chapters and routes to the VIP/subscription entry.
- Explanation limit routes exhausted free users to the VIP/subscription entry.
- Subscription page shows the real monthly product price in the Play-distributed build.
- Monthly subscription starts the Google Play purchase sheet.
- Restore purchase restores VIP after reinstall.
- VIP unlock removes chapter, explanation, mock exam, and review limits.

## Current Local Verification

- `flutter analyze` passed with no issues.
- Subscription and entitlement test scope passed with 53 tests.
- Full `flutter test` reached 175 passing tests and one unrelated failure because the worktree currently has `web/index.html` deleted.
- `flutter build appbundle --release` succeeded.
- The release AAB signature verified successfully.
- The merged release manifest uses package `com.patentego.app`, version code `4`, target SDK `36`, and includes `com.android.vending.BILLING`.
- Android API 35 Google Play emulator previously verified clean first launch, chapter lock, explanation-limit routing, and subscription page entry.
- A connected Samsung device currently has a shell-installed debug build, which cannot retrieve the real Play subscription product.
- Real purchase and restore verification requires this AAB (or a later unique version code) to be distributed through Google Play internal testing.
