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
    var onFinishEditing: ((UIImage?, PhotoEditState?, Bool) -> Void)? // (finalImage, ajustes, salvou?)

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

    private var initialEditState: PhotoEditState

    init(photo: UIImage, originalURL: URL, namespace: Namespace.ID, matchedID: String, initialEditState: PhotoEditState? = nil, onFinishEditing: ((UIImage?, PhotoEditState?, Bool) -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: PhotoEditorViewModel(image: photo, originalImageURL: originalURL))
        self.namespace = namespace
        self.matchedID = matchedID
        self.onFinishEditing = onFinishEditing
        self.initialEditState = initialEditState ?? PhotoEditState()
    }

    var body: some View {
        ZStack {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    ZStack(alignment: .bottom) {
                        PhotoEditorMainImage(
                            // Show the original image when there are no filters applied yet,
                            // so the initial view is always full-quality.
                            image: Binding(get: { viewModel.originalImage }, set: { _ in }),
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
                            .padding(.bottom, 8)
                            .transition(
                                .asymmetric(
                                    insertion: .scale(scale: 0.9).combined(with: .opacity),
                                    removal: .opacity
                                )
                            )
                        }
                    }
                    VStack{
                        ZStack {
                            switch selectedCategory {
                            case "filters":
                                Text("Filtros desabilitados nesta versão").padding()
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                            case "edit":
                                PhotoEditorAdjustments(
                                    contrast: $viewModel.editState.contrast,
                                    brightness: $viewModel.editState.brightness,
                                    exposure: $viewModel.editState.exposure,
                                    saturation: $viewModel.editState.saturation,
                                    vibrance: $viewModel.editState.vibrance,
                                    colorInvert: $viewModel.editState.colorInvert,
                                    pixelateAmount: $viewModel.editState.pixelateAmount,
                                    colorTint: $viewModel.editState.colorTint,
                                    colorTintSecondary: $viewModel.editState.colorTintSecondary,
                                    isDualToneActive: $viewModel.editState.isDualToneActive,
                                    colorTintIntensity: $viewModel.editState.colorTintIntensity,
                                    colorTintFactor: $viewModel.editState.colorTintFactor,
                                    onBeginAdjust: { viewModel.beginInteractiveAdjustments() },
                                    onEndAdjust: { viewModel.endInteractiveAdjustments() }
                                )
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                            case "sticker":
                                Text("Sticker UI placeholder").padding()
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                            default:
                                EmptyView()
                            }
                        }
                        .animation(.easeOut(duration: 0.28), value: selectedCategory)
                        PhotoEditorToolbar(
                            selectedCategory: $selectedCategory,
                            bottomSize: $bottomSize
                        )
                        .padding(.bottom, 20)
                    }
                    .padding(.vertical)
                    // Painel inferior usa cor de fundo que contrasta com o texto primário
                    .background(colorSchemeManager.secondaryColor)
                    .padding(.bottom, geometry.safeAreaInsets.bottom)
                    // Medir altura do painel de ajustes para posicionar o toast acima dele
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(key: EditorAdjustmentsHeightKey.self, value: proxy.size.height + geometry.safeAreaInsets.bottom)
                        }
                    )
                }
            }
            LoadingOverlay(isVisible: $isSaving, title: "Salvando edição...")
            // toast agora é renderizado dentro da área da imagem
            // Top controls (match camera style)
            VStack {
                HStack {
                    Button(action: {
                        if hasChanges {
                            showSaveDiscardModal = true
                        } else {
                            onFinishEditing?(nil, nil, false)
                            dismiss()
                        }
                    }) {
                        Image(systemName: "xmark")
                            .editorIconStyle()
                    }
                    Spacer()
                    Button(action: {
                        // Tap: desfaz apenas a última alteração registrada
                        let gen = UIImpactFeedbackGenerator(style: .light)
                        gen.impactOccurred()
                        if viewModel.canUndo {
                            viewModel.undoLastChange()
                        } else if viewModel.editState != PhotoEditState() {
                            // Sem histórico (ex.: nova sessão), mas há alterações: reset limpo
                            viewModel.resetAllEditsToClean()
                        } else {
                            // Nada a desfazer: não mostrar toast indevido
                        }
                    }) {
                        Image(systemName: "arrow.uturn.backward")
                            .editorIconStyle()
                    }
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.5)
                            .onEnded { _ in
                                // Long press: desfaz tudo (reset total)
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
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                Spacer()
            }
        }
        // Modal de salvar/descartar ao tentar voltar
        .confirmationDialog("Salvar alterações?", isPresented: $showSaveDiscardModal, titleVisibility: .visible) {
            Button("Salvar", role: .none) {
                isSaving = true
                DispatchQueue.global(qos: .userInitiated).async {
                    let finalImage = viewModel.generateFinalImage()
                    DispatchQueue.main.async {
                        onFinishEditing?(finalImage, viewModel.editState, true)
                        viewModel.editState = initialEditState
                        isSaving = false
                        dismiss()
                    }
                }
            }
            Button("Descartar", role: .destructive) {
                onFinishEditing?(nil, nil, false)
                dismiss()
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Você deseja salvar as alterações feitas nesta edição?")
        }
        .ignoresSafeArea(edges: .bottom)
        .onAppear {
            viewModel.editState = initialEditState
        }
        .onChange(of: viewModel.editState) { newValue in
            hasChanges = (newValue != initialEditState)
        }
        .onPreferenceChange(EditorAdjustmentsHeightKey.self) { h in
            adjustmentsHeight = h
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

#Preview {
    ContentView()
}
