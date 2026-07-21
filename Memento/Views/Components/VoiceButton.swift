import SwiftUI

struct VoiceButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "mic.fill")
                .font(.title3)
        }
        .glassEffect(.regular.interactive(), in: .circle)
    }
}
