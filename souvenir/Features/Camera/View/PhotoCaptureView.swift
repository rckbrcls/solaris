import SwiftUI
import AVFoundation
import Foundation
import UIKit  // Adicionado para garantir que UIImage está disponível

// Estilo consistente para ícones redondos na câmera
private struct CameraIconButtonStyle: ViewModifier {
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
    func cameraIconStyle(size: CGFloat = 44, background: Material = .ultraThinMaterial) -> some View {
        self.modifier(CameraIconButtonStyle(size: size, background: background))
    }
}

struct PhotoCaptureView: View {
    var onPhotoCaptured: (UIImage) -> Void
    @State private var capturedImage: UIImage? = nil
    @State private var isPhotoTaken: Bool = false
    @State private var isFlashOn: Bool = false
    @State private var isGridOn: Bool = false
    @State private var zoomFactor: CGFloat = 1.0
    // Aspect ratio selection
    enum AspectOption: String, CaseIterable, Identifiable {
        case original = "Original"
        case square = "1:1"
        case ratio4x3 = "4:3"
        case ratio3x2 = "3:2"
        case ratio16x9 = "16:9"
        case ratio9x16 = "9:16"
        var id: String { rawValue }
        // Returns width:height factors (portrait-aware)
        var width: CGFloat {
            switch self {
            case .original: return 0 // handled specially
            case .square: return 1
            case .ratio4x3: return 4
            case .ratio3x2: return 3
            case .ratio16x9: return 9
            case .ratio9x16: return 9
            }
        }
        var height: CGFloat {
            switch self {
            case .original: return 0
            case .square: return 1
            case .ratio4x3: return 3
            case .ratio3x2: return 2
            case .ratio16x9: return 16 // portrait framing of 16:9
            case .ratio9x16: return 16
            }
        }
    }
    @State private var selectedAspect: AspectOption = .ratio4x3
    @State private var showAspectMenu: Bool = false
    @Environment(\.dismiss) var dismiss
    @State private var isDraggingDismiss: Bool = false
    
