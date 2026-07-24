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

    /// 坐标聚焦触发（新增物品保存后自动定位）
    var focusCoordinate: CLLocationCoordinate2D?
    var focusTrigger: Int = 0

    var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074),
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
    )

    private let dbService = DatabaseService.shared

    // MARK: - Data Loading

    /// 后台线程读库，主线程赋值 —— 避免 queue.sync 阻塞主线程造成卡顿
    /// completion 在主线程回调（供需要读取最新 items 的场景，如详情页更新后重选）
    func loadItems(completion: (() -> Void)? = nil) {
        isLoading = true
        loadError = nil

        Task.detached(priority: .userInitiated) {
            do {
                let fetched = try DatabaseService.shared.fetchAll()
                await MainActor.run {
                    self.items = fetched
                    self.isLoading = false
                    completion?()
                }
            } catch {
                await MainActor.run {
                    self.loadError = error.localizedDescription
                    self.isLoading = false
                    print("[MapViewModel] 加载失败: \(error)")
                    completion?()
                }
            }
        }
    }

    /// 增分插入一条刚保存的物品，不整表重查 —— 保存后地图立即出针，主线程零阻塞
    /// items 按 createdAt 降序，插到正确位置维持排序一致
    func addSavedItem(_ item: Item) {
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx] = item
            return
        }
        let insertIndex = items.firstIndex(where: { $0.createdAt <= item.createdAt }) ?? items.count
        items.insert(item, at: insertIndex)
    }

    // MARK: - Actions

    func focusOnItem(_ item: Item) {
        selectedItem = item
        focusCoordinate = item.coordinate
        focusTrigger += 1
    }

    /// 聚焦到指定坐标（供 ContentView 在自动保存后调用）
    func focusOnCoordinate(_ coordinate: CLLocationCoordinate2D) {
        focusCoordinate = coordinate
        focusTrigger += 1
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
