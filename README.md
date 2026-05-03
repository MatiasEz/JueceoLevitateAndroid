# Jueceo Coreografias Android Tablet

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
- Stores local values with pending sync.
- Upserts scores/feedback to Supabase.
- Shows scores and dictamen by Genero-Edad-Cantidad with the same average/tie rules as iPad.
- Exports ranking/dictamen PDF from the tablet.
- Lets the admin upload an Excel into the `excel_imports` queue in Supabase.
