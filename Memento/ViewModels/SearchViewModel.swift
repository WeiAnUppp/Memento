import SwiftUI

@Observable
final class SearchViewModel {
    var queryText: String = ""
    var results: [SearchResult] = []
    var isSearching: Bool = false

    func performSearch() {
        guard !queryText.isEmpty else { return }
        // TODO: Day 10 — 混合搜索（MiMo 关键词 + Apple NL 向量 + 文本匹配）
    }
}
