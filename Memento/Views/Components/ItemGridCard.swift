//
//  ItemGridCard.swift
//  Memento
//
//  Created by 胡杰 on 2026/7/25.
//

import SwiftUI

struct ItemGridCard: View {
    let item: Item

    /// 位置标签：优先 AI 生成的 locationLabel，否则截取场景
    private var shortLocation: String {
        if let loc = item.locationLabel, !loc.isEmpty { return loc }
        if let ds = item.displayScene, !ds.isEmpty { return String(ds.prefix(6)) }
        guard let scene = item.scene, !scene.isEmpty else { return "" }
        return String(scene.prefix(6))
    }

    var body: some View {
        // ① 固定边框 — Color.clear 定义了卡片的确定边界
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // ② 图片填入边框 — 作为背景，填满但绝不改变边框尺寸
            .background { backgroundFill }
            // ③ 渐变遮罩 — 保证白色文字可读
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.4),
                        .init(color: .black.opacity(0.55), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            // ④ 文字贴在边框上 — 相对于 Color.clear 的边界定位，与图片无关
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.headline)
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
                .padding(.leading, 12)
                .padding(.trailing, 12)
                .padding(.bottom, 12)
            }
            .clipped()
    }

    // MARK: - Background（填入边框，永远不改变边框尺寸）

    @ViewBuilder
    private var backgroundFill: some View {
        if let firstPath = item.imagePaths.first,
           let url = DatabaseService.imageURL(for: firstPath),
           let data = try? Data(contentsOf: url),
           let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
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
