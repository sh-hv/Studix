# Changelog

## Unreleased

### Data safety
- Recorder: leaving a recording in progress now asks to save, delete or keep recording instead of deleting it.
- Notes: an unreadable note is never overwritten with an empty one (a copy is kept and autosave is paused). Save errors for notes, images and drawings are now reported.
- Deleting a subject or an item asks for confirmation. Deleting a subject also clears it from deadlines and tasks.
- Restore no longer rejects a whole backup because one entry has a missing file; that entry is skipped and counted. Pending notifications are fully replaced after a restore.
- The index keeps a previous copy (`index.previous.json`) and falls back to it when the main index cannot be read. Unreadable items no longer make the whole library fail to decode.
- Empty notes that were never written in are removed when their editor closes.

### Performance and stability
- Photos from the library are no longer rendered at 3x scale (about 9x memory) when straightened.
- Scan editor renders filter previews off the main thread, only when a setting changes. Saving builds the PDF page by page off the main thread.
- Backup and restore run off the main thread with a progress indicator.
- Table and chart cells use bounds-checked bindings, which avoids crashes when deleting rows or columns.
- OCR and note text moved out of `index.json` into `Text/` files. Existing data is migrated automatically.

### Features and fixes
- Search now includes note text. Documents that were never indexed are indexed on launch. OCR covers up to 500 pages (80 image pages).
- Paper templates (ruled, grid) now show in the note editor.
- New deadlines screen lists upcoming and past deadlines and supports editing and deleting.
- Notifications are rebuilt from scratch on every change, capped at 60 pending, shown while the app is open, and the deadline sheet warns when notifications are off.
- `parseNumber` handles thousands separators ("1,000").
- Imported files are checked to be valid PDFs, and import and scan failures are reported.
- Recordings that were played to the end start from the beginning.
- Drawing previews stay readable in dark mode.
- Accessibility labels for icon-only buttons.
- Fixed the afternoon greeting.

## 1.1.0 – Reliability and UI refresh

### Fixed and hardened
- Local JSON writes now report failures instead of silently swallowing every persistence error.
- Corrupt indexes are preserved for recovery rather than being silently overwritten.
- Backup creation verifies that the current index was saved successfully.
- Backup restore validates archive paths, rejects symlinks and excessive archive sizes, validates the decoded library and referenced files, and swaps data with a rollback path.
- Restored deadlines and unfinished tasks have their local notifications rescheduled.
- Task reminders are re-created when an unfinished task is re-enabled.
- Recording setup now checks microphone permission and audio-session setup, handles audio interruptions, reports failures, and avoids saving empty failed recordings.
- Playback setup now reports file/session errors and clamps restored playback positions.
- Notes are saved when their content changes, in addition to view exit and app backgrounding.
- GitHub Actions now builds when source or project files change, validates pull requests, and clearly labels the generated IPA as unsigned.

### UI and maintainability
- Added a shared design system with reusable surfaces, section headings and dashboard metrics.
- Refreshed the home dashboard, course cards, settings and statistics screens.
- Updated the accent and course color palette.
- Added architecture and contribution guidance for future feature development.
- Bumped the app marketing version to 1.1.0.
