import SwiftUI
import UIKit
import MetalPetal
import os.log

struct PhotoEditState: Codable, Equatable {
    var contrast: Float = 1.0
    var brightness: Float = 0.0
    var exposure: Float = 0.0
    var saturation: Float = 1.0
    var vibrance: Float = 0.0
    var opacity: Float = 1.0
    var fade: Float = 0.0
    var vignette: Float = 0.0
    var colorInvert: Float = 0.0
    var pixelateAmount: Float = 1.0
    var sharpen: Float = 0.0
    var clarity: Float = 0.0
    var grain: Float = 0.0
    var grainSize: Float = 0.0
    var colorTint: SIMD4<Float> = SIMD4<Float>(0, 0, 0, 0)
    var colorTintIntensity: Float = 1.0
    var colorTintFactor: Float = 0.30
    var colorTintSecondary: SIMD4<Float> = SIMD4<Float>(0, 0, 0, 0)
    var isDualToneActive: Bool = false
    var skinTone: Float = 0.0
}

struct CompleteEditState: Codable, Equatable {
    var editState: PhotoEditState
    var baseFilterState: PhotoEditState

    init(editState: PhotoEditState, baseFilterState: PhotoEditState) {
        self.editState = editState
        self.baseFilterState = baseFilterState
    }
}

// MARK: - PhotoEditorViewModel

@Observable
final class PhotoEditorViewModel {
    // MARK: - State (stored for @Observable tracking + SwiftUI bindings)
    var editState = PhotoEditState()
    var baseFilterState = PhotoEditState()
    var previewImage: UIImage?
    var lastUndoMessage: String? = nil
    var isInteracting: Bool = false
    var originalImage: UIImage?

    // MARK: - Sub-components
    let renderer: PreviewRenderer
    var history: EditHistory<CompleteEditState>

    // MARK: - Derived state
    var combinedState: PhotoEditState {
        FilterStateManager.combinedState(base: baseFilterState, edit: editState)
    }

    var canUndo: Bool { history.canUndo }
    var canRedo: Bool { history.canRedo }
    var undoStack: [CompleteEditState] { history.undoStack }

    // MARK: - Internal
    private var originalImageURL: URL?
    private var originalImageData: Data?
    var grainSeed: Float = 0.0
    private var inChangeTransaction: Bool = false
    private var filterChangePending: Bool = false
    private var interactionStartState: CompleteEditState? = nil
    private var previewTask: Task<Void, Never>?

    // MARK: - Init

    init(image: UIImage?, originalImageURL: URL? = nil, originalImageData: Data? = nil, grainSeed: Float = 0.0) {
        self.originalImage = image
        self.originalImageURL = originalImageURL
        self.originalImageData = originalImageData
        self.grainSeed = grainSeed
        self.renderer = PreviewRenderer(grainSeed: grainSeed)
        self.history = EditHistory<CompleteEditState>(limit: AppSettings.shared.historyLimit)
        renderer.buildPreviewBases(from: image)
    }

    // MARK: - Preview Base

    var previewBase: UIImage? { renderer.previewBase }

    var previewThumbnailBase: UIImage? { renderer.previewThumbnailBase }

    func buildPreviewBases() {
        renderer.buildPreviewBases(from: originalImage)
    }

    func resetPreviewBases() {
        buildPreviewBases()
    }

    // MARK: - Preview Update

