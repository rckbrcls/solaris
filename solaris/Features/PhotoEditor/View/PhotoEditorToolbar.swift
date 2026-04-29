//
//  PhotoEditorToolbar.swift
//  solaris
//
//  Created by Erick Barcelos on 30/05/25.
//

import SwiftUI
import PhosphorSwift

struct PhotoEditorToolbar: View {
    @Binding var selectedCategory: String
    @Binding var bottomSize: CGFloat

    var body: some View {
        HStack(spacing: 8) {

            CategoryButton(category: "filters", icon: Ph.palette.bold, selectedCategory: $selectedCategory, bottomSize: $bottomSize, targetSize: 0.25)

            CategoryButton(category: "edit", icon: Ph.slidersHorizontal.bold, selectedCategory: $selectedCategory, bottomSize: $bottomSize, targetSize: 0.30)

            CategoryButton(category: "export", icon: Ph.export.bold, selectedCategory: $selectedCategory, bottomSize: $bottomSize, targetSize: 0.22)
        }
        .padding(.horizontal)


    }
}

struct CategoryButton: View {
    let category: String
    let icon: Image
    @Binding var selectedCategory: String
    @Binding var bottomSize: CGFloat
    let targetSize: CGFloat

    var body: some View {
        Button(action: {
            selectedCategory = category
            bottomSize = targetSize
        }) {
            VStack {
                icon
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .foregroundColor(
                        selectedCategory == category
                        ? Color.textPrimary
                        : Color.textSecondary
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
                    ? Color.borderSelected
                    : Color.borderSubtle,
                borderLineWidth: selectedCategory == category ? 2 : 1
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedCategory == category)
            .scaleEffect(selectedCategory == category ? 1.02 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedCategory == category)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(category.capitalized)
    }
}
