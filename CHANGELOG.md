# Changelog

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
