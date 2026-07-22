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
            while locationService.currentLocation == nil {
                try? await Task.sleep(for: .milliseconds(200))
            }
            guard let location = locationService.currentLocation else { return }
            viewModel.centerOnUser(location.coordinate)
        }
    }
}
