import SwiftUI
import UIKit


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

    private var initialEditState: PhotoEditState

    init(photo: UIImage, namespace: Namespace.ID, matchedID: String, initialEditState: PhotoEditState? = nil, onFinishEditing: ((UIImage?, PhotoEditState?, Bool) -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: PhotoEditorViewModel(image: photo))
        self.namespace = namespace
        self.matchedID = matchedID
        self.onFinishEditing = onFinishEditing
        self.initialEditState = initialEditState ?? PhotoEditState()
    }

    var body: some View {
        ZStack {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    PhotoEditorMainImage(
                        image: $viewModel.previewBase,
                        filteredImage: $viewModel.previewImage,
                        matchedID: matchedID,
                        namespace: namespace,
                        zoomScale: $zoomScale,
                        lastZoomScale: $lastZoomScale
                    )
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
                                    colorTintFactor: $viewModel.editState.colorTintFactor
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
                }
            }
            if isSaving {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                ProgressView("Salvando...")
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .foregroundColor(.white)
                    .padding(40)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(16)
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
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    if hasChanges {
                        showSaveDiscardModal = true
                    } else {
                        onFinishEditing?(nil, nil, false)
                        dismiss()
                    }
                }) {
                    Label("Voltar", systemImage: "chevron.left")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    // Restaura a imagem original e reseta todos os ajustes
                    if let original = viewModel.originalImage {
                        viewModel.previewBase = original.resizeToFit(maxSize: 1024)
                        viewModel.editState = PhotoEditState() // Reset total
                    }
                }) {
                    Label("Reverter", systemImage: "arrow.uturn.backward")
                }
            }
        }
    }
}

#Preview {
    ContentView()
}

