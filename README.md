# Solaris

> **Status:** Active
> This project is currently maintained as a native iOS photo editor.

Native iOS photo editor focused on local photo capture, private storage, GPU filters, presets, metadata-aware export, and a polished SwiftUI editing workflow.

## Summary

- [What it is](#what-it-is)
- [Goals](#goals)
- [Product areas](#product-areas)
- [Project map](#project-map)
- [Current state](#current-state)
- [Working notes](#working-notes)

## What it is

Solaris is an iOS app for capturing, organizing, and editing photos locally. It uses SwiftUI for the app shell, UIKit/AVFoundation for camera capture, file-based persistence for photos, and GPU-accelerated image processing for filters.

## Goals

- Provide a privacy-first photo editor with local storage.
- Keep original images, thumbnails, edits, and manifest data under app-owned files.
- Support a fast editing experience with preview and high-resolution output paths.
- Offer presets, sliders, saved filters, undo/redo, and metadata-aware export.
- Feel native to modern iOS rather than like a web wrapper.

## Product areas

- Home photo grid and import flow.
- Camera capture with foreground/background session handling.
- Photo editor with filters, presets, slider adjustments, and undo/redo.
- Settings for color scheme, RAW behavior, metadata preservation, and camera options.
- Shared image services for loading, saving, thumbnails, HEIC export, and metadata.

## Project map

```text
solaris/
├── solaris/
│   ├── Features/ # Home, Camera, PhotoEditor, and Settings modules
│   ├── Shared/   # Components, services, app state, and theme helpers
│   └── SolarisApp.swift
├── solaris.xcodeproj
├── solaris.xcworkspace
├── solarisTests/
├── solarisUITests/
└── CLAUDE.md
```

## Current state

The codebase is a real iOS app. `CLAUDE.md` contains the most detailed architecture notes, including storage layout, Metal/MetalPetal processing, and navigation flow.

## Working notes

- Do not run build or test commands from agent sessions in this workspace.
- Keep photo data local unless product direction changes explicitly.
- Treat `PhotoLibrary`, `AppSettings`, and `ImageCache` singletons as existing architecture, not accidental globals.
