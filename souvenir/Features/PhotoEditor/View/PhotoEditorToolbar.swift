//
//  PhotoEditorToolbar.swift
//  souvenir
//
//  Created by Erick Barcelos on 30/05/25.
//

import SwiftUI

struct PhotoEditorToolbar: View {
    @Binding var selectedCategory: String
    @Binding var bottomSize: CGFloat

    var body: some View {
        HStack(spacing: 8) {
            
            CategoryButton(category: "filters", icon: "paintpalette", selectedCategory: $selectedCategory, bottomSize: $bottomSize, targetSize: 0.25)
            
            CategoryButton(category: "sticker", icon: "seal", selectedCategory: $selectedCategory, bottomSize: $bottomSize, targetSize: 0.25)
            
            CategoryButton(category: "edit", icon: "slider.horizontal.3", selectedCategory: $selectedCategory, bottomSize: $bottomSize, targetSize: 0.30)
        }
        .padding(.horizontal)

        
    }
}

struct CategoryButton: View {
    let category: String
    let icon: String
    @Binding var selectedCategory: String
    @Binding var bottomSize: CGFloat
    let targetSize: CGFloat
    @EnvironmentObject private var colorSchemeManager: ColorSchemeManager

    var body: some View {
        Button(action: {
            selectedCategory = category
            bottomSize = targetSize
        }) {
            VStack {
                Image(systemName: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .foregroundColor(
                        selectedCategory == category
                        ? colorSchemeManager.primaryColor
                        : colorSchemeManager.primaryColor.opacity(0.55)
                    )
            }
            .padding(.vertical, 8)
            .padding(.horizontal)
            .boxBlankStyle(cornerRadius: 12, padding: 0, maxWidth: CGFloat.infinity, height: 40)
            .background(
                selectedCategory == category
                ? colorSchemeManager.primaryColor.opacity(0.08)
                : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}
