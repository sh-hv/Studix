# Studix – Engineering Notes

## Current application boundaries

| Area | Primary files | Responsibility |
|---|---|---|
| App shell | `StudixApp.swift`, `DesignSystem.swift` | App lifecycle, navigation, theme and reusable UI |
| Domain and persistence | `Models.swift` | Codable models, `Store`, local files and backup lifecycle |
| Study library | `Library.swift` | Subjects, item lists and content creation |
| Documents | `Documents.swift`, `Scan.swift`, `Search.swift` | PDF reading, scanning, image processing and OCR |
| Audio | `Audio.swift` | Recording, playback, progress and markers |
| Notes | `Notes.swift` | Rich note blocks, PencilKit drawings, tables and charts |
| Planning | `Tasks.swift`, `Deadlines.swift` | Tasks, deadlines and local notifications |
| Preferences | `Settings.swift` | Language, backup and local usage statistics |

## Recommended direction for future growth

The current app is intentionally lightweight and uses a single observable `Store` for local state. As features grow, split responsibilities into services while keeping the existing JSON format compatible:

1. `Persistence`: repository protocol, JSON implementation, migrations and file coordination.
2. `Backup`: archive inspection, validation, export/import and rollback.
3. `Notifications`: one scheduler responsible for task and deadline requests.
4. `Audio`: recording and playback services independent of SwiftUI screens.
5. `Documents`: PDF import, scanning, OCR and indexing services.
6. `Features`: feature-specific view models and screens.

Do not move all features to a database merely for architectural fashion. If search, relationships or concurrent updates become a bottleneck, introduce SwiftData/Core Data behind a repository boundary and provide a one-time migration from `index.json`.

## Reliability requirements

- Never delete the current data directory before validating a replacement backup.
- Never ignore a failed primary save without surfacing a recoverable error.
- Recreate pending notifications after restoring data.
- Keep external file names as validated relative names; never trust archive paths.
- Avoid synchronous OCR or large image transformations on the main thread.
- Preserve existing model fields or implement explicit versioned migrations.

## UI requirements

- Reuse the design tokens and surface components in `DesignSystem.swift`.
- Support Arabic RTL and English LTR on every new screen.
- Provide empty, error and long-content states.
- Use Dynamic Type-friendly text and accessible labels for icon-only controls.
- Prefer small reusable feature components over monolithic view bodies.
