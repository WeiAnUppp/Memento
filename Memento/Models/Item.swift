//
//  Item.swift
//  Memento
//
//  Created by WeiAnUppp on 2026/7/21.
//

import Foundation
import CoreLocation

struct Item: Identifiable, Codable, Equatable {
    var id: Int64?
    var name: String
    var itemDescription: String
    var keywords: String?
    var scene: String?
    var userNote: String?
    var latitude: Double
    var longitude: Double
    var emoji: String?
    var imagePath: String?
    var createdAt: Date
    var updatedAt: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// 多图路径（兼容旧单值格式和 JSON 数组格式）
    var imagePaths: [String] {
        guard let imagePath, !imagePath.isEmpty else { return [] }
        if imagePath.hasPrefix("[") {
            return (try? JSONDecoder().decode([String].self, from: Data(imagePath.utf8))) ?? []
        } else {
            return [imagePath]
        }
    }
}
