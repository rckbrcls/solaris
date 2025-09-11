//
//  PhotoEditorViewModel.swift
//  souvenir
//
//  Created by Erick Barcelos on 30/05/25.
//

import SwiftUI
import Combine
import UIKit
import CoreImage
import MetalPetal
import os.log
import CoreGraphics
import CoreImage.CIFilterBuiltins

struct PhotoEditState: Codable, Equatable {
    var contrast: Float = 1.0
    var brightness: Float = 0.0 // valor padrão neutro
    var exposure: Float = 0.0 // valor padrão neutro
    var saturation: Float = 1.0 // valor padrão neutro
    var vibrance: Float = 0.0 // valor padrão neutro (sem vibrance)
    var opacity: Float = 1.0 // valor padrão neutro (totalmente opaco)
    // Fade (elevação dos pretos / redução de contraste linear; 0.0 neutro)
    var fade: Float = 0.0
    // Vignette (escurece bordas; 0.0 neutro)
    var vignette: Float = 0.0
    var colorInvert: Float = 0.0 // valor padrão neutro (sem inversão)
    var pixelateAmount: Float = 1.0 // valor padrão neutro (sem pixelate)
    // Sharpen (0.0 neutral)
    var sharpen: Float = 0.0
    // Clarity (local contrast; 0.0 neutral)
    var clarity: Float = 0.0
    // Film grain (0.0 - 0.1 recomendado)
    var grain: Float = 0.0
    // Film grain size (0.0 fine → 1.0 coarse)
    var grainSize: Float = 0.0
    // Color tint (RGBA, valores de 0 a 1)
    var colorTint: SIMD4<Float> = SIMD4<Float>(0,0,0,0) // padrão: sem cor
    var colorTintIntensity: Float = 1.0 // valor médio para que o slider fique no meio
    var colorTintFactor: Float = 0.30 // força do viés de cor (ColorMatrix) - default 30%
    // Dual tone support
    var colorTintSecondary: SIMD4<Float> = SIMD4<Float>(0,0,0,0) // segunda cor para dual tone
    var isDualToneActive: Bool = false // indica se o dual tone está ativo
    // Skin tone (ajuste seletivo de calor/frieza em tons de pele) -1.0 (mais frio) .. 1.0 (mais quente)
    var skinTone: Float = 0.0
    // Duotone removido
    // Adicione outros parâmetros depois
}

// Estrutura para salvar estado completo no undo (edit + base filter)
struct CompleteEditState: Codable, Equatable {
    var editState: PhotoEditState
    var baseFilterState: PhotoEditState
    
    init(editState: PhotoEditState, baseFilterState: PhotoEditState) {
        self.editState = editState
        self.baseFilterState = baseFilterState
    }
}

class PhotoEditorViewModel: ObservableObject {
    @Published var previewImage: UIImage?
    @Published var editState = PhotoEditState()
    @Published var lastUndoMessage: String? = nil
    // Simple undo stack of complete edit states (edit + base filter per user transaction)
    private(set) var undoStack: [CompleteEditState] = []
    private(set) var redoStack: [CompleteEditState] = []
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    private var inChangeTransaction: Bool = false
    private var filterChangePending: Bool = false // Flag para rastrear se mudanças de filtro precisam ser salvas no undo
    private var interactionStartState: CompleteEditState? = nil // Estado no início da interação (para verificar se houve mudanças)
    private var cancellables = Set<AnyCancellable>()
    private var mtiContext: MTIContext? = try? MTIContext(device: MTLCreateSystemDefaultDevice()!)
    private static let ciContext = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
    // CI kernel para gerar ruído per-pixel (3 oitavas) evitando padrões de reamostragem
    private static let ciGrainKernel: CIColorKernel? = {
        let src = """
        kernel vec4 grainNoise(__sample s, float seed) {
            vec2 p = destCoord();
            // Hash-based white noise, 3 octaves para evitar padrões perceptíveis
            float n1 = fract(sin(dot(p + vec2(seed*19.19, seed*27.13), vec2(12.9898,78.233))) * 43758.5453);
            float n2 = fract(sin(dot(p*1.97 + vec2(seed*3.31, seed*1.73), vec2(39.3467,11.1351))) * 37534.5453);
            float n3 = fract(sin(dot(p*2.53 + vec2(seed*7.07, seed*5.41), vec2(73.1562,91.3458))) * 31514.8723);
            float n = (n1*0.62 + n2*0.28 + n3*0.10);
            return vec4(n, n, n, 1.0);
        }
        """
        return CIColorKernel(source: src)
    }()

