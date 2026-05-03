# Architecture

## Overview

Solaris is a native iOS photo editor built with SwiftUI, local file storage, camera/photo flows, image services, and GPU-aware editing paths.

## Components

- `solaris/SolarisApp.swift`: app entry point.
- `solaris/Features/`: Home, Camera, PhotoEditor, and Settings modules.
- `solaris/Shared/Services/`: image loading, saving, metadata, and export helpers.
- `solaris/Shared/State/`: app settings and saved filter state.
- `solaris/Shared/Components/`: reusable UI and editing components.
- `solaris/Shared/Theme/`: visual tokens and liquid glass helpers.

## Data Flow

1. Photos are imported or captured locally.
2. Services persist originals, thumbnails, metadata, and edited outputs.
3. Editor views apply filter and adjustment state.
4. Export services produce saved images with the configured metadata behavior.

## Security and Privacy

The README describes Solaris as local and privacy-first. Avoid adding cloud storage or remote processing without explicitly updating the privacy model.

## Trade-offs

- Local storage improves privacy but makes backup/export behavior important.
- GPU-aware processing supports richer edits but can require careful memory management.
