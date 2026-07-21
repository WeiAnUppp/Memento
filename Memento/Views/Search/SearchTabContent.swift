import SwiftUI

struct SearchTabContent: View {
    let searchText: String

    var body: some View {
        Group {
            if searchText.isEmpty {
                ContentUnavailableView(
                    "搜索物品",
                    systemImage: "magnifyingglass",
                    description: Text("输入关键词查找你记录过的物品")
                )
            } else {
                // TODO: Day 10 — 搜索结果列表
                List {
                    Text("搜索结果")
                }
                .listStyle(.plain)
            }
        }
    }
}
