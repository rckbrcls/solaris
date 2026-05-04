# Contributing To Solaris

Solaris is a native iOS photo editor built with Swift, SwiftUI, UIKit, AVFoundation, PhotosUI, ImageIO, MetalPetal, and custom Metal shaders. Contributions should preserve the app's local-first photo workflow and native iOS architecture.

## Before You Start

- Open `solaris.xcworkspace` in Xcode.
- Let Xcode resolve Swift Package Manager dependencies.
- Read `README.md`, `docs/architecture.md`, and `docs/development.md`.
- Keep visible source strings in English.
- Do not introduce backend, analytics, cloud sync, authentication, or remote storage without updating architecture, security, deployment, and privacy documentation.

## Project-Specific Quality Bar

Good Solaris changes are:

- Native iOS changes, not web or cross-platform abstractions.
- Local-first unless a product decision explicitly changes the privacy model.
- Consistent with the feature folders under `solaris/Features`.
- Careful with image memory, thumbnail sizes, Metal rendering, and full-quality export.
- Careful with metadata preservation and photo permissions.
- Covered by tests when the changed behavior is pure logic or persistence-related.

## Development Guidelines

- Keep camera session logic in `CameraService`.
- Keep UIKit camera gestures and overlays in `CameraViewController`.
- Keep SwiftUI camera controls in `PhotoCaptureView`.
- Keep editor state transitions in `PhotoEditorViewModel`.
- Keep filter-composition semantics in `FilterStateManager`.
- Keep storage contract changes centered on `PhotoLibrary`.
- Keep app settings in `AppSettings` and saved user filters in `SavedFiltersStore`.
- Add source strings through `String(localized:)` and update `Localizable.xcstrings`.

## Tests

The current tests are mostly template-level. When adding meaningful behavior, prefer tests around:

- Filter state combination and comparison.
- Undo/redo history behavior.
- Settings persistence shape.
- Saved filter add/delete behavior.
- Manifest loading, path normalization, backup fallback, and cleanup.

Camera, PhotosUI, and Metal behavior can be difficult to test deterministically. Isolate pure logic so it can be covered without device hardware or image fixtures.

## Pull Request Checklist

Before opening a pull request:

- Confirm the change fits the current local-first iOS scope.
- Confirm new UI strings are English source strings and are localizable.
- Confirm documentation is updated when behavior, architecture, privacy, storage, or release assumptions change.
- Confirm no credentials, generated build products, DerivedData, or local Xcode user state are committed.
- Confirm test limitations are described honestly if tests were not added or could not be run.

## Documentation Expectations

Do not add generic docs. Add or update documentation only when it explains a real Solaris behavior:

- Use `README.md` for project overview and setup.
- Use `docs/architecture.md` for technical structure and data flow.
- Use `docs/development.md` for implementation workflow.
- Use `docs/security.md` for privacy, permissions, metadata, and sensitive data.
- Use `docs/deployment.md` for release/distribution details.
- Use `docs/troubleshooting.md` for real failure modes.

Do not create API, database, Docker, backend, or CI docs unless those systems are actually added to the codebase.
