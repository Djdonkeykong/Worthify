# Flutter App Design System & Guidelines for Worthify

## Project Overview
Worthify is an AI-powered art identification and value estimation app. Users photograph a painting or artwork → the app identifies it (artist, title, style, year) and provides an AI-estimated value range. Target users: thrift shoppers, estate sale buyers, museum visitors, people who inherited artwork.

## Design System Rules - ALWAYS FOLLOW THESE

### Colors
- **Primary Color**: `#F9F8F7` (Gallery Off-White) - Main backgrounds
- **Surface**: `#EFEFED` - Cards and elevated surfaces
- **Secondary / CTA**: `#1C1B1A` (Near-Black) - Buttons, active nav states, key actions
- **Borders**: `#E2E0DD` (Warm Light Gray)
- **Text Colors**:
  - Primary Text: `#1C1B1A` (Near-black)
  - Secondary Text: `#6B6966` (Muted warm gray)
  - Tertiary Text: `#9C9A97` (Captions, inactive)
- **Navigation**:
  - Active: `#1C1B1A` (near-black)
  - Inactive: `#9C9A97` (muted gray)
- **State Colors**:
  - Error: `#EF4444`
  - Success: `#22C55E`
  - Warning: `#F59E0B`

### AppColors Token Reference
- `AppColors.primary` → `#F9F8F7` (gallery off-white background)
- `AppColors.primaryDark` → `#EFEFED` (surface variant)
- `AppColors.secondary` → `#1C1B1A` (near-black CTAs and active states)
- `AppColors.outline` → `#E2E0DD` (borders)

### Corner Radius Standards
- **Small**: 8px - Chips, badges
- **Medium**: 12px - Cards, inputs, containers
- **Large**: 16px - Modals, bottom sheets
- **Extra Large**: 28px - Primary buttons

### Navigation System
- **Bottom Navigation**: Uses IndexedStack to preserve state between tabs
- **Tabs**: Home (Camera), Collection (Saved), Profile
- **Icons Only**: No text labels on navigation items
- **Active State**: Near-black (`#1C1B1A`)
- **Inactive State**: Muted gray (`#9C9A97`)

### Component Styles
- **Primary Actions**: `#1C1B1A` background with white text, 28px border radius
- **Secondary Actions**: Off-white surface with warm gray border, 28px border radius
- **Cards**: White/off-white surface with `#E2E0DD` borders
- **Modal Sheets**: Rounded top corners, off-white surface
- **Back Buttons**: Light circle with dark icon

### Typography
- **Font**: Inter (via `google_fonts`) — no hardcoded `fontFamily` strings
- **Display Small**: 36px, Bold - Hero headings
- **Headline Small**: 24px, Bold - Section headers
- **Title Large**: 22px, SemiBold - Card titles
- **Title Medium**: 16px, Medium - Component titles
- **Body Large**: 16px, Regular - Primary body
- **Body Medium**: 14px, Regular - Secondary body
- **Body Small**: 12px, Regular - Captions

### Spacing System
- **XS**: 4px
- **SM**: 8px
- **M**: 16px (default padding)
- **L**: 24px
- **XL**: 32px
- **XXL**: 48px

## CRITICAL RULES & INSTRUCTIONS

- **Gallery aesthetic**: Off-white backgrounds (`#F9F8F7`) with near-black text and CTAs
- **No red accent** — AppColors.secondary is `#1C1B1A`, not red
- **Inter font** via google_fonts — never hardcode `fontFamily: 'Inter'` as a string
- **Use IndexedStack navigation** — preserve state between tabs
- Use `AppColors.secondary` for CTAs and active states
- Use `context.spacing.m` and `context.radius.medium` for consistent spacing/radius
- **Legal**: Never claim certified appraisal — always show value range + confidence level + disclaimer

### Artwork Detection Pipeline
1. User captures artwork photo
2. Backend sends image to SearchAPI.io (Google Image Search mode)
3. Extract top 5–10 results (artist, title, auction data, links)
4. Send structured results to LLM → returns structured JSON:
   - `identified_artist`, `artwork_title`, `year_estimate`, `style`, `medium_guess`
   - `is_original_or_print`, `confidence_level`, `estimated_value_range`
   - `value_reasoning`, `comparable_examples_summary`
5. Display result with disclaimer + save to user's collection

### File Structure
```
lib/
├── main.dart
├── core/
│   ├── theme/
│   │   ├── app_theme.dart
│   │   ├── color_schemes.dart
│   │   ├── app_colors.dart
│   │   ├── app_spacing.dart
│   │   ├── app_radius.dart
│   │   └── theme_extensions.dart
│   └── constants/
├── shared/
│   ├── navigation/
│   │   └── main_navigation.dart
│   └── widgets/
└── src/features/
    ├── home/          ← camera/scan tab
    ├── wardrobe/      ← saved collection (UI: "Collection")
    ├── detection/     ← artwork detection pipeline
    ├── profile/
    ├── auth/          ← Supabase + Google/Apple (fully working)
    └── onboarding/    ← art style preferences
```

### Code Conventions
- Use `const` constructors wherever possible
- Use Riverpod for state management
- Use theme extensions consistently: `context.spacing.m`, `context.radius.large`
- Follow Material 3 component patterns
- Include accessibility semantics

## Tech Stack
- Flutter 3.19+ (Material 3)
- State Management: Riverpod
- Backend: Supabase (auth + database)
- Payments: RevenueCat + Superwall
- Analytics: Amplitude
- Push Notifications: Firebase Cloud Messaging
- Auth: Google Sign-In + Sign in with Apple
- Font: Inter via google_fonts

## Development Commands
- `flutter run --dart-define-from-file=.env` - Run with env vars
- `flutter test` - Run tests
- `flutter build apk` - Build Android
- `flutter analyze` - Static analysis
- `flutter pub get` - Get dependencies
