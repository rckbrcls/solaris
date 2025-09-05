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

// Circular neutral icon style (match camera buttons)
private struct EditorIconButtonStyle: ViewModifier {
    var size: CGFloat = 44
    var background: Material = .ultraThinMaterial
    var foreground: Color = .primary

    func body(content: Content) -> some View {
        content
            .foregroundColor(foreground)
            .frame(width: size, height: size)
            .background(background, in: Circle())
            .overlay(
                Circle()
                    .stroke(Color.primary.opacity(0.2), lineWidth: 1)
            )
            .contentShape(Circle())
    }
}

private extension View {
    func editorIconStyle(size: CGFloat = 44, background: Material = .ultraThinMaterial) -> some View {
        self.modifier(EditorIconButtonStyle(size: size, background: background))
    }
}


struct PhotoEditorView: View {
    @State private var isSaving: Bool = false
    let namespace: Namespace.ID
    let matchedID: String
    var onFinishEditing: ((UIImage?, PhotoEditState?, [PhotoEditState], Bool) -> Void)? // (finalImage, ajustes, historico, salvou?)

    @State private var zoomScale: CGFloat = 1.0
    @State private var lastZoomScale: CGFloat = 1.0
    @State private var bottomSize: CGFloat = 0.25
    @State private var selectedCategory: String = "filters"
    @EnvironmentObject private var colorSchemeManager: ColorSchemeManager
    @StateObject private var viewModel: PhotoEditorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showSaveDiscardModal = false
    @State private var hasChanges = false
    @State private var showUndoToast = false
    @State private var adjustmentsHeight: CGFloat = 0
    @State private var imageHeight: CGFloat = 0
    @State private var undoToastWorkItem: DispatchWorkItem? = nil
    @State private var showSaveDiscardContent: Bool = false

    private var initialEditState: PhotoEditState
    private var initialHistory: [PhotoEditState]

    init(photo: UIImage, originalURL: URL, namespace: Namespace.ID, matchedID: String, initialEditState: PhotoEditState? = nil, initialHistory: [PhotoEditState] = [], onFinishEditing: ((UIImage?, PhotoEditState?, [PhotoEditState], Bool) -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: PhotoEditorViewModel(image: photo, originalImageURL: originalURL))
        self.namespace = namespace
        self.matchedID = matchedID
        self.onFinishEditing = onFinishEditing
        self.initialEditState = initialEditState ?? PhotoEditState()
        self.initialHistory = initialHistory
    }

