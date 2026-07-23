//
//  CaptureOverlay.swift
//  Memento
//
//  Created by WeiAnUppp on 2026/7/23.
//
//  从 CaptureView 提取的可复用 UI 组件，供 ContentView 的底部栏浮层使用

import SwiftUI

// MARK: - Photo Card Stack

/// 照片卡片堆叠 — 多张图片可滑动浏览
struct PhotoCardStack: View {
    let images: [UIImage]
    @Binding var mainImageIndex: Int
    @Binding var dragOffset: CGSize
    let cardSize: CGFloat
    var onRemove: ((Int) -> Void)?

    var body: some View {
        let count = images.count
        let safeIndex = min(max(mainImageIndex, 0), max(count - 1, 0))

        return VStack(spacing: 12) {
            if images.isEmpty {
                RoundedRectangle(cornerRadius: 24)
                    .fill(.quaternary)
                    .frame(width: cardSize, height: cardSize)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.system(size: 44))
                            .foregroundStyle(.tertiary)
                    }
            } else {
                ZStack {
                    // 用图片索引作 ForEach id，SwiftUI 可追踪同一张卡片在不同深度的位移
                    let startIdx = safeIndex
                    let endIdx = min(startIdx + 3, count)
                    ForEach(startIdx..<endIdx, id: \.self) { idx in
                        let depth = idx - safeIndex
                        cardView(
                            image: images[idx],
                            depth: depth,
                            isTop: depth == 0,
                            index: idx
                        )
                        .zIndex(Double(-depth))
                    }
                }
                .frame(width: cardSize, height: cardSize)
                // 流体弹簧：自然减速感，高阻尼不弹跳
                .animation(.spring(response: 0.35, dampingFraction: 0.82), value: safeIndex)

                // 页码指示器
                if count > 1 {
                    HStack(spacing: 6) {
                        ForEach(0..<count, id: \.self) { index in
                            Capsule()
                                .fill(index == safeIndex ? Color.primary : Color.secondary.opacity(0.25))
                                .frame(width: index == safeIndex ? 16 : 6, height: 6)
                                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: safeIndex)
                        }
                    }
                }
            }
        }
    }

    private func cardView(image: UIImage, depth: Int, isTop: Bool, index: Int) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: cardSize, height: cardSize)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.12), radius: 10, y: 5)
            .scaleEffect(depth == 0 ? 1 : 1 - CGFloat(depth) * 0.04)
            .offset(y: CGFloat(depth) * 8)
            .opacity(depth == 0 ? 1 : 0.45 - Double(depth) * 0.15)
            .offset(x: isTop ? dragOffset.width : 0)
            // 右上角删除按钮 — iOS 26 玻璃圆按钮，仅顶层卡片显示，带弹性动画
            .overlay(alignment: .topTrailing) {
                if let onRemove {
                    Button {
                        onRemove(index)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 32, height: 32)
                    }
                    .glassEffect(.regular.interactive(), in: .circle)
                    .tint(.primary)
                    .padding(8)
                    .opacity(isTop ? 1 : 0)
                    .scaleEffect(isTop ? 1 : 0.5)
                    .blur(radius: isTop ? 0 : 4)
                    .animation(.spring(response: 0.35, dampingFraction: 0.72), value: isTop)
                    .allowsHitTesting(isTop)
                }
            }
    }
}

// MARK: - Analysis Overlay

/// AI 分析中 — 显示图片 + 进度
struct AnalysisOverlay: View {
    let image: UIImage?

    var body: some View {
        VStack(spacing: 20) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
            }
            ProgressView("AI 正在识别物品…")
                .font(.headline)
            Text("结合你提供的信息分析物品特征")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .padding(.horizontal, 16)
    }
}

// MARK: - AI Result Overlay

/// AI 识别结果预览卡片
struct AIResultOverlay: View {
    let response: AIResponse
    @Binding var editedName: String
    let onSave: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let emoji = response.emoji {
                    HStack(spacing: 8) {
                        Text(emoji).font(.largeTitle)
                        Text("AI 推荐图标").font(.subheadline).foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("物品名称").font(.subheadline).foregroundStyle(.secondary)
                    TextField("物品名称", text: $editedName)
                        .font(.title3).bold()
                        .textFieldStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("描述").font(.subheadline).foregroundStyle(.secondary)
                    Text(response.description)
                        .font(.body)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassEffect(.regular, in: .rect(cornerRadius: 12))
                }

                if !response.scene.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("场景").font(.subheadline).foregroundStyle(.secondary)
                        Text(response.scene)
                            .font(.body)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassEffect(.regular, in: .rect(cornerRadius: 12))
                    }
                }

                if !response.keywords.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("关键词").font(.subheadline).foregroundStyle(.secondary)
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 80), spacing: 8)],
                            spacing: 8
                        ) {
                            ForEach(Array(response.keywords.keys.sorted()), id: \.self) { key in
                                HStack(spacing: 4) {
                                    Text(key)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Text(response.keywords[key] ?? "")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .glassEffect(.regular, in: .capsule)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: 340)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .padding(.horizontal, 16)
    }
}

// MARK: - Capture Error Overlay

/// 记录错误状态
struct CaptureErrorOverlay: View {
    let message: String
    let onRetry: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange)

            Text("出错了")
                .font(.title3)
                .fontWeight(.semibold)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .padding(.horizontal, 16)
    }
}

// MARK: - Saving Overlay

/// 保存中
struct SavingOverlay: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .font(.headline)
            Text("正在保存…")
                .font(.headline)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .padding(.horizontal, 16)
    }
}

// MARK: - Swipe Gesture Helper

extension PhotoCardStack {
    var swipeGesture: some Gesture {
        DragGesture()
            .onChanged { dragOffset = $0.translation }
            .onEnded { value in
                let count = images.count
                guard count > 0 else {
                    dragOffset = .zero
                    return
                }
                let threshold: CGFloat = 60
                var newIndex = mainImageIndex
                if value.translation.width < -threshold, newIndex < count - 1 {
                    newIndex += 1
                } else if value.translation.width > threshold, newIndex > 0 {
                    newIndex -= 1
                }
                newIndex = min(max(newIndex, 0), count - 1)

                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    mainImageIndex = newIndex
                    dragOffset = .zero
                }
            }
    }
}
