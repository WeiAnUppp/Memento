import SwiftUI
import MapKit

@Observable
final class MapViewModel {
    var items: [Item] = []
    var selectedItem: Item?
    var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074),
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
    )

    func loadItems() {
        // TODO: Day 9 — 从数据库加载物品
    }

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
}
