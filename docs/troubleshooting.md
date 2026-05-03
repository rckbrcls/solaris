# Troubleshooting

## Photos do not load or save

Start with `ImageIOService`, `PhotoSaveService`, and local storage helpers before changing editor views.

## Edits are slow or memory-heavy

Review image size, cache behavior, and the GPU/filter path described in `CLAUDE.md`.

## Metadata export looks wrong

Check the image export services and app settings that control metadata preservation.

## UI state does not persist

Review `AppSettings`, `SavedFiltersStore`, and related UserDefaults-backed state.
