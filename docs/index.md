# Solaris Documentation

Solaris is a medium-sized single native iOS app for local photo capture, organization, editing, and export. The documentation in this folder is intentionally focused on what exists in the current Swift/Xcode codebase.

## Guides

- [Architecture](architecture.md) - app modules, SwiftUI/UIKit boundaries, data flow, persistence, and rendering pipeline.
- [Development](development.md) - project-specific development workflow and extension rules.
- [Security And Privacy](security.md) - permissions, local data, metadata, privacy manifest, and known privacy limits.
- [Troubleshooting](troubleshooting.md) - likely Xcode, package, camera, storage, and Metal rendering issues.
- [Deployment](deployment.md) - current release inputs and missing deployment automation.

## Intentionally Absent

- No API documentation exists because Solaris has no backend routes, RPC layer, SDK surface, or network API.
- No database documentation exists because Solaris uses app-container files and UserDefaults rather than a database.
- No separate setup guide exists because setup is simple enough to keep in the root README.
