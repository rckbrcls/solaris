
import SwiftUI
import PhotosUI

struct PhotosScrollView<PhotoType: Identifiable>: View where PhotoType.ID == String {
    @Binding var photos: [PhotoType]
    @Binding var selectedItems: [PhotosPickerItem]
    @State private var selectedPhotoIndices: Set<Int> = []
    @State private var showShareSheet: Bool = false

    var ns: Namespace.ID
    var onPhotoSelected: (Int) -> Void
    var onPhotosChanged: () -> Void
    // Novo: delega a exclusão para o chamador para poder remover arquivos
    var onDelete: ([Int]) -> Void = { _ in }
    var onSelectionChanged: (Bool) -> Void
    var getImage: (PhotoType) -> UIImage

    var selectedPhotos: [UIImage] {
        selectedPhotoIndices.compactMap { index in
            if index < photos.count { return getImage(photos[index]) }
            else { return nil }
        }
    }

    var body: some View {
        VStack {
            ScrollView {
                GeometryReader { geo in
                    // Grid fixa em 3 colunas. Células 100% quadradas e do mesmo tamanho.
                    let columnsCount: Int = 3
                    let spacing: CGFloat = 10
                    let sidePadding: CGFloat = 16
                    let totalWidth = geo.size.width - (sidePadding * 2)
                    let cellSize = floor((totalWidth - (CGFloat(columnsCount - 1) * spacing)) / CGFloat(columnsCount))

                    let columns = Array(repeating: GridItem(.fixed(cellSize), spacing: spacing), count: columnsCount)

                    LazyVGrid(columns: columns, spacing: spacing) {
                        // Primeiro item: botão de import
                        PhotosPicker(selection: $selectedItems,
                                     maxSelectionCount: 6,
                                     matching: .images) {
                            ZStack {
                                Image(systemName: "plus")
                                    .foregroundColor(Color.textSecondary)
                                    .font(.system(size: 28))
                            }
                            .frame(width: cellSize, height: cellSize)
                            .liquidGlass(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .accessibilityLabel(String(localized: "Import photos"))

                        // Demais itens: thumbnails padronizadas
                        ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                            PhotoGridItem(
                                photo: getImage(photo),
                                index: index,
                                ns: ns,
                                isSelected: selectedPhotoIndices.contains(index),
                                size: cellSize,
                                onLongPress: {
                                    Haptics.medium()
                                    _ = withAnimation { selectedPhotoIndices.insert(index) }
                                },
                                onTap: {
                                    if selectedPhotoIndices.isEmpty { onPhotoSelected(index) }
                                    else {
                                        withAnimation {
                                            if selectedPhotoIndices.contains(index) { selectedPhotoIndices.remove(index) }
                                            else { selectedPhotoIndices.insert(index) }
                                        }
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, sidePadding)
                    .padding(.vertical, 12)
                }
                // O GeometryReader já define o layout; não force altura 0
            }
            if !selectedPhotoIndices.isEmpty {
                HStack {
                    Button(action: {
                        showShareSheet = true
                    }) {
                        Label(String(localized: "Share"), systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .tint(Color.textOnAccent)
                            .liquidGlass(
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous),
                                borderColor: Color.actionShare.opacity(0.2)
                            )
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.actionShare.opacity(0.7))
                            )
                    }
                    Button(action: {
                        let indicesToRemove = selectedPhotoIndices.sorted(by: >)
                        onDelete(indicesToRemove)
                        selectedPhotoIndices.removeAll()
                        onPhotosChanged()
                    }) {
                        Label(String(localized: "Delete"), systemImage: "trash")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .tint(Color.textOnAccent)
                            .liquidGlass(
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous),
                                borderColor: Color.actionDestructive.opacity(0.2)
                            )
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.actionDestructive.opacity(0.75))
                            )
                    }
                }
                .padding()
            }
        }
        .onChange(of: selectedPhotoIndices) { _, newValue in
            onSelectionChanged(!newValue.isEmpty)
        }
        .sheet(isPresented: $showShareSheet) {
            ActivityView(activityItems: selectedPhotos)
        }
    }
}
