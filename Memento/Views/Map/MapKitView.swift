//
//  MapKitView.swift
//  Memento
//
//  UIViewRepresentable 包裹 MKMapView
//  大头针拖拽通过 UIKit 手势识别器实现，不依赖 MKAnnotationView.isDraggable
//  缩放到一定级别自动聚类（原生 MKAnnotationView clusteringIdentifier）
//

import SwiftUI
import MapKit

// MARK: - Item Annotation Point

final class ItemPoint: NSObject, MKAnnotation {
    let itemId: Int64
    let itemName: String
    var emoji: String
    dynamic var coordinate: CLLocationCoordinate2D

    var title: String? { itemName }

    init(item: Item) {
        self.itemId = item.id ?? 0
        self.itemName = item.name
        self.emoji = item.emoji ?? "📍"
        self.coordinate = item.coordinate
    }
}

// MARK: - MapKitView

struct MapKitView: UIViewRepresentable {
    let items: [Item]
    var movingItemId: Int64?
    var userCoordinate: CLLocationCoordinate2D?
    var centerTrigger: Int
    var focusCoordinate: CLLocationCoordinate2D?
    var focusTrigger: Int
    var colorScheme: ColorScheme?

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

        // 注册单物品 pin 和聚合 cluster 两种样式
        mapView.register(MKAnnotationView.self, forAnnotationViewWithReuseIdentifier: "Pin")
        mapView.register(MKAnnotationView.self, forAnnotationViewWithReuseIdentifier: "Cluster")

        context.coordinator.mapView = mapView
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.onTapItem = onTapItem
        context.coordinator.onMoveStarted = onMoveStarted
        context.coordinator.onMoveCompleted = onMoveCompleted

        // 主题切换时刷新所有聚类气泡颜色
        if colorScheme != context.coordinator.lastColorScheme {
            context.coordinator.lastColorScheme = colorScheme
            context.coordinator.refreshAnnotationImages(in: mapView)
        }

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

        // 坐标聚焦（物品保存后自动定位到 GPS 位置）
        if focusTrigger != context.coordinator.lastFocusTrigger,
           let coord = focusCoordinate {
            context.coordinator.lastFocusTrigger = focusTrigger
            let region = MKCoordinateRegion(
                center: coord,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
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
        var lastFocusTrigger = -1
        var lastColorScheme: ColorScheme?
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

                let itemEmoji = item.emoji ?? "📍"
                if point.emoji != itemEmoji, let view = mapView.view(for: point) {
                    point.emoji = itemEmoji
                    view.image = pinImage(emoji: itemEmoji)
                }
            }
        }

        // MARK: Refresh Annotations

        /// 遍历所有标注，用当前配色重新生成图片（聚类气泡 + 单 pin）
        func refreshAnnotationImages(in mapView: MKMapView) {
            for annotation in mapView.annotations {
                guard let view = mapView.view(for: annotation) else { continue }

                if let cluster = annotation as? MKClusterAnnotation {
                    let memberEmojis = cluster.memberAnnotations
                        .compactMap { ($0 as? ItemPoint)?.emoji }
                    let freq = Dictionary(memberEmojis.map { ($0, 1) }, uniquingKeysWith: +)
                    let sortedEmojis = freq.sorted { $0.value > $1.value }.map(\.key)
                    let shownEmojis = Array(sortedEmojis.prefix(2))

                    let img = clusterBubbleImage(emojis: shownEmojis, totalCount: cluster.memberAnnotations.count)
                    view.image = img
                    view.frame.size = img.size
                    view.centerOffset = CGPoint(x: 0, y: -img.size.height / 2)
                } else if let point = annotation as? ItemPoint {
                    view.image = pinImage(emoji: point.emoji)
                    view.frame.size = CGSize(width: 40, height: 46)
                    view.centerOffset = CGPoint(x: 0, y: -20)
                }
            }
        }

        // MARK: Pin Image

