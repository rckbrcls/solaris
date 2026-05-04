# Development

This guide documents how to work inside the current Solaris codebase. It is specific to this repository and does not describe a generic iOS app workflow.

## Development Environment

Use Xcode as the primary development environment. The repository contains an Xcode project and workspace, with Swift Package Manager dependencies resolved through shared package resolution files.

Open `solaris.xcworkspace` by default. `solaris.xcodeproj` is also present, but the workspace is the safer entry point for preserving package resolution behavior.

Agents working in this workspace must not run build, run, or test commands. Human developers can use Xcode's Product menu when they need to build, run, test, preview, or archive.

## Source Organization

- Add user-facing features under `solaris/Features/<FeatureName>/`.
- Add reusable UI, utilities, and cross-feature state under `solaris/Shared/`.
- Keep feature-specific view models, services, filters, and views inside their feature folder when they are not reused elsewhere.
- Keep visual tokens in `solaris/Assets.xcassets/Colors` and shared styling helpers in `solaris/Shared/Theme`.
- Keep visible source strings in English and route localizable UI copy through `String(localized:)`.

## Adding Or Changing Filters

Filter changes usually affect several layers. Update all relevant pieces together:

- `PhotoEditState` in `PhotoEditorViewModel.swift` for persisted adjustment fields.
- `FilterStateManager` for combining base filter state and slider edit state.
- `FilterPipeline.standard(grainSeed:)` for render order.
- `FilterStages.swift` or a dedicated filter file for the MetalPetal stage.
- `Effects.metal` only when a custom shader is required.
- `PhotoEditorAdjustments.swift` when the filter needs user controls.
- `PhotoEditorFilters.swift` when presets or thumbnail rendering need to reflect the new effect.
- `Localizable.xcstrings` when visible UI strings are added.

When adding a persisted field to `PhotoEditState`, consider old manifest compatibility. `PhotoRecord` and `PhotoEditState` are Codable and loaded from `manifest.json`.

## Editing The Photo Storage Model

The storage contract lives in `PhotoLibrary` and is consumed heavily by `HomeView` and the editor save flow. Changes to storage should preserve:

- `Documents/PhotoStorage/originals` for source files.
- `Documents/PhotoStorage/thumbs` for thumbnails.
- `Documents/PhotoStorage/edits` for saved edited outputs.
- `manifest.json` as the catalog.
- `manifest.json.bak` as the fallback catalog.
- Path normalization when app container paths change.
- Atomic-ish manifest writes using a temporary file and replacement.

If a new file type or sidecar is added, update cleanup logic so orphaned files do not accumulate.

## Camera Changes

Keep AVFoundation session details inside `CameraService` unless a UIKit-specific gesture or overlay requires `CameraViewController`.

Use the current boundaries:

- SwiftUI screen state and controls: `PhotoCaptureView`.
- SwiftUI-to-UIKit bridge: `CameraPreview`.
- UIKit gestures and visual overlays: `CameraViewController`.
- AVFoundation session, devices, capture, focus, exposure, and zoom: `CameraService`.

Be careful with `CameraCommands`. It must keep stable identity through `@State`, otherwise SwiftUI updates can drop the controller reference used by camera buttons.

## Settings And Preferences

`AppSettings` is the source of truth for persisted app preferences. New settings should:

- Be added to the observable class.
- Be added to the private `Stored` Codable payload.
- Be restored in `restore()`.
- Be persisted in `persist()`.
- Be exposed through `SettingsView` only when there is a real user-facing reason.

Saved user filters belong in `SavedFiltersStore`, not in `AppSettings`.

## UI And Visual Conventions

Solaris uses native SwiftUI, semantic asset colors, glass-style surfaces, compact icon controls, and haptic feedback.

Follow the existing patterns:

- Use asset catalog colors such as `Color.textPrimary`, `Color.borderSubtle`, and `Color.actionAccent`.
- Use `.liquidGlass(...)` for existing glass surfaces.
- Use `Haptics` helpers for tactile feedback instead of ad hoc generators where possible.
- Keep app source strings in English.
- Add accessibility labels for icon-only controls.

Do not add web-specific behavior, browser translation tags, DOM assumptions, or frontend framework patterns. Solaris is not a web app.

## Testing Priorities

The existing XCTest targets are mostly template-level. The highest-value future tests are pure logic tests that do not require camera hardware or image fixtures:

- `FilterStateManager.combinedState(...)`.
- `FilterStateManager.isStatesSimilar(...)`.
- `EditHistory` undo/redo/reset behavior.
- `AppSettings` Codable persistence shape.
- `SavedFiltersStore` add/delete behavior.
- `PhotoLibrary` manifest path normalization and backup fallback.

UI tests should stay narrow until deterministic fixtures and app state reset helpers exist.

## Things Not Present In This Repository

- No backend server.
- No network API client.
- No authentication or authorization flow.
- No database, ORM, migration system, or seed scripts.
- No Docker setup.
- No CI configuration.
- No fastlane, TestFlight automation, or App Store Connect automation.
