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
    @Environment(\.dismiss) var dismiss
    @State private var isDraggingDismiss: Bool = false
    
    var body: some View {
        ZStack {
            Color(UIColor.systemBackground).ignoresSafeArea()
            VStack {
                ZStack {
                    CameraPreview(capturedImage: $capturedImage, isPhotoTaken: $isPhotoTaken, isFlashOn: $isFlashOn, zoomFactor: $zoomFactor)
                        .allowsHitTesting(!isDraggingDismiss)
                        .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.width * 16.0 / 9.0)
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
                
                VStack {
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
            
            HStack(alignment: .center) {
                Button(action: {
                    isGridOn.toggle()
                }) {
                    Image(systemName: isGridOn ? "square.grid.3x3.fill" : "square.grid.3x3")
                        .cameraIconStyle()
                }
                
                Spacer()
                
                Button(action: {
                    isFlashOn.toggle()
                }) {
                    Image(systemName: isFlashOn ? "bolt.fill" : "bolt")
                        .cameraIconStyle()
                }
                
                Spacer()
                
                Button(action: {
                    NotificationCenter.default.post(name: .switchCamera, object: nil)
                }) {
                    Image(systemName: "camera.rotate")
                        .cameraIconStyle()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            
                Spacer()
            }
            .navigationBarBackButtonHidden(true)
            .onChange(of: capturedImage) { newImage in
                if let image = newImage {
                    onPhotoCaptured(image.fixOrientation())
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
