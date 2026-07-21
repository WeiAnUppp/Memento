import SwiftUI
import MapKit

struct MapHomeView: View {
    @State private var viewModel = MapViewModel()

    var body: some View {
        Map(position: $viewModel.cameraPosition) {
            ForEach(viewModel.items) { item in
                Annotation(item.name, coordinate: item.coordinate) {
                    ItemAnnotation(item: item)
                        .onTapGesture { viewModel.selectedItem = item }
                }
            }
        }
        .mapStyle(.standard)
        .ignoresSafeArea(edges: .top)
    }
}
