//
//  ItemListView.swift
//  Memento
//
//  Created by WeiAnUppp on 2026/7/21.
//

import SwiftUI

struct ItemListView: View {
    var onDataChanged: (() -> Void)?
    var onBarVisibilityChange: ((Bool) -> Void)?

    @State private var items: [Item] = []
    @State private var selectedItem: Item?
    @State private var showDetail = false
    @State private var barHidden = false

    private let dbService = DatabaseService.shared

    var body: some View {
        Group {
            if items.isEmpty {
                emptyView
            } else {
                listView
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .onAppear { loadItems() }
        .sheet(isPresented: $showDetail) {
            if let item = selectedItem {
                ItemDetailView(item: item)
            }
        }
    }

    // MARK: - List

    private var listView: some View {
        List {
            ForEach(items) { item in
                Button {
                    selectedItem = item
                    showDetail = true
                } label: {
                    ItemCard(item: item)
                }
                .buttonStyle(.plain)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        deleteItem(item)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 66, for: .scrollContent)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y
        } action: { _, newValue in
            let shouldHide = newValue > 50
            if shouldHide != barHidden {
                barHidden = shouldHide
                onBarVisibilityChange?(!shouldHide)
            }
        }
        .refreshable {
            loadItems()
        }
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

        // 删除图片文件
        DatabaseService.deleteImage(at: item.imagePath)

        // 删除数据库记录
        do {
            try dbService.delete(id: id)
            items.removeAll { $0.id == id }
            onDataChanged?()
        } catch {
            print("[ItemListView] 删除失败: \(error)")
        }
    }
}
