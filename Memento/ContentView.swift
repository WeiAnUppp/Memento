//
//  ContentView.swift
//  Memento
//
//  Created by WeiAnUppp on 2026/7/21.
//

import SwiftUI

// MARK: - App Page

enum AppPage: String, CaseIterable {
    case map = "地图"
    case list = "列表"
    case settings = "设置"

    var icon: String {
        switch self {
        case .map: return "map.fill"
        case .list: return "list.bullet"
        case .settings: return "gearshape.fill"
        }
    }
}

// MARK: - ContentView

struct ContentView: View {
    @State private var selectedPage: AppPage = .map
    @State private var showCapture = false
    @State private var showSearch = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // 页面内容（全屏）
            pageContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // 顶部浮层
            VStack(spacing: 0) {
                topBar
                Spacer()
            }

            // 底部导航栏 【 +  搜索  🎤 】
            bottomNavBar
                .padding(.horizontal, 23)
                .padding(.bottom, 18)
        }
        .fullScreenCover(isPresented: $showSearch) {
            SearchModalView()
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(alignment: .center) {
            // 非地图页面：左上角标题
            if selectedPage != .map {
                Text(selectedPage.rawValue)
                    .font(.title2)
                    .fontWeight(.semibold)
            }

            Spacer()

            // 筛选菜单 — iOS 26 Messages 风格
            Menu {
                Picker("视图", selection: $selectedPage) {
                    ForEach(AppPage.allCases, id: \.self) { page in
                        Label(page.rawValue, systemImage: page.icon)
                            .tag(page)
                    }
                }
            } label: {
                Image(systemName: "line.horizontal.3.decrease")
                    .font(.title2)
                    .frame(width: 50, height: 50)
            }
            .glassEffect(.regular.interactive(), in: .circle)
            .tint(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    // MARK: - Bottom Nav Bar 【 +  搜索  🎤 】

    private var bottomNavBar: some View {
        HStack(spacing: 8) {
            // ⊕ 加号按钮
            Button {
                showCapture = true
            } label: {
                Image(systemName: "plus")
                    .font(.title3)
                    .fontWeight(.medium)
                    .frame(width: 50, height: 50)
            }
            .glassEffect(.regular.interactive(), in: .circle)
            .tint(.primary)

            // 搜索栏
            Button {
                showSearch = true
            } label: {
                Label("搜索物品...", systemImage: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .frame(height: 50)
                    .glassEffect(.regular, in: .capsule)
            }
            .buttonStyle(.plain)
            .tint(.primary)

            // 语音按钮
            Button {
                // TODO: Day 11 — 语音输入
            } label: {
                Image(systemName: "mic.fill")
                    .font(.title3)
                    .frame(width: 50, height: 50)
            }
            .glassEffect(.regular.interactive(), in: .circle)
            .tint(.primary)
        }
    }

    // MARK: - Page Content

    /// 顶部栏高度，用于非地图页面顶部留白
    private var topBarHeight: CGFloat { 66 }

    @ViewBuilder
    private var pageContent: some View {
        switch selectedPage {
        case .map:
            MapHomeView()
        case .list:
            ItemListView()
                .padding(.top, topBarHeight)
        case .settings:
            SettingsView()
                .padding(.top, topBarHeight)
        }
    }
}

// MARK: - Search Modal

private struct SearchModalView: View {
    @Environment(\.dismiss) private var dismiss
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
        .searchable(text: $searchText)
    }
}

#Preview {
    ContentView()
}
