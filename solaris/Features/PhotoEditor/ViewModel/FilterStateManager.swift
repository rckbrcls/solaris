import SwiftUI

/// Stateless helper for filter state logic: combining base + edit states,
/// comparing states, and managing filter application types.
enum FilterStateManager {

    /// Merges baseFilterState and editState into a combined rendering state.
    static func combinedState(base: PhotoEditState, edit: PhotoEditState) -> PhotoEditState {
        var combined = base

        // Multiplicative (always applied)
        combined.contrast = base.contrast * edit.contrast
        combined.saturation = base.saturation * edit.saturation

        // Additive (always applied)
        combined.brightness = base.brightness + edit.brightness
        combined.exposure = base.exposure + edit.exposure
        combined.vibrance = base.vibrance + edit.vibrance
        combined.fade = base.fade + edit.fade
        combined.vignette = base.vignette + edit.vignette
        combined.grain = base.grain + edit.grain
        combined.sharpen = base.sharpen + edit.sharpen
        combined.clarity = base.clarity + edit.clarity
        combined.pixelateAmount = base.pixelateAmount + edit.pixelateAmount
        combined.skinTone = base.skinTone + edit.skinTone

        // Special effects: prefer editState if non-default, otherwise base
        combined.colorInvert = edit.colorInvert != 0.0 ? edit.colorInvert : base.colorInvert
        combined.opacity = edit.opacity != 1.0 ? edit.opacity : base.opacity

        // Color tint: editState overrides if it has custom values
        let defaultTint = SIMD4<Float>(0, 0, 0, 0)
        if edit.colorTint != defaultTint || edit.isDualToneActive {
            combined.colorTint = edit.colorTint
            combined.colorTintSecondary = edit.colorTintSecondary
            combined.isDualToneActive = edit.isDualToneActive
            combined.colorTintIntensity = edit.colorTintIntensity
            combined.colorTintFactor = edit.colorTintFactor
        }

        return combined
    }

    // MARK: - Filter Application Type

    enum FilterApplicationType {
        case base
        case sliders
        case none
    }

    static func getFilterApplicationType(editState: PhotoEditState, baseFilterState: PhotoEditState, filterState: PhotoEditState) -> FilterApplicationType {
        if isStatesSimilar(baseFilterState, filterState) { return .base }
        if isStatesSimilar(editState, filterState) { return .sliders }
        return .none
    }

    static func isFilterApplied(editState: PhotoEditState, baseFilterState: PhotoEditState, filterState: PhotoEditState) -> Bool {
        getFilterApplicationType(editState: editState, baseFilterState: baseFilterState, filterState: filterState) != .none
    }

    static func isFilterAppliedToSliders(editState: PhotoEditState, filterState: PhotoEditState) -> Bool {
        isStatesSimilar(editState, filterState)
    }

    static func isFilterAppliedAsBase(baseFilterState: PhotoEditState, filterState: PhotoEditState) -> Bool {
        isStatesSimilar(baseFilterState, filterState)
    }

    static func hasFilterCombination(editState: PhotoEditState, baseFilterState: PhotoEditState) -> Bool {
        let defaultState = PhotoEditState()
        return !isStatesSimilar(editState, defaultState) && !isStatesSimilar(baseFilterState, defaultState)
    }

    static func getSliderFilter(editState: PhotoEditState) -> PhotoEditState? {
        let defaultState = PhotoEditState()
        return isStatesSimilar(editState, defaultState) ? nil : editState
    }

    static func getBaseFilter(baseFilterState: PhotoEditState) -> PhotoEditState? {
        let defaultState = PhotoEditState()
        return isStatesSimilar(baseFilterState, defaultState) ? nil : baseFilterState
    }

    static func getCurrentAppliedFilter(editState: PhotoEditState, baseFilterState: PhotoEditState) -> PhotoEditState? {
        let defaultState = PhotoEditState()
        if !isStatesSimilar(baseFilterState, defaultState) { return baseFilterState }
        if !isStatesSimilar(editState, defaultState) { return editState }
        return nil
    }

    static func hasAnyFilterApplied(editState: PhotoEditState, baseFilterState: PhotoEditState) -> Bool {
        let defaultState = PhotoEditState()
        return !isStatesSimilar(baseFilterState, defaultState) || !isStatesSimilar(editState, defaultState)
    }

    // MARK: - Comparison Primitives

    static func floatsMatch(_ a: Float, _ b: Float, tolerance: Float = 0.001) -> Bool {
        abs(a - b) < tolerance
    }

    static func colorsMatch(_ c1: SIMD4<Float>, _ c2: SIMD4<Float>, tolerance: Float = 0.001) -> Bool {
        floatsMatch(c1.x, c2.x, tolerance: tolerance) &&
        floatsMatch(c1.y, c2.y, tolerance: tolerance) &&
        floatsMatch(c1.z, c2.z, tolerance: tolerance) &&
        floatsMatch(c1.w, c2.w, tolerance: tolerance)
    }

    // MARK: - State Comparison

    static func isStatesSimilar(_ state1: PhotoEditState, _ state2: PhotoEditState) -> Bool {
        floatsMatch(state1.contrast, state2.contrast) &&
        floatsMatch(state1.brightness, state2.brightness) &&
        floatsMatch(state1.exposure, state2.exposure) &&
        floatsMatch(state1.saturation, state2.saturation) &&
        floatsMatch(state1.vibrance, state2.vibrance) &&
        floatsMatch(state1.opacity, state2.opacity) &&
        floatsMatch(state1.fade, state2.fade) &&
        floatsMatch(state1.vignette, state2.vignette) &&
        floatsMatch(state1.colorInvert, state2.colorInvert) &&
        floatsMatch(state1.pixelateAmount, state2.pixelateAmount) &&
        floatsMatch(state1.sharpen, state2.sharpen) &&
        floatsMatch(state1.clarity, state2.clarity) &&
        floatsMatch(state1.grain, state2.grain) &&
        floatsMatch(state1.grainSize, state2.grainSize) &&
        colorsMatch(state1.colorTint, state2.colorTint) &&
        colorsMatch(state1.colorTintSecondary, state2.colorTintSecondary) &&
        floatsMatch(state1.colorTintIntensity, state2.colorTintIntensity) &&
        floatsMatch(state1.colorTintFactor, state2.colorTintFactor) &&
        state1.isDualToneActive == state2.isDualToneActive &&
        floatsMatch(state1.skinTone, state2.skinTone)
    }
}