    /// Call this whenever editState or baseFilterState changes to regenerate the GPU preview.
    /// Cancels any in-flight render for responsive slider interaction.
    func requestPreviewUpdate() {
        previewTask?.cancel()
        let state = combinedState
        previewTask = Task { [weak self] in
            guard let self else { return }
            let image = self.renderer.generatePreview(state: state)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.previewImage = image
            }
        }
    }

    // MARK: - Interactive Adjustments

    func beginInteractiveAdjustments() {
        guard !isInteracting else { return }
        isInteracting = true
        renderer.switchToLowRes()
        interactionStartState = CompleteEditState(editState: editState, baseFilterState: baseFilterState)
        inChangeTransaction = true
    }

    func endInteractiveAdjustments() {
        isInteracting = false
        renderer.switchToHighRes()

        let currentState = CompleteEditState(editState: editState, baseFilterState: baseFilterState)
        if let startState = interactionStartState, startState != currentState {
            history.push(startState)
            history.clearRedo()
            filterChangePending = false
        }

        inChangeTransaction = false
        interactionStartState = nil
        requestPreviewUpdate()
    }

    // MARK: - Filter Application

    private func registerFilterUndoIfNeeded() {
        if !filterChangePending {
            let completeState = CompleteEditState(editState: editState, baseFilterState: baseFilterState)
            history.push(completeState)
            history.clearRedo()
            filterChangePending = true
        }
    }

    func applyBaseFilter(_ filterState: PhotoEditState) {
        let defaultState = PhotoEditState()
        if FilterStateManager.isStatesSimilar(baseFilterState, filterState) {
            registerFilterUndoIfNeeded()
            baseFilterState = defaultState
        } else {
            registerFilterUndoIfNeeded()
            baseFilterState = filterState
        }
        requestPreviewUpdate()
    }

    func applySliderFilter(_ filterState: PhotoEditState) {
        let defaultState = PhotoEditState()
        if FilterStateManager.isStatesSimilar(editState, filterState) {
            registerFilterUndoIfNeeded()
            editState = defaultState
        } else {
            registerFilterUndoIfNeeded()
            editState = filterState
        }
        requestPreviewUpdate()
    }

    func removeFilter(_ filterState: PhotoEditState) {
        let appType = FilterStateManager.getFilterApplicationType(
            editState: editState, baseFilterState: baseFilterState, filterState: filterState
        )
        switch appType {
        case .base: baseFilterState = PhotoEditState()
        case .sliders: editState = PhotoEditState()
        case .none: break
        }
        requestPreviewUpdate()
    }

    func clearBaseFilter() {
        baseFilterState = PhotoEditState()
        requestPreviewUpdate()
    }

    func clearSliderFilter() {
        editState = PhotoEditState()
        requestPreviewUpdate()
    }

    func clearAllFilters() {
        baseFilterState = PhotoEditState()
        editState = PhotoEditState()
        requestPreviewUpdate()
    }

    // MARK: - Filter Query (delegates to FilterStateManager)

    func isFilterApplied(_ filterState: PhotoEditState) -> Bool {
        FilterStateManager.isFilterApplied(editState: editState, baseFilterState: baseFilterState, filterState: filterState)
    }

    func isFilterAppliedToSliders(_ filterState: PhotoEditState) -> Bool {
        FilterStateManager.isFilterAppliedToSliders(editState: editState, filterState: filterState)
    }

    func isFilterAppliedAsBase(_ filterState: PhotoEditState) -> Bool {
        FilterStateManager.isFilterAppliedAsBase(baseFilterState: baseFilterState, filterState: filterState)
    }

    var hasFilterCombination: Bool {
        FilterStateManager.hasFilterCombination(editState: editState, baseFilterState: baseFilterState)
    }

    func getSliderFilter() -> PhotoEditState? {
        FilterStateManager.getSliderFilter(editState: editState)
    }

    func getBaseFilter() -> PhotoEditState? {
        FilterStateManager.getBaseFilter(baseFilterState: baseFilterState)
    }

    var hasAnyFilterApplied: Bool {
        FilterStateManager.hasAnyFilterApplied(editState: editState, baseFilterState: baseFilterState)
    }

    // MARK: - Undo / Redo

    func seedUndoBaselineIfNeeded(baseline: PhotoEditState = PhotoEditState()) {
        let baselineComplete = CompleteEditState(editState: baseline, baseFilterState: PhotoEditState())
        let currentComplete = CompleteEditState(editState: editState, baseFilterState: baseFilterState)
        if !history.canUndo && currentComplete != baselineComplete {
            history.push(baselineComplete)
            history.clearRedo()
        }
    }

    func beginChangeTransaction() {
        if !inChangeTransaction {
            let completeState = CompleteEditState(editState: editState, baseFilterState: baseFilterState)
            history.push(completeState)
            history.clearRedo()
            filterChangePending = false
            inChangeTransaction = true
        }
    }

    func endChangeTransaction() {
        inChangeTransaction = false
    }

    func registerUndoPoint() {
        let completeState = CompleteEditState(editState: editState, baseFilterState: baseFilterState)
        history.push(completeState)
        history.clearRedo()
    }

    func undoLastChange() {
        let current = CompleteEditState(editState: editState, baseFilterState: baseFilterState)
        guard let previous = history.undo(current: current) else { return }

        let editKeys = diffChangedKeys(from: current.editState, to: previous.editState)
        let baseKeys = diffChangedKeys(from: current.baseFilterState, to: previous.baseFilterState)

        editState = previous.editState
        baseFilterState = previous.baseFilterState
        filterChangePending = false

        lastUndoMessage = buildUndoMessage(fromEditKeys: editKeys, baseKeys: baseKeys)
        requestPreviewUpdate()
    }

    func redoLastChange() {
        let current = CompleteEditState(editState: editState, baseFilterState: baseFilterState)
        guard let next = history.redo(current: current) else { return }

        let editKeys = diffChangedKeys(from: current.editState, to: next.editState)
        let baseKeys = diffChangedKeys(from: current.baseFilterState, to: next.baseFilterState)

        editState = next.editState
        baseFilterState = next.baseFilterState
        filterChangePending = false

        lastUndoMessage = buildRestoreMessage(fromEditKeys: editKeys, baseKeys: baseKeys)
        requestPreviewUpdate()
    }

    func redoAllChanges() {
        guard history.canRedo else { return }
        var current = CompleteEditState(editState: editState, baseFilterState: baseFilterState)
        var latest = current
        while history.canRedo {
            if let next = history.redo(current: current) {
                current = next
                latest = next
            } else { break }
        }
        editState = latest.editState
        baseFilterState = latest.baseFilterState
        lastUndoMessage = "Restored: all adjustments"
        requestPreviewUpdate()
    }

    func resetAllEditsToClean() {
        let clean = PhotoEditState()
        let cleanComplete = CompleteEditState(editState: clean, baseFilterState: PhotoEditState())
        let currentComplete = CompleteEditState(editState: editState, baseFilterState: baseFilterState)

        if currentComplete != cleanComplete {
            history.resetWithRedo(currentComplete)
            editState = clean
            baseFilterState = PhotoEditState()
            filterChangePending = false
            lastUndoMessage = "Reverted: all adjustments"
            requestPreviewUpdate()
        } else {
            lastUndoMessage = nil
        }
    }

    func clearLastUndoMessage() { lastUndoMessage = nil }

    // MARK: - Persistent History

    func loadPersistentUndoHistory(_ historyStates: [PhotoEditState]) {
        var cleaned: [CompleteEditState] = []
        cleaned.reserveCapacity(historyStates.count)
        for s in historyStates {
            let completeState = CompleteEditState(editState: s, baseFilterState: PhotoEditState())
            if cleaned.last != completeState { cleaned.append(completeState) }
        }
        let currentComplete = CompleteEditState(editState: editState, baseFilterState: baseFilterState)
        while let last = cleaned.last, last == currentComplete { cleaned.removeLast() }
        let limit = AppSettings.shared.historyLimit
        history = EditHistory<CompleteEditState>(limit: limit)
        for state in Array(cleaned.suffix(limit)) {
            history.push(state)
        }
    }

    // MARK: - Final Image

    func generateFinalImage() -> UIImage? {
        renderer.generateFinalImage(
            originalURL: originalImageURL,
            originalData: originalImageData,
            originalImage: originalImage,
            state: combinedState
        )
    }

    // MARK: - Diff helpers

    func diffChangedKeys(from a: PhotoEditState, to b: PhotoEditState) -> [String] {
        var keys: [String] = []
        if !FilterStateManager.floatsMatch(a.contrast, b.contrast) { keys.append("contrast") }
        if !FilterStateManager.floatsMatch(a.brightness, b.brightness) { keys.append("brightness") }
        if !FilterStateManager.floatsMatch(a.exposure, b.exposure) { keys.append("exposure") }
        if !FilterStateManager.floatsMatch(a.saturation, b.saturation) { keys.append("saturation") }
        if !FilterStateManager.floatsMatch(a.vibrance, b.vibrance) { keys.append("vibrance") }
        if !FilterStateManager.floatsMatch(a.opacity, b.opacity) { keys.append("opacity") }
        if !FilterStateManager.floatsMatch(a.fade, b.fade) { keys.append("fade") }
        if !FilterStateManager.floatsMatch(a.vignette, b.vignette) { keys.append("vignette") }
        if !FilterStateManager.floatsMatch(a.colorInvert, b.colorInvert) { keys.append("colorInvert") }
        if !FilterStateManager.floatsMatch(a.pixelateAmount, b.pixelateAmount) { keys.append("pixelateAmount") }
        if !FilterStateManager.floatsMatch(a.sharpen, b.sharpen) { keys.append("sharpen") }
        if !FilterStateManager.floatsMatch(a.clarity, b.clarity) { keys.append("clarity") }
        if !FilterStateManager.floatsMatch(a.grain, b.grain) { keys.append("grain") }
        if !FilterStateManager.floatsMatch(a.grainSize, b.grainSize) { keys.append("grainSize") }
        if !FilterStateManager.colorsMatch(a.colorTint, b.colorTint) { keys.append("colorTint") }
        if !FilterStateManager.colorsMatch(a.colorTintSecondary, b.colorTintSecondary) { keys.append("colorTintSecondary") }
        if !FilterStateManager.floatsMatch(a.colorTintIntensity, b.colorTintIntensity) { keys.append("colorTintIntensity") }
        if !FilterStateManager.floatsMatch(a.colorTintFactor, b.colorTintFactor) { keys.append("colorTintFactor") }
        if a.isDualToneActive != b.isDualToneActive { keys.append("isDualToneActive") }
        if !FilterStateManager.floatsMatch(a.skinTone, b.skinTone) { keys.append("skinTone") }
        return keys
    }

    private static let parameterNames: [String: String] = [
        "contrast": "Contrast", "brightness": "Brightness", "exposure": "Exposure",
        "saturation": "Saturation", "vibrance": "Vibrance", "opacity": "Opacity",
        "fade": "Fade", "vignette": "Vignette", "colorInvert": "Invert",
        "pixelateAmount": "Pixelate", "sharpen": "Sharpness", "clarity": "Clarity",
        "grain": "Grain", "grainSize": "Grain Size", "colorTint": "Tint",
        "colorTintSecondary": "Secondary Tint", "colorTintIntensity": "Tint Intensity",
        "colorTintFactor": "Tint Strength", "isDualToneActive": "Dual Tone",
        "skinTone": "Skin Tone"
    ]

    private func buildUndoMessage(fromEditKeys editKeys: [String], baseKeys: [String]) -> String? {
        if !baseKeys.isEmpty { return "Undone: Filter" }
        if editKeys.isEmpty { return nil }
        return formatMessage(prefix: "Undone", keys: editKeys)
    }

    private func buildRestoreMessage(fromEditKeys editKeys: [String], baseKeys: [String]) -> String? {
        if !baseKeys.isEmpty { return "Restored: Filter" }
        if editKeys.isEmpty { return nil }
        return formatMessage(prefix: "Restored", keys: editKeys)
    }

    private func formatMessage(prefix: String, keys: [String]) -> String {
        let names = Self.parameterNames
        if keys.count == 1 {
            return "\(prefix): \(names[keys[0]] ?? keys[0])"
        }
        let firstTwo = keys.prefix(2).compactMap { names[$0] ?? $0 }.joined(separator: ", ")
        let rest = keys.count - 2
        return rest > 0 ? "\(prefix): \(firstTwo) +\(rest)" : "\(prefix): \(firstTwo)"
    }
}