        private func pinImage(emoji: String, dragging: Bool = false) -> UIImage {
            let totalW: CGFloat = 40
            let totalH: CGFloat = 46
            let pointH: CGFloat = 6
            let pointHalfW: CGFloat = 5
            let circleD: CGFloat = 36
            let circleY: CGFloat = 2

            let bgColor: UIColor = {
                if dragging { return .systemOrange }
                return UIColor { trait in
                    trait.userInterfaceStyle == .dark
                        ? UIColor(white: 0.22, alpha: 0.96)
                        : UIColor(white: 0.97, alpha: 0.96)
                }
            }()

            return UIGraphicsImageRenderer(size: CGSize(width: totalW, height: totalH)).image { ctx in
                let cgContext = ctx.cgContext
                let midX = totalW / 2

                // 阴影
                cgContext.setShadow(offset: CGSize(width: 0, height: 1), blur: 4,
                                    color: UIColor.black.withAlphaComponent(0.15).cgColor)

                // 圆形
                bgColor.setFill()
                let circleRect = CGRect(x: (totalW - circleD) / 2, y: circleY,
                                        width: circleD, height: circleD)
                cgContext.fillEllipse(in: circleRect)

                // 底部小尖头
                let triPath = UIBezierPath()
                triPath.move(to: CGPoint(x: midX - pointHalfW, y: circleY + circleD - 1))
                triPath.addLine(to: CGPoint(x: midX, y: circleY + circleD + pointH - 1))
                triPath.addLine(to: CGPoint(x: midX + pointHalfW, y: circleY + circleD - 1))
                triPath.close()
                triPath.fill()

                // 重置阴影再绘制 emoji
                cgContext.setShadow(offset: .zero, blur: 0, color: nil)

                let fontSize: CGFloat = 20
                let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: fontSize)]
                let emojiStr = emoji as NSString
                let stringSize = emojiStr.size(withAttributes: attrs)
                let x = (totalW - stringSize.width) / 2
                let y = circleY + (circleD - stringSize.height) / 2
                emojiStr.draw(at: CGPoint(x: x, y: y), withAttributes: attrs)
            }
        }

        // MARK: Cluster Bubble Image

        /// 圆角矩形气泡 + 底部小尖头，显示最多 2 个 emoji + 剩余数量 +N
        /// 风格参考 Apple「查找」App 的聚合标注
        private func clusterBubbleImage(emojis: [String], totalCount: Int) -> UIImage {
            let maxShown = 2
            let shownEmojis = Array(emojis.prefix(maxShown))
            let extraCount = totalCount - shownEmojis.count

            let emojiFont = UIFont.systemFont(ofSize: 22)
            let countFont = UIFont.systemFont(ofSize: 14, weight: .medium)

            let emojiStr = shownEmojis.joined()
            let countStr = extraCount > 0 ? "+\(extraCount)" : ""

            let emojiRect = (emojiStr as NSString).boundingRect(
                with: CGSize(width: 200, height: 40),
                options: .usesLineFragmentOrigin,
                attributes: [.font: emojiFont],
                context: nil
            )
            let countRect = extraCount > 0
                ? (countStr as NSString).boundingRect(
                    with: CGSize(width: 80, height: 40),
                    options: .usesLineFragmentOrigin,
                    attributes: [.font: countFont],
                    context: nil
                  )
                : .zero

            // +N 胶囊 badge 尺寸
            let badgeHPad: CGFloat = extraCount > 0 ? 7 : 0
            let badgeVPad: CGFloat = extraCount > 0 ? 3 : 0
            let badgeW = extraCount > 0 ? countRect.width + badgeHPad * 2 : 0
            let badgeH = extraCount > 0 ? countRect.height + badgeVPad * 2 : 0

            let spacing: CGFloat = extraCount > 0 ? 8 : 0
            let contentW = emojiRect.width + spacing + badgeW
            let contentH = max(emojiRect.height, badgeH)

            let hPad: CGFloat = 16
            let vPad: CGFloat = 10
            let cornerRadius: CGFloat = 20
            let bodyW = contentW + hPad * 2
            let bodyH = contentH + vPad * 2

            let pointH: CGFloat = 7
            let pointHalfW: CGFloat = 6

            let totalW = bodyW
            let totalH = bodyH + pointH
            let bodyRect = CGRect(x: 0, y: 0, width: totalW, height: bodyH)

            // 气泡背景：自适应深色模式
            let bubbleColor = UIColor { trait in
                switch trait.userInterfaceStyle {
                case .dark:
                    return UIColor(white: 0.22, alpha: 0.96)
                default:
                    return UIColor(white: 0.97, alpha: 0.96)
                }
            }

            // +N badge 底色：深色模式下更灰
            let badgeBgColor = UIColor { trait in
                switch trait.userInterfaceStyle {
                case .dark:
                    return UIColor(white: 0.32, alpha: 1)
                default:
                    return UIColor(white: 0.92, alpha: 1)
                }
            }

            return UIGraphicsImageRenderer(size: CGSize(width: totalW, height: totalH)).image { ctx in
                let cgContext = ctx.cgContext

                // 阴影
                cgContext.setShadow(offset: CGSize(width: 0, height: 2), blur: 8,
                                    color: UIColor.black.withAlphaComponent(0.15).cgColor)

                // 气泡主体
                bubbleColor.setFill()
                let bodyPath = UIBezierPath(roundedRect: bodyRect, cornerRadius: cornerRadius)
                bodyPath.fill()

                // 底部小尖头
                let midX = totalW / 2
                let triPath = UIBezierPath()
                triPath.move(to: CGPoint(x: midX - pointHalfW, y: bodyH - 1))
                triPath.addLine(to: CGPoint(x: midX, y: totalH))
                triPath.addLine(to: CGPoint(x: midX + pointHalfW, y: bodyH - 1))
                triPath.close()
                triPath.fill()

                // 重置阴影再绘制文字
                cgContext.setShadow(offset: .zero, blur: 0, color: nil)

                // Emoji
                let baseY = (bodyH - contentH) / 2
                (emojiStr as NSString).draw(
                    at: CGPoint(x: hPad, y: baseY + (contentH - emojiRect.height) / 2),
                    withAttributes: [.font: emojiFont]
                )

                // +N 胶囊 badge
                if extraCount > 0 {
                    let badgeX = hPad + emojiRect.width + spacing
                    let badgeY = baseY + (contentH - badgeH) / 2
                    let badgeRect = CGRect(x: badgeX, y: badgeY, width: badgeW, height: badgeH)

                    let badgePath = UIBezierPath(
                        roundedRect: badgeRect,
                        cornerRadius: badgeH / 2
                    )
                    badgeBgColor.setFill()
                    badgePath.fill()

                    (countStr as NSString).draw(
                        at: CGPoint(
                            x: badgeX + badgeHPad,
                            y: badgeY + (badgeH - countRect.height) / 2
                        ),
                        withAttributes: [
                            .font: countFont,
                            .foregroundColor: UIColor.secondaryLabel
                        ]
                    )
                }
            }
        }

        // MARK: Annotation View（单物品 emoji pin + cluster 聚合）

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            // --- 聚合 cluster：椭圆形气泡 + emoji + +N ---
            if let cluster = annotation as? MKClusterAnnotation {
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: "Cluster", for: cluster
                )
                view.canShowCallout = false
                view.displayPriority = .defaultHigh

                let memberEmojis = cluster.memberAnnotations
                    .compactMap { ($0 as? ItemPoint)?.emoji }
                let freq = Dictionary(memberEmojis.map { ($0, 1) }, uniquingKeysWith: +)
                let sortedEmojis = freq.sorted { $0.value > $1.value }.map(\.key)
                let shownEmojis = Array(sortedEmojis.prefix(2))
                let totalCount = cluster.memberAnnotations.count

                let img = clusterBubbleImage(emojis: shownEmojis, totalCount: totalCount)
                view.image = img
                view.frame.size = img.size
                view.centerOffset = CGPoint(x: 0, y: -img.size.height / 2)

                return view
            }

            // --- 单个物品 ---
            guard let point = annotation as? ItemPoint else { return nil }

            let view = mapView.dequeueReusableAnnotationView(
                withIdentifier: "Pin", for: point
            ) as! MKAnnotationView

            view.annotation = point
            view.canShowCallout = false
            view.isDraggable = false
            view.isEnabled = true
            view.clusteringIdentifier = "item"   // ← 启用原生聚类

            view.image = pinImage(emoji: point.emoji)
            view.frame.size = CGSize(width: 40, height: 46)
            view.centerOffset = CGPoint(x: 0, y: -20)

            // 每次复用重建手势
            view.gestureRecognizers?.removeAll()

            let tap = UITapGestureRecognizer(target: self, action: #selector(handlePinTap(_:)))
            view.addGestureRecognizer(tap)

            let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handlePinLongPress(_:)))
            longPress.minimumPressDuration = 0.15
            view.addGestureRecognizer(longPress)

            tap.require(toFail: longPress)

            return view
        }

        // MARK: - Tap（点击 → 详情）

        @objc private func handlePinTap(_ gesture: UITapGestureRecognizer) {
            guard let pinView = gesture.view as? MKAnnotationView,
                  let point = pinView.annotation as? ItemPoint else { return }
            onTapItem?(point.itemId)
        }

        // MARK: - Long Press → 拖拽

        @objc private func handlePinLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard let mapView = mapView,
                  let pinView = gesture.view as? MKAnnotationView,
                  let point = pinView.annotation as? ItemPoint else { return }

            let touchPoint = gesture.location(in: mapView)

            switch gesture.state {
            case .began:
                draggingItemId = point.itemId
                let pinScreenPoint = mapView.convert(point.coordinate, toPointTo: mapView)
                dragTouchOffset = CGPoint(
                    x: pinScreenPoint.x - touchPoint.x,
                    y: pinScreenPoint.y - touchPoint.y
                )
                onMoveStarted?(point.itemId)

                pinView.image = pinImage(emoji: point.emoji, dragging: true)
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
            guard let point = view.annotation as? ItemPoint else { return }
            view.image = pinImage(emoji: point.emoji, dragging: false)
            UIView.animate(withDuration: 0.2) {
                view.transform = .identity
            }
        }

        // MARK: didSelect

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            // 聚类保留选中状态，支持原生点击放大动画
            if view.annotation is MKClusterAnnotation { return }
            mapView.deselectAnnotation(view.annotation, animated: false)
        }
    }
}
