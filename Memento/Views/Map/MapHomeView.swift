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

    /// 递增触发地图居中（0 = 初始，每次需要居中时 +1）
    @State private var centerTrigger = 0

    var body: some View {
        MapKitView(
            items: viewModel.items,
            movingItemId: viewModel.movingItemId,
            userCoordinate: locationService.currentLocation?.coordinate,
            centerTrigger: centerTrigger,
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
                ItemDetailView(item: item)
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
}
