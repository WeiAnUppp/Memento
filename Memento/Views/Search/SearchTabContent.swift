//
//  SearchTabContent.swift
//  Memento
//
//  Created by WeiAnUppp on 2026/7/21.
//

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
                            .foregroundStyle(.secondary)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("搜索")
        }
        .searchable(text: $searchText)
    }
}
