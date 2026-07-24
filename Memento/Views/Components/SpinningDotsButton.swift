//
//  SpinningDotsButton.swift
//  Memento
//
//  Created by WeiAnUppp on 2026/7/23.
//
//  左上角后台 AI 分析加载指示器 —— 旋转圆点 + 玻璃圆形按钮

import SwiftUI

// MARK: - Spinning Dots Button

/// 玻璃圆形按钮（50×50），内含 8 个旋转小圆点，表示后台 AI 分析进行中。
///
/// 分析完成时先触发圆点收拢动画（内部 scale，不触发 glass re-sample），
/// 收拢完成后外层再做淡出，整体消失过程流畅不卡顿。
struct SpinningDotsButton: View {
    let action: () -> Void
    /// 外部设为 true 触发完成收拢动画
    @Binding var isCompleting: Bool
    /// 完成动画全部结束后回调，外层接到后隐藏整个按钮
    let onCompletionFinished: () -> Void

    var body: some View {
        Button(action: action) {
            SpinningDotsView(isCompleting: $isCompleting, onCompletionFinished: onCompletionFinished)
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
///
/// 颜色关键：使用 SF Symbol `circle.fill`（而非 `Circle()` shape），保证与
/// 同页面筛选按钮（`line.horizontal.3.decrease`）走同一条 glass tint 渲染管线，
/// 颜色完全一致。
struct SpinningDotsView: View {
    private let dotCount = 8
    private let radius: CGFloat = 9
    private let dotSize: CGFloat = 3.5
    private let rotationSpeed: TimeInterval = 7.0  // 一圈秒数

    @State private var spinning = false
    /// 收拢动画专用：每个圆点独立缩放 → 0
    @State private var dotScales: [CGFloat] = Array(repeating: 1, count: 8)
    /// 整体透明度，收拢时跟随淡出
    @State private var groupOpacity: Double = 1

    @Binding var isCompleting: Bool
    let onCompletionFinished: () -> Void

    var body: some View {
        ZStack {
            ForEach(0..<dotCount, id: \.self) { i in
                let angle = Double(i) / Double(dotCount) * 2 * .pi
                Image(systemName: "circle.fill")
                    .font(.system(size: dotSize))
                    .scaleEffect(dotScales[i])
                    .offset(x: radius * cos(angle), y: radius * sin(angle))
            }
        }
        .opacity(groupOpacity)
        .rotationEffect(.degrees(spinning ? 360 : 0))
        .onAppear {
            withAnimation(.linear(duration: rotationSpeed).repeatForever(autoreverses: false)) {
                spinning = true
            }
        }
        .onChange(of: isCompleting) { _, completing in
            guard completing else { return }
            // 阶段 1：圆点逐个收拢 + 整体淡出（0.5s spring）
            withAnimation(.spring(response: 0.45, dampingFraction: 0.65)) {
                groupOpacity = 0
            }
            for i in 0..<dotCount {
                let delay = Double(i) * 0.03
                withAnimation(.spring(response: 0.35, dampingFraction: 0.55).delay(delay)) {
                    dotScales[i] = 0.01
                }
            }
            // 阶段 2：动画播完后通知外层
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                onCompletionFinished()
            }
        }
    }
}

#Preview {
    SpinningDotsButton(
        action: {},
        isCompleting: .constant(false),
        onCompletionFinished: {}
    )
    .padding()
}
