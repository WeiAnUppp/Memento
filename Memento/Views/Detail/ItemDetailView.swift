//
//  ItemDetailView.swift
//  Memento
//
//  Created by WeiAnUppp on 2026/7/21.
//

import SwiftUI

// MARK: - Emoji 分组

private let emojiGroups: [(String, [String])] = [
    ("常用", ["📍", "📦", "🔑", "📱", "💻", "👕", "👟", "📚", "💊", "🎧", "💍", "👜"]),
    ("物品", ["📷", "🔦", "💳", "🕶️", "🧸", "📝", "🎮", "⌚", "🔋", "💿", "🎸", "🖊️"]),
    ("标记", ["❤️", "⭐", "🔶", "💎", "🎯", "🔔", "💡", "🏠", "🚗", "🌈", "🔥", "🧲"]),
]

// MARK: - ItemDetailView

struct ItemDetailView: View {
    let item: Item
    var onUpdate: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var selectedEmoji: String
    @State private var currentImageIndex = 0

    init(item: Item, onUpdate: (() -> Void)? = nil) {
        self.item = item
        self.onUpdate = onUpdate
        _selectedEmoji = State(initialValue: item.emoji ?? "📍")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 多图展示
                    let paths = item.imagePaths
                    if !paths.isEmpty {
                        VStack(spacing: 8) {
                            TabView(selection: $currentImageIndex) {
                                ForEach(Array(paths.enumerated()), id: \.offset) { index, imagePath in
                                    if let url = DatabaseService.imageURL(for: imagePath),
                                       let data = try? Data(contentsOf: url),
                                       let uiImage = UIImage(data: data) {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(maxHeight: 280)
                                            .clipShape(RoundedRectangle(cornerRadius: 16))
                                            .tag(index)
                                    } else {
                                        // 图片加载失败时显示占位
                                        VStack(spacing: 8) {
                                            Image(systemName: "photo.badge.exclamationmark")
                                                .font(.system(size: 40))
                                                .foregroundStyle(.secondary)
                                            Text("图片加载失败")
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }
                                        .frame(maxHeight: 280)
                                        .tag(index)
                                    }
                                }
                            }
                            .tabViewStyle(.page(indexDisplayMode: .always))
                            .frame(height: 300)

                            // 图片计数
                            if paths.count > 1 {
                                Text("\(currentImageIndex + 1) / \(paths.count)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    // 图标选择
                    emojiPickerSection

                    // 物品名称
                    VStack(alignment: .leading, spacing: 4) {
                        Text("物品名称").font(.caption).foregroundStyle(.secondary)
                        Text(item.name).font(.title2).fontWeight(.semibold)
                    }

                    // 描述
                    VStack(alignment: .leading, spacing: 4) {
                        Text("描述").font(.caption).foregroundStyle(.secondary)
                        Text(item.itemDescription).font(.body)
                    }

                    // 场景
                    if let scene = item.scene, !scene.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("所在场景").font(.caption).foregroundStyle(.secondary)
                            Text(scene).font(.body)
                        }
                    }

                    // 用户备注
                    if let note = item.userNote, !note.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("备注").font(.caption).foregroundStyle(.secondary)
                            Text(note).font(.body)
                        }
                    }

                    // 时间
                    VStack(alignment: .leading, spacing: 4) {
                        Text("记录时间").font(.caption).foregroundStyle(.secondary)
                        Text(item.createdAt.formatted(date: .long, time: .shortened))
                            .font(.subheadline)
                    }
                }
                .padding(20)
            }
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    // MARK: - Emoji Picker

    private var emojiPickerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("图标").font(.caption).foregroundStyle(.secondary)

            ForEach(emojiGroups, id: \.0) { group in
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.0).font(.caption2).foregroundStyle(.tertiary)
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 8),
                        spacing: 6
                    ) {
                        ForEach(group.1, id: \.self) { emoji in
                            Button {
                                selectedEmoji = emoji
                                saveEmoji(emoji)
                            } label: {
                                Text(emoji)
                                    .font(.title3)
                                    .frame(width: 38, height: 38)
                                    .background(
                                        selectedEmoji == emoji
                                            ? Color.blue.opacity(0.15)
                                            : Color.clear
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(
                                                selectedEmoji == emoji ? Color.blue.opacity(0.4) : Color.clear,
                                                lineWidth: 1.5
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Save

    private func saveEmoji(_ emoji: String) {
        guard let id = item.id else { return }
        do {
            try DatabaseService.shared.updateEmoji(id: id, emoji: emoji)
            onUpdate?()
        } catch {
            print("[ItemDetailView] 更新图标失败: \(error)")
        }
    }
}
