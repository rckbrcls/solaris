//
//  PhotoGridItem.swift
//  souvenir
//
//  Created by Erick Barcelos on 12/04/25.
//
import SwiftUI
import PhotosUI

struct PhotoGridItem: View {
    let photo: UIImage
    let index: Int
    let ns: Namespace.ID
    let isSelected: Bool
    let size: CGFloat?
    var onLongPress: () -> Void
    // Novo closure para tratar o toque simples
    var onTap: () -> Void

    @State private var isPressed: Bool = false

    init(photo: UIImage,
         index: Int,
         ns: Namespace.ID,
         isSelected: Bool,
         size: CGFloat? = nil,
         onLongPress: @escaping () -> Void,
         onTap: @escaping () -> Void) {
        self.photo = photo
        self.index = index
        self.ns = ns
        self.isSelected = isSelected
        self.size = size
        self.onLongPress = onLongPress
        self.onTap = onTap
    }

    var body: some View {
        ZStack {
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()
                .matchedTransitionSource(id: "photo_\(index)", in: ns)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.primary : Color.clear, lineWidth: 3)
                .allowsHitTesting(false)
        )
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isPressed)
        // Determina a área de toque completa, e unifica o onTap aqui
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture { onTap() }
        .onLongPressGesture(
            minimumDuration: 0.2,
            maximumDistance: 10,
            pressing: { inProgress in
                withAnimation(.easeInOut(duration: 0.2)) { isPressed = inProgress }
            },
            perform: { onLongPress() }
        )
    }
}
