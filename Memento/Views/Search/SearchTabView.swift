import SwiftUI

struct SearchTabView: View {
    @State private var searchText = ""

    var body: some View {
        List {
            if searchText.isEmpty {
                ContentUnavailableView(
                    "搜索物品",
                    systemImage: "magnifyingglass",
                    description: Text("输入关键词或点击麦克风语音搜索")
                )
            } else {
                // TODO: Day 10 — 搜索结果
                Text("搜索结果")
            }
        }
        .listStyle(.plain)
        .searchable(text: $searchText, placement: .toolbar)
    }
}
