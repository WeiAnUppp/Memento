//
//  SheetTabView.swift
//  Memento
//
//  Created by 胡杰 on 2026/7/24.
//

import SwiftUI

extension EnvironmentValues {
    @Entry var sheetTabVisibilityProgress: CGFloat = 1
}

struct SheetTabView<Selection: Hashable, TabC: TabContent<Selection>>: View {
    @Binding var selection: Selection
    @TabContentBuilder<Selection> var tabs: TabC
    @State private var tabVisibilityProgress: CGFloat = 0
    var body: some View {
        TabView(selection: $selection) {
            tabs
        }
        .environment(\.sheetTabVisibilityProgress, tabVisibilityProgress)
        .navigationTransition(.crossFade)
        .presentationDetents(detents)
        .presentationBackgroundInteraction(.enabled(upThrough: .large))
        .interactiveDismissDisabled()
        .background {
            Rectangle()
                .foregroundStyle(.clear)
                .onGeometryChange(for: CGSize.self) {
                    $0.size
                } action: { newValue in
                    let height = min(max(newValue.height - 125, 0), 100)
                    let progress = height / 100
                    tabVisibilityProgress = progress
                }
                .ignoresSafeArea()
        }
    }
    
    var detents: Set<PresentationDetent> {
        return [.height(95), .fraction(0.45), .large]
    }
}

#Preview {
    ContentView()
}
