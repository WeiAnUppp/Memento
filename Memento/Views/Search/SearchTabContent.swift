import SwiftUI

struct SearchTabContent: View {
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            Group {
                if searchText.isEmpty {
                    ContentUnavailableView(
                        "搜索物品",
                        systemImage: "magnifyingglass",
                        description: Text("输入关键词查找你记录过的物品")
                    )
                } else {
                    List {
                        Text("搜索结果")
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("搜索")
        }
        .searchable(text: $searchText)
    }
}
