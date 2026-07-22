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
    var imagePath: String?
    var createdAt: Date
    var updatedAt: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
