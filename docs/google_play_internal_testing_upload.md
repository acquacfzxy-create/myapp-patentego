# Google Play Internal Testing Upload Notes

Date: 2026-06-09

## Build Artifact

- Package: `com.patentego.app`
- Version: `1.0.0+1`
- AAB: `build/app/outputs/bundle/release/app-release.aab`
- Size: 69.1 MB
- SHA-256: `e8cde31ed1861c7a74d68cccf1fee16ceab44670f832c4825b33b4cfb61b2f81`

## Release Notes

```text
Internal QA build: Android clean launch, chapter lock, explanation limit, and subscription entry validation.
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

- `flutter test` passed with 42 tests.
- `flutter analyze` passed with no issues.
- `flutter build appbundle --release` succeeded.
- Android API 35 Google Play emulator previously verified clean first launch, chapter lock, explanation-limit routing, and subscription page entry.
- This pass did not rerun emulator verification because no Android emulator/device is currently attached.
- Local emulator cannot verify real Play Billing purchase/restore; Play internal testing is required for that.
