//
//  AIResponse.swift
//  Memento
//
//  Created by WeiAnUppp on 2026/7/21.
//

import Foundation

struct AIResponse: Codable, Equatable {
    let name: String
    let description: String
    let scene: String
    let keywords: [String: String]
    let emoji: String?
}

struct SearchQuery: Codable {
    let keywords: [String: String]
    let searchText: String
}
