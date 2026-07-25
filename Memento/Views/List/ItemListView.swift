//
//  ItemListView.swift
//  Memento
//
//  Created by WeiAnUppp on 2026/7/21.
//

import SwiftUI
import MapKit

struct ItemListView: View {
    var onDataChanged: (() -> Void)?
    var onBarVisibilityChange: ((Bool) -> Void)?

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
        VStack(spacing: 0) {
            Text(item.name)
                .font(.title)
                .bold()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)

            Text(item.itemDescription)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)

            let paths = item.imagePaths
            if !paths.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(paths.enumerated()), id: \.offset) { index, _ in
                            if let url = DatabaseService.imageURL(for: paths[index]),
                               let data = try? Data(contentsOf: url),
                               let uiImage = UIImage(data: data) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 120, height: 80)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }

            Map(initialPosition: .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: item.latitude, longitude: item.longitude),
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            ))) {
                Marker(item.name, coordinate: CLLocationCoordinate2D(
                    latitude: item.latitude, longitude: item.longitude
                ))
            }
            .frame(height: 160)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(16)

            HStack(spacing: 16) {
                Button {
                    // 编辑功能（可后续接入编辑页）
                } label: {
                    Text("编辑")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .background {
                    Capsule()
                        .fill(.gray.opacity(0.2))
                }

                Button {
                    deleteItem(item)
                    dismiss()
                } label: {
                    Text("删除")
                        .font(.headline)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .background {
                    Capsule()
                        .fill(.gray.opacity(0.2))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .safeAreaPadding(safeArea)
        .contentShape(.rect)
        .onTapGesture { dismiss() }
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
