//
//  MementoApp.swift
//  Memento
//
//  Created by WeiAnUppp on 2026/7/21.
//

import SwiftUI

@main
struct MementoApp: App {
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system

    init() {
        // 启动时按需重建搜索索引（旧向量含 JSON 噪声，与查询不对齐）
        SearchIndexService.reindexIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(appearanceMode.colorScheme)
        }
    }
}
