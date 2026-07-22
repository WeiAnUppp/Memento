//
//  ItemDetailView.swift
//  Memento
//
//  Created by WeiAnUppp on 2026/7/21.
//

import SwiftUI

struct ItemDetailView: View {
    let item: Item
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 图片
                    if let imagePath = item.imagePath,
                       let url = DatabaseService.imageURL(for: imagePath),
                       let data = try? Data(contentsOf: url),
                       let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 280)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }

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
}
