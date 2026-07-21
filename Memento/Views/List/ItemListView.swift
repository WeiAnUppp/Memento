//
//  ItemListView.swift
//  Memento
//
//  Created by WeiAnUppp on 2026/7/21.
//

import SwiftUI

struct ItemListView: View {
    // TODO: Day 9 — 时间线物品列表
    var body: some View {
        List {
            // TODO: 物品数据
            ContentUnavailableView(
                "暂无物品",
                systemImage: "tray",
                description: Text("拍照记录你的第一个物品")
            )
        }
        .listStyle(.plain)
    }
}
