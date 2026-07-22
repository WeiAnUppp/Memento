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
    @State private var showSearch = false
    @State private var settingsNavigationDepth = 0

    /// 设置页使用原生大标题导航栏，不需要自定义顶栏
    private var showCustomTopBar: Bool {
        selectedPage != .settings
    }

    /// 底部搜索栏：设置页子页面隐藏，其他始终显示
    private var showBottomBar: Bool {
        if selectedPage == .settings && settingsNavigationDepth > 0 {
            return false
        }
        return true
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            pageContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showCustomTopBar {
                VStack(spacing: 0) {
                    customTopBar
                    Spacer()
                }
            }

            bottomNavBar
                .padding(.horizontal, 23)
                .padding(.bottom, 18)
                .offset(y: showBottomBar ? 0 : 80)
                .opacity(showBottomBar ? 1 : 0)
                .animation(.smooth(duration: 0.35), value: showBottomBar)
        }
        .fullScreenCover(isPresented: $showSearch) {
            SearchModalView()
        }
    }

    // MARK: - Custom Top Bar（地图、列表）

    private var customTopBar: some View {
        HStack(alignment: .center) {
            Spacer()

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
        .padding(.top, 4)
        .padding(.bottom, 0)
    }

    // MARK: - Bottom Nav Bar

    private var bottomNavBar: some View {
        HStack(spacing: 8) {
            Button {
                showSearch = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.primary)
                    Text("搜索物品...")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "mic.fill")
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 14)
                .frame(height: 50)
                .glassEffect(.regular, in: .capsule)
            }
            .buttonStyle(.plain)
            .tint(.primary)

            Menu {
                Button { } label: {
                    Label("照片", systemImage: "photo.on.rectangle")
                }
                Button { } label: {
                    Label("相机", systemImage: "camera.fill")
                }
            } label: {
                Image(systemName: "plus")
                    .font(.title3)
                    .fontWeight(.medium)
                    .frame(width: 50, height: 50)
            }
            .glassEffect(.regular.interactive(), in: .circle)
            .tint(.primary)
        }
    }

    // MARK: - Page Content

    @ViewBuilder
    private var pageContent: some View {
        switch selectedPage {
        case .map:
            MapHomeView()

        case .list:
            ItemListView()
                .padding(.top, 66)

        case .settings:
            SettingsView(
                selectedPage: $selectedPage,
                navigationDepth: $settingsNavigationDepth
            )
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
                    Button("关闭") { dismiss() }
                }
            }
        }
        .searchable(text: $searchText)
    }
}

#Preview {
    ContentView()
}
