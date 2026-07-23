//
//  SoundWaveView.swift
//  Memento
//
//  Created by WeiAnUppp on 2026/7/23.
//
//  声波动画组件 — TimelineView 驱动的动态音频波形
//  录音时显示在屏幕中央，提供实时视觉反馈

import SwiftUI

// MARK: - Sound Wave View

/// 录音声波动画浮层
/// 包含 5 根动态频条 + 停止按钮，使用 TimelineView 实现 60fps 丝滑动画
struct SoundWaveView: View {
    let onStop: () -> Void

    private let barCount = 5

    var body: some View {
        VStack(spacing: 28) {
            TimelineView(.animation) { timeline in
                let now = timeline.date.timeIntervalSince1970

                HStack(alignment: .center, spacing: 6) {
                    ForEach(0..<barCount, id: \.self) { index in
                        let height = barHeight(for: index, at: now)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.red.opacity(0.85))
                            .frame(width: 5, height: height)
                    }
                }
                .frame(height: 64)
            }

            Button(action: onStop) {
                ZStack {
                    Circle()
                        .fill(.red.opacity(0.15))
                        .frame(width: 56, height: 56)

                    Image(systemName: "stop.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.red)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 44)
        .padding(.vertical, 32)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    private func barHeight(for index: Int, at time: TimeInterval) -> CGFloat {
        let frequencies: [Double] = [3.5, 4.8, 6.0, 4.5, 3.2]
        let amplitudes: [Double] = [20, 48, 64, 48, 20]
        let minHeight: CGFloat = 8

        let i = min(index, barCount - 1)
        let freq = frequencies[i]
        let amp = amplitudes[i]

        let value = sin(time * freq) * 0.7
                  + sin(time * freq * 1.4 + 0.5) * 0.2
                  + sin(time * freq * 2.1 + 1.2) * 0.1

        let normalized = (value + 1) / 2
        return minHeight + normalized * (amp - minHeight)
    }
}

#Preview {
    ZStack {
        Color(.systemBackground).ignoresSafeArea()
        SoundWaveView(onStop: {})
    }
}

// MARK: - Inline Sound Wave

/// 胶囊内嵌声波动画 — 替代"正在聆听…"文字
/// 自适应宽度铺满胶囊，纯动画不依赖音频输入
struct InlineSoundWave: View {
    var body: some View {
        GeometryReader { geometry in
            let barWidth: CGFloat = 2
            let spacing: CGFloat = 2.5
            let totalPerBar = barWidth + spacing
            let count = max(4, Int((geometry.size.width + spacing) / totalPerBar))

            TimelineView(.animation) { timeline in
                let now = timeline.date.timeIntervalSince1970

                HStack(alignment: .center, spacing: 0) {
                    ForEach(0..<count, id: \.self) { index in
                        let height = barHeight(for: index, total: count, at: now)
                        RoundedRectangle(cornerRadius: 1)
                            .fill(.red.opacity(0.65))
                            .frame(width: barWidth, height: height)
                            .padding(.trailing, spacing)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: 28)
    }

    /// 频条高度 — 钟形分布，纯正弦动画
    private func barHeight(for index: Int, total: Int, at time: TimeInterval) -> CGFloat {
        let center = Double(total - 1) / 2.0
        let distFromCenter = abs(Double(index) - center) / max(center, 1)

        let amp = 5 + (1 - distFromCenter * 0.75) * 17
        let minH: CGFloat = 4
        let freq = 3.5 + distFromCenter * 4.0
        let phase = Double(index) * 0.4

        let value = sin(time * freq + phase) * 0.7
                  + sin(time * freq * 1.35 + phase + 1.0) * 0.3

        let normalized = (value + 1) / 2
        return minH + normalized * (amp - minH)
    }
}
