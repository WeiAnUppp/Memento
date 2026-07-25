//
//  MapHomeView.swift
//  Memento
//
//  Created by WeiAnUppp on 2026/7/21.
//

import SwiftUI
import MapKit

struct MapHomeView: View {
    @Bindable var viewModel: MapViewModel
    let locationService: LocationService
    @State private var showDetail = false
    @Environment(\.colorScheme) private var colorScheme

    /// 递增触发地图居中（0 = 初始，每次需要居中时 +1）
    @State private var centerTrigger = 0

    var body: some View {
        MapKitView(
            items: viewModel.items,
            movingItemId: viewModel.movingItemId,
            userCoordinate: locationService.currentLocation?.coordinate,
            centerTrigger: centerTrigger,
            focusCoordinate: viewModel.focusCoordinate,
            focusTrigger: viewModel.focusTrigger,
            colorScheme: colorScheme,
            onTapItem: { id in
                guard let item = viewModel.items.first(where: { $0.id == id }) else { return }
                viewModel.selectedItem = item
                showDetail = true
            },
            onMoveStarted: { id in
                viewModel.startMoving(byId: id)
            },
            onMoveCompleted: { id, lat, lon in
                viewModel.commitMove(id: id, latitude: lat, longitude: lon)
            }
        )
        .ignoresSafeArea()
        .overlay(alignment: .topTrailing) {
            Button {
                centerTrigger += 1
            } label: {
                Image(systemName: "location.fill")
                    .font(.title3)
                    .frame(width: 50, height: 50)
            }
            .glassEffect(.regular.interactive(), in: .circle)
            .tint(.primary)
            .padding(.top, 64)
            .padding(.trailing, 16)
        }
        .overlay(alignment: .top) {
            if viewModel.movingItemId != nil {
                Text("拖拽大头针到正确位置，松手确认")
                    .font(.caption)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.top, 64)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $showDetail) {
            if let item = viewModel.selectedItem {
                ZStack(alignment: .topTrailing) {
                    ScrollView {
                        VStack(spacing: 0) {
                            // 主图（hero，与列表页展开状态一致）
                            heroImage(for: item)

                            // 详情内容（与列表页共用 ItemDetailContent）
                            ItemDetailContent(
                                item: item,
                                safeArea: EdgeInsets(),
                                dismiss: nil,
                                onUpdate: {
                                    viewModel.loadItems {
                                        if let id = item.id,
                                           let updated = viewModel.items.first(where: { $0.id == id }) {
                                            viewModel.selectedItem = updated
                                        }
                                    }
                                },
                                onDeleteRequested: { showDetail = false },
                                showMainImage: false
                            )
                        }
                    }
                    .background(.background)

                    // X 关闭按钮（与列表详情页一致：glass 风格 xmark）
                    Button {
                        showDetail = false
                    } label: {
                        Image(systemName: "xmark")
                            .frame(width: 20, height: 30)
                            .contentShape(.circle)
                    }
                    .buttonStyle(.glass)
                    .padding(.top, 16)
                    .padding(.trailing, 16)
                }
            }
        }
        .onAppear {
            locationService.requestPermission()
            viewModel.loadItems()
        }
        .task {
            guard !viewModel.hasInitialCentered else { return }
            while locationService.currentLocation == nil {
                try? await Task.sleep(for: .milliseconds(200))
            }
            guard locationService.currentLocation != nil else { return }
            viewModel.hasInitialCentered = true
            centerTrigger += 1
        }
    }

    // MARK: - Hero Image

    /// 与列表页 AppStoreTransition 展开时的 hero 图片风格一致
    @ViewBuilder
    private func heroImage(for item: Item) -> some View {
        if let firstPath = item.imagePaths.first,
           let url = DatabaseService.imageURL(for: firstPath),
           let data = try? Data(contentsOf: url),
           let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(height: 460)
                .clipped()
        } else {
            Rectangle()
                .fill(.quaternary)
                .frame(height: 460)
                .overlay {
                    Text(item.emoji ?? "📦")
                        .font(.system(size: 64))
                }
        }
    }
}
