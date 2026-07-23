//
//  ItemCard.swift
//  Memento
//
//  Created by WeiAnUppp on 2026/7/21.
//

import SwiftUI

struct ItemCard: View {
    let item: Item

    var body: some View {
        HStack(spacing: 14) {
            // 左侧：缩略图
            thumbnailView

            // 右侧：名称 + 位置·时间
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.headline)
                    .lineLimit(1)

                locationAndDate
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.quaternary, lineWidth: 0.5)
        )
    }

    // MARK: - Thumbnail

    @ViewBuilder
    private var thumbnailView: some View {
        if let imagePath = item.imagePath,
           let url = DatabaseService.imageURL(for: imagePath),
           let data = try? Data(contentsOf: url),
           let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(.quaternary)
                .frame(width: 64, height: 64)
                .overlay {
                    Text(item.emoji ?? "📦")
                        .font(.system(size: 28))
                }
        }
    }

    // MARK: - Location & Date

    private var locationAndDate: some View {
        HStack(spacing: 4) {
            if let scene = item.scene, !scene.isEmpty {
                Text(scene)
            }
            if item.scene?.isEmpty == false {
                Text("·")
                    .foregroundStyle(.tertiary)
            }
            Text(item.createdAt.friendlyChineseFormat)
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}
