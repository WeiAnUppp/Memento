import SwiftUI
import MapKit

struct MapHomeView: View {
    @State private var viewModel = MapViewModel()

    var body: some View {
        ZStack {
            Map(position: $viewModel.cameraPosition) {
                ForEach(viewModel.items) { item in
                    Annotation(item.name, coordinate: item.coordinate) {
                        ItemAnnotation(item: item)
                            .onTapGesture { viewModel.selectedItem = item }
                    }
                }
            }
            .mapStyle(.standard)

            // 右下角拍照按钮
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button {
                        // TODO: Day 8 — 跳转拍照
                    } label: {
                        Image(systemName: "camera.fill")
                            .font(.title2)
                    }
                    .glassEffect(.regular.interactive(), in: .circle)
                    .controlSize(.extraLarge)
                    .padding(.trailing, 20)
                    .padding(.bottom, 80)
                }
            }
        }
        .ignoresSafeArea(edges: .top)
    }
}
