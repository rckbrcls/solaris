//
//  PhotoEditorToolbar.swift
//  solaris
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
                    .scaleEffect(selectedCategory == category ? 1.1 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: selectedCategory == category)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 36)
            .liquidGlass(
                in: RoundedRectangle(cornerRadius: 12, style: .continuous),
                borderColor: selectedCategory == category
                    ? colorSchemeManager.primaryColor.opacity(0.6)
                    : Color.primary.opacity(0.08),
                borderLineWidth: selectedCategory == category ? 2 : 1
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedCategory == category)
            .scaleEffect(selectedCategory == category ? 1.02 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedCategory == category)
        }
        .buttonStyle(.plain)
    }
}
