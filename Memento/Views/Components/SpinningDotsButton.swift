//
//  SpinningDotsButton.swift
//  Memento
//
//  Created by WeiAnUppp on 2026/7/23.
//
//  左上角后台 AI 分析加载指示器 —— 旋转圆点 + 玻璃圆形按钮

import SwiftUI

// MARK: - Spinning Dots Button

/// 玻璃圆形按钮（50×50），内含 8 个旋转小圆点，表示后台 AI 分析进行中
struct SpinningDotsButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SpinningDotsView()
                .frame(width: 50, height: 50)
        }
        .glassEffect(.regular.interactive(), in: .circle)
        .tint(.primary)
    }
}

// MARK: - Spinning Dots View

/// 8 个小圆点均匀分布在圆环上，整体匀速旋转。
///
/// 性能关键：不用 TimelineView（每帧都会重建 8 个子视图 + 让外层 glassEffect
/// 跟着每帧重采样背景 → 卡顿）。改为**静态视图树 + rotationEffect 无限动画**：
/// 旋转由 Core Animation 渲染服务器（GPU）驱动，主线程每帧零开销，玻璃只采样一次。
struct SpinningDotsView: View {
    private let dotCount = 8
    private let radius: CGFloat = 9
    private let dotSize: CGFloat = 3.5
    private let rotationSpeed: TimeInterval = 7.0  // 一圈秒数

    @State private var spinning = false

    var body: some View {
        ZStack {
            ForEach(0..<dotCount, id: \.self) { i in
                let angle = Double(i) / Double(dotCount) * 2 * .pi
                Circle()
                    .fill(.primary)
                    .frame(width: dotSize, height: dotSize)
                    .offset(x: radius * cos(angle), y: radius * sin(angle))
            }
        }
        .rotationEffect(.degrees(spinning ? 360 : 0))
        .onAppear {
            // 一次性开启无限线性旋转，交给渲染服务器，主线程不参与逐帧计算
            withAnimation(.linear(duration: rotationSpeed).repeatForever(autoreverses: false)) {
                spinning = true
            }
        }
    }
}

#Preview {
    SpinningDotsButton {}
        .padding()
}
