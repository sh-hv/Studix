# Studix

Studix is a native iOS study workspace built with SwiftUI. It brings course organization, documents, lecture recordings, notes, tasks and deadlines into one app.

## Build

The repository is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
xcodegen generate
xcodebuild -resolvePackageDependencies -project Studix.xcodeproj -scheme Studix
xcodebuild -project Studix.xcodeproj -scheme Studix -destination 'generic/platform=iOS' build
```

The GitHub Actions workflow builds the Release configuration for `iphoneos` whenever app sources, project configuration or workflow files change. It publishes an **unsigned IPA** as a workflow artifact and GitHub Release asset. The IPA must be signed with an Apple Development or Distribution certificate before it can be installed or distributed through the App Store.

To run a build manually, open **Actions → Build and Validate Studix → Run workflow**.

## Project structure

```text
Sources/
  StudixApp.swift       App entry point, theme and tab navigation
  DesignSystem.swift    Shared surfaces, dashboard components and visual tokens
  Models.swift          Domain models, local store and backup/restore
  Library.swift         Course and content library screens
  Documents.swift      PDF viewing and document scanning integration
  Scan.swift            Scan editing and image processing
  Audio.swift           Recording and playback
  Notes.swift           Rich notes, drawing, tables and charts
  Tasks.swift           Task list and task reminders
  Deadlines.swift       Deadlines and reminder scheduling
  Search.swift          Search and OCR
  Settings.swift        Preferences, statistics and backup UI
```

## Architecture principles

- **Views render state:** SwiftUI screens should focus on presentation and user interaction.
- **Domain models stay serializable:** persisted models should remain `Codable` and should receive explicit migrations when their schema changes.
- **Store is the local source of truth:** all changes to courses, content, tasks and deadlines flow through `Store` so persistence remains consistent.
- **Keep feature logic isolated:** when adding a substantial feature, put its models and feature-specific services in their own files instead of growing `Models.swift` or `StudixApp.swift`.
- **Centralize shared UI:** use `Theme`, `StudixSurface`, `SectionHeading` and the components in `DesignSystem.swift` to keep new screens visually consistent.
- **Treat user files as durable data:** write files atomically, report failures, validate imports before replacing current data, and keep a rollback path for destructive operations.

## Local data and backups

The app stores its index and user files under `Documents/Data`. `index.json` contains the library metadata; PDF, audio, note and drawing assets are stored alongside it.

A backup is a ZIP archive of this directory. Restore now stages and validates the archive before swapping it into place, checks archive paths, validates the JSON index and verifies referenced files. The current data directory is retained until the replacement succeeds.

## Localization

The app supports Arabic and English. Add new user-facing strings to `Sources/en.lproj/Localizable.strings`; Arabic strings are the source keys used by the current localization helper. Test both right-to-left and left-to-right layouts when changing shared components.

## Contribution checklist

1. Keep feature code in focused files and reuse shared design components.
2. Preserve compatibility with existing `Library` backups or add a migration.
3. Handle file, audio-session and notification errors explicitly.
4. Check empty, loading, failure and large-data states in the UI.
5. Run the GitHub Actions build before merging.
