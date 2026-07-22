//
//  MapViewModel.swift
//  Memento
//
//  Created by WeiAnUppp on 2026/7/21.
//

import SwiftUI
import MapKit

@Observable
final class MapViewModel {
    var items: [Item] = []
    var selectedItem: Item?
    var isLoading = false
    var loadError: String?

    var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074),
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
    )

    private let dbService = DatabaseService.shared

    // MARK: - Data Loading

    func loadItems() {
        isLoading = true
        loadError = nil

        do {
            items = try dbService.fetchAll()
        } catch {
            loadError = error.localizedDescription
            print("[MapViewModel] 加载失败: \(error)")
        }

        isLoading = false
    }

    // MARK: - Actions

    func focusOnItem(_ item: Item) {
        withAnimation {
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: item.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                )
            )
            selectedItem = item
        }
    }

    func deselectItem() {
        selectedItem = nil
    }

    func centerOnUser(_ location: CLLocationCoordinate2D) {
        withAnimation {
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: location,
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                )
            )
        }
    }
}
