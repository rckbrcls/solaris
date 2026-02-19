//
//  PhotoEditorMainImage.swift
//  solaris
//
//  Created by Erick Barcelos on 30/05/25.
//

import SwiftUI

struct PhotoEditorMainImage: View {
    @Binding var image: UIImage?
    @Binding var filteredImage: UIImage?
    let matchedID: String
    let namespace: Namespace.ID
    @Binding var zoomScale: CGFloat
    @Binding var lastZoomScale: CGFloat
    
    // Calcula o tamanho exibido (aspectFit) para a imagem dentro do espaço disponível
    private func fittedSize(for imageSize: CGSize, in container: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0, container.width > 0, container.height > 0 else {
            return .zero
        }
        let wRatio = container.width / imageSize.width
        let hRatio = container.height / imageSize.height
        let scale = min(wRatio, hRatio)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let filtered = filteredImage {
                    VStack { Spacer(minLength: 0)
                        let size = fittedSize(for: filtered.size, in: proxy.size)
                        Image(uiImage: filtered)
                            .resizable()
                            .renderingMode(.original)
                            .interpolation(.high)
                            .antialiased(true)
                            .matchedGeometryEffect(id: matchedID, in: namespace, isSource: false)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: size.width, height: size.height)
                            .cornerRadius(20)
                            .zoomable(minZoomScale: 1, doubleTapZoomScale: 3)
                            .compositingGroup()
                            .padding(.bottom, 6)
                            .animation(.none, value: filtered)
                        Spacer(minLength: 0)
                    }
                } else if let original = image {
                    VStack { Spacer(minLength: 0)
                        let size = fittedSize(for: original.size, in: proxy.size)
                        Image(uiImage: original)
                            .resizable()
                            .renderingMode(.original)
                            .interpolation(.high)
                            .antialiased(true)
                            .matchedGeometryEffect(id: matchedID, in: namespace, isSource: false)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: size.width, height: size.height)
                            .cornerRadius(20)
                            .zoomable(minZoomScale: 1, doubleTapZoomScale: 3)
                            .compositingGroup()
                            .padding(.bottom, 6)
                        Spacer(minLength: 0)
                    }
                } else {
                    Text("Load or select an image to edit")
                        .font(.headline)
                        .foregroundColor(Color.textPlaceholder)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
                
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
        }
        .frame(maxHeight: .infinity)
    }
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}

// Removed dynamic container clipping to avoid jank in zoom
