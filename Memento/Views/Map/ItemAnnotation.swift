import SwiftUI

struct ItemAnnotation: View {
    let item: Item

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: "mappin.circle.fill")
                .font(.title)
                .foregroundStyle(.blue)
            Text(item.name)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .glassEffect(.regular, in: .capsule)
        }
    }
}
