# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

This is an iOS app built with Xcode. Open `solaris.xcworkspace` (not `.xcodeproj` — CocoaPods workspace is required).

```bash
# Install CocoaPods dependencies (first time or after Podfile changes)
pod install

# Build from command line
xcodebuild -workspace solaris.xcworkspace -scheme solaris -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Run tests
xcodebuild -workspace solaris.xcworkspace -scheme solaris -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test

# Run a single test
xcodebuild -workspace solaris.xcworkspace -scheme solaris -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:solarisTests/solarisTests/testExample test
```

Deployment target: iOS 26.0. SPM dependencies (MetalPetal, FluidGradient) are resolved automatically by Xcode. CocoaPods 1.15.2+ required. Tests are currently template stubs with minimal coverage.

## Architecture

**Feature-based MVVM** with SwiftUI as the primary UI framework and UIKit for camera (AVFoundation). App entry point is `SolarisApp.swift` (`@main`), which initializes `ColorSchemeManager` as a state object and configures the SwiftData container.

### Feature Modules (`solaris/Features/`)

- **Camera** — Photo capture using AVFoundation. `CameraViewController` (UIKit) is wrapped via `CameraPreview` (UIViewControllerRepresentable) and presented from `PhotoCaptureView` (SwiftUI). Camera events (capture, switch) use `NotificationCenter`.
- **PhotoEditor** — GPU-accelerated image editing. `PhotoEditorViewModel` manages edit state with undo/redo stacks. Filters use MetalPetal with custom Metal shaders (`Filters/`, `Processing/Shaders/`). Filter presets are defined in `PhotoEditorFilters.swift`.

### Shared Layer (`solaris/Shared/`)

- **State** — `AppSettings` singleton persists user preferences via UserDefaults (color space, raw handling, metadata preservation, front camera mirroring).
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

`PhotoLibrary` (singleton) manages all file I/O with atomic writes. `PhotoRecord` tracks each photo's URLs and `PhotoEditState` (all edit parameters as Codable struct). SwiftData is configured (`Item` model, `Persistence.swift`) but the primary storage is file-based.

### Key Patterns

- **Dual-resolution preview**: Editor generates both high-res (for zoom) and low-res (for responsive slider interaction) previews.
- **Filter application**: Tap applies filter as base state (preserves slider adjustments); long-press applies directly to sliders. Both modes tracked separately in `PhotoEditorViewModel`.
- **Metal filter pipeline**: 15-stage GPU pipeline in `PhotoEditorViewModel.applyFilters()` — saturation → vibrance → exposure → brightness → contrast → fade → opacity → pixelate → clarity → sharpen → color tint/duotone → skin tone → invert → vignette → grain. Custom Metal shaders live in `Processing/Shaders/Effects.metal` (luma grain, duotone, skin tone via YCbCr masking, vignette). MetalPetal built-in filters handle the rest.
- **Singletons**: `PhotoLibrary.shared`, `AppSettings.shared`, `ImageCache.shared`. No formal DI container — uses SwiftUI environment + singletons.

### Navigation Flow

`ContentView` → photo grid (`PhotosScrollView`) with NavigationStack. Camera opens as `fullScreenCover`. Editor via `navigationDestination`. Settings via `sheet`.

### Filter Presets

Six preset groups defined in `PhotoEditorFilters.swift`: Classics, Cinema, Vintage, Portrait, Street, DÖST. Each preset maps to a `PhotoEditState` with predefined parameter values. Filter application has two modes: tap (applies as `baseFilterState` — persists but sliders stay neutral) and long-press (applies directly to edit sliders for immediate preview).
