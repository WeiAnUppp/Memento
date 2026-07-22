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

    /// 是否已完成首次定位居中（避免每次切回地图都重新居中）
    var hasInitialCentered = false

    /// 当前正在被拖拽的大头针 ID（nil = 无拖拽）
    var movingItemId: Int64?

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

    // MARK: - 大头针拖拽移动（MKMapView 原生拖拽回调）

    /// 拖拽开始
    func startMoving(byId id: Int64) {
        movingItemId = id
    }

    /// 拖拽结束：新坐标写入 items + 数据库
    func commitMove(id: Int64, latitude: Double, longitude: Double) {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            movingItemId = nil
            return
        }
        items[index].latitude = latitude
        items[index].longitude = longitude

        do {
            try dbService.updateLocation(id: id, latitude: latitude, longitude: longitude)
        } catch {
            print("[MapViewModel] 移动保存失败: \(error)")
        }

        movingItemId = nil
    }
}
