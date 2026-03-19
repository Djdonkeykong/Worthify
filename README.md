# Worthify

Worthify is now an iOS-first SwiftUI app backed by the existing Supabase and detection services in this repository.

## Repo layout

- `ios/`
  - SwiftUI client app skeleton and source
- `supabase/`
  - database migrations and Edge Functions
- `server/`
  - artwork detection backend
- `assets/`
  - reusable images and brand assets
- `docs/`
  - migration and implementation notes

## Current client status

The Flutter client has been retired from the repo structure. The active client is the native SwiftUI app under `ios/`.

The native app currently centers on:

- email OTP auth against Supabase
- image upload to Cloudinary
- artwork analysis through the existing backend endpoint
- saved analysis/history loading from Supabase
- profile and subscription snapshot loading from Supabase

## Native app setup

The iOS client uses XcodeGen.

1. Open `ios/`
2. Fill in `Config/Base.xcconfig` or the per-config overrides
3. Run:

```bash
xcodegen generate
```

4. Open the generated Xcode project on macOS
5. Build and run from Xcode

## Backend setup

### Supabase

The repo keeps the existing Supabase schema and functions in `supabase/`.

### Detection server

The artwork detection backend remains in `server/`.

## Notes

- This workspace cannot generate or build an Xcode project from Windows, so final project generation still needs macOS.
- If you want Apple Sign In, Google Sign-In, RevenueCat, Superwall, and APNS fully wired in the native client, those are the next native-only tasks after the current direct-networking SwiftUI flow.
