import Foundation

struct SearchResult: Identifiable {
    let item: Item
    let score: Double
    var id: Int64 { item.id ?? 0 }
}
