# Worthify iOS App

This folder contains the active SwiftUI client for Worthify.

The old Flutter iOS project has been removed. This folder is now the only client app in the repository.

## What is here

- `project.yml`
  - XcodeGen project definition for the native app skeleton
- `Config/`
  - xcconfig placeholders for runtime keys
- `WorthifyNative/`
  - SwiftUI source organized by app, core, services, and features
- `WorthifyNativeTests/`
  - minimal test target

## What works in source now

- direct Supabase email OTP auth
- local session restore with refresh-token flow
- Cloudinary image upload
- artwork analysis requests
- saved analysis/history loading
- profile and subscription snapshot loading

## How to use this on macOS

1. Install Xcode.
2. Install XcodeGen if needed.
3. From this folder, run:

```bash
xcodegen generate
```

4. Open `WorthifyNative.xcodeproj`.
5. Fill in the values in `Config/Debug.xcconfig` and `Config/Release.xcconfig`.
6. Build and run from Xcode.

## What still needs native implementation

- Apple Sign In
- Google Sign-In
- RevenueCat
- Superwall
- APNS/FCM
- Share extension

## Bundle and signing

The project is configured for `com.worthify.worthify`. Complete signing and team settings in Xcode before building for device or release.

## Share extension

The share extension is deferred. The app-group config sync remains in the native app so a new extension can be added later without bringing Flutter back.
