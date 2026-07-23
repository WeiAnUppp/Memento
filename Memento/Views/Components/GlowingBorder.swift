//
//  GlowingBorder.swift
//  Memento
//
//  Created by WeiAnUppp on 2026/7/23.
//
//  渐变发光边框 — TimelineView 驱动，丝滑 60fps 旋转渐变
//  用于提示用户输入描述等需要吸引注意力的交互区域

import SwiftUI

// MARK: - Glowing Border Modifier

/// 渐变发光边框，使用 TimelineView 实现丝滑连续动画
struct GlowingBorder: ViewModifier {
    /// 边框形状
    enum GlowShape {
        case capsule
        case roundedRect(cornerRadius: CGFloat)
    }

    let shape: GlowShape
    let lineWidth: CGFloat
    let glowRadius: CGFloat
    let isActive: Bool

    /// 白色渐变停靠点 — 明暗交替营造流光质感
    private let gradientStops: [Gradient.Stop] = [
        .init(color: .white.opacity(0.55), location: 0.0),
        .init(color: .white.opacity(0.28), location: 0.2),
        .init(color: .white.opacity(0.50), location: 0.4),
        .init(color: .white.opacity(0.12), location: 0.55),
        .init(color: .white.opacity(0.45), location: 0.75),
        .init(color: .white.opacity(0.22), location: 0.9),
        .init(color: .white.opacity(0.55), location: 1.0),
    ]

    func body(content: Content) -> some View {
        if isActive {
            content
                .overlay {
                    glowOverlay
                        .allowsHitTesting(false)
                }
        } else {
            content
        }
    }

    /// 发光层：外层模糊辉光 + 内层清晰描边
    @ViewBuilder
    private var glowOverlay: some View {
        TimelineView(.animation) { timeline in
            let seconds = timeline.date.timeIntervalSince1970
            let phase = (seconds.truncatingRemainder(dividingBy: 5) / 5) * 360

            let gradient = AngularGradient(
                gradient: Gradient(stops: gradientStops),
                center: .center,
                angle: .degrees(phase)
            )

            ZStack {
                // 外层：模糊辉光
                shapeView
                    .stroke(gradient, lineWidth: lineWidth + glowRadius)
                    .blur(radius: glowRadius)
                    .opacity(0.7)

                // 内层：清晰描边
                shapeView
                    .stroke(gradient, lineWidth: lineWidth)
                    .opacity(0.85)
            }
        }
    }

    private var shapeView: AnyShape {
        switch shape {
        case .capsule:
            AnyShape(Capsule())
        case .roundedRect(let cornerRadius):
            AnyShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}

// MARK: - View Extension

extension View {
    /// 添加渐变发光边框
    /// - Parameters:
    ///   - shape: 边框形状，`.capsule` 或 `.roundedRect(cornerRadius:)`
    ///   - lineWidth: 描边宽度，默认 1.5
    ///   - glowRadius: 辉光模糊半径，默认 4
    func glowingBorder(
        shape: GlowingBorder.GlowShape,
        lineWidth: CGFloat = 1.5,
        glowRadius: CGFloat = 4,
        isActive: Bool = true
    ) -> some View {
        modifier(GlowingBorder(
            shape: shape,
            lineWidth: lineWidth,
            glowRadius: glowRadius,
            isActive: isActive
        ))
    }
}
