//
//  ItemAnnotation.swift
//  Memento
//
//  Created by WeiAnUppp on 2026/7/21.
//

import SwiftUI

struct ItemAnnotation: View {
    let item: Item
    var isMoving: Bool = false

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: "mappin.circle.fill")
                .font(.title)
                .foregroundStyle(isMoving ? .orange : .blue)
                .shadow(radius: isMoving ? 8 : 0)
            Text(item.name)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .glassEffect(.regular, in: .capsule)
        }
        .scaleEffect(isMoving ? 1.25 : 1.0)
        .animation(.bouncy(duration: 0.3), value: isMoving)
    }
}
