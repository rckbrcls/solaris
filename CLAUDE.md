# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

This is an iOS app built with Xcode. Open `solaris.xcodeproj` directly (no CocoaPods — only SPM).

```bash
# Build from command line
xcodebuild -project solaris.xcodeproj -scheme solaris -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Run tests
xcodebuild -project solaris.xcodeproj -scheme solaris -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test

# Run a single test
xcodebuild -project solaris.xcodeproj -scheme solaris -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:solarisTests/solarisTests/testExample test
```

Deployment target: iOS 26.0. SPM dependencies (MetalPetal, FluidGradient) are resolved automatically by Xcode. Tests are currently template stubs with minimal coverage.

## Architecture

**Feature-based MVVM** with SwiftUI as the primary UI framework and UIKit for camera (AVFoundation). App entry point is `SolarisApp.swift` (`@main`), which initializes `ColorSchemeManager` as a state object.

### Feature Modules (`solaris/Features/`)

- **Home** — Main screen with photo grid. `HomeView` (renamed from ContentView) displays `PhotosScrollView` with `PhotoGridItem` cells. Handles photo import, camera launch, and editor navigation.
- **Camera** — Photo capture using AVFoundation. `CameraViewController` (UIKit) is wrapped via `CameraPreview` (UIViewControllerRepresentable) and presented from `PhotoCaptureView` (SwiftUI). Camera events (capture, switch) use `NotificationCenter`.
- **PhotoEditor** — GPU-accelerated image editing. `PhotoEditorViewModel` manages edit state with undo/redo stacks. Filters use MetalPetal with custom Metal shaders (`Filters/`, `Processing/Shaders/`). Filter presets are defined in `PhotoEditorFilters.swift`.
- **Settings** — App settings screen. `SettingsView` manages user preferences.

### Shared Layer (`solaris/Shared/`)

- **State** — `AppSettings` singleton persists user preferences via UserDefaults (color space, raw handling, metadata preservation, front camera mirroring). `SavedFiltersStore` manages user-saved filter presets.
- **Services** — `ImageIOService.swift` contains image I/O utilities: HEIC export, full-quality loading, RAW detection, metadata-preserving writes, thumbnail generation, and format detection.
- **Theme** — `ColorSchemeManager` (environment object injected at app root) manages light/dark mode. `LiquidGlassModifier` provides glass-effect styling with iOS 26+ native support and fallback.
- **Components** — Reusable UI: `ImageCache` (NSCache, 50MB/500 items), `ZoomableModifier`, `LoadingOverlay`, `ActivityView`.

### Data & Persistence

Photos are stored as files, not in a database:

```
~/Documents/PhotoStorage/
├── originals/    # Raw captured photos (HEIC/JPG/PNG/RAW)
├── thumbs/       # 512px max thumbnails
├── edits/        # Edited versions
└── manifest.json # PhotoManifest registry
```

`PhotoLibrary` (singleton) manages all file I/O with atomic writes. `PhotoRecord` tracks each photo's URLs and `PhotoEditState` (all edit parameters as Codable struct).

### Key Patterns

- **Dual-resolution preview**: Editor generates both high-res (for zoom) and low-res (for responsive slider interaction) previews.
- **Filter application**: Tap applies filter as base state (preserves slider adjustments); long-press applies directly to sliders. Both modes tracked separately in `PhotoEditorViewModel`.
- **Metal filter pipeline**: 15-stage GPU pipeline in `PhotoEditorViewModel.applyFilters()` — saturation → vibrance → exposure → brightness → contrast → fade → opacity → pixelate → clarity → sharpen → color tint/duotone → skin tone → invert → vignette → grain. Custom Metal shaders live in `Processing/Shaders/Effects.metal` (luma grain, duotone, skin tone via YCbCr masking, vignette). MetalPetal built-in filters handle the rest.
- **Singletons**: `PhotoLibrary.shared`, `AppSettings.shared`, `ImageCache.shared`. No formal DI container — uses SwiftUI environment + singletons.

### Navigation Flow

`HomeView` → photo grid (`PhotosScrollView`) with NavigationStack. Camera opens as `fullScreenCover`. Editor via `navigationDestination`. Settings via `sheet`.

### Filter Presets

Six preset groups defined in `PhotoEditorFilters.swift`: Classics, Cinema, Vintage, Portrait, Street, DÖST. Each preset maps to a `PhotoEditState` with predefined parameter values. Filter application has two modes: tap (applies as `baseFilterState` — persists but sliders stay neutral) and long-press (applies directly to edit sliders for immediate preview).
