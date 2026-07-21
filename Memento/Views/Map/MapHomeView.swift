//
//  MapHomeView.swift
//  Memento
//
//  Created by WeiAnUppp on 2026/7/21.
//

import SwiftUI
import MapKit

struct MapHomeView: View {
    @State private var viewModel = MapViewModel()
    @State private var locationService = LocationService()

    var body: some View {
        Map(position: $viewModel.cameraPosition) {
            UserAnnotation()

            ForEach(viewModel.items) { item in
                Annotation(item.name, coordinate: item.coordinate) {
                    ItemAnnotation(item: item)
                        .onTapGesture { viewModel.selectedItem = item }
                }
            }
        }
        .mapStyle(.standard)
        .ignoresSafeArea(edges: .top)
        .overlay(alignment: .topTrailing) {
            // 自定义定位按钮 — 放在筛选按钮下方
            Button {
                guard let location = locationService.currentLocation else { return }
                withAnimation {
                    viewModel.cameraPosition = .region(
                        MKCoordinateRegion(
                            center: location.coordinate,
                            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                        )
                    )
                }
            } label: {
                Image(systemName: "location.fill")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .glassEffect(.regular.interactive(), in: .circle)
            .padding(.top, 58)   // 筛选按钮下方
            .padding(.trailing, 16)
        }
        .onAppear {
            locationService.requestPermission()
        }
        .task {
            // 等待获取到用户位置后自动定位
            while locationService.currentLocation == nil {
                try? await Task.sleep(for: .milliseconds(200))
            }
            guard let location = locationService.currentLocation else { return }
            withAnimation {
                viewModel.cameraPosition = .region(
                    MKCoordinateRegion(
                        center: location.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                    )
                )
            }
        }
    }
}
