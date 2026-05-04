# Solaris

Solaris is a native iOS photo editor focused on local capture, private photo storage, GPU-accelerated filters, saved presets, metadata-aware export, and a polished SwiftUI editing workflow.

The project is a medium-sized single iOS app. It is not a web app, backend, API service, CLI, package library, database project, or monorepo.

## Project Status

- Status: active native iOS app.
- App target: `solaris`.
- Test targets: `solarisTests` and `solarisUITests`.
- Deployment target: iOS 26.0.
- Bundle identifier: `polterware.solaris`.
- License: GPLv3, as defined in `LICENSE`.

Build, run, and test commands were not executed during this documentation pass. The repository owner has instructed agents not to run build or run commands in this workspace.

## What Solaris Does

Solaris lets users capture, import, organize, edit, save, and share photos locally on iOS. The app keeps its own local photo catalog under the app container, applies filter and adjustment state through a MetalPetal pipeline, and writes edited output with configurable metadata and color profile behavior.

Main capabilities in the current codebase:

- Local photo grid with import, selection, delete, and share flows.
- Full-screen camera flow using AVFoundation through a UIKit controller embedded in SwiftUI.
- Camera controls for flash, grid overlay, aspect ratio, front/back camera, zoom, focus, and exposure lock.
- GPU-backed photo editor with filter presets, sliders, saved filters, undo/redo, reset, save, discard, and share export.
- Local persistence for originals, thumbnails, edited files, edit state, base filter state, and undo history.
- Settings for metadata preservation, export color profile, undo history limit, and front camera mirroring.
- English source localization with Brazilian Portuguese translations in `solaris/Localizable.xcstrings`.
- Apple privacy manifest in `solaris/PrivacyInfo.xcprivacy`.

## Technology Stack

| Area | Technology |
| --- | --- |
| App framework | SwiftUI |
| UIKit integration | `UIViewControllerRepresentable`, `UIActivityViewController`, UIKit camera controller |
| Camera | AVFoundation |
| Photo import | PhotosUI |
| Image I/O | ImageIO, UniformTypeIdentifiers, AVFoundation HEIC constants |
| GPU processing | MetalPetal and custom Metal shaders |
| Visual system | Asset catalog colors, SwiftUI materials/glass effect, FluidGradient |
| Icons | SF Symbols and Phosphor Swift |
| Persistence | App-container files plus UserDefaults |
| Tests | XCTest targets generated for unit and UI tests |
| Dependencies | Swift Package Manager through the Xcode project/workspace |

Pinned Swift Package Manager dependencies are recorded in `solaris.xcworkspace/xcshareddata/swiftpm/Package.resolved`:

- `MetalPetal` 1.25.2
- `FluidGradient` 1.0.0
- `phosphor-icons/swift` 2.1.0

## Repository Structure

```text
.
├── solaris/                         # Main iOS app source
│   ├── SolarisApp.swift             # App entry point and scene lifecycle bridge
│   ├── Localizable.xcstrings        # English source strings and pt-BR translations
│   ├── PrivacyInfo.xcprivacy        # Apple privacy manifest
│   ├── Assets.xcassets/             # App icons, logos, semantic colors, visual assets
│   ├── Features/
│   │   ├── Home/                    # Grid, import, delete, share, camera/editor navigation
│   │   ├── Camera/                  # SwiftUI camera shell, UIKit bridge, AVFoundation service
│   │   ├── PhotoEditor/             # Editor UI, view model, filters, shaders, photo library
│   │   └── Settings/                # Settings form backed by AppSettings
│   └── Shared/
│       ├── Components/              # Reusable views, haptics, image cache, edit history
│       ├── Services/                # Image I/O and photo-save helpers
│       ├── State/                   # UserDefaults-backed app and saved-filter state
│       └── Theme/                   # Color scheme observer, glass modifier, animations
├── solaris.xcodeproj/               # Xcode project
├── solaris.xcworkspace/             # Workspace containing the Xcode project and SPM resolution
├── solarisTests/                    # Unit test target, currently template-level
├── solarisUITests/                  # UI test target, currently launch/template-level
├── docs/                            # Focused project documentation
├── CONTRIBUTING.md                  # Solaris-specific contribution workflow
├── CLAUDE.md                        # Agent-facing implementation notes
└── LICENSE                          # GPLv3
```

