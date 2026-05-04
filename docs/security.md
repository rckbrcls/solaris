# Security And Privacy

Solaris handles user photos, camera access, photo-library access, and optional metadata preservation. Even without a backend, these are sensitive privacy surfaces.

## Current Privacy Model

The current codebase is local-first:

- No backend server was found.
- No network API client was found.
- No analytics, telemetry, crash-reporting, advertising, or tracking SDK was found.
- No authentication, authorization, session token, keychain, or account model was found.
- No cloud database or remote storage integration was found.

Photos and edits remain inside the app container unless the user exports or shares them through iOS system UI.

## Permissions

The Xcode project generates Info.plist usage descriptions for:

- Camera access: Solaris uses the camera to capture photos for editing.
- Photo library read access: Solaris imports photos for editing.
- Photo library add access: Solaris saves edited photos to the user's Photo Library.

Camera authorization is handled in `PhotoCaptureView` through `AVCaptureDevice.authorizationStatus(for: .video)` and `AVCaptureDevice.requestAccess(for: .video)`.

Photo import uses `PhotosPicker`, which delegates selection and access behavior to the system picker.

## Local Data Storage

Photo files are stored under the app container:

```text
Documents/PhotoStorage/
├── originals/
├── thumbs/
├── edits/
├── manifest.json
└── manifest.json.bak
```

`PhotoLibrary.ensureDirs()` marks the storage root as excluded from iCloud backup to avoid consuming the user's iCloud quota.

The manifest stores local file URLs and edit state. It is not encrypted by Solaris. The files rely on iOS app sandboxing and device-level protections.

## Metadata Handling

Solaris can preserve source metadata when writing edited output. This behavior is controlled by `AppSettings.shared.preserveMetadata`.

Important implication: if preserved metadata includes GPS or device details, exported/shared images may carry that information. Any future UI or release notes should be clear about this behavior.

Relevant code:

- `SettingsView` exposes the `Preserve metadata (EXIF/GPS)` toggle.
- `ImageIOService.writeUIImageWithSourceMetadata(...)` copies source properties when preservation is enabled.
- `AppSettings.ExportColorSpacePreference` controls export color space behavior.

## Privacy Manifest

`solaris/PrivacyInfo.xcprivacy` currently declares:

- `NSPrivacyTracking` as false.
- No tracking domains.
- No collected data types.
- Accessed API categories for file timestamps and UserDefaults.

If future work adds networking, analytics, crash reporting, account features, cloud sync, or additional required-reason APIs, the privacy manifest and App Store privacy answers must be updated.

## Secrets

No secrets, API keys, service tokens, or environment-variable based credentials were identified.

Do not add credentials to the repository. If future services require secrets, use platform-appropriate secret storage and update this document.

## Input And File Safety

Solaris imports user-selected image data and camera-captured data. Main safety boundaries:

- Use `ImageIO` and `UTType` detection rather than trusting filename extensions.
- Keep thumbnail generation bounded by max pixel sizes.
- Preserve manifest backup and path normalization behavior.
- Delete old edited files when replacing edits to avoid orphan buildup.
- Keep orphan cleanup conservative and manifest-based.

## Known Risks

- Local photo files and manifests are not encrypted by app-level code.
- Metadata preservation can re-export sensitive EXIF/GPS metadata.
- Template-level tests do not currently protect storage, metadata, or rendering behavior.
- No production crash reporting or monitoring setup was found.

TODO: not identified in the current codebase - a final user-facing privacy policy, App Store privacy questionnaire answers, and production monitoring policy.