    var body: some View {
        ZStack {
            Color(UIColor.systemBackground).ignoresSafeArea()
            VStack {
                ZStack {
                    let previewW = UIScreen.main.bounds.width
                    let previewH: CGFloat = {
                        switch selectedAspect {
                        case .original:
                            return previewW * 4.0 / 3.0 // default preview 4:3, saved will use sensor crop later
                        default:
                            return previewW * (selectedAspect.height / max(1, selectedAspect.width))
                        }
                    }()
                    CameraPreview(capturedImage: $capturedImage, isPhotoTaken: $isPhotoTaken, isFlashOn: $isFlashOn, zoomFactor: $zoomFactor)
                        .allowsHitTesting(!isDraggingDismiss)
                        .frame(width: previewW, height: previewH)
                        .clipped()
                        .cornerRadius(20)
                
                if isGridOn {
                    GeometryReader { geo in
                        Path { path in
                            let width = geo.size.width
                            let height = geo.size.height
                            let columnWidth = width / 3
                            let rowHeight = height / 3
                            path.move(to: CGPoint(x: columnWidth, y: 0))
                            path.addLine(to: CGPoint(x: columnWidth, y: height))
                            path.move(to: CGPoint(x: 2 * columnWidth, y: 0))
                            path.addLine(to: CGPoint(x: 2 * columnWidth, y: height))
                            path.move(to: CGPoint(x: 0, y: rowHeight))
                            path.addLine(to: CGPoint(x: width, y: rowHeight))
                            path.move(to: CGPoint(x: 0, y: 2 * rowHeight))
                            path.addLine(to: CGPoint(x: width, y: 2 * rowHeight))
                        }
                        .stroke(Color.white.opacity(0.7), lineWidth: 1)
                    }
                }
                
                VStack(spacing: 8) {
                    HStack {
                        Button(action: {
                            dismiss()
                        }) {
                            Image(systemName: "xmark")
                                .cameraIconStyle()
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    Spacer()
                    HStack(alignment: .center) {
                        Spacer()
                        
                        Button(action: {
                            NotificationCenter.default.post(name: .capturePhoto, object: nil)
                        }) {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 70, height: 70)
                                .overlay(
                                    Circle()
                                        .stroke(.thinMaterial, lineWidth: 2)
                                )
                                .shadow(radius: 5)
                        }
                        .padding(20)
                        
                        Spacer()
                        // Additional button or user-selected functionality can be placed here
                    }
                }
                .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.width * 16.0 / 9.0)
            }
            
            // Bottom overlay controls: grid, flash, aspect, switch
            VStack {
                if showAspectMenu {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(AspectOption.allCases) { opt in
                                Button(action: { withAnimation(.easeOut(duration: 0.15)) { selectedAspect = opt; showAspectMenu = false } }) {
                                    Text(opt.rawValue)
                                        .font(.caption.bold())
                                        .foregroundColor(selectedAspect == opt ? .white : .primary)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(
                                            selectedAspect == opt ? Color.accentColor : Color.primary.opacity(0.08)
                                        )
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                HStack(alignment: .center) {
                    Button(action: { isGridOn.toggle() }) {
                        Image(systemName: isGridOn ? "square.grid.3x3.fill" : "square.grid.3x3")
                            .cameraIconStyle()
                    }
                    Spacer()
                    Button(action: { isFlashOn.toggle() }) {
                        Image(systemName: isFlashOn ? "bolt.fill" : "bolt")
                            .cameraIconStyle()
                    }
                    Spacer()
                    Button(action: { withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) { showAspectMenu.toggle() } }) {
                        HStack(spacing: 6) {
                            Image(systemName: "rectangle.split.2x1")
                            Text(selectedAspect.rawValue)
                                .font(.caption)
                        }
                        .cameraIconStyle()
                    }
                    Spacer()
                    Button(action: { NotificationCenter.default.post(name: .switchCamera, object: nil) }) {
                        Image(systemName: "camera.rotate")
                            .cameraIconStyle()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            
        }
            .navigationBarBackButtonHidden(true)
            .onChange(of: capturedImage) { newImage in
                if let image = newImage {
                    let fixed = image.fixOrientation()
                    let cropped = cropToSelectedAspect(fixed, aspect: selectedAspect)
                    onPhotoCaptured(cropped)
                }
            }
            .padding(.top)
            .highPriorityGesture(
                DragGesture(minimumDistance: 20)
                    .onChanged { value in
                        // Apenas sinaliza que está arrastando para evitar conflitos de gesto do preview
                        if value.translation.height > 0 { isDraggingDismiss = true }
                    }
                    .onEnded { value in
                        defer { isDraggingDismiss = false }
                        let threshold: CGFloat = 120
                        if value.translation.height > threshold {
                            // Não anima o conteúdo; apenas faz o mesmo dismiss do botão (animação do sistema)
                            dismiss()
                        }
                    }
            )
            .tint(.primary)
        }
    }
}

#Preview {
    PhotoCaptureView(onPhotoCaptured: { _ in })
}

// MARK: - Helpers
extension PhotoCaptureView {
    private func cropToSelectedAspect(_ image: UIImage, aspect: AspectOption) -> UIImage {
        guard aspect != .original else { return image }
        let w = image.size.width
        let h = image.size.height
        let targetW = aspect.width
        let targetH = aspect.height
        guard targetW > 0, targetH > 0 else { return image }
        let targetRatio = targetW / targetH
        let imageRatio = w / h
        var cropRect: CGRect
        if imageRatio > targetRatio {
            // image is wider than target; crop width
            let newW = h * targetRatio
            cropRect = CGRect(x: (w - newW) / 2.0, y: 0, width: newW, height: h)
        } else {
            // image is taller than target; crop height
            let newH = w / targetRatio
            cropRect = CGRect(x: 0, y: (h - newH) / 2.0, width: w, height: newH)
        }
        guard let cg = image.cgImage?.cropping(to: cropRect.integral) else { return image }
        // Return cropped (keeping original scale/orientation as .up)
        return UIImage(cgImage: cg, scale: image.scale, orientation: .up)
    }
}
