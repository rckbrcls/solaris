import SwiftUI
import UIKit

// PreferenceKey para medir a altura do painel de ajustes
private struct EditorAdjustmentsHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// PreferenceKey para medir a altura da área da imagem
private struct EditorImageHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// Icon button style consolidated in Shared/Components/GlassIconStyle.swift


struct PhotoEditorView: View {
    @State private var isSaving: Bool = false
    let namespace: Namespace.ID
    let matchedID: String
    var onFinishEditing: ((UIImage?, PhotoEditState?, PhotoEditState?, [PhotoEditState], Bool) -> Void)? // (finalImage, ajustes, baseFiltro, historico, salvou?)

    @State private var zoomScale: CGFloat = 1.0
    @State private var lastZoomScale: CGFloat = 1.0
    @State private var bottomSize: CGFloat = 0.25
    @State private var selectedCategory: String = "filters"
    @State private var viewModel: PhotoEditorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showSaveDiscardModal = false
    @State private var hasChanges = false
    @State private var showUndoToast = false
    @State private var adjustmentsHeight: CGFloat = 0
    @State private var imageHeight: CGFloat = 0
    @State private var undoToastWorkItem: DispatchWorkItem? = nil
    @State private var showSaveDiscardContent: Bool = false
    @State private var showExportSheet = false
    @State private var exportItems: [Any] = []
    @State private var showSaveFilterAlert = false
    @State private var saveFilterName = ""

    private var initialEditState: PhotoEditState
    private var initialBaseFilterState: PhotoEditState
    private var initialHistory: [PhotoEditState]

    init(photo: UIImage, originalURL: URL, namespace: Namespace.ID, matchedID: String, photoId: String = "", initialEditState: PhotoEditState? = nil, initialBaseFilterState: PhotoEditState? = nil, initialHistory: [PhotoEditState] = [], onFinishEditing: ((UIImage?, PhotoEditState?, PhotoEditState?, [PhotoEditState], Bool) -> Void)? = nil) {
        let seed = Float(abs(photoId.hashValue) % 65536) / 65536.0
        let vm = PhotoEditorViewModel(image: photo, originalImageURL: originalURL, grainSeed: seed)
        _viewModel = State(initialValue: vm)
        self.namespace = namespace
        self.matchedID = matchedID
        self.onFinishEditing = onFinishEditing
        self.initialEditState = initialEditState ?? PhotoEditState()
        self.initialBaseFilterState = initialBaseFilterState ?? PhotoEditState()
        self.initialHistory = initialHistory
    }

    var body: some View {
        AnyView(rootView())
        // Modal padrão removido; usamos um overlay customizado
        .ignoresSafeArea(edges: .bottom)
        .onAppear {
            viewModel.editState = initialEditState
            viewModel.baseFilterState = initialBaseFilterState
            viewModel.loadPersistentUndoHistory(initialHistory)
            // Ensure hasChanges reflects differences from initial states (edit + base filter)
            hasChanges = (viewModel.editState != initialEditState) || (viewModel.baseFilterState != initialBaseFilterState)
        }
        .onChange(of: viewModel.editState) {
            hasChanges = (viewModel.editState != initialEditState) || (viewModel.baseFilterState != initialBaseFilterState)
            // Only trigger preview from here during interactive adjustments (slider drags),
            // since ViewModel methods (undo, filter apply, etc.) already call requestPreviewUpdate().
            if viewModel.isInteracting {
                viewModel.requestPreviewUpdate()
            }
        }
        .onChange(of: viewModel.baseFilterState) {
            hasChanges = (viewModel.editState != initialEditState) || (viewModel.baseFilterState != initialBaseFilterState)
        }
        .onPreferenceChange(EditorAdjustmentsHeightKey.self) { h in
            withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                adjustmentsHeight = h
            }
        }
        .onPreferenceChange(EditorImageHeightKey.self) { h in
            imageHeight = h
        }
        .onChange(of: viewModel.lastUndoMessage) {
            guard viewModel.lastUndoMessage != nil else { return }
            // Cancel any previous scheduled hide to avoid early dismissal
            undoToastWorkItem?.cancel()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { showUndoToast = true }
            let work = DispatchWorkItem {
                withAnimation(.easeOut(duration: 0.4)) { showUndoToast = false }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [viewModel] in
                    viewModel.clearLastUndoMessage()
                }
            }
            undoToastWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)
        }
        .onDisappear {
            undoToastWorkItem?.cancel()
            undoToastWorkItem = nil
        }
        .sheet(isPresented: $showExportSheet) {
            ActivityView(activityItems: exportItems)
        }
        .alert(String(localized: "Save Filter"), isPresented: $showSaveFilterAlert) {
            TextField(String(localized: "Filter name"), text: $saveFilterName)
            Button(String(localized: "Save")) {
                let name = saveFilterName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                SavedFiltersStore.shared.addFilter(name: name, state: viewModel.combinedState)
                let gen = UINotificationFeedbackGenerator()
                gen.notificationOccurred(.success)
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "Give your current edit a name to reuse it as a filter preset."))
        }
        .toolbar { } // remove default toolbar items
    }
}

