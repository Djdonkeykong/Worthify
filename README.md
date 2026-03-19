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

#### Run the detection server locally with ngrok

The iOS app only depends on `ARTWORK_ENDPOINT`, so you can replace the Render URL with a tunnel to your local FastAPI server.

1. Create a server env file from `server/.env.example` and fill in:
   - `SEARCHAPI_KEY`
   - `ANTHROPIC_API_KEY`
2. Install the server dependencies:

```bash
pip install -r server/artwork_requirements.txt
```

3. Run the server locally:

```bash
cd server
uvicorn artwork_server:app --host 0.0.0.0 --port 8000
```

4. In another terminal, expose it with ngrok:

```bash
ngrok http 8000
```

5. Point the app to the tunnel URL:
   - `ARTWORK_ENDPOINT=https://<your-ngrok-domain>/identify`

Notes:

- If you use Codemagic/TestFlight, update the `ARTWORK_ENDPOINT` variable in the `worthify_env` group and rebuild the app.
- If you use a local Xcode build, set `ARTWORK_ENDPOINT` in `ios/Config/Base.xcconfig`.
- If your ngrok URL changes on every run, the app needs a rebuilt config unless you use a reserved/stable tunnel domain.

## Notes

- This workspace cannot generate or build an Xcode project from Windows, so final project generation still needs macOS.
- If you want Apple Sign In, Google Sign-In, RevenueCat, Superwall, and APNS fully wired in the native client, those are the next native-only tasks after the current direct-networking SwiftUI flow.
