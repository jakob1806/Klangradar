# Klangradar Native for iPhone and iPad

This directory contains a **parallel SwiftUI client**. It does not replace or
modify the existing Flutter app in `../app` and it uses the same Supabase
backend contracts.

## Open and run

```bash
cd ios-native
ruby Scripts/generate_project.rb
open KlangradarNative.xcodeproj
```

The app builds without secrets and then uses deterministic preview data. To
connect the live backend, copy the local secrets template:

```bash
cp Config/Secrets.plist.example Config/Secrets.plist
ruby Scripts/generate_project.rb
```

The generator automatically includes the local file as an application resource.
Alternatively, set `SUPABASE_URL` and `SUPABASE_ANON_KEY` in the active Xcode
scheme's environment variables. `Config/Secrets.plist` is ignored by Git and
must never be committed.

When the existing Flutter `.env` is available locally, the same public client
configuration can be imported without printing credentials:

```bash
ruby Scripts/import_flutter_env.rb
ruby Scripts/generate_project.rb
```

## Build from the command line

```bash
xcodebuild \
  -project KlangradarNative.xcodeproj \
  -scheme KlangradarNative \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Architecture

```text
KlangradarNative/
├── App/                    SwiftUI entry point and dependency composition
├── Core/
│   ├── Configuration/      local, non-secret runtime configuration
│   ├── Networking/         URLSession + Supabase PostgREST client
│   └── Repositories/       backend-facing protocols and implementations
├── DesignSystem/           shared Liquid Glass and visual components
├── Domain/Models/          backend-independent Swift models
├── Features/               feature-first SwiftUI screens and view models
└── Resources/              asset catalogs and future string catalogs
```

The deployment target is iOS/iPadOS 17. On iOS 26 and newer, custom controls
use Apple's native Liquid Glass APIs. Older systems fall back to native SwiftUI
materials. Standard `TabView`, navigation bars and toolbars automatically adopt
the current system appearance.

## Rules

- Keep Flutter and SwiftUI clients independent.
- Share backend contracts, not UI code.
- Never copy secrets from `app/.env` into tracked Swift files.
- Keep repository protocols injectable so preview data and tests remain usable.
- Regenerate the Xcode project after adding source files:
  `ruby Scripts/generate_project.rb`.
- Do not remove a Flutter feature until the native equivalent has parity tests.

See `CLAUDE.md` and `MIGRATION_STATUS.md` before continuing work.
