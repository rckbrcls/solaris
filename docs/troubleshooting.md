# Troubleshooting

This guide covers likely issues for the current Solaris iOS codebase. It does not cover backend, database, Docker, or web deployment problems because those systems are not present.

## Xcode Cannot Resolve Packages

Likely cause: Swift Package Manager has not resolved `MetalPetal`, `FluidGradient`, or `phosphor-icons/swift`.

What to check:

- Open `solaris.xcworkspace` in Xcode.
- Let Xcode resolve packages.
- Check `solaris.xcworkspace/xcshareddata/swiftpm/Package.resolved`.
- Confirm network access to GitHub if Xcode needs to fetch packages.

Do not add CocoaPods or a `Podfile`; the project currently uses Swift Package Manager.

## The Project Opens But iOS APIs Are Missing

Likely cause: Xcode or the selected SDK does not support the configured iOS 26.0 deployment target or SwiftUI glass APIs.

What to check:

- Confirm the installed Xcode version supports the configured SDK.
- Confirm the selected simulator/device is compatible with iOS 26.0.
- Check `solaris.xcodeproj/project.pbxproj` for `IPHONEOS_DEPLOYMENT_TARGET = 26.0`.

`LiquidGlassModifier` currently calls `.glassEffect(...)`, so compatibility depends on the SDK expected by the project.

## Camera Preview Is Blank Or Camera Controls Do Nothing

Likely causes:

- Camera access is denied.
- Simulator camera behavior is limited.
- `CameraCommands` lost its controller reference.
- AVFoundation session setup failed for the selected device.

What to check:

- `PhotoCaptureView` permission handling.
- `CameraPreview.makeUIViewController(...)` and `updateUIViewController(...)`.
- `CameraViewController.viewDidLoad()`.
- `CameraService.configure(position:)`.
- Real-device behavior if the simulator cannot provide the needed camera behavior.

## Camera Does Not Pause Or Resume Correctly

The app lifecycle bridge starts in `SolarisApp.swift`, which posts `.pauseCameraSession` and `.resumeCameraSession` notifications. `CameraViewController` observes those notifications and calls `CameraService.pause()` or `CameraService.resume()`.

What to check:

- `Notification+Camera.swift` notification names.
- Observer registration and cleanup in `CameraViewController`.
- `scenePhase` handling in `SolarisApp`.

## Imported Photos Do Not Appear

Likely failure points:

- `PhotosPickerItem.loadTransferable(type: Data.self)` fails.
- Thumbnail generation fails.
- The manifest is not saved after import.
- The loaded thumbnail file is empty or unreadable.

What to check:

- `HomeView.processImport(items:)`.
- `detectImageRawInfo(data:)`.
- `detectImageExtension(data:)`.
- `loadUIImageThumbnail(from:maxPixel:)`.
- `PhotoLibrary.saveManifest(...)`.
- `Documents/PhotoStorage/thumbs`.

## Photos Disappear After Restart

Likely causes:

- `manifest.json` is missing or corrupt.
- The app container path changed and path normalization failed.
- Original files are missing.
- Records were dropped because `PhotoLibrary` could not find the original file.

What to check:

- `PhotoLibrary.loadManifest()`.
- `PhotoLibrary.manifestBackupURL()`.
- Path normalization in `_loadManifest()`.
- Existence of files in `Documents/PhotoStorage/originals`.

`PhotoLibrary` intentionally drops records whose original file no longer exists.

## Edits Save But Thumbnails Look Stale

Likely causes:

- Previous thumbnail was not overwritten.
- `ImageCache` still holds an old thumbnail.
- The updated `PhotoRecord` was not written back into `records` and `photos`.

What to check:

- Editor save flow in `HomeView`.
- `writeUIImageWithSourceMetadata(...)`.
- `finalImage.resizeToFit(maxSize: 512)`.
- `ImageCache.shared.set(...)`.
- `PhotoLibrary.saveManifest(...)`.

## Metal Rendering Fails Or Preview Is Missing

Likely causes:

- Metal device/context creation failed.
- A custom Metal shader is unavailable.
- A filter stage returned nil.
- The image has an unsupported color profile, orientation, or bitmap shape.

What to check:

- `PreviewRenderer`.
- `FilterPipeline.standard(grainSeed:)`.
- `FilterStages.swift`.
- Custom filters: `DuotoneFilter`, `SkinToneFilter`, `VignetteFilter`, `LumaGrainFilter`.
- `Effects.metal`.
- `UIImage+FixOrientation.swift`.

`GrainStage` logs if `LumaGrainFilter` returns nil and then falls back to the input image.

## Metadata Export Looks Wrong

Likely causes:

- `AppSettings.shared.preserveMetadata` is disabled.
- The source image does not contain the expected metadata.
- Color space conversion selected a different target profile.
- HEIC export failed and JPEG fallback behavior was used.

What to check:

- `SettingsView`.
- `AppSettings.ExportColorSpacePreference`.
- `writeUIImageWithSourceMetadata(...)`.
- `convertUIImage(...)`.
- Source file metadata in the original image.

## Saved Filters Do Not Persist

Likely causes:

- The filter state was not considered non-default.
- The filter name was empty.
- UserDefaults data for `SavedFilters_v1` was not written or decoded.

What to check:

- `SavedFiltersStore.addFilter(name:state:)`.
- `SavedFiltersStore.restore()`.
- `PhotoEditorView` save-filter alert.
- `FilterStateManager.hasAnyFilterApplied(...)`.
