<h1 align="center">Studix</h1>

<p align="center">
  A native iOS study workspace: subjects, PDFs, scans, lecture recordings, notes, tasks and deadlines in one app.
</p>

<p align="center">
  <a href="README.ar.md">العربية</a> · English
</p>

<p align="center">
  <img alt="iOS 16+" src="https://img.shields.io/badge/iOS-16.0%2B-blue">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-SwiftUI-orange">
  <img alt="Languages" src="https://img.shields.io/badge/languages-Arabic%20%7C%20English-green">
</p>

---

## Features

- **Subjects** with colors, grades and a dashboard that shows upcoming deadlines and open tasks.
- **Documents**: import PDFs or scan paper with the camera, adjust filters, and save as PDF. Scanned pages are searchable through on-device OCR.
- **Recordings**: record lectures with pause, bookmarks and background recording. Playback supports speed control and remembers where you stopped.
- **Notes**: text, headings, lists, checklists, tables, charts, photos and Apple Pencil drawings, on blank, ruled or grid paper.
- **Tasks and deadlines** with local reminders.
- **Search** across titles, note text and PDF text.
- **Backup and restore** as a single ZIP file.
- **Arabic and English**, with full right-to-left support.
- **Private by design**: everything is stored on the device. There are no accounts and no servers.

## Requirements

- iPhone running iOS 16.0 or later (portrait).
- To build: a Mac with Xcode, or the included GitHub Actions workflow.

## Build

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen), and the only dependency is [ZIPFoundation](https://github.com/weichsel/ZIPFoundation).

```bash
brew install xcodegen
xcodegen generate
open Studix.xcodeproj
```

### Without a Mac

The workflow in `.github/workflows/build.yml` builds the app on a GitHub macOS runner:

1. Push to `main`, or open **Actions → Build and Validate Studix → Run workflow**.
2. When the run succeeds, the **latest** release contains `Studix-unsigned.ipa`.
3. If the build fails, download the `build-log` artifact from the run page.

## Install

The IPA is **unsigned**. Sign and install it with a sideloading tool such as AltStore, SideStore or Sideloadly. Apps signed with a free Apple ID expire after 7 days and must be re-signed.

## Project structure

```text
Sources/
  StudixApp.swift       App entry point, theme and tab navigation
  DesignSystem.swift    Shared surfaces and dashboard components
  Models.swift          Models, local store, backup and restore
  Library.swift         Subjects and content lists
  Documents.swift       PDF reader and scanner integration
  Scan.swift            Scan editing and image processing
  Audio.swift           Recording and playback
  Notes.swift           Notes, drawings, tables and charts
  Tasks.swift           Task list
  Deadlines.swift       Deadlines and reminders
  Search.swift          Search and OCR
  Settings.swift        Language, statistics and backup screens
  en.lproj/             English strings
  Assets.xcassets/      App icon and images
```

More detail is in [ARCHITECTURE.md](ARCHITECTURE.md).

## Your data

The app keeps its library under `Documents/Data`: `index.json` for metadata, plus PDFs, audio, notes, drawings and a `Text/` folder for search text. A backup is a ZIP of that folder. Restore validates the archive before replacing anything and keeps the old data until the new data is in place.

## Localization

Arabic strings are the source keys. Add the English translation of every new string to `Sources/en.lproj/Localizable.strings`, and check both right-to-left and left-to-right layouts.

## Contributing

1. Keep feature code in focused files and reuse the components in `DesignSystem.swift`.
2. Keep existing backups readable, or add a migration.
3. Handle file, audio and notification errors explicitly.
4. Check empty, error and large-data states.
5. Make sure the GitHub Actions build passes before merging.

See [CHANGELOG.md](CHANGELOG.md) for release notes.