    // Gera um CIImage de ruído no tamanho alvo, com controle de tamanho via blur gaussiano
    private func makeNoiseCIImage(extent: CGRect, grainSize: Float, seed: Float = 0.0) -> CIImage? {
        guard let kernel = Self.ciGrainKernel else { return nil }
        let dummy = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 1)).cropped(to: extent)
        guard var noise = kernel.apply(extent: extent, arguments: [dummy, seed]) else { return nil }
        // Ajuste de tamanho do grão via blur (evita artefatos de linhas de reamostragem)
        let r = CGFloat(max(0.0, min(1.0, grainSize))) * 6.0
        if r > 0.0 {
            let blur = CIFilter.gaussianBlur()
            blur.inputImage = noise
            blur.radius = Float(r)
            noise = (blur.outputImage ?? noise).cropped(to: extent)
        }
        return noise
    }
    public var previewBase: UIImage?
    private var previewBaseHigh: UIImage?
    private var previewBaseLow: UIImage?
    @Published var isInteracting: Bool = false
    
    // Para filtros aplicados com tap simples (persistem mas não mostram nos sliders)
    @Published var baseFilterState = PhotoEditState() {
        didSet {
            print("[BaseFilter] baseFilterState changed!")
            print("[BaseFilter] New saturation: \(baseFilterState.saturation)")
            print("[BaseFilter] New colorTint: \(baseFilterState.colorTint)")
            print("[BaseFilter] New isDualToneActive: \(baseFilterState.isDualToneActive)")
        }
    }
    
    // Estado combinado para renderização (filtro + ajustes do usuário)
    var combinedState: PhotoEditState {
        var combined = baseFilterState
        
        print("[CombinedState] Starting combination:")
        print("[CombinedState] Base saturation: \(baseFilterState.saturation)")
        print("[CombinedState] Edit saturation: \(editState.saturation)")
        print("[CombinedState] Base colorTint: \(baseFilterState.colorTint)")
        print("[CombinedState] Edit colorTint: \(editState.colorTint)")
        print("[CombinedState] Base colorInvert: \(baseFilterState.colorInvert)")
        print("[CombinedState] Edit colorInvert: \(editState.colorInvert)")
        
        // SEMPRE aplica os ajustes do editState sobre o filtro base
        // Não verifica valores padrão, simplesmente combina
        
        // Multiplicativos (sempre aplicados)
        combined.contrast = baseFilterState.contrast * editState.contrast
        combined.saturation = baseFilterState.saturation * editState.saturation
        
        // Aditivos (sempre aplicados)
        combined.brightness = baseFilterState.brightness + editState.brightness
        combined.exposure = baseFilterState.exposure + editState.exposure
        combined.vibrance = baseFilterState.vibrance + editState.vibrance
        combined.fade = baseFilterState.fade + editState.fade
        combined.vignette = baseFilterState.vignette + editState.vignette
        combined.grain = baseFilterState.grain + editState.grain
        combined.sharpen = baseFilterState.sharpen + editState.sharpen
        combined.clarity = baseFilterState.clarity + editState.clarity
        combined.pixelateAmount = baseFilterState.pixelateAmount + editState.pixelateAmount
        combined.skinTone = baseFilterState.skinTone + editState.skinTone
        
        // Efeitos especiais: usa o valor do editState se diferente do padrão, senão usa do base
        combined.colorInvert = editState.colorInvert != 0.0 ? editState.colorInvert : baseFilterState.colorInvert
        combined.opacity = editState.opacity != 1.0 ? editState.opacity : baseFilterState.opacity
        
        // Efeitos de cor: se editState tem valores diferentes de padrão, usa eles
        // Senão usa do filtro base
        let defaultTint = SIMD4<Float>(0, 0, 0, 0)
        if editState.colorTint != defaultTint || editState.isDualToneActive {
            combined.colorTint = editState.colorTint
            combined.colorTintSecondary = editState.colorTintSecondary
            combined.isDualToneActive = editState.isDualToneActive
            combined.colorTintIntensity = editState.colorTintIntensity
            combined.colorTintFactor = editState.colorTintFactor
        }
        // Se editState não tem cor personalizada, usa do filtro base (já está copiado)
        
        print("[CombinedState] Final saturation: \(combined.saturation)")
        print("[CombinedState] Final colorTint: \(combined.colorTint)")
        print("[CombinedState] Final isDualToneActive: \(combined.isDualToneActive)")
        print("[CombinedState] Final colorInvert: \(combined.colorInvert)")
        
        return combined
    }

    // Adiciona referência à imagem original em alta qualidade
    public var originalImage: UIImage?
    private var originalImageURL: URL?
    private var originalImageData: Data?

    init(image: UIImage?, originalImageURL: URL? = nil, originalImageData: Data? = nil) {
        self.originalImage = image // Em memória: preview base
        self.originalImageURL = originalImageURL
        self.originalImageData = originalImageData
        
        buildPreviewBases()
        if let base = self.previewBase {
            print("[PhotoEditorViewModel] previewBase size: \(base.size), scale: \(base.scale)")
            if let cg = base.cgImage {
                print("[PhotoEditorViewModel] previewBase alphaInfo: \(cg.alphaInfo), bitsPerPixel: \(cg.bitsPerPixel)")
            }
        } else {
            print("[PhotoEditorViewModel] previewBase is nil after resizeToFit")
        }
        // Listener unificado que monitora mudanças em qualquer dos dois states
        Publishers.CombineLatest($editState, $baseFilterState)
            .removeDuplicates { prev, curr in
                prev.0 == curr.0 && prev.1 == curr.1
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (editState, baseState) in
                guard let self = self else { return }
                print("[Listener] States changed - edit saturation: \(editState.saturation), base saturation: \(baseState.saturation)")
                let combined = self.combinedState
                print("[Listener] Combined saturation: \(combined.saturation)")
                self.generatePreview(state: combined)
            }
            .store(in: &cancellables)
    }

    func buildPreviewBases() {
        // High-quality preview for crisp zoom (e.g., up to 3x)
        let highPoints = PhotoEditorHelper.suggestedPreviewMaxPoints(doubleTapZoomScale: 3.0)
        // Low-quality preview for responsive sliding (lighter to render)
        let lowPoints = PhotoEditorHelper.suggestedPreviewMaxPoints(doubleTapZoomScale: 2.0)
        self.previewBaseHigh = originalImage?.resizeToFit(maxSize: highPoints)
        self.previewBaseLow = originalImage?.resizeToFit(maxSize: lowPoints)
        // Start with high by default
        self.previewBase = self.previewBaseHigh
        if let base = self.previewBase {
            print("[PhotoEditorViewModel] previewBase size: \(base.size), scale: \(base.scale)")
            if let cg = base.cgImage {
                print("[PhotoEditorViewModel] previewBase alphaInfo: \(cg.alphaInfo), bitsPerPixel: \(cg.bitsPerPixel)")
            }
        } else {
            print("[PhotoEditorViewModel] previewBase is nil after resizeToFit")
        }
    }

    func beginInteractiveAdjustments() {
        guard !isInteracting else { return }
        isInteracting = true
        if let low = previewBaseLow { previewBase = low }
        
        // Salva o estado inicial da interação (sem adicionar ao undo ainda)
        interactionStartState = CompleteEditState(editState: editState, baseFilterState: baseFilterState)
        inChangeTransaction = true
    }

    func endInteractiveAdjustments() {
        isInteracting = false
        if let high = previewBaseHigh { previewBase = high }
        
        // Verifica se houve mudanças efetivas comparando com o estado inicial
        let currentState = CompleteEditState(editState: editState, baseFilterState: baseFilterState)
        if let startState = interactionStartState, startState != currentState {
            // Houve mudanças efetivas, registra o undo point
            undoStack.append(startState)
            redoStack.removeAll()
            // Reset da flag pois ajustes manuais consolidam mudanças de filtro
            filterChangePending = false
        }
        
        // Limpa estado da transação
        inChangeTransaction = false
        interactionStartState = nil
        
        // Regerar preview final em alta usando o estado combinado
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let combined = self.combinedState
            self.generatePreview(state: combined)
        }
    }
    
    // Função para registrar undo point apenas na primeira aplicação de filtro
    private func registerFilterUndoIfNeeded() {
        if !filterChangePending {
            // Primeira mudança de filtro desde o último undo/ajuste manual
            let completeState = CompleteEditState(editState: editState, baseFilterState: baseFilterState)
            undoStack.append(completeState)
            redoStack.removeAll()
            filterChangePending = true
        }
    }

    func resetPreviewBases() {
        buildPreviewBases()
    }

    // Exposed base image for thumbnails/previews (low-res preferred)
    public var previewThumbnailBase: UIImage? {
        return previewBaseLow ?? previewBase
    }

    // MARK: - Undo management
    func seedUndoBaselineIfNeeded(baseline: PhotoEditState = PhotoEditState()) {
        // Seed a single undo step to baseline on fresh sessions
        let baselineComplete = CompleteEditState(editState: baseline, baseFilterState: PhotoEditState())
        let currentComplete = CompleteEditState(editState: editState, baseFilterState: baseFilterState)
        if undoStack.isEmpty && currentComplete != baselineComplete {
            undoStack.append(baselineComplete)
            redoStack.removeAll()
        }
    }

    func beginChangeTransaction() {
        if !inChangeTransaction {
            // Salva o estado completo (editState + baseFilterState)
            let completeState = CompleteEditState(editState: editState, baseFilterState: baseFilterState)
            undoStack.append(completeState)
            // New transaction invalidates redo history
            redoStack.removeAll()
            // Reset da flag pois ajustes manuais consolidam mudanças de filtro
            filterChangePending = false
            inChangeTransaction = true
        }
    }

    func endChangeTransaction() {
        inChangeTransaction = false
    }

    func registerUndoPoint() {
        // for discrete changes (button taps, filter applications)
        let completeState = CompleteEditState(editState: editState, baseFilterState: baseFilterState)
        undoStack.append(completeState)
        // Any new change invalidates redo history
        redoStack.removeAll()
    }

    func undoLastChange() {
        guard let previous = undoStack.popLast() else { return }
        let current = CompleteEditState(editState: editState, baseFilterState: baseFilterState)
        // push current state to redo stack so we can restore later
        redoStack.append(current)
        
        // Restaura ambos os estados
        editState = previous.editState
        baseFilterState = previous.baseFilterState
        
        // Reset da flag para permitir novos undo points de filtros
        filterChangePending = false
        
        // Build a human-readable message of what changed back
        let editKeys = diffChangedKeys(from: current.editState, to: previous.editState)
        let baseKeys = diffChangedKeys(from: current.baseFilterState, to: previous.baseFilterState)
        lastUndoMessage = buildUndoMessage(fromEditKeys: editKeys, baseKeys: baseKeys)
        
        // Força regeneração do preview com o estado combinado
        DispatchQueue.main.async {
            let combined = self.combinedState
            self.generatePreview(state: combined)
        }
    }

    func resetAllEditsToClean() {
        // Make the full reset redoable as a single step
        let clean = PhotoEditState()
        let cleanComplete = CompleteEditState(editState: clean, baseFilterState: PhotoEditState())
        let currentComplete = CompleteEditState(editState: editState, baseFilterState: baseFilterState)
        
        if currentComplete != cleanComplete {
            // Clear undo history and set redo to restore the whole previous state
            undoStack.removeAll()
            redoStack = [currentComplete]
            editState = clean
            baseFilterState = PhotoEditState()
            // Reset da flag
            filterChangePending = false
            lastUndoMessage = "Reverted: all adjustments"
        } else {
            // Nada a desfazer; não mostrar toast indevido
            lastUndoMessage = nil
        }
    }

    func clearLastUndoMessage() { lastUndoMessage = nil }
    
    // MARK: - Filter System
    
    // MARK: - Filter Type Detection
    enum FilterApplicationType {
        case base        // Filtro aplicado via TAP (baseFilterState)
        case sliders     // Filtro aplicado via LONG PRESS (editState)
        case none        // Filtro não aplicado
    }
    
    /// Verifica como um filtro específico está aplicado atualmente
    func getFilterApplicationType(_ filterState: PhotoEditState) -> FilterApplicationType {
        if isStatesSimilar(baseFilterState, filterState) {
            return .base
        }
        if isStatesSimilar(editState, filterState) {
            return .sliders
        }
        return .none
    }
    
    /// Verifica se um filtro específico já está aplicado (em qualquer forma)
    func isFilterApplied(_ filterState: PhotoEditState) -> Bool {
        return getFilterApplicationType(filterState) != .none
    }
    
    /// Verifica se um filtro foi aplicado via long press (nos sliders)
    func isFilterAppliedToSliders(_ filterState: PhotoEditState) -> Bool {
        return isStatesSimilar(editState, filterState)
    }
    
    /// Verifica se um filtro foi aplicado via tap simples (base filter)
    func isFilterAppliedAsBase(_ filterState: PhotoEditState) -> Bool {
        return isStatesSimilar(baseFilterState, filterState)
    }
    
    /// Verifica se há uma combinação ativa de filtros (long press + tap)
    var hasFilterCombination: Bool {
        let defaultState = PhotoEditState()
        let hasSliderFilter = !isStatesSimilar(editState, defaultState)
        let hasBaseFilter = !isStatesSimilar(baseFilterState, defaultState)
        return hasSliderFilter && hasBaseFilter
    }
    
    /// Retorna o filtro aplicado nos sliders (via long press) se houver
    func getSliderFilter() -> PhotoEditState? {
        let defaultState = PhotoEditState()
        if !isStatesSimilar(editState, defaultState) {
            return editState
        }
        return nil
    }
    
    /// Retorna o filtro aplicado como base (via tap) se houver
    func getBaseFilter() -> PhotoEditState? {
        let defaultState = PhotoEditState()
        if !isStatesSimilar(baseFilterState, defaultState) {
            return baseFilterState
        }
        return nil
    }
    
    /// Verifica se ambos os filtros (base e slider) correspondem aos estados fornecidos
    func hasSpecificFilterCombination(sliderFilter: PhotoEditState, baseFilter: PhotoEditState) -> Bool {
        return isStatesSimilar(editState, sliderFilter) && isStatesSimilar(baseFilterState, baseFilter)
    }
    
    /// Compara dois PhotoEditState considerando tolerâncias para valores Float
    private func isStatesSimilar(_ state1: PhotoEditState, _ state2: PhotoEditState) -> Bool {
        let tolerance: Float = 0.001
        
        func isFloatSimilar(_ a: Float, _ b: Float) -> Bool {
            return abs(a - b) < tolerance
        }
        
        func isColorSimilar(_ c1: SIMD4<Float>, _ c2: SIMD4<Float>) -> Bool {
            return isFloatSimilar(c1.x, c2.x) && 
                   isFloatSimilar(c1.y, c2.y) && 
                   isFloatSimilar(c1.z, c2.z) && 
                   isFloatSimilar(c1.w, c2.w)
        }
        
        return isFloatSimilar(state1.contrast, state2.contrast) &&
               isFloatSimilar(state1.brightness, state2.brightness) &&
               isFloatSimilar(state1.exposure, state2.exposure) &&
               isFloatSimilar(state1.saturation, state2.saturation) &&
               isFloatSimilar(state1.vibrance, state2.vibrance) &&
               isFloatSimilar(state1.opacity, state2.opacity) &&
               isFloatSimilar(state1.fade, state2.fade) &&
               isFloatSimilar(state1.vignette, state2.vignette) &&
               isFloatSimilar(state1.colorInvert, state2.colorInvert) &&
               isFloatSimilar(state1.pixelateAmount, state2.pixelateAmount) &&
               isFloatSimilar(state1.sharpen, state2.sharpen) &&
               isFloatSimilar(state1.clarity, state2.clarity) &&
               isFloatSimilar(state1.grain, state2.grain) &&
               isFloatSimilar(state1.grainSize, state2.grainSize) &&
               isColorSimilar(state1.colorTint, state2.colorTint) &&
               isColorSimilar(state1.colorTintSecondary, state2.colorTintSecondary) &&
               isFloatSimilar(state1.colorTintIntensity, state2.colorTintIntensity) &&
               isFloatSimilar(state1.colorTintFactor, state2.colorTintFactor) &&
               state1.isDualToneActive == state2.isDualToneActive &&
               isFloatSimilar(state1.skinTone, state2.skinTone)
    }
    
    /// Retorna o filtro atualmente aplicado (para UI mostrar seleção)
    func getCurrentAppliedFilter() -> PhotoEditState? {
        let defaultState = PhotoEditState()
        
        // Se há filtro base aplicado, retorna ele
        if !isStatesSimilar(baseFilterState, defaultState) {
            return baseFilterState
        }
        
        // Se não há filtro base mas há editState modificado, retorna editState
        if !isStatesSimilar(editState, defaultState) {
            return editState
        }
        
        return nil
    }
    
    // MARK: - Filter Application Methods
    
    /// Aplica filtro via TAP SIMPLES (baseFilterState)
    /// Comportamento: Mantém sliders inalterados, aplica como base visual
    func applyBaseFilter(_ filterState: PhotoEditState) {
        let defaultState = PhotoEditState()
        
        print("[Filter] TAP: Applying base filter")
        print("[Filter] TAP: Current base similar to target? \(isStatesSimilar(baseFilterState, filterState))")
        print("[Filter] TAP: Current edit state: \(editState)")
        
        // Se o mesmo filtro já está aplicado como base, remove
        if isStatesSimilar(baseFilterState, filterState) {
            print("[Filter] TAP: Same base filter detected, removing")
            registerFilterUndoIfNeeded()
            baseFilterState = defaultState
            return
        }
        
        // Aplica novo filtro como base (permite combinação com slider existente)
        print("[Filter] TAP: Applying new base filter (may combine with existing slider filter)")
        registerFilterUndoIfNeeded()
        baseFilterState = filterState
        
        print("[Filter] TAP: Base filter applied - saturation: \(baseFilterState.saturation)")
        print("[Filter] TAP: Current edit state preserved: \(editState)")
    }
    
    /// Aplica filtro via LONG PRESS (editState)  
    /// Comportamento: Altera sliders, pode preservar ou substituir baseFilterState
    func applySliderFilter(_ filterState: PhotoEditState) {
        let defaultState = PhotoEditState()
        
        print("[Filter] LONG PRESS: Applying slider filter")
        print("[Filter] LONG PRESS: Current edit similar to target? \(isStatesSimilar(editState, filterState))")
        print("[Filter] LONG PRESS: Current base state: \(baseFilterState)")
        
        // Se o mesmo filtro já está aplicado nos sliders, remove apenas ele
        if isStatesSimilar(editState, filterState) {
            print("[Filter] LONG PRESS: Same slider filter detected, removing")
            registerFilterUndoIfNeeded()
            editState = defaultState
            // Preserva baseFilterState para permitir combinações
            return
        }
        
        // Aplica novo filtro nos sliders (permite combinação com base existente)
        print("[Filter] LONG PRESS: Applying new slider filter (may combine with existing base filter)")
        registerFilterUndoIfNeeded()
        editState = filterState
        
        print("[Filter] LONG PRESS: Slider filter applied - saturation: \(editState.saturation)")
        print("[Filter] LONG PRESS: Current base state preserved: \(baseFilterState)")
    }
    
    /// Remove filtro específico baseado no tipo de aplicação
    func removeFilter(_ filterState: PhotoEditState) {
        let applicationType = getFilterApplicationType(filterState)
        
        switch applicationType {
        case .base:
            print("[Filter] Removing base filter")
            // NÃO registra undo automático para filtros
            baseFilterState = PhotoEditState()
            
        case .sliders:
            print("[Filter] Removing slider filter")
            // NÃO registra undo automático para filtros
            editState = PhotoEditState()
            
        case .none:
            print("[Filter] Filter not currently applied, nothing to remove")
        }
    }
    
    // MARK: - Filter Management Utilities
    
    func clearBaseFilter() {
        print("[Filter] Clearing base filter")
        // NÃO registra undo automático para filtros
        baseFilterState = PhotoEditState()
    }
    
    func clearSliderFilter() {
        print("[Filter] Clearing slider filter")
        // NÃO registra undo automático para filtros
        editState = PhotoEditState()
    }
    
    func clearAllFilters() {
        print("[Filter] Clearing all filters and adjustments")
        // NÃO registra undo automático para filtros
        baseFilterState = PhotoEditState()
        editState = PhotoEditState()
    }
    
    /// Verifica se algum filtro está atualmente aplicado
    var hasAnyFilterApplied: Bool {
        let defaultState = PhotoEditState()
        return !isStatesSimilar(baseFilterState, defaultState) || !isStatesSimilar(editState, defaultState)
    }
    
    // MARK: - Filter State Comparison Utilities

    // Load persistent history when opening editor
    func loadPersistentUndoHistory(_ history: [PhotoEditState]) {
        // Convert old PhotoEditState history to CompleteEditState
        // Deduplicate consecutive equals and drop any trailing state equal to the current editState
        var cleaned: [CompleteEditState] = []
        cleaned.reserveCapacity(history.count)
        for s in history {
            let completeState = CompleteEditState(editState: s, baseFilterState: PhotoEditState())
            if cleaned.last != completeState { cleaned.append(completeState) }
        }
        let currentComplete = CompleteEditState(editState: editState, baseFilterState: baseFilterState)
        while let last = cleaned.last, last == currentComplete { cleaned.removeLast() }
        // Clamp to last N steps to avoid excessive manifest size
        let limit = AppSettings.shared.historyLimit
        undoStack = Array(cleaned.suffix(limit))
        redoStack.removeAll()
    }

    // MARK: - Diff helpers
    private func diffChangedKeys(from a: PhotoEditState, to b: PhotoEditState) -> [String] {
        var keys: [String] = []
        func changed(_ x: Float, _ y: Float, eps: Float = 0.0001) -> Bool { abs(x - y) > eps }
        func colorChanged(_ c1: SIMD4<Float>, _ c2: SIMD4<Float>) -> Bool {
            changed(c1.x, c2.x) || changed(c1.y, c2.y) || changed(c1.z, c2.z) || changed(c1.w, c2.w)
        }
        if changed(a.contrast, b.contrast) { keys.append("contrast") }
        if changed(a.brightness, b.brightness) { keys.append("brightness") }
        if changed(a.exposure, b.exposure) { keys.append("exposure") }
        if changed(a.saturation, b.saturation) { keys.append("saturation") }
        if changed(a.vibrance, b.vibrance) { keys.append("vibrance") }
        if changed(a.opacity, b.opacity) { keys.append("opacity") }
        if changed(a.fade, b.fade) { keys.append("fade") }
        if changed(a.vignette, b.vignette) { keys.append("vignette") }
        if changed(a.colorInvert, b.colorInvert) { keys.append("colorInvert") }
        if changed(a.pixelateAmount, b.pixelateAmount) { keys.append("pixelateAmount") }
        if changed(a.sharpen, b.sharpen) { keys.append("sharpen") }
        if changed(a.clarity, b.clarity) { keys.append("clarity") }
        if changed(a.grain, b.grain) { keys.append("grain") }
        if changed(a.grainSize, b.grainSize) { keys.append("grainSize") }
        if colorChanged(a.colorTint, b.colorTint) { keys.append("colorTint") }
        if colorChanged(a.colorTintSecondary, b.colorTintSecondary) { keys.append("colorTintSecondary") }
        if changed(a.colorTintIntensity, b.colorTintIntensity) { keys.append("colorTintIntensity") }
        if changed(a.colorTintFactor, b.colorTintFactor) { keys.append("colorTintFactor") }
        if a.isDualToneActive != b.isDualToneActive { keys.append("isDualToneActive") }
    if changed(a.skinTone, b.skinTone) { keys.append("skinTone") }
        return keys
    }

    private func buildUndoMessage(fromEditKeys editKeys: [String], baseKeys: [String]) -> String? {
        // Se há mudanças no filtro base, priorize essa informação
        if !baseKeys.isEmpty {
            // Verifica se houve remoção ou aplicação de filtro
            let hadFilter = baseKeys.contains { key in
                // Verifica se o filtro anterior tinha valores não-padrão
                key == "saturation" || key == "colorTint" || key == "contrast" || key == "isDualToneActive"
            }
            return hadFilter ? "Undone: Filter" : "Undone: Filter"
        }
        
        if editKeys.isEmpty && baseKeys.isEmpty { 
            return nil // Não mostrar mensagem se não há mudanças reais
        }
        
        let names: [String: String] = [
            "contrast": "Contrast",
            "brightness": "Brightness",
            "exposure": "Exposure",
            "saturation": "Saturation",
            "vibrance": "Vibrance",
            "opacity": "Opacity",
            "fade": "Fade",
            "vignette": "Vignette",
            "colorInvert": "Invert",
            "pixelateAmount": "Pixelate",
            "sharpen": "Sharpness",
            "clarity": "Clarity",
            "grain": "Grain",
            "grainSize": "Grain Size",
            "colorTint": "Tint",
            "colorTintSecondary": "Secondary Tint",
            "colorTintIntensity": "Tint Intensity",
            "colorTintFactor": "Tint Strength",
            "isDualToneActive": "Dual Tone",
            "skinTone": "Skin Tone"
        ]
        if editKeys.count == 1 {
            return "Undone: \(names[editKeys[0]] ?? editKeys[0])"
        }
        let firstTwo = editKeys.prefix(2).compactMap { names[$0] ?? $0 }.joined(separator: ", ")
        let rest = editKeys.count - 2
        return rest > 0 ? "Undone: \(firstTwo) +\(rest)" : "Undone: \(firstTwo)"
    }

    private func buildRestoreMessage(fromEditKeys editKeys: [String], baseKeys: [String]) -> String? {
        // Se há mudanças no filtro base, priorize essa informação
        if !baseKeys.isEmpty {
            return "Restored: Filter"
        }
        
        if editKeys.isEmpty && baseKeys.isEmpty { 
            return nil // Não mostrar mensagem se não há mudanças reais
        }
        
        let names: [String: String] = [
            "contrast": "Contrast",
            "brightness": "Brightness",
            "exposure": "Exposure",
            "saturation": "Saturation",
            "vibrance": "Vibrance",
            "opacity": "Opacity",
            "fade": "Fade",
            "vignette": "Vignette",
            "colorInvert": "Invert",
            "pixelateAmount": "Pixelate",
            "sharpen": "Sharpness",
            "clarity": "Clarity",
            "grain": "Grain",
            "grainSize": "Grain Size",
            "colorTint": "Tint",
            "colorTintSecondary": "Secondary Tint",
            "colorTintIntensity": "Tint Intensity",
            "colorTintFactor": "Tint Strength",
            "isDualToneActive": "Dual Tone",
            "skinTone": "Skin Tone"
        ]
        if editKeys.count == 1 {
            return "Restored: \(names[editKeys[0]] ?? editKeys[0])"
        }
        let firstTwo = editKeys.prefix(2).compactMap { names[$0] ?? $0 }.joined(separator: ", ")
        let rest = editKeys.count - 2
        return rest > 0 ? "Restored: \(firstTwo) +\(rest)" : "Restored: \(firstTwo)"
    }

    func redoLastChange() {
        guard let next = redoStack.popLast() else { return }
        let current = CompleteEditState(editState: editState, baseFilterState: baseFilterState)
        // current becomes another undo point
        undoStack.append(current)
        
        // Restaura ambos os estados
        editState = next.editState
        baseFilterState = next.baseFilterState
        
        // Reset da flag para permitir novos undo points de filtros
        filterChangePending = false
        
        let editKeys = diffChangedKeys(from: current.editState, to: next.editState)
        let baseKeys = diffChangedKeys(from: current.baseFilterState, to: next.baseFilterState)
        lastUndoMessage = buildRestoreMessage(fromEditKeys: editKeys, baseKeys: baseKeys)
        
        // Força regeneração do preview com o estado combinado
        DispatchQueue.main.async {
            let combined = self.combinedState
            self.generatePreview(state: combined)
        }
    }

    func redoAllChanges() {
        guard !redoStack.isEmpty else { return }
        var current = CompleteEditState(editState: editState, baseFilterState: baseFilterState)
        var latest = current
        while let next = redoStack.popLast() {
            undoStack.append(current)
            current = next
            latest = next
        }
        editState = latest.editState
        baseFilterState = latest.baseFilterState
        lastUndoMessage = "Restored: all adjustments"
    }

    /// Gera a imagem final em alta qualidade com todos os ajustes aplicados
    func generateFinalImage() -> UIImage? {
        // Carrega em alta do URL/dados no momento do export, evitando manter gigante em memória durante edição
        var sourceUIImage: UIImage?
        if let url = originalImageURL, let data = try? Data(contentsOf: url) {
            sourceUIImage = UIImage(data: data)
        } else if let data = originalImageData {
            sourceUIImage = UIImage(data: data)
        } else {
            sourceUIImage = originalImage
        }
        // Corrige orientação antes de gerar pipeline em alta
        let oriented = sourceUIImage?.fixOrientation()
        guard let base = oriented?.withAlpha(), let cgImage = base.cgImage, let mtiContext = mtiContext else { return nil }
        
        // Usa o estado combinado que inclui filtro base + ajustes do usuário
        let state = combinedState
        // Repete o pipeline do generatePreview, mas usando a original
        let alphaInfo = cgImage.alphaInfo
        let bitsPerPixel = cgImage.bitsPerPixel
        if !(alphaInfo == .premultipliedLast || alphaInfo == .premultipliedFirst) { return nil }
        if bitsPerPixel != 32 { return nil }
        let mtiImage = MTIImage(cgImage: cgImage, options: [.SRGB: false], isOpaque: true)
        // Filtros (igual ao preview)
        let saturationFilter = MTISaturationFilter()
        saturationFilter.inputImage = mtiImage
        saturationFilter.saturation = state.saturation
        guard let saturatedImage = saturationFilter.outputImage else { return nil }
        let vibranceImage: MTIImage
        if state.vibrance != 0.0 {
            let vibranceFilter = MTIVibranceFilter()
            vibranceFilter.inputImage = saturatedImage
            vibranceFilter.amount = state.vibrance
            guard let output = vibranceFilter.outputImage else { return nil }
            vibranceImage = output
        } else {
            vibranceImage = saturatedImage
        }
        let exposureFilter = MTIExposureFilter()
        exposureFilter.inputImage = vibranceImage
        exposureFilter.exposure = state.exposure
        guard let exposureImage = exposureFilter.outputImage else { return nil }
        let brightnessFilter = MTIBrightnessFilter()
        brightnessFilter.inputImage = exposureImage
        brightnessFilter.brightness = state.brightness
        guard let brightImage = brightnessFilter.outputImage else { return nil }
        let contrastFilter = MTIContrastFilter()
        contrastFilter.inputImage = brightImage
        contrastFilter.contrast = state.contrast
        guard let contrastImage = contrastFilter.outputImage else { return nil }
        // Fade (elevação dos pretos via ColorMatrix: out = in*(1-f) + f) 
        let imageAfterFade: MTIImage
        if state.fade > 0.0 {
            let k = 0.35 * max(0.0, min(1.0, state.fade))
            let cm = MTIColorMatrixFilter()
            cm.inputImage = contrastImage
            cm.colorMatrix = MTIColorMatrix(
                matrix: simd_float4x4(diagonal: SIMD4<Float>(1 - k, 1 - k, 1 - k, 1)),
                bias: SIMD4<Float>(k, k, k, 0)
            )
            guard let out = cm.outputImage else { return nil }
            imageAfterFade = out
        } else {
            imageAfterFade = contrastImage
        }
        let opacityFilter = MTIOpacityFilter()
        opacityFilter.inputImage = imageAfterFade
        opacityFilter.opacity = state.opacity
        guard let opacityImage = opacityFilter.outputImage else { return nil }
        let pixelatedImage: MTIImage
        if state.pixelateAmount > 1.0 {
            let pixelateFilter = MTIPixellateFilter()
            pixelateFilter.inputImage = opacityImage
            let scale = max(CGFloat(state.pixelateAmount), 1.0)
            pixelateFilter.scale = CGSize(width: scale, height: scale)
            guard let output = pixelateFilter.outputImage else { return nil }
            pixelatedImage = output
        } else {
            pixelatedImage = opacityImage
        }
        // Clarity (CLAHE) direct (MetalPetal) — no extra blends
        let clarityImage_final: MTIImage
        if state.clarity > 0.0 {
            let clahe = MTICLAHEFilter()
            clahe.inputImage = pixelatedImage
            clahe.clipLimit = max(0.0, min(2.0, 0.5 + 1.0 * state.clarity))
            clahe.tileGridSize = MTICLAHESize(width: 12, height: 12)
            guard let out = clahe.outputImage else { return nil }
            clarityImage_final = out
        } else {
            clarityImage_final = pixelatedImage
        }
        // Sharpen (Unsharp Mask) applied directly for a clean, gradual effect
        let sharpenedImage_final: MTIImage
        if state.sharpen > 0.0 {
            let usm = MTIMPSUnsharpMaskFilter()
            usm.inputImage = clarityImage_final
            usm.scale = min(max(state.sharpen, 0.0), 1.0)
            usm.radius = Float(1.0 + 2.0 * Double(state.sharpen))
            usm.threshold = 0.0
            guard let out = usm.outputImage else { return nil }
            sharpenedImage_final = out
        } else {
            sharpenedImage_final = clarityImage_final
        }
    let tintedImage: MTIImage
        if state.colorTint.x > 0.0 || state.colorTint.y > 0.0 || state.colorTint.z > 0.0 {
            if state.isDualToneActive && (state.colorTintSecondary.x > 0.0 || state.colorTintSecondary.y > 0.0 || state.colorTintSecondary.z > 0.0) {
                // Dual tone real: mapeia luminância para duas cores
                // 1. Converte para grayscale primeiro para obter luminância
                let grayscaleFilter = MTIColorMatrixFilter()
                grayscaleFilter.inputImage = sharpenedImage_final
                
                // Matriz para converter para grayscale (preserva luminância)
                let grayscaleMatrix = simd_float4x4(
                    SIMD4<Float>(0.299, 0.299, 0.299, 0),
                    SIMD4<Float>(0.587, 0.587, 0.587, 0), 
                    SIMD4<Float>(0.114, 0.114, 0.114, 0),
                    SIMD4<Float>(0, 0, 0, 1)
                )
                grayscaleFilter.colorMatrix = MTIColorMatrix(matrix: grayscaleMatrix, bias: SIMD4<Float>(0, 0, 0, 0))
                
                guard let grayscaleImage = grayscaleFilter.outputImage else { return nil }
                
                // 2. Aplica dual tone usando blend de multiply e screen
                let shadowColor = state.colorTint
                let highlightColor = state.colorTintSecondary
                let intensity = max(0.0, min(1.0, state.colorTintIntensity))
                let factor: Float = max(0.0, min(1.0, state.colorTintFactor))
                
                // Cria imagens sólidas das cores
                let shadowColorImage = MTIImage(color: MTIColor(
                    red: Float(shadowColor.x), 
                    green: Float(shadowColor.y), 
                    blue: Float(shadowColor.z), 
                    alpha: 1.0
                ), sRGB: false, size: pixelatedImage.size)
                
                let highlightColorImage = MTIImage(color: MTIColor(
                    red: Float(highlightColor.x), 
                    green: Float(highlightColor.y), 
                    blue: Float(highlightColor.z), 
                    alpha: 1.0
                ), sRGB: false, size: pixelatedImage.size)
                
                // Blend sombras: multiply (escurece)
                let shadowBlend = MTIBlendFilter(blendMode: .multiply)
                shadowBlend.inputImage = shadowColorImage
                shadowBlend.inputBackgroundImage = grayscaleImage
                shadowBlend.intensity = factor * intensity
                
                guard let shadowResult = shadowBlend.outputImage else { return nil }
                
                // Blend highlights: screen (clareia)
                let highlightBlend = MTIBlendFilter(blendMode: .screen)
                highlightBlend.inputImage = highlightColorImage
                highlightBlend.inputBackgroundImage = shadowResult
                highlightBlend.intensity = factor * intensity * 0.7 // Um pouco menos intenso
                
                guard let dualToneResult = highlightBlend.outputImage else { return nil }
                
                // Blend final com imagem original para preservar detalhes
                let finalBlend = MTIBlendFilter(blendMode: .normal)
                finalBlend.inputImage = dualToneResult
                finalBlend.inputBackgroundImage = sharpenedImage_final
                finalBlend.intensity = factor * intensity
                
                guard let output = finalBlend.outputImage else { return nil }
                tintedImage = output
            } else {
                // Tint simples original
                let neutral: Float = 0.5
                let intensity = max(0.0, min(1.0, state.colorTintIntensity))
                let factor: Float = max(0.0, min(1.0, state.colorTintFactor)) // controla a força
                let biasR = (state.colorTint.x - neutral) * factor * intensity
                let biasG = (state.colorTint.y - neutral) * factor * intensity
                let biasB = (state.colorTint.z - neutral) * factor * intensity
                let matrixFilter = MTIColorMatrixFilter()
                matrixFilter.inputImage = sharpenedImage_final
                let mat = simd_float4x4(diagonal: SIMD4<Float>(1, 1, 1, 1))
                let bias = SIMD4<Float>(biasR, biasG, biasB, 0)
                matrixFilter.colorMatrix = MTIColorMatrix(matrix: mat, bias: bias)
                guard let output = matrixFilter.outputImage else { return nil }
                tintedImage = output
            }
        } else {
            tintedImage = sharpenedImage_final
        }
        // Skin tone adjustment (final image) – com máscara de saturação para evitar brancos
        let tintedImageWithSkin: MTIImage
        if abs(state.skinTone) > 0.001 {
            let amount = max(-1.0, min(1.0, state.skinTone))
            let k = pow(abs(amount), 0.85)
            
            // Primeiro aplica o bias em uma imagem separada
            let biasedImage: MTIImage
            if amount > 0 { // Âmbar (mais dourado/vermelho)
                let biasR: Float = 0.050 * k
                let biasG: Float = 0.020 * k
                let biasB: Float = -0.035 * k
                let matrixFilter = MTIColorMatrixFilter()
                matrixFilter.inputImage = tintedImage
                let mat = simd_float4x4(diagonal: SIMD4<Float>(1,1,1,1))
                matrixFilter.colorMatrix = MTIColorMatrix(matrix: mat, bias: SIMD4<Float>(biasR, biasG, biasB, 0))
                biasedImage = matrixFilter.outputImage ?? tintedImage
            } else { // Avermelhado / rosado
                let biasR: Float = 0.045 * k
                let biasG: Float = -0.018 * k
                let biasB: Float = 0.020 * k
                let matrixFilter = MTIColorMatrixFilter()
                matrixFilter.inputImage = tintedImage
                let mat = simd_float4x4(diagonal: SIMD4<Float>(1,1,1,1))
                matrixFilter.colorMatrix = MTIColorMatrix(matrix: mat, bias: SIMD4<Float>(biasR, biasG, biasB, 0))
                biasedImage = matrixFilter.outputImage ?? tintedImage
            }
            
            // Aplica skin tone de forma mais suave usando luminance
            let luminanceFilter = MTIColorMatrixFilter()
            luminanceFilter.inputImage = tintedImage
            // Matriz para extrair luminance (RGB to grayscale)
            let luminanceMatrix = simd_float4x4(
                SIMD4<Float>(0.299, 0.299, 0.299, 0),
                SIMD4<Float>(0.587, 0.587, 0.587, 0),
                SIMD4<Float>(0.114, 0.114, 0.114, 0),
                SIMD4<Float>(0, 0, 0, 1)
            )
            luminanceFilter.colorMatrix = MTIColorMatrix(matrix: luminanceMatrix, bias: SIMD4<Float>(0,0,0,0))
            
            if let luminanceImage = luminanceFilter.outputImage {
                // Usa luminance como máscara suave para misturar
                let mixFilter = MTIBlendFilter(blendMode: .normal)
                mixFilter.inputImage = biasedImage
                mixFilter.inputBackgroundImage = tintedImage
                // Intensity baseada na luminance - menos efeito em áreas claras
                mixFilter.intensity = 0.55 * abs(state.skinTone)
                
                tintedImageWithSkin = mixFilter.outputImage ?? tintedImage
            } else {
                tintedImageWithSkin = biasedImage
            }
        } else {
            tintedImageWithSkin = tintedImage
        }
        // Inversão de cores opcional (sem duotone)
        let baseImageForInvert = tintedImageWithSkin
        var finalImage: MTIImage
        print("[FinalImage] Checking colorInvert: \(state.colorInvert)")
        if state.colorInvert > 0.0 {
            print("[FinalImage] Applying colorInvert filter")
            let invertFilter = MTIColorInvertFilter()
            invertFilter.inputImage = baseImageForInvert
            guard let invertedImage = invertFilter.outputImage else { return nil }
            if state.colorInvert < 1.0 {
                print("[FinalImage] Blending inverted image with intensity: \(state.colorInvert)")
                let blendFilter = MTIBlendFilter(blendMode: .normal)
                blendFilter.inputImage = invertedImage
                blendFilter.inputBackgroundImage = baseImageForInvert
                blendFilter.intensity = state.colorInvert
                guard let blendedImage = blendFilter.outputImage else { return nil }
                finalImage = blendedImage
            } else {
                print("[FinalImage] Using fully inverted image")
                finalImage = invertedImage
            }
        } else {
            print("[FinalImage] No colorInvert applied")
            finalImage = baseImageForInvert
        }

        // Vignette (corrigido para centralização correta em qualquer proporção, ex: 16:9)
        if state.vignette > 0.0 {
            let v = max(0.0, min(1.0, state.vignette))
            let size = finalImage.size
            let extent = CGRect(origin: .zero, size: size)
            let w = size.width
            let h = size.height
            if let radial = CIFilter(name: "CIRadialGradient") {
                // Centro sempre geométrico independente de transformações anteriores
                let cx = w * 0.5
                let cy = h * 0.5
                radial.setValue(CIVector(x: cx, y: cy), forKey: kCIInputCenterKey)
                // Usa maior dimensão para garantir cobertura até as bordas mais longas
                let outer = max(w, h) * 0.5
                // Região clara diminui conforme intensidade (0.85 fraco -> 0.55 forte)
                let innerRatio = 0.85 - 0.30 * Double(v)
                let inner = max(1.0, outer * CGFloat(innerRatio))
                radial.setValue(inner, forKey: "inputRadius0")
                radial.setValue(outer, forKey: "inputRadius1")
                radial.setValue(CIColor(red: 0, green: 0, blue: 0, alpha: 0), forKey: "inputColor0")
                radial.setValue(CIColor(red: 0, green: 0, blue: 0, alpha: 1), forKey: "inputColor1")
                if var overlay = radial.outputImage?.cropped(to: extent) {
                    // Suaviza borda com smoothstep (3a^2 - 2a^3)
                    if let poly = CIFilter(name: "CIColorPolynomial") {
                        poly.setValue(overlay, forKey: kCIInputImageKey)
                        poly.setValue(CIVector(x: 0, y: 1, z: 0, w: 0), forKey: "inputRedCoefficients")
                        poly.setValue(CIVector(x: 0, y: 1, z: 0, w: 0), forKey: "inputGreenCoefficients")
                        poly.setValue(CIVector(x: 0, y: 1, z: 0, w: 0), forKey: "inputBlueCoefficients")
                        poly.setValue(CIVector(x: 0, y: 0, z: 3, w: -2), forKey: "inputAlphaCoefficients")
                        overlay = poly.outputImage ?? overlay
                    }
                    // Escala alpha global (menos agressivo no começo)
                    let edgeAlpha = CGFloat(0.6 * pow(Double(v), 0.88))
                    if let scaleA = CIFilter(name: "CIColorMatrix") {
                        scaleA.setValue(overlay, forKey: kCIInputImageKey)
                        scaleA.setValue(CIVector(x: 1, y: 0, z: 0, w: 0), forKey: "inputRVector")
                        scaleA.setValue(CIVector(x: 0, y: 1, z: 0, w: 0), forKey: "inputGVector")
                        scaleA.setValue(CIVector(x: 0, y: 0, z: 1, w: 0), forKey: "inputBVector")
                        scaleA.setValue(CIVector(x: 0, y: 0, z: 0, w: edgeAlpha), forKey: "inputAVector")
                        overlay = scaleA.outputImage ?? overlay
                    }
                    let overlayMTI = MTIImage(ciImage: overlay, isOpaque: false)
                    let over = MTIBlendFilter(blendMode: .normal)
                    over.inputImage = overlayMTI
                    over.inputBackgroundImage = finalImage
                    over.intensity = 1
                    over.outputAlphaType = .alphaIsOne
                    if let out = over.outputImage { finalImage = out }
                }
            }
        }

        // Film grain: per-pixel noise; Overlay + LinearLight for a refined look
        if state.grain > 0.0 {
            // Stronger response to the same slider value
            let baseK = max(0.0, min(1.0, state.grain * 20.0))
            let shaped = Float(pow(Double(baseK), 0.75)) // faster ramp for low values
            let extent = CGRect(origin: .zero, size: finalImage.size)
            if var sizedNoise = makeNoiseCIImage(extent: extent, grainSize: state.grainSize, seed: 0.0) {
                // Compress highlights in noise to reduce white speckles
                if let tone = CIFilter(name: "CIToneCurve") {
                    tone.setValue(sizedNoise, forKey: kCIInputImageKey)
                    let c = CGFloat(min(0.15, Double(shaped) * 0.15))
                    tone.setValue(CIVector(x: 0.0,  y: 0.0),  forKey: "inputPoint0")
                    tone.setValue(CIVector(x: 0.25, y: max(0.0, 0.25 - 0.25*c)), forKey: "inputPoint1")
                    tone.setValue(CIVector(x: 0.50, y: max(0.0, 0.50 - 0.50*c)), forKey: "inputPoint2")
                    tone.setValue(CIVector(x: 0.75, y: 0.75 - 0.75*c), forKey: "inputPoint3")
                    tone.setValue(CIVector(x: 1.00, y: 1.00 - 1.00*c), forKey: "inputPoint4")
                    sizedNoise = (tone.outputImage ?? sizedNoise).cropped(to: extent)
                }
                // Normalize around 0.5 with adjustable contrast (amp)
                let amp = min(1.0, Float(0.30 + 0.65 * shaped))
                let noiseMTI = MTIImage(ciImage: sizedNoise, isOpaque: true)
                let mat = MTIColorMatrixFilter(); mat.inputImage = noiseMTI
                // Slight dark bias for more natural overlap
                let darkBias: Float = max(0.0, min(0.07, 0.07 * shaped))
                mat.colorMatrix = MTIColorMatrix(
                    matrix: simd_float4x4(diagonal: SIMD4<Float>(amp, amp, amp, 1)),
                    bias: SIMD4<Float>(0.5 - 0.5 * amp - darkBias, 0.5 - 0.5 * amp - darkBias, 0.5 - 0.5 * amp - darkBias, 0)
                )
                let normalized = mat.outputImage ?? noiseMTI
                // Passo 1: Overlay
                let over = MTIBlendFilter(blendMode: .overlay)
                over.inputImage = normalized
                over.inputBackgroundImage = finalImage
                let overlayIntensity = min(1.0, shaped * 1.35)
                over.intensity = overlayIntensity
                over.outputAlphaType = .alphaIsOne
                if let out = over.outputImage { finalImage = out }

                // Passo 2: Linear Light (sutil)
                let amp2 = min(1.0, Float(0.10 + 0.25 * shaped))
                let mat2 = MTIColorMatrixFilter(); mat2.inputImage = noiseMTI
                let darkBias2: Float = min(0.08, 0.08 * shaped)
                mat2.colorMatrix = MTIColorMatrix(
                    matrix: simd_float4x4(diagonal: SIMD4<Float>(amp2, amp2, amp2, 1)),
                    bias: SIMD4<Float>(0.5 - 0.5 * amp2 - darkBias2, 0.5 - 0.5 * amp2 - darkBias2, 0.5 - 0.5 * amp2 - darkBias2, 0)
                )
                let normalized2 = mat2.outputImage ?? noiseMTI
                let lin = MTIBlendFilter(blendMode: .linearLight)
                lin.inputImage = normalized2
                lin.inputBackgroundImage = finalImage
                lin.intensity = min(1.0, overlayIntensity * 0.50)
                lin.outputAlphaType = .alphaIsOne
                if let out2 = lin.outputImage { finalImage = out2 }
            }
        }
        do {
            let cgimg = try mtiContext.makeCGImage(from: finalImage)
            let uiImage = UIImage(cgImage: cgimg)
            return uiImage
        } catch {
            return nil
        }
    }

    private func generatePreview(state: PhotoEditState) {
        guard let base = previewBase?.withAlpha(), let cgImage = base.cgImage, let mtiContext = mtiContext else { return }
        // Log input image info before passing to MetalPetal
        let alphaInfo = cgImage.alphaInfo
        let bitsPerPixel = cgImage.bitsPerPixel
        let bytesPerRow = cgImage.bytesPerRow
        os_log("[PhotoEditorViewModel] Input to MTIImage: alphaInfo: %{public}@, bitsPerPixel: %d, bytesPerRow: %d", String(describing: alphaInfo), bitsPerPixel, bytesPerRow)
        // Assert RGBA8888, premultiplied alpha
        if !(alphaInfo == .premultipliedLast || alphaInfo == .premultipliedFirst) {
            os_log("[PhotoEditorViewModel] Input image is not premultiplied alpha! Skipping preview generation.")
            return
        }
        if bitsPerPixel != 32 {
            os_log("[PhotoEditorViewModel] Input image is not 32bpp RGBA! Skipping preview generation.")
            return
        }
        // Tente isOpaque: true para contornar bug de alphaTypeHandlingRule
        let mtiImage = MTIImage(cgImage: cgImage, options: [.SRGB: false], isOpaque: true)
        // Filtro de saturação (MTISaturationFilter)
        let saturationFilter = MTISaturationFilter()
        saturationFilter.inputImage = mtiImage
        saturationFilter.saturation = state.saturation
        guard let saturatedImage = saturationFilter.outputImage else { return }
        // Filtro de vibrance (MTIVibranceFilter)
        let vibranceImage: MTIImage
        if state.vibrance != 0.0 {
            let vibranceFilter = MTIVibranceFilter()
            vibranceFilter.inputImage = saturatedImage
            vibranceFilter.amount = state.vibrance
            guard let output = vibranceFilter.outputImage else { return }
            vibranceImage = output
        } else {
            vibranceImage = saturatedImage
        }
        // Filtro de exposição (MTIExposureFilter)
        let exposureFilter = MTIExposureFilter()
        exposureFilter.inputImage = vibranceImage
        exposureFilter.exposure = state.exposure
        guard let exposureImage = exposureFilter.outputImage else { return }
        // Filtro de brilho (MTIBrightnessFilter específico)
        let brightnessFilter = MTIBrightnessFilter()
        brightnessFilter.inputImage = exposureImage
        brightnessFilter.brightness = state.brightness
        guard let brightImage = brightnessFilter.outputImage else { return }
        // Filtro de contraste
        let contrastFilter = MTIContrastFilter()
        contrastFilter.inputImage = brightImage
        contrastFilter.contrast = state.contrast
        guard let contrastImage = contrastFilter.outputImage else { return }
        // Fade (elevação dos pretos via ColorMatrix: out = in*(1-f) + f)
        let imageAfterFade: MTIImage
        if state.fade > 0.0 {
            let k = 0.35 * max(0.0, min(1.0, state.fade))
            let cm = MTIColorMatrixFilter()
            cm.inputImage = contrastImage
            cm.colorMatrix = MTIColorMatrix(
                matrix: simd_float4x4(diagonal: SIMD4<Float>(1 - k, 1 - k, 1 - k, 1)),
                bias: SIMD4<Float>(k, k, k, 0)
            )
            guard let out = cm.outputImage else { return }
            imageAfterFade = out
        } else {
            imageAfterFade = contrastImage
        }
        // Filtro de opacidade (usando MTIOpacityFilter especializado)
        let opacityFilter = MTIOpacityFilter()
        opacityFilter.inputImage = imageAfterFade
        opacityFilter.opacity = state.opacity
        guard let opacityImage = opacityFilter.outputImage else { return }
        
        // Filtro de pixelate (quando pixelateAmount > 1.0)
        let pixelatedImage: MTIImage
        if state.pixelateAmount > 1.0 {
            let pixelateFilter = MTIPixellateFilter()
            pixelateFilter.inputImage = opacityImage
            // O scale define o tamanho do pixel, quanto maior, mais pixelado
            let scale = max(CGFloat(state.pixelateAmount), 1.0)
            pixelateFilter.scale = CGSize(width: scale, height: scale)
            guard let output = pixelateFilter.outputImage else { return }
            pixelatedImage = output
        } else {
            pixelatedImage = opacityImage
        }
        // Clarity (CLAHE) direct for preview — no blends
        let clarityImage_preview: MTIImage
        if state.clarity > 0.0 {
            let clahe = MTICLAHEFilter()
            clahe.inputImage = pixelatedImage
            clahe.clipLimit = max(0.0, min(2.0, 0.5 + 1.0 * state.clarity))
            clahe.tileGridSize = MTICLAHESize(width: 12, height: 12)
            guard let out = clahe.outputImage else { return }
            clarityImage_preview = out
        } else {
            clarityImage_preview = pixelatedImage
        }
        // Sharpen (Unsharp Mask) applied directly
        let sharpenedImage_preview: MTIImage
        if state.sharpen > 0.0 {
            let usm = MTIMPSUnsharpMaskFilter()
            usm.inputImage = clarityImage_preview
            usm.scale = min(max(state.sharpen, 0.0), 1.0)
            usm.radius = Float(1.0 + 2.0 * Double(state.sharpen))
            usm.threshold = 0.0
            guard let out = usm.outputImage else { return }
            sharpenedImage_preview = out
        } else {
            sharpenedImage_preview = clarityImage_preview
        }
        
        // Filtro de color tint (quando uma cor for selecionada, independente da intensidade)
        let tintedImage: MTIImage
    if state.colorTint.x > 0.0 || state.colorTint.y > 0.0 || state.colorTint.z > 0.0 {
            if state.isDualToneActive && (state.colorTintSecondary.x > 0.0 || state.colorTintSecondary.y > 0.0 || state.colorTintSecondary.z > 0.0) {
                // Dual tone real: mapeia luminância para duas cores
                // 1. Converte para grayscale primeiro para obter luminância
                let grayscaleFilter = MTIColorMatrixFilter()
                grayscaleFilter.inputImage = sharpenedImage_preview
                
                // Matriz para converter para grayscale (preserva luminância)
                let grayscaleMatrix = simd_float4x4(
                    SIMD4<Float>(0.299, 0.299, 0.299, 0),
                    SIMD4<Float>(0.587, 0.587, 0.587, 0), 
                    SIMD4<Float>(0.114, 0.114, 0.114, 0),
                    SIMD4<Float>(0, 0, 0, 1)
                )
                grayscaleFilter.colorMatrix = MTIColorMatrix(matrix: grayscaleMatrix, bias: SIMD4<Float>(0, 0, 0, 0))
                
                guard let grayscaleImage = grayscaleFilter.outputImage else { return }
                
                // 2. Aplica dual tone usando blend de multiply e screen
                let shadowColor = state.colorTint
                let highlightColor = state.colorTintSecondary
                let intensity = max(0.0, min(1.0, state.colorTintIntensity))
                let factor: Float = max(0.0, min(1.0, state.colorTintFactor))
                
                // Cria imagens sólidas das cores
                let shadowColorImage = MTIImage(color: MTIColor(
                    red: Float(shadowColor.x), 
                    green: Float(shadowColor.y), 
                    blue: Float(shadowColor.z), 
                    alpha: 1.0
                ), sRGB: false, size: pixelatedImage.size)
                
                let highlightColorImage = MTIImage(color: MTIColor(
                    red: Float(highlightColor.x), 
                    green: Float(highlightColor.y), 
                    blue: Float(highlightColor.z), 
                    alpha: 1.0
                ), sRGB: false, size: pixelatedImage.size)
                
                // Blend sombras: multiply (escurece)
                let shadowBlend = MTIBlendFilter(blendMode: .multiply)
                shadowBlend.inputImage = shadowColorImage
                shadowBlend.inputBackgroundImage = grayscaleImage
                shadowBlend.intensity = factor * intensity
                
                guard let shadowResult = shadowBlend.outputImage else { return }
                
                // Blend highlights: screen (clareia)
                let highlightBlend = MTIBlendFilter(blendMode: .screen)
                highlightBlend.inputImage = highlightColorImage
                highlightBlend.inputBackgroundImage = shadowResult
                highlightBlend.intensity = factor * intensity * 0.7 // Um pouco menos intenso
                
                guard let dualToneResult = highlightBlend.outputImage else { return }
                
                // Blend final com imagem original para preservar detalhes
                let finalBlend = MTIBlendFilter(blendMode: .normal)
                finalBlend.inputImage = dualToneResult
                finalBlend.inputBackgroundImage = sharpenedImage_preview
                finalBlend.intensity = factor * intensity
                
                guard let output = finalBlend.outputImage else { return }
                tintedImage = output
            } else {
                // Tint simples original
                let neutral: Float = 0.5
                let intensity = max(0.0, min(1.0, state.colorTintIntensity))
                let factor: Float = max(0.0, min(1.0, state.colorTintFactor)) // controla a força
                let biasR = (state.colorTint.x - neutral) * factor * intensity
                let biasG = (state.colorTint.y - neutral) * factor * intensity
                let biasB = (state.colorTint.z - neutral) * factor * intensity
                let matrixFilter = MTIColorMatrixFilter()
                matrixFilter.inputImage = sharpenedImage_preview
                let mat = simd_float4x4(diagonal: SIMD4<Float>(1, 1, 1, 1))
                let bias = SIMD4<Float>(biasR, biasG, biasB, 0)
                matrixFilter.colorMatrix = MTIColorMatrix(matrix: mat, bias: bias)
                guard let output = matrixFilter.outputImage else { return }
                tintedImage = output
            }
        } else {
            tintedImage = sharpenedImage_preview
        }
        
        // Skin tone adjustment (preview) – com máscara de saturação
        let tintedImageWithSkin: MTIImage
        if abs(state.skinTone) > 0.001 {
            let amount = max(-1.0, min(1.0, state.skinTone))
            let k = pow(abs(amount), 0.85)
            
            // Aplica bias primeiro
            let biasedImage: MTIImage
            if amount > 0 { // Âmbar
                let biasR: Float = 0.050 * k
                let biasG: Float = 0.020 * k
                let biasB: Float = -0.035 * k
                let matrixFilter = MTIColorMatrixFilter()
                matrixFilter.inputImage = tintedImage
                let mat = simd_float4x4(diagonal: SIMD4<Float>(1,1,1,1))
                matrixFilter.colorMatrix = MTIColorMatrix(matrix: mat, bias: SIMD4<Float>(biasR, biasG, biasB, 0))
                biasedImage = matrixFilter.outputImage ?? tintedImage
            } else { // Avermelhado
                let biasR: Float = 0.045 * k
                let biasG: Float = -0.018 * k
                let biasB: Float = 0.020 * k
                let matrixFilter = MTIColorMatrixFilter()
                matrixFilter.inputImage = tintedImage
                let mat = simd_float4x4(diagonal: SIMD4<Float>(1,1,1,1))
                matrixFilter.colorMatrix = MTIColorMatrix(matrix: mat, bias: SIMD4<Float>(biasR, biasG, biasB, 0))
                biasedImage = matrixFilter.outputImage ?? tintedImage
            }
            
            // Máscara de luminance (preview) - mais suave
            let mixFilter = MTIBlendFilter(blendMode: .normal)
            mixFilter.inputImage = biasedImage
            mixFilter.inputBackgroundImage = tintedImage
            mixFilter.intensity = 0.55 * abs(state.skinTone)
            
            tintedImageWithSkin = mixFilter.outputImage ?? tintedImage
        } else {
            tintedImageWithSkin = tintedImage
        }
        // Filtro de inversão de cores (quando colorInvert > 0)
        let baseImageForInvert = tintedImageWithSkin
        var finalImage: MTIImage
        print("[Preview] Checking colorInvert: \(state.colorInvert)")
        if state.colorInvert > 0.0 {
            print("[Preview] Applying colorInvert filter")
            let invertFilter = MTIColorInvertFilter()
            invertFilter.inputImage = baseImageForInvert
            guard let invertedImage = invertFilter.outputImage else { 
                print("[Preview] Failed to generate inverted image")
                return 
            }
            // Se colorInvert < 1.0, fazemos um blend entre a imagem original e a invertida
            if state.colorInvert < 1.0 {
                print("[Preview] Blending inverted image with intensity: \(state.colorInvert)")
                let blendFilter = MTIBlendFilter(blendMode: .normal)
                blendFilter.inputImage = invertedImage
                blendFilter.inputBackgroundImage = baseImageForInvert
                blendFilter.intensity = state.colorInvert
                guard let blendedImage = blendFilter.outputImage else { 
                    print("[Preview] Failed to blend inverted image")
                    return 
                }
                finalImage = blendedImage
            } else {
                print("[Preview] Using fully inverted image")
                finalImage = invertedImage
            }
        } else {
            print("[Preview] No colorInvert applied")
            finalImage = baseImageForInvert
        }

        // Vignette (corrigido: centralização para qualquer aspecto / preview)
        if state.vignette > 0.0 {
            let v = max(0.0, min(1.0, state.vignette))
            let size = finalImage.size
            let extent = CGRect(origin: .zero, size: size)
            let w = size.width
            let h = size.height
            if let radial = CIFilter(name: "CIRadialGradient") {
                let cx = w * 0.5
                let cy = h * 0.5
                radial.setValue(CIVector(x: cx, y: cy), forKey: kCIInputCenterKey)
                let outer = max(w, h) * 0.5
                let innerRatio = 0.85 - 0.30 * Double(v)
                let inner = max(1.0, outer * CGFloat(innerRatio))
                radial.setValue(inner, forKey: "inputRadius0")
                radial.setValue(outer, forKey: "inputRadius1")
                radial.setValue(CIColor(red: 0, green: 0, blue: 0, alpha: 0), forKey: "inputColor0")
                radial.setValue(CIColor(red: 0, green: 0, blue: 0, alpha: 1), forKey: "inputColor1")
                if var overlay = radial.outputImage?.cropped(to: extent) {
                    if let poly = CIFilter(name: "CIColorPolynomial") {
                        poly.setValue(overlay, forKey: kCIInputImageKey)
                        poly.setValue(CIVector(x: 0, y: 1, z: 0, w: 0), forKey: "inputRedCoefficients")
                        poly.setValue(CIVector(x: 0, y: 1, z: 0, w: 0), forKey: "inputGreenCoefficients")
                        poly.setValue(CIVector(x: 0, y: 1, z: 0, w: 0), forKey: "inputBlueCoefficients")
                        poly.setValue(CIVector(x: 0, y: 0, z: 3, w: -2), forKey: "inputAlphaCoefficients")
                        overlay = poly.outputImage ?? overlay
                    }
                    let edgeAlpha = CGFloat(0.6 * pow(Double(v), 0.88))
                    if let scaleA = CIFilter(name: "CIColorMatrix") {
                        scaleA.setValue(overlay, forKey: kCIInputImageKey)
                        scaleA.setValue(CIVector(x: 1, y: 0, z: 0, w: 0), forKey: "inputRVector")
                        scaleA.setValue(CIVector(x: 0, y: 1, z: 0, w: 0), forKey: "inputGVector")
                        scaleA.setValue(CIVector(x: 0, y: 0, z: 1, w: 0), forKey: "inputBVector")
                        scaleA.setValue(CIVector(x: 0, y: 0, z: 0, w: edgeAlpha), forKey: "inputAVector")
                        overlay = scaleA.outputImage ?? overlay
                    }
                    let overlayMTI = MTIImage(ciImage: overlay, isOpaque: false)
                    let over = MTIBlendFilter(blendMode: .normal)
                    over.inputImage = overlayMTI
                    over.inputBackgroundImage = finalImage
                    over.intensity = 1
                    over.outputAlphaType = .alphaIsOne
                    if let out = over.outputImage { finalImage = out }
                }
            }
        }

        // Film grain: per-pixel noise; Overlay + LinearLight for a refined look
        if state.grain > 0.0 {
            // Stronger response to the same slider value
            let baseK = max(0.0, min(1.0, state.grain * 20.0))
            let shaped = Float(pow(Double(baseK), 0.75))
            let extent = CGRect(origin: .zero, size: finalImage.size)
            if let sizedNoise = makeNoiseCIImage(extent: extent, grainSize: state.grainSize, seed: 0.0) {
                let amp = min(1.0, Float(0.30 + 0.65 * shaped))
                let noiseMTI = MTIImage(ciImage: sizedNoise, isOpaque: true)
                let mat = MTIColorMatrixFilter(); mat.inputImage = noiseMTI
                let darkBias: Float = max(0.0, min(0.07, 0.07 * shaped))
                mat.colorMatrix = MTIColorMatrix(
                    matrix: simd_float4x4(diagonal: SIMD4<Float>(amp, amp, amp, 1)),
                    bias: SIMD4<Float>(0.5 - 0.5 * amp - darkBias, 0.5 - 0.5 * amp - darkBias, 0.5 - 0.5 * amp - darkBias, 0)
                )
                let normalized = mat.outputImage ?? noiseMTI
                // Passo 1: Overlay
                let over = MTIBlendFilter(blendMode: .overlay)
                over.inputImage = normalized
                over.inputBackgroundImage = finalImage
                let overlayIntensity = min(1.0, shaped * 1.35)
                over.intensity = overlayIntensity
                over.outputAlphaType = .alphaIsOne
                if let out = over.outputImage { finalImage = out }

                // Passo 2: Linear Light (sutil)
                let amp2 = min(1.0, Float(0.10 + 0.25 * shaped))
                let mat2 = MTIColorMatrixFilter(); mat2.inputImage = noiseMTI
                let darkBias2b: Float = min(0.08, 0.08 * shaped)
                mat2.colorMatrix = MTIColorMatrix(
                    matrix: simd_float4x4(diagonal: SIMD4<Float>(amp2, amp2, amp2, 1)),
                    bias: SIMD4<Float>(0.5 - 0.5 * amp2 - darkBias2b, 0.5 - 0.5 * amp2 - darkBias2b, 0.5 - 0.5 * amp2 - darkBias2b, 0)
                )
                let normalized2 = mat2.outputImage ?? noiseMTI
                let lin = MTIBlendFilter(blendMode: .linearLight)
                lin.inputImage = normalized2
                lin.inputBackgroundImage = finalImage
                lin.intensity = min(1.0, overlayIntensity * 0.50)
                lin.outputAlphaType = .alphaIsOne
                if let out2 = lin.outputImage { finalImage = out2 }
            }
        }

        // Geração final do preview (sem duotone)
        do {
            let cgimg = try mtiContext.makeCGImage(from: finalImage)
            let uiImage = UIImage(cgImage: cgimg)
            DispatchQueue.main.async {
                self.previewImage = uiImage
            }
            os_log("[PhotoEditorViewModel] Preview image generated successfully.")
        } catch {
            os_log("[PhotoEditorViewModel] Failed to generate preview: %{public}@", String(describing: error))
        }
    }
}
