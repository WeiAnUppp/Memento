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

/// 8 个小圆点均匀分布在圆环上，整体匀速旋转
struct SpinningDotsView: View {
    @State private var rotation: Double = 0

    private let dotCount = 8
    private let radius: CGFloat = 9

    var body: some View {
        ZStack {
            ForEach(0..<dotCount, id: \.self) { i in
                let angle = Double(i) / Double(dotCount) * 2 * .pi
                Image(systemName: "circle.fill")
                    .font(.system(size: 3.5))
                    .offset(x: radius * cos(angle), y: radius * sin(angle))
            }
        }
        .rotationEffect(.degrees(rotation))
        .onAppear {
            withAnimation(.linear(duration: 7.0).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}

#Preview {
    SpinningDotsButton {}
        .padding()
}
