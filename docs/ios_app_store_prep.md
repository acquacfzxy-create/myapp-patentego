# PatenteGo iOS App Store / TestFlight Prep

This file collects the values and tasks that can be prepared before the Apple
Developer account is approved.

## Current Build Values

- App name: `PatenteGo`
- Bundle ID: `com.patentego.app`
- Version: `1.0.0`
- Build number: `1`
- SKU suggestion: `patentego-ios-100`
- Primary category suggestion: `Education`
- Secondary category suggestion: `Reference`
- Privacy Policy URL:
  `https://acquacfzxy-create.github.io/myapp-patentego/privacy.html`
- Terms of Service URL:
  `https://acquacfzxy-create.github.io/myapp-patentego/terms.html`
- Support URL suggestion:
  `https://acquacfzxy-create.github.io/myapp-patentego/support.html`

## Local iOS Status

- `flutter build ios --release --no-codesign`: passes.
- `xcodebuild archive`: currently blocked by missing Apple Developer Team.
- Xcode workspace: `ios/Runner.xcworkspace`
- Runner target bundle ID: `com.patentego.app`
- Sign in with Apple entitlement: present in `ios/Runner/Runner.entitlements`
- Firebase iOS config: `ios/Runner/GoogleService-Info.plist`
- Google Sign-In URL scheme: present in `ios/Runner/Info.plist`

## App Store Connect App Record

Create the app after the Apple Developer account is approved.

- Platform: iOS
- Name: `PatenteGo`
- Primary language: Italian
- Bundle ID: `com.patentego.app`
- SKU: `patentego-ios-100`
- User Access: Full Access

Important: Apple notes that the App Store Connect Bundle ID must match the
Xcode project bundle ID, and the Bundle ID cannot be changed after uploading a
build.

## Suggested Product Page Copy

### Subtitle

Italian driving quiz

### Promotional Text

Practice for the Italian driving theory exam with multilingual explanations,
mock exams, mistake review, favorites, and progress sync.

### Description

PatenteGo helps learners prepare for the Italian driving theory exam with a
large question bank, chapter practice, mock exams, mistake review, favorites,
and multilingual explanations.

Core features:

- Practice by chapter with clear question navigation.
- Mock exams modeled around the real exam flow.
- Review wrong answers and favorite questions.
- Read structured explanations with key points and study tips.
- Switch between supported study languages.
- Sign in with Apple or Google to keep progress in sync.
- Upgrade to PatenteGo VIP for full access and cloud sync.

PatenteGo is an independent study tool and is not affiliated with, endorsed by,
or operated by Italian government authorities.

### Keywords

patente, quiz patente, driving test, theory exam, Italy, Italian driving,
driving license, practice test

### Review Notes

PatenteGo is a study app for the Italian driving theory exam. The app supports
guest use, Apple/Google sign-in, local progress, cloud sync, and a monthly VIP
subscription.

The subscription product ID used by the app is:

`patentego_vip_monthly`

The privacy policy and terms are available in the app subscription page and at:

- `https://acquacfzxy-create.github.io/myapp-patentego/privacy.html`
- `https://acquacfzxy-create.github.io/myapp-patentego/terms.html`

If the reviewer needs a logged-in account, create a temporary demo account in
Firebase Auth before submission and record it here.

Demo account:

- Email: `TBD`
- Password: `TBD`

## In-App Purchase Setup

Create this in App Store Connect after the app record exists.

- Type: Auto-renewable subscription
- Product ID: `patentego_vip_monthly`
- Reference name: `PatenteGo VIP Monthly`
- Subscription group reference name: `PatenteGo VIP`
- Subscription group display name: `PatenteGo VIP`
- Duration: 1 month
- Pricing: decide in App Store Connect
- Localization display name: `PatenteGo VIP Monthly`
- Localization description:
  `Unlock full practice access, mock exams, mistake review, explanations, study reports, and cloud sync.`

Apple requires subscription products to be created inside a subscription group
in App Store Connect.

## TestFlight Internal Test Plan

Run these checks on a real iPhone after the first TestFlight build is available.

- Fresh install opens without crashing.
- Guest first launch and language selection.
- Chapter practice loads questions and images.
- Mock exam can start and finish.
- Wrong-answer review shows saved mistakes.
- Favorites can be added and reviewed.
- Explanation modal opens and respects free/VIP access.
- Apple sign-in works.
- Google sign-in works.
- Guest progress can merge into account.
- Firestore cloud sync restores progress after reinstall.
- Subscription page loads `patentego_vip_monthly`.
- Sandbox purchase unlocks VIP.
- Restore purchase unlocks VIP after reinstall.
- VIP removes practice, mock exam, explanation, and review locks.

## App Privacy Notes To Verify

Before submission, answer App Privacy in App Store Connect based on actual app
behavior. Current likely data categories:

- Contact info: email address from Firebase/Auth providers.
- User ID: Firebase UID.
- Purchases: VIP entitlement and subscription status.
- User content / app activity: learning progress, favorites, wrong counts,
  mastered status, mock exam history, daily usage counters.
- Diagnostics: only if Firebase/Apple/Google SDKs collect diagnostics in the
  shipped configuration.

Verify every answer against the final SDK configuration before submission.

## Local StoreKit Testing

Local StoreKit testing can be prepared before App Store Connect is ready:

1. Open `ios/Runner.xcworkspace`.
2. Choose File > New > File from Template.
3. Search for `StoreKit Configuration File`.
4. Create a local file such as `PatenteGo.storekit`.
5. Add an auto-renewable subscription group.
6. Add product ID `patentego_vip_monthly`.
7. In the Runner scheme, Run > Options, select the StoreKit configuration file.
8. Run on a simulator or real device and test purchase/restore.

Apple's StoreKit testing environment uses local product data when the
configuration file is active, so this does not require App Store Connect
products to exist yet.

## Official References

- App information:
  `https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/`
- Upload builds:
  `https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/`
- Add internal testers:
  `https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers/`
- Auto-renewable subscription information:
  `https://developer.apple.com/help/app-store-connect/reference/auto-renewable-subscription-information`
- StoreKit testing in Xcode:
  `https://developer.apple.com/documentation/xcode/setting-up-storekit-testing-in-xcode/`
