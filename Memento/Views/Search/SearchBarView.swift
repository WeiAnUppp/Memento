//
//  SearchBarView.swift
//  Memento
//
//  Created by WeiAnUppp on 2026/7/21.
//

import SwiftUI

struct SearchBarView: View {
    @Binding var isActive: Bool
    @State private var searchText = ""

    var body: some View {
        HStack(spacing: 12) {
            // 文字输入
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索物品...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .glassEffect(.regular, in: .capsule)

            // 语音按钮
            Button {
                // TODO: Day 11 — 语音输入
            } label: {
                Image(systemName: "mic.fill")
                    .font(.title3)
            }
            .glassEffect(.regular.interactive(), in: .circle)

            // 关闭按钮
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    isActive = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.subheadline)
            }
            .glassEffect(.regular, in: .circle)
        }
    }
}