## Prerequisites

- macOS with Xcode capable of opening an iOS 26.0 project.
- iOS Simulator or a physical iOS device.
- Apple Developer signing setup if building for a physical device or archiving.
- Network access when Xcode needs to resolve Swift Package Manager dependencies.

No CocoaPods, Carthage, Docker, backend service, database server, or environment-variable setup was identified in the current codebase.

## Installation And Local Development

1. Clone the repository.
2. Open `solaris.xcworkspace` in Xcode. `solaris.xcodeproj` also references the app project, but the workspace is the safer default because it carries the shared SwiftPM resolution.
3. Let Xcode resolve Swift Package Manager dependencies.
4. Select the `solaris` scheme and an iOS 26.0-compatible simulator or device.
5. Use Xcode's Product menu for build, run, test, archive, and previews.

There are no package-manager scripts such as `npm`, `pnpm`, `bun`, `make`, or `Package.swift` commands in this repository.

## Runtime Data

Solaris stores photos as files in the app container, not in a database:

```text
Documents/PhotoStorage/
├── originals/          # Imported or captured originals
├── thumbs/             # 512 px thumbnails
├── edits/              # Saved edited outputs
├── manifest.json       # PhotoManifest catalog
└── manifest.json.bak   # Backup of the previous manifest
```

`PhotoLibrary` manages the storage root, manifest loading, path normalization, manifest backup, and orphan file cleanup. App preferences and saved filter presets are stored in UserDefaults keys `AppSettings_v1` and `SavedFilters_v1`.

## Build And Test Notes

Human developers can use Xcode to build, run, and test the app. This documentation pass did not verify command-line builds or tests.

Current test coverage is minimal:

- `solarisTests/solarisTests.swift` contains template unit tests.
- `solarisUITests/solarisUITests.swift` launches the app.
- `solarisUITests/solarisUITestsLaunchTests.swift` captures a launch screenshot attachment.

Meaningful future tests should cover pure state logic first, especially `FilterStateManager`, `EditHistory`, image path normalization, saved filter persistence, and settings serialization.

## Privacy And Security Summary

Solaris is local-first in the current codebase:

- No backend, network client, remote API, telemetry SDK, analytics SDK, authentication flow, or authorization model was found.
- Camera and photo-library permissions are declared through generated Info.plist settings in `solaris.xcodeproj/project.pbxproj`.
- `solaris/PrivacyInfo.xcprivacy` declares no tracking, no tracking domains, and no collected data types.
- The privacy manifest declares accessed API categories for file timestamps and UserDefaults.
- Export can preserve metadata, including EXIF/GPS, depending on `AppSettings.shared.preserveMetadata`.

See `docs/security.md` for project-specific privacy and metadata notes.

## Documentation

- `docs/architecture.md` explains the app structure, local data flow, camera bridge, editor pipeline, and persistence model.
- `docs/development.md` describes how to extend Solaris safely.
- `docs/security.md` documents privacy, permissions, metadata, and local data concerns.
- `docs/troubleshooting.md` covers likely setup and runtime problems.
- `docs/deployment.md` documents the current release inputs and the lack of deployment automation.

## Current Limitations

- No production deployment pipeline, CI workflow, fastlane setup, TestFlight automation, or rollback workflow was identified.
- Unit and UI tests are still mostly template-level.
- Photo persistence is local to the app container. There is no sync, backup integration, account model, or remote storage.
- The app depends on iOS 26.0 APIs such as SwiftUI glass styling. Compatibility below that target is not established by the project settings.
- Simulator camera behavior is limited by the simulator environment; real capture behavior should be checked on device.

## License

Solaris is distributed under GPLv3. See `LICENSE`.