    var body: some View {
        AnyView(rootView())
        // Modal padrão removido; usamos um overlay customizado
        .ignoresSafeArea(edges: .bottom)
        .onAppear {
            viewModel.editState = initialEditState
            viewModel.loadPersistentUndoHistory(initialHistory)
        }
        .onChange(of: viewModel.editState) { newValue in
            hasChanges = (newValue != initialEditState)
        }
        .onPreferenceChange(EditorAdjustmentsHeightKey.self) { h in
            withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                adjustmentsHeight = h
            }
        }
        .onPreferenceChange(EditorImageHeightKey.self) { h in
            imageHeight = h
        }
        .onChange(of: viewModel.lastUndoMessage) { msg in
            guard msg != nil else { return }
            // Cancel any previous scheduled hide to avoid early dismissal
            undoToastWorkItem?.cancel()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { showUndoToast = true }
            let work = DispatchWorkItem { [weak viewModel] in
                withAnimation(.easeOut(duration: 0.4)) { showUndoToast = false }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    viewModel?.clearLastUndoMessage()
                }
            }
            undoToastWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)
        }
        .onDisappear {
            undoToastWorkItem?.cancel()
            undoToastWorkItem = nil
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
        ZStack(alignment: .bottom) {
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
            .padding(.bottom, 16)
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
            .background(colorSchemeManager.secondaryColor)
            .padding(.bottom, max(6, geometry.safeAreaInsets.bottom))
            .frame(minHeight: adjustmentsHeight + max(6, geometry.safeAreaInsets.bottom))
            // Elimina qualquer hairline visual entre imagem e menu
            .offset(y: -0.5)
    }

    @ViewBuilder
    func categoryView() -> some View {
        if selectedCategory == "filters" {
            PhotoEditorFilters(
                editState: $viewModel.editState,
                registerUndo: { viewModel.registerUndoPoint() },
                baseImage: viewModel.previewThumbnailBase ?? viewModel.originalImage
            )
        } else if selectedCategory == "edit" {
            PhotoEditorAdjustments(
                contrast: $viewModel.editState.contrast,
                brightness: $viewModel.editState.brightness,
                exposure: $viewModel.editState.exposure,
                saturation: $viewModel.editState.saturation,
                vibrance: $viewModel.editState.vibrance,
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
                onBeginAdjust: { viewModel.beginInteractiveAdjustments() },
                onEndAdjust: { viewModel.endInteractiveAdjustments() }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if selectedCategory == "sticker" {
            Text("Sticker UI placeholder").padding()
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
    @ViewBuilder
    func undoToastView() -> some View {
        if showUndoToast, let msg = viewModel.lastUndoMessage {
            HStack(spacing: 8) {
                Image(systemName: "arrow.uturn.backward")
                    .foregroundColor(.primary)
                Text(msg)
                    .font(.footnote.bold())
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.primary.opacity(0.15), lineWidth: 1))
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
            LoadingOverlay(isVisible: $isSaving, title: "Salvando edição...")
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
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                showSaveDiscardModal = true
                            }
                            // Animate content in slightly after mounting
                            DispatchQueue.main.async {
                                withAnimation(.easeOut(duration: 0.22)) { showSaveDiscardContent = true }
                            }
                        } else {
                            onFinishEditing?(nil, nil, viewModel.undoStack, false)
                            dismiss()
                        }
                    }) {
                        Image(systemName: "xmark")
                            .editorIconStyle()
                    }
                Spacer()
                Button(action: {
                    let gen = UIImpactFeedbackGenerator(style: .light)
                    gen.impactOccurred()
                    if viewModel.canUndo {
                        viewModel.undoLastChange()
                    }
                }) {
                    Image(systemName: "arrow.uturn.backward")
                        .editorIconStyle()
                }
                .disabled(!viewModel.canUndo)
                .opacity(viewModel.canUndo ? 1.0 : 0.35)
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.5)
                        .onEnded { _ in
                            let gen = UIImpactFeedbackGenerator(style: .heavy)
                            gen.impactOccurred()
                            if let _ = viewModel.originalImage {
                                viewModel.resetPreviewBases()
                                zoomScale = 1.0
                                lastZoomScale = 1.0
                                viewModel.resetAllEditsToClean()
                            }
                        }
                )
                Button(action: {
                    let gen = UIImpactFeedbackGenerator(style: .light)
                    gen.impactOccurred()
                    if viewModel.canRedo {
                        viewModel.redoLastChange()
                    }
                }) {
                    Image(systemName: "arrow.uturn.forward")
                        .editorIconStyle()
                }
                .disabled(!viewModel.canRedo)
                .opacity(viewModel.canRedo ? 1.0 : 0.35)
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.5)
                        .onEnded { _ in
                            let gen = UIImpactFeedbackGenerator(style: .heavy)
                            gen.impactOccurred()
                            if viewModel.canRedo {
                                viewModel.redoAllChanges()
                            }
                        }
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            Spacer()
        }
    }

    // Custom modal for save/discard with our app style
    var saveDiscardOverlay: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .opacity(showSaveDiscardContent ? 1.0 : 0.0)
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.22)) { showSaveDiscardContent = false }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.23) {
                        showSaveDiscardModal = false
                    }
                }
            // Card
            VStack(spacing: 14) {
                Text("Salvar alterações?")
                    .font(.headline)
                Text("Você deseja salvar as alterações feitas nesta edição?")
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
                        Text("Salvar")
                            .font(.body.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .foregroundColor(.white)
                    }
                    Button(action: {
                        withAnimation(.easeOut(duration: 0.22)) { showSaveDiscardContent = false }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.23) {
                            onFinishEditing?(nil, nil, viewModel.undoStack, false)
                            dismiss()
                        }
                    }) {
                        Text("Descartar")
                            .font(.body.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.red, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .foregroundColor(.white)
                    }
                    Button(action: {
                        withAnimation(.easeOut(duration: 0.22)) { showSaveDiscardContent = false }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.23) {
                            showSaveDiscardModal = false
                        }
                    }) {
                        Text("Cancelar")
                            .font(.body.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.15), lineWidth: 1))
                            .foregroundColor(.primary)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 360)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.12), lineWidth: 1))
            .shadow(radius: 12)
            .padding(.horizontal, 24)
            .opacity(showSaveDiscardContent ? 1.0 : 0.0)
            .scaleEffect(showSaveDiscardContent ? 1.0 : 0.96)
            .animation(.easeOut(duration: 0.22), value: showSaveDiscardContent)
            .onAppear { withAnimation(.easeOut(duration: 0.22)) { showSaveDiscardContent = true } }
        }
    }

    func performSaveAndExit() {
        showSaveDiscardModal = false
        isSaving = true
        DispatchQueue.global(qos: .userInitiated).async {
            let finalImage = viewModel.generateFinalImage()
            DispatchQueue.main.async {
                onFinishEditing?(finalImage, viewModel.editState, viewModel.undoStack, true)
                viewModel.editState = initialEditState
                isSaving = false
                dismiss()
            }
        }
    }
}

#Preview {
    ContentView()
}
