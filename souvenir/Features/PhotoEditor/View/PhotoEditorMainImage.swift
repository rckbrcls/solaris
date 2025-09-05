//
//  PhotoEditorMainImage.swift
//  souvenir
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

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let filtered = filteredImage {
                    VStack { Spacer(minLength: 0)
                        Image(uiImage: filtered)
                            .resizable()
                            .renderingMode(.original)
                            .interpolation(.high)
                            .antialiased(true)
                            .matchedGeometryEffect(id: matchedID, in: namespace, isSource: false)
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: proxy.size.width)
                            .zoomable(minZoomScale: 1, doubleTapZoomScale: 3)
                            .animation(.none, value: filtered)
                        Spacer(minLength: 0)
                    }
                } else if let original = image {
                    VStack { Spacer(minLength: 0)
                        Image(uiImage: original)
                            .resizable()
                            .renderingMode(.original)
                            .interpolation(.high)
                            .antialiased(true)
                            .matchedGeometryEffect(id: matchedID, in: namespace, isSource: false)
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: proxy.size.width)
                            .zoomable(minZoomScale: 1, doubleTapZoomScale: 3)
                        Spacer(minLength: 0)
                    }
                } else {
                    Text("Carregue ou selecione uma imagem para editar")
                        .font(.headline)
                        .foregroundColor(.gray)
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
