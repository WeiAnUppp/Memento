//
//  ItemGridCard.swift
//  Memento
//
//  Created by WeiAnUppp on 2026/7/25.
//

import SwiftUI

struct ItemGridCard: View {
    let item: Item

    /// 位置文本缩略（取前6字）
    private var shortLocation: String {
        guard let scene = item.scene, !scene.isEmpty else { return "" }
        if scene.count <= 6 { return scene }
        return String(scene.prefix(6))
    }

    var body: some View {
        Color.clear
            .overlay {
                ZStack(alignment: .bottomLeading) {
                    // 背景图片
                    backgroundImage

                    // 底部渐变遮罩
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.4),
                            .init(color: .black.opacity(0.55), location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    // 文字区 — Spacer 将标题+副标题整体压到底部
                    VStack(alignment: .leading, spacing: 4) {
                        Spacer(minLength: 0)

                        Text(item.name)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        HStack(spacing: 4) {
                            if !shortLocation.isEmpty {
                                Text(shortLocation)
                                Text("·")
                                    .foregroundStyle(.white.opacity(0.35))
                            }
                            Text(item.createdAt.friendlyChineseFormat)
                        }
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                    }
                    .frame(maxHeight: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }
            .clipped()
    }

    // MARK: - Background

    @ViewBuilder
    private var backgroundImage: some View {
        if let firstPath = item.imagePaths.first,
           let url = DatabaseService.imageURL(for: firstPath),
           let data = try? Data(contentsOf: url),
           let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            LinearGradient(
                colors: [.indigo, .purple.opacity(0.7)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay {
                Text(item.emoji ?? "📦")
                    .font(.system(size: 44))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }
}
