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

    var body: some View {
        Map(position: $viewModel.cameraPosition) {
            UserAnnotation()

            ForEach(viewModel.items) { item in
                Annotation(item.name, coordinate: item.coordinate) {
                    ItemAnnotation(item: item)
                        .onTapGesture {
                            viewModel.selectedItem = item
                            showDetail = true
                        }
                }
            }
        }
        .mapStyle(.standard)
        .mapControls {}   // 隐藏默认控件（比例尺、指南针等）
        .ignoresSafeArea(edges: .top)
        .overlay(alignment: .topTrailing) {
            Button {
                guard let location = locationService.currentLocation else { return }
                viewModel.centerOnUser(location.coordinate)
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
            // 仅在首次启动时居中到用户位置，避免每次切回地图都重新跳转
            guard !viewModel.hasInitialCentered else { return }
            while locationService.currentLocation == nil {
                try? await Task.sleep(for: .milliseconds(200))
            }
            guard let location = locationService.currentLocation else { return }
            viewModel.centerOnUser(location.coordinate)
            viewModel.hasInitialCentered = true
        }
    }
}
