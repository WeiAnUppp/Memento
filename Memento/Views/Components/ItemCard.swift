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
        VStack(alignment: .leading, spacing: 8) {
            Text(item.name)
                .font(.headline)
            Text(item.itemDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }
}
