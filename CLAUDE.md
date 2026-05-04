# CLAUDE.md

This file gives agent-facing guidance for working in this repository.

## Workspace Rule

Do not run build, run, archive, simulator, or test commands from agent sessions in this workspace. Human developers can use Xcode directly when they need those actions.

The command examples below are developer references only, not agent instructions to execute them.

## Project Summary

Solaris is a medium-sized single native iOS app for local photo capture, organization, editing, and export.

It is not a web app, backend, API service, CLI, package library, database project, desktop app, mobile monorepo, or multi-package repository.

## Xcode Project

- Main target: `solaris`
- Test targets: `solarisTests`, `solarisUITests`
- Default entry point: `solaris/SolarisApp.swift`
- Preferred Xcode entry: `solaris.xcworkspace`
- Project file: `solaris.xcodeproj`
- Deployment target: iOS 26.0
- Bundle identifier: `polterware.solaris`
- Dependency manager: Swift Package Manager
- CocoaPods: not present

Reference commands for human developers:

```bash
xcodebuild -project solaris.xcodeproj -scheme solaris -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
xcodebuild -project solaris.xcodeproj -scheme solaris -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

## Architecture

Solaris uses feature-based organization with SwiftUI for the main app shell and UIKit for camera and share-sheet integration.

### Feature Modules

- `solaris/Features/Home` - main grid, import, delete, share, camera launch, settings launch, editor navigation, manifest loading, and thumbnail cache updates.
- `solaris/Features/Camera` - SwiftUI camera screen, UIKit preview bridge, AVFoundation session/capture service, focus/exposure/zoom/camera switching.
- `solaris/Features/PhotoEditor` - editor UI, filter browser, adjustment controls, view model, preview/final rendering, MetalPetal stages, custom Metal shaders, and local photo library records.
- `solaris/Features/Settings` - user-facing preferences backed by `AppSettings`.

### Shared Layer

- `solaris/Shared/State` - `AppSettings` and `SavedFiltersStore`, both UserDefaults-backed.
- `solaris/Shared/Services` - image I/O, metadata-aware writing, HEIC export, RAW detection, thumbnails, and photo save helpers.
- `solaris/Shared/Components` - reusable views, haptics, zoom, image cache, share sheet, and edit history.
- `solaris/Shared/Theme` - color scheme observation, glass styling, and animation constants.

## Persistence

Solaris stores photos as local files, not in a database:

```text
Documents/PhotoStorage/
├── originals/
├── thumbs/
├── edits/
├── manifest.json
└── manifest.json.bak
```

`PhotoLibrary` owns directory creation, manifest loading, backup fallback, path normalization, manifest saving, orphan cleanup, and file deletion.

`PhotoRecord` persists original URL, thumbnail URL, optional edited URL, optional `PhotoEditState`, optional `baseFilterState`, optional edit history, and creation date.

`AppSettings` stores `AppSettings_v1` in UserDefaults. `SavedFiltersStore` stores `SavedFilters_v1` in UserDefaults.

## Editor Pipeline

`PhotoEditorViewModel` owns current edit state, base filter state, undo/redo history, preview update scheduling, interactive adjustment transactions, and final image generation.

`FilterStateManager` combines base filter state and slider edit state. Preserve this separation:

- Tap on a preset applies it as `baseFilterState`.
- Long press on a preset applies it into slider/edit state.

`PreviewRenderer` builds high-resolution and low-resolution preview bases and uses `FilterPipeline.standard(grainSeed:)`.

The standard pipeline order is saturation, vibrance, exposure, brightness, contrast, fade, opacity, pixelate, clarity, sharpen, color tint/duotone, skin tone, invert, vignette, and grain.

Custom shader-backed filters live under:

- `solaris/Features/PhotoEditor/Filters`
- `solaris/Features/PhotoEditor/Processing/Shaders/Effects.metal`

## Privacy Notes

The current codebase has no backend, network API client, analytics SDK, authentication, authorization, cloud sync, database, or remote storage.

Camera/photo permissions and privacy manifest behavior are documented in `docs/security.md`.

Metadata preservation is user-configurable through `AppSettings.shared.preserveMetadata`. Treat EXIF/GPS behavior as a privacy-sensitive feature.

## Documentation Rules

All documentation must be project-specific and written in English.

Do not create generic API, database, deployment, setup, or internal folder README files unless the codebase actually gains the corresponding system.

Keep documentation synchronized with:

- `README.md`
- `docs/architecture.md`
- `docs/development.md`
- `docs/security.md`
- `docs/troubleshooting.md`
- `docs/deployment.md`
