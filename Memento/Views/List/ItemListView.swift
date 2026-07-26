//
//  ItemListView.swift
//  Memento
//
//  Created by 胡杰 on 2026/7/21.
//

import SwiftUI

struct ItemListView: View {
    var onDataChanged: (() -> Void)?
    var onBarVisibilityChange: ((Bool) -> Void)?
    let onNavigateToMap: ((Item) -> Void)?
    var refreshTrigger: Int = 0

    @State private var items: [Item] = []
    @State private var barHidden = false

    private let dbService = DatabaseService.shared

    var body: some View {
        Group {
            if items.isEmpty {
                emptyView
            } else {
                gridView
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .onAppear { loadItems() }
        .onChange(of: refreshTrigger) { loadItems() }
    }

    // MARK: - Grid

    private var gridView: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 15),
                    GridItem(.flexible(), spacing: 15)
                ],
                spacing: 15
            ) {
                ForEach(items) { item in
                    AppStoreTransition(
                        config: .init(cardCornerRadius: 16)
                    ) { isExpanded, dismiss in
                        if isExpanded {
                            expandedHero(for: item, dismiss: dismiss)
                        } else {
                            ItemGridCard(item: item)
                        }
                    } content: { safeArea, dismiss in
                        detailContent(for: item, safeArea: safeArea, dismiss: dismiss)
                    }
                    .frame(height: 200)
                    .contextMenu {
                        Button {
                            // 编辑（暂不实现）
                        } label: {
                            Label("编辑", systemImage: "pencil")
                        }

                        Button(role: .destructive) {
                            deleteItem(item)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal, 15)
        }
        .contentMargins(.top, 56, for: .scrollContent)
        .refreshable {
            loadItems()
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y
        } action: { _, newValue in
            let shouldHide = newValue > 80
            if shouldHide != barHidden {
                barHidden = shouldHide
                onBarVisibilityChange?(!shouldHide)
            }
        }
    }

    // MARK: - Expanded Hero

    private func expandedHero(for item: Item, dismiss: (() -> Void)?) -> some View {
        Group {
            if let firstPath = item.imagePaths.first,
               let url = DatabaseService.imageURL(for: firstPath),
               let data = try? Data(contentsOf: url),
               let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        Text(item.emoji ?? "📦")
                            .font(.system(size: 64))
                    }
            }
        }
        .overlay {
            if let dismiss {
                Rectangle()
                    .foregroundStyle(.clear)
                    .contentShape(.rect)
                    .onTapGesture { dismiss() }
                    .transition(.identity)
            }
        }
    }

    // MARK: - Detail Content

    private func detailContent(for item: Item, safeArea: EdgeInsets, dismiss: @escaping () -> Void) -> some View {
        ItemDetailContent(
            item: item,
            safeArea: safeArea,
            dismiss: dismiss,
            onUpdate: { loadItems(); onDataChanged?() },
            onNavigateToMap: { [onNavigateToMap] in
                onNavigateToMap?(item)
            }
        )
    }

    // MARK: - Empty State

    private var emptyView: some View {
        ContentUnavailableView {
            Label("暂无物品", systemImage: "tray")
        } description: {
            Text("拍照记录你的第一个物品")
        }
    }

    // MARK: - Data

    private func loadItems() {
        do {
            items = try dbService.fetchAll()
        } catch {
            print("[ItemListView] 加载失败: \(error)")
        }
    }

    private func deleteItem(_ item: Item) {
        guard let id = item.id else { return }

        DatabaseService.deleteImages(at: item.imagePaths)

        do {
            try dbService.delete(id: id)
            items.removeAll { $0.id == id }
            onDataChanged?()
        } catch {
            print("[ItemListView] 删除失败: \(error)")
        }
    }
}

