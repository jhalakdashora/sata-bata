# Sata Bata

A Flutter app for splitting shared expenses with friends and groups. It has a
free tier plus an **Sata Bata Pro** tier. See [docs/FEATURE_SPEC.md](docs/FEATURE_SPEC.md)
for the feature map and the architecture.

## Run

```bash
flutter pub get
flutter run                      # demo mode: in-memory data, no backend needed
```

### With Supabase and Google sign-in

Follow [docs/SUPABASE_SETUP.md](docs/SUPABASE_SETUP.md), copy
`config/example.json` to `config/dev.json`, fill it in, then run:

```bash
flutter run --dart-define-from-file=config/dev.json
```

## Test

```bash
flutter analyze
flutter test
```

## Stack

- Riverpod 3 for state management
- go_router for navigation
- Supabase (Postgres with row-level security, auth, realtime) for the backend
- Integer minor-unit money math in a pure-Dart domain layer
- Pro tier behind `EntitlementRepository` (a mock paywall for now; RevenueCat later)

## Renaming

The name and app ID live in `config/brand.properties` and `lib/app/brand.dart`.
To change them, run `tool/rename_app.sh "New Name"`. See [docs/RENAMING.md](docs/RENAMING.md).

## Design review screenshots

```bash
flutter test test_screenshots --update-goldens   # writes test_screenshots/goldens/*.png
```
