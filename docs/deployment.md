# Deployment

Solaris is a native iOS app. Deployment means signing, archiving, validating, and distributing the app through Apple tooling.

No automated deployment pipeline was identified in the current codebase.

## Current Release Inputs

Detected project values:

| Field | Current value |
| --- | --- |
| App target | `solaris` |
| Bundle identifier | `polterware.solaris` |
| Display name | `Solaris` |
| App category | `public.app-category.photography` |
| Marketing version | `1.0` |
| Current project version | `1` |
| Deployment target | iOS 26.0 |
| Code signing style | Automatic |
| Development team | `VCF3DS6BTV` |

The generated Info.plist settings include camera and photo-library usage descriptions:

- `NSCameraUsageDescription`
- `NSPhotoLibraryUsageDescription`
- `NSPhotoLibraryAddUsageDescription`

The project also includes `solaris/PrivacyInfo.xcprivacy`.

## Manual Release Path

Use Xcode for release work:

1. Confirm the `solaris` scheme and Release configuration.
2. Confirm signing team, bundle identifier, and provisioning state.
3. Confirm app version and build number.
4. Confirm the privacy manifest and App Store privacy disclosures match current behavior.
5. Confirm camera/photo permission strings are accurate.
6. Archive the app from Xcode.
7. Validate and distribute through Apple's Organizer workflow.

This documentation pass did not run archive, build, validation, or upload commands.

## Missing Automation

The following were not identified in the current codebase:

- GitHub Actions or other CI workflows.
- fastlane configuration.
- ExportOptions plist.
- TestFlight automation.
- App Store Connect API integration.
- Release scripts.
- Rollback workflow.
- Crash reporting or production monitoring SDK.

TODO: not identified in the current codebase - final App Store release process, final signing ownership, TestFlight procedure, production monitoring, and rollback policy.

## Pre-Release Checklist

Before shipping a build, verify the following manually:

- App launches on a real iOS device.
- Camera permission flow works.
- Photo import permission flow works.
- Captured and imported photos persist after app restart.
- Edited files, thumbnails, and manifest updates persist.
- Metadata preservation behavior matches the user-facing setting.
- Saved filters persist through app restart.
- Export/share flow returns the expected edited image.
- Privacy manifest and App Store privacy questionnaire remain aligned.

## Security And Privacy Release Notes

Solaris currently has no backend, user account, authentication, analytics SDK, or remote storage. A future release that adds any remote service must update:

- `README.md`
- `docs/architecture.md`
- `docs/security.md`
- App Store privacy disclosures
- `solaris/PrivacyInfo.xcprivacy`
