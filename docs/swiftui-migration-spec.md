# Worthify Native App Notes

## Current state

The repo now treats the SwiftUI app in `ios/` as the only client application.

The Flutter client has been removed. The backend remains in:

- `supabase/`
- `server/`

## Native app scope

The current native client is built around a small working core:

- email OTP auth against Supabase Auth
- local session persistence with refresh-token restoration
- image upload to Cloudinary
- artwork analysis through the existing `ARTWORK_ENDPOINT`
- saved analysis/history fetches from Supabase
- profile and subscription snapshot fetches from Supabase
- app-group config sync for future extension work

## Backend contracts still in use

### Environment

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `ARTWORK_ENDPOINT`
- `CLOUDINARY_CLOUD_NAME`
- `CLOUDINARY_API_KEY`
- `CLOUDINARY_API_SECRET`
- `SEARCHAPI_KEY`
- `APIFY_API_TOKEN`
- `APP_GROUP_ID`

### Supabase tables expected by the native app

- `users`
- `artwork_identifications`

The repo still contains additional schema for other flows under `supabase/migrations`, but the native client currently depends on the tables above most directly.

## What still needs macOS work

- generate the Xcode project from `ios/project.yml`
- build and run in Xcode
- verify that the deployed Supabase project includes the tables the native app queries
- add native Apple Sign In, Google Sign-In, RevenueCat, Superwall, and APNS if those flows are still required
