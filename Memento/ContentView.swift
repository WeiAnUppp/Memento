import SwiftUI

struct ContentView: View {
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TabView {
                Tab("地图", systemImage: "map") {
                    MapHomeView()
                }

                Tab("列表", systemImage: "list.bullet") {
                    ItemListView()
                }

                Tab("设置", systemImage: "gearshape") {
                    SettingsView()
                }

                Tab(role: .search) {
                    SearchTabContent()
                }
            }

            // 右下角拍照按钮
            Button {
                // TODO: Day 8
            } label: {
                Image(systemName: "camera.fill")
                    .font(.title2)
                    .frame(width: 56, height: 56)
            }
            .glassEffect(.regular.interactive(), in: .circle)
            .padding(.trailing, 20)
            .padding(.bottom, 88)
        }
    }
}

#Preview {
    ContentView()
}
