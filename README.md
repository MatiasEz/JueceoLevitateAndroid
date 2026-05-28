# Levitate Android Tablet

Companion Flutter app for Android tablets. It uses the same Supabase schema as the iPad app and keeps the same core workflow: event, judge, routines, score sheet, feedback, scores, dictamen and PDF share.

## First Setup

The Android host folder is included. On a machine with Flutter installed:

```bash
flutter pub get
flutter run \
  --dart-define=SUPABASE_URL=https://bozkbpirrwjtpmjqcexx.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_jZv2loPhbPvameq6bUOgqA_5hEQJ2tc
```

If Flutter asks to refresh generated platform files, run:

```bash
flutter create . --platforms=android
```

## Current parity surface

- Home dashboard with next routines, metrics and judge entry.
- Admin panel for ATI with block selection, quick actions and "edit as judge".
- Reads the active/shared Supabase event.
- Selects event and judge.
- Lists blocks/routines with search.
- Scores criteria and writes feedback.
- Marks vestuario, coreografía and música favorites per judge.
- Stores local values with pending sync.
- Upserts scores/feedback/favorites to Supabase.
- Shows scores and dictamen by Género-Edad-Cantidad with the same average/tie rules as iPad.
- Exports ranking/dictamen PDF from the tablet.
- Lets the admin upload an Excel into the `excel_imports` queue in Supabase.

## Self-hosted Android updates

The app checks this GitHub Pages manifest on startup:

```text
https://matiasez.github.io/JueceoLevitateAndroid/latest.json
```

To publish a new APK outside Play Store:

1. Bump `version` in `pubspec.yaml`, for example `0.1.1+2`.
2. Build the APK:

```bash
flutter build apk --release
```

3. Create a GitHub Release and upload the APK as `jueceo.apk`.
4. Update `latest.json` with the new `versionCode`, `versionName`, notes and APK URL.

Android still asks the user to allow installs from this app and confirm the installer. The APK must be signed with the same key as the installed version.