// MARK: - Subviews
private extension PhotoEditorView {
    // Reduce inference load by lifting complex bindings
    var originalImageBinding: Binding<UIImage?> {
        Binding<UIImage?>(get: { viewModel.originalImage }, set: { _ in })
    }
    var imageContainer: some View {
        @Bindable var viewModel = self.viewModel
        return ZStack(alignment: .bottom) {
            PhotoEditorMainImage(
                image: originalImageBinding,
                filteredImage: $viewModel.previewImage,
                matchedID: matchedID,
                namespace: namespace,
                zoomScale: $zoomScale,
                lastZoomScale: $lastZoomScale
            )
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: EditorImageHeightKey.self, value: proxy.size.height)
                }
            )
            .overlay(undoToastView().padding(.bottom, 8), alignment: .bottom)
        }
    }

    @ViewBuilder
    func adjustmentsContainer(geometry: GeometryProxy) -> some View {
        // Build the content first and measure its intrinsic height
        let content = VStack(spacing: 8) {
            categoryView()
                .animation(.easeOut(duration: 0.28), value: selectedCategory)
            PhotoEditorToolbar(
                selectedCategory: $selectedCategory,
                bottomSize: $bottomSize
            )
            .padding(.bottom, 18)
        }
        .padding(.top, 10)
        .padding(.bottom, 6)
        
        // Measure only the intrinsic content (before adding outer background/padding)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: EditorAdjustmentsHeightKey.self, value: proxy.size.height)
            }
        )

        content
            .padding(.bottom, max(6, geometry.safeAreaInsets.bottom))
            .frame(minHeight: adjustmentsHeight + max(6, geometry.safeAreaInsets.bottom))
            // Elimina qualquer hairline visual entre imagem e menu
            .offset(y: -0.5)
    }

    @ViewBuilder
    func categoryView() -> some View {
        @Bindable var viewModel = self.viewModel
        if selectedCategory == "filters" {
            PhotoEditorFilters(
                editState: $viewModel.editState,
                registerUndo: { viewModel.registerUndoPoint() },
                baseImage: viewModel.previewThumbnailBase ?? viewModel.originalImage,
                applyBaseFilter: { filterState in viewModel.applyBaseFilter(filterState) },
                applyCompleteFilter: { filterState in viewModel.applySliderFilter(filterState) },
                isFilterApplied: { filterState in viewModel.isFilterApplied(filterState) },
                isFilterAppliedToSliders: { filterState in viewModel.isFilterAppliedToSliders(filterState) },
                isFilterAppliedAsBase: { filterState in viewModel.isFilterAppliedAsBase(filterState) },
                hasFilterCombination: { viewModel.hasFilterCombination },
                getSliderFilter: { viewModel.getSliderFilter() },
                getBaseFilter: { viewModel.getBaseFilter() }
            )
        } else if selectedCategory == "edit" {
            PhotoEditorAdjustments(
                contrast: $viewModel.editState.contrast,
                brightness: $viewModel.editState.brightness,
                exposure: $viewModel.editState.exposure,
                saturation: $viewModel.editState.saturation,
                vibrance: $viewModel.editState.vibrance,
                fade: $viewModel.editState.fade,
                vignette: $viewModel.editState.vignette,
                colorInvert: $viewModel.editState.colorInvert,
                pixelateAmount: $viewModel.editState.pixelateAmount,
                grain: $viewModel.editState.grain,
                sharpen: $viewModel.editState.sharpen,
                clarity: $viewModel.editState.clarity,
                colorTint: $viewModel.editState.colorTint,
                colorTintSecondary: $viewModel.editState.colorTintSecondary,
                isDualToneActive: $viewModel.editState.isDualToneActive,
                colorTintIntensity: $viewModel.editState.colorTintIntensity,
                colorTintFactor: $viewModel.editState.colorTintFactor,
                skinTone: $viewModel.editState.skinTone,
                onBeginAdjust: { viewModel.beginInteractiveAdjustments() },
                onEndAdjust: { viewModel.endInteractiveAdjustments() }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if selectedCategory == "export" {
            exportSection
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    var exportSection: some View {
        VStack(spacing: 10) {
            Text(String(localized: "Export photo"))
                .font(.subheadline.bold())
                .foregroundColor(Color.textPrimary)

            HStack(spacing: 10) {
                Button(action: {
                    saveFilterName = ""
                    showSaveFilterAlert = true
                }) {
                    Label(String(localized: "Save filter"), systemImage: "camera.filters")
                        .font(.footnote.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.actionAccent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundColor(Color.textOnAccent)
                }
                .disabled(!viewModel.hasAnyFilterApplied)
                .opacity(viewModel.hasAnyFilterApplied ? 1.0 : 0.5)

                Button(action: { performShareExport() }) {
                    Label(String(localized: "Share"), systemImage: "square.and.arrow.up")
                        .font(.footnote.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .liquidGlass(
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous),
                            borderColor: Color.borderMedium
                        )
                        .foregroundColor(Color.textPrimary)
                }
            }
            .disabled(isSaving)
        }
        .padding(.horizontal)
        .padding(.top, 6)
    }

    @ViewBuilder
    func undoToastView() -> some View {
        if showUndoToast, let msg = viewModel.lastUndoMessage {
            HStack(spacing: 8) {
                Image(systemName: "arrow.uturn.backward")
                    .foregroundColor(Color.textPrimary)
                Text(msg)
                    .font(.footnote.bold())
                    .foregroundColor(Color.textPrimary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .liquidGlass(
                in: Capsule(),
                borderColor: Color.borderMedium
            )
            .shadow(radius: 3)
            .transition(.asymmetric(insertion: .scale(scale: 0.9).combined(with: .opacity), removal: .opacity))
        }
    }

    // Root view extracted to reduce type-checking pressure
    func rootView() -> some View {
        ZStack {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    imageContainer
                    adjustmentsContainer(geometry: geometry)
                }
            }
            LoadingOverlay(isVisible: $isSaving, title: String(localized: "Saving edit..."))
            topControls
            // Custom Save/Discard overlay
            if showSaveDiscardModal { saveDiscardOverlay }
        }
    }

    var topControls: some View {
        VStack {
            HStack {
                    Button(action: {
                        if hasChanges {
                            withAnimation(.editorSpring) {
                                showSaveDiscardModal = true
                            }
                            // Animate content in slightly after mounting
                            DispatchQueue.main.async {
                                withAnimation(.editorDismiss) { showSaveDiscardContent = true }
                            }
                        } else {
                            // Converte CompleteEditState de volta para PhotoEditState para compatibilidade
                            let editHistory = viewModel.undoStack.map { $0.editState }
                            onFinishEditing?(nil, nil, nil, editHistory, false)
                            dismiss()
                        }
                    }) {
                        Image(systemName: "xmark")
                            .glassIconStyle(size: 36)
                    }
                    .accessibilityLabel(String(localized: "Close editor"))
                Spacer()
                Button(action: {
                    Haptics.light()
                    if viewModel.canUndo {
                        viewModel.undoLastChange()
                    }
                }) {
                    Image(systemName: "arrow.uturn.backward")
                        .glassIconStyle(size: 36)
                }
                .accessibilityLabel(String(localized: "Undo"))
                .disabled(!viewModel.canUndo)
                .opacity(viewModel.canUndo ? 1.0 : 0.35)
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.5)
                        .onEnded { _ in
                            Haptics.heavy()
                            viewModel.resetPreviewBases()
                            zoomScale = 1.0
                            lastZoomScale = 1.0
                            viewModel.resetAllEditsToClean()
                        }
                )
                Button(action: {
                    Haptics.light()
                    if viewModel.canRedo {
                        viewModel.redoLastChange()
                    }
                }) {
                    Image(systemName: "arrow.uturn.forward")
                        .glassIconStyle(size: 36)
                }
                .accessibilityLabel(String(localized: "Redo"))
                .disabled(!viewModel.canRedo)
                .opacity(viewModel.canRedo ? 1.0 : 0.35)
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.5)
                        .onEnded { _ in
                            Haptics.heavy()
                            if viewModel.canRedo {
                                viewModel.redoAllChanges()
                            }
                        }
                )
            }
            .padding(.horizontal, 12)
            Spacer()
        }
    }

    // Custom modal for save/discard with our app style
    var saveDiscardOverlay: some View {
        ZStack {
            // Backdrop
            Color.overlayDimming
                .ignoresSafeArea()
                .opacity(showSaveDiscardContent ? 1.0 : 0.0)
                .onTapGesture {
                    withAnimation(.editorDismiss) { showSaveDiscardContent = false }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.23) {
                        showSaveDiscardModal = false
                    }
                }
            // Card
            VStack(spacing: 14) {
                Text(String(localized: "Save changes?"))
                    .font(.headline)
                Text(String(localized: "Do you want to save the changes to this edit?"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                VStack(spacing: 10) {
                    Button(action: {
                        withAnimation(.easeOut(duration: 0.12)) { showSaveDiscardContent = false }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                            performSaveAndExit()
                        }
                    }) {
                        Text(String(localized: "Save"))
                            .font(.body.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.actionAccent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .foregroundColor(Color.textOnAccent)
                    }
                    Button(action: {
                        withAnimation(.editorDismiss) { showSaveDiscardContent = false }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.23) {
                            // Converte CompleteEditState de volta para PhotoEditState para compatibilidade
                            let editHistory = viewModel.undoStack.map { $0.editState }
                            onFinishEditing?(nil, nil, nil, editHistory, false)
                            dismiss()
                        }
                    }) {
                        Text(String(localized: "Discard"))
                            .font(.body.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.actionDestructive, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .foregroundColor(Color.textOnAccent)
                    }
                    Button(action: {
                        withAnimation(.editorDismiss) { showSaveDiscardContent = false }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.23) {
                            showSaveDiscardModal = false
                        }
                    }) {
                        Text(String(localized: "Cancel"))
                            .font(.body.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .liquidGlass(
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous),
                                borderColor: Color.borderMedium
                            )
                            .foregroundColor(Color.textPrimary)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 360)
            .liquidGlass(
                in: RoundedRectangle(cornerRadius: 16, style: .continuous),
                borderColor: Color.borderMedium
            )
            .shadow(radius: 12)
            .padding(.horizontal, 24)
            .opacity(showSaveDiscardContent ? 1.0 : 0.0)
            .scaleEffect(showSaveDiscardContent ? 1.0 : 0.96)
            .animation(.editorDismiss, value: showSaveDiscardContent)
            .onAppear { withAnimation(.editorDismiss) { showSaveDiscardContent = true } }
        }
    }

    func performSaveAndExit() {
        showSaveDiscardModal = false
        isSaving = true
        let vm = viewModel
        Task {
            let finalImage = await Task.detached(priority: .userInitiated) {
                vm.generateFinalImage()
            }.value
            let editHistory = viewModel.undoStack.map { $0.editState }
            onFinishEditing?(finalImage, viewModel.editState, viewModel.baseFilterState, editHistory, true)
            viewModel.editState = initialEditState
            isSaving = false
            dismiss()
        }
    }

    func performShareExport() {
        isSaving = true
        let vm = viewModel
        Task {
            let finalImage = await Task.detached(priority: .userInitiated) {
                vm.generateFinalImage()
            }.value
            isSaving = false
            guard let finalImage else { return }
            exportItems = [finalImage]
            showExportSheet = true
        }
    }
}

#Preview {
    HomeView()
}
