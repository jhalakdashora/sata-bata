# Renaming the app

The name shown to users comes from **one place**:

| File | Used by |
|---|---|
| `config/brand.properties` | Android (launcher label, application ID) and iOS (display name, bundle ID, permission prompts) |
| `lib/app/brand.dart` | Everything inside the app (titles, Pro name, sign-in screen) |

Don't edit them by hand. Run:

```bash
tool/rename_app.sh "New Name"                     # change the name only
tool/rename_app.sh "New Name" com.yourco.newapp   # change the name and the app ID
```

`test/brand_test.dart` fails if the two files ever disagree.

## Name vs. ID

- **Name** (for example "Sata Bata"): change it any time, including after the app
  is published.
- **App ID** (`com.satabata.app`): the permanent identity on the Play Store
  and App Store. Change it freely **before** publishing. If you've already
  set up Google sign-in, also update the Android and iOS OAuth clients (see
  `SUPABASE_SETUP.md` step B2).

The code itself uses the neutral package name `split_app`, so no code
changes are needed when the brand changes.

Colors are in `lib/app/brand.dart` too: `seedColor` sets the whole theme,
and `proColor` is the Pro accent.
