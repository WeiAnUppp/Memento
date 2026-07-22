//
//  MapKitView.swift
//  Memento
//
//  UIViewRepresentable 包裹 MKMapView
//  大头针拖拽通过 UIKit 手势识别器实现，不依赖 MKAnnotationView.isDraggable
//

import SwiftUI
import MapKit

// MARK: - Item Annotation Point

final class ItemPoint: NSObject, MKAnnotation {
    let itemId: Int64
    let itemName: String
    dynamic var coordinate: CLLocationCoordinate2D

    var title: String? { itemName }

    init(item: Item) {
        self.itemId = item.id ?? 0
        self.itemName = item.name
        self.coordinate = item.coordinate
    }
}

// MARK: - MapKitView

struct MapKitView: UIViewRepresentable {
    let items: [Item]
    var movingItemId: Int64?
    var userCoordinate: CLLocationCoordinate2D?
    var centerTrigger: Int

    let onTapItem: (Int64) -> Void
    let onMoveStarted: (Int64) -> Void
    let onMoveCompleted: (Int64, Double, Double) -> Void

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.showsCompass = false
        mapView.showsScale = false
        mapView.isPitchEnabled = false
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mapView.register(MKAnnotationView.self, forAnnotationViewWithReuseIdentifier: "Pin")

        context.coordinator.mapView = mapView
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.onTapItem = onTapItem
        context.coordinator.onMoveStarted = onMoveStarted
        context.coordinator.onMoveCompleted = onMoveCompleted

        context.coordinator.syncAnnotations(
            mapView: mapView,
            items: items,
            movingId: movingItemId
        )

        if centerTrigger != context.coordinator.lastCenterTrigger,
           let coord = userCoordinate {
            context.coordinator.lastCenterTrigger = centerTrigger
            let region = MKCoordinateRegion(
                center: coord,
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
            mapView.setRegion(region, animated: true)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate {
        weak var mapView: MKMapView?
        private var annotationMap: [Int64: ItemPoint] = [:]

        var lastCenterTrigger = -1
        var onTapItem: ((Int64) -> Void)?
        var onMoveStarted: ((Int64) -> Void)?
        var onMoveCompleted: ((Int64, Double, Double) -> Void)?

        /// 拖拽状态
        private var draggingItemId: Int64?
        private var dragTouchOffset: CGPoint = .zero

        // MARK: Annotation Sync

        func syncAnnotations(mapView: MKMapView, items: [Item], movingId: Int64?) {
            let newIds = Set(items.compactMap(\.id))
            let currentIds = Set(annotationMap.keys)

            for id in currentIds.subtracting(newIds) where id != movingId {
                if let point = annotationMap.removeValue(forKey: id) {
                    mapView.removeAnnotation(point)
                }
            }

            for item in items {
                guard let id = item.id, annotationMap[id] == nil else { continue }
                let point = ItemPoint(item: item)
                annotationMap[id] = point
                mapView.addAnnotation(point)
            }

            for item in items {
                guard let id = item.id, id != movingId, let point = annotationMap[id] else { continue }
                let newCoord = item.coordinate
                if abs(point.coordinate.latitude - newCoord.latitude) > 0.000001 ||
                   abs(point.coordinate.longitude - newCoord.longitude) > 0.000001 {
                    point.coordinate = newCoord
                }
            }
        }

        // MARK: Annotation View（添加 UIKit 手势）

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let point = annotation as? ItemPoint else { return nil }

            let view = mapView.dequeueReusableAnnotationView(
                withIdentifier: "Pin", for: point
            ) as! MKAnnotationView

            view.annotation = point
            view.canShowCallout = false
            view.isDraggable = false   // 不用系统拖拽
            view.isEnabled = true

            // 蓝色圆形 pin
            let size: CGFloat = 32
            let image = UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { ctx in
                UIColor.systemBlue.setFill()
                ctx.cgContext.fillEllipse(in: CGRect(x: 2, y: 2, width: size - 4, height: size - 4))
            }
            view.image = image
            view.frame.size = CGSize(width: size, height: size)
            view.centerOffset = CGPoint(x: 0, y: -size / 2)

            // 每次复用都要重建手势（避免残留状态）
            view.gestureRecognizers?.removeAll()

            // Tap → 详情
            let tap = UITapGestureRecognizer(target: self, action: #selector(handlePinTap(_:)))
            view.addGestureRecognizer(tap)

            // Long press → 拖拽
            let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handlePinLongPress(_:)))
            longPress.minimumPressDuration = 0.15
            view.addGestureRecognizer(longPress)

            // 短按需等长按失败后才触发
            tap.require(toFail: longPress)

            return view
        }

        // MARK: - Tap（点击 → 详情）

        @objc private func handlePinTap(_ gesture: UITapGestureRecognizer) {
            guard let pinView = gesture.view as? MKAnnotationView,
                  let point = pinView.annotation as? ItemPoint else { return }
            onTapItem?(point.itemId)
        }

        // MARK: - Long Press → 拖拽（UIKit 手势，不受 MapKit 拦截）

        @objc private func handlePinLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard let mapView = mapView,
                  let pinView = gesture.view as? MKAnnotationView,
                  let point = pinView.annotation as? ItemPoint else { return }

            let touchPoint = gesture.location(in: mapView)

            switch gesture.state {
            case .began:
                draggingItemId = point.itemId
                // 计算手指与大头针中心之间的偏移
                let pinScreenPoint = mapView.convert(point.coordinate, toPointTo: mapView)
                dragTouchOffset = CGPoint(
                    x: pinScreenPoint.x - touchPoint.x,
                    y: pinScreenPoint.y - touchPoint.y
                )
                onMoveStarted?(point.itemId)

                // 视觉反馈
                let size: CGFloat = 32
                let orangeImage = UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { ctx in
                    UIColor.systemOrange.setFill()
                    ctx.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: size, height: size))
                }
                pinView.image = orangeImage
                UIView.animate(withDuration: 0.15) {
                    pinView.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
                }

            case .changed:
                guard draggingItemId == point.itemId else { return }
                let adjustedPoint = CGPoint(
                    x: touchPoint.x + dragTouchOffset.x,
                    y: touchPoint.y + dragTouchOffset.y
                )
                let newCoord = mapView.convert(adjustedPoint, toCoordinateFrom: mapView)
                point.coordinate = newCoord

            case .ended:
                guard draggingItemId == point.itemId else { return }
                onMoveCompleted?(point.itemId, point.coordinate.latitude, point.coordinate.longitude)
                resetPinView(pinView)
                draggingItemId = nil

            case .cancelled, .failed:
                resetPinView(pinView)
                draggingItemId = nil

            default:
                break
            }
        }

        private func resetPinView(_ view: MKAnnotationView) {
            let size: CGFloat = 32
            let blueImage = UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { ctx in
                UIColor.systemBlue.setFill()
                ctx.cgContext.fillEllipse(in: CGRect(x: 2, y: 2, width: size - 4, height: size - 4))
            }
            view.image = blueImage
            UIView.animate(withDuration: 0.2) {
                view.transform = .identity
            }
        }

        // MARK: didSelect（不再使用，防止干扰）
        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            mapView.deselectAnnotation(view.annotation, animated: false)
        }
    }
}
