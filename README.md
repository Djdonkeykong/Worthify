# Worthify - AI Art Identification & Value Estimation App

Worthify is a Flutter mobile application that uses AI to identify artwork and estimate its value. Photograph a painting or artwork → the app identifies the artist, title, style, and year, then provides an AI-estimated value range.

## Who is it for?
- Thrift shoppers and estate sale buyers
- Museum visitors curious about a piece
- People who inherited artwork and want to know what it's worth

## How it works
1. User photographs artwork with their camera (or uploads an image)
2. Backend sends the image to SearchAPI.io (Google Image Search mode)
3. Top results (artist, title, auction data) are extracted and sent to an LLM
4. LLM returns structured identification + value estimate
5. Result is displayed with a confidence level, value range, and legal disclaimer
6. User can save artworks to their Collection

> **Legal note:** Worthify never claims to provide a certified appraisal. All value estimates are AI-generated ranges for informational purposes only.

## Tech Stack
- **Frontend:** Flutter 3.19+ (Material 3), Riverpod state management
- **Backend:** Supabase (auth + database), custom detection server
- **Auth:** Google Sign-In + Sign in with Apple
- **Payments:** RevenueCat + Superwall
- **Analytics:** Amplitude
- **Push Notifications:** Firebase Cloud Messaging
- **Font:** Inter via google_fonts

## Development

```bash
# Install dependencies
flutter pub get

# Run with environment variables
flutter run --dart-define-from-file=.env

# Static analysis
flutter analyze

# Run tests
flutter test

# Build for Android
flutter build apk
```

## Environment Variables
See `ENV_DEPLOYMENT_GUIDE.md` for the full list of required environment variables.

## Design System
The app uses a gallery aesthetic:
- **Background:** `#F9F8F7` (gallery off-white)
- **CTAs / Active states:** `#1C1B1A` (near-black)
- **Font:** Inter (google_fonts)

See `CLAUDE.md` for the full design system specification.
