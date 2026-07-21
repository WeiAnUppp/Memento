import SwiftUI
import MapKit

struct MapHomeView: View {
    @State private var viewModel = MapViewModel()
    @State private var locationService = LocationService()

    var body: some View {
        Map(position: $viewModel.cameraPosition) {
            UserAnnotation()

            ForEach(viewModel.items) { item in
                Annotation(item.name, coordinate: item.coordinate) {
                    ItemAnnotation(item: item)
                        .onTapGesture { viewModel.selectedItem = item }
                }
            }
        }
        .mapStyle(.standard)
        .mapControls {
            MapUserLocationButton()
        }
        .ignoresSafeArea(edges: .top)
        .onAppear {
            locationService.requestPermission()
        }
        .task {
            // 等待获取到用户位置后自动定位
            while locationService.currentLocation == nil {
                try? await Task.sleep(for: .milliseconds(200))
            }
            guard let location = locationService.currentLocation else { return }
            withAnimation {
                viewModel.cameraPosition = .region(
                    MKCoordinateRegion(
                        center: location.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                    )
                )
            }
        }
    }
}
