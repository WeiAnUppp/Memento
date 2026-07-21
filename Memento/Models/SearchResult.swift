//
//  SearchResult.swift
//  Memento
//
//  Created by WeiAnUppp on 2026/7/21.
//

import Foundation

struct SearchResult: Identifiable {
    let item: Item
    let score: Double
    var id: Int64 { item.id ?? 0 }
}
