//
//  ContentView.swift
//  Memento
//
//  Created by WeiAnUppp on 2026/7/21.
//

import SwiftUI

// MARK: - App Page

enum AppPage: String, CaseIterable {
    case map = "地图"
    case list = "列表"
    case settings = "设置"

    var icon: String {
        switch self {
        case .map: return "map.fill"
        case .list: return "list.bullet"
        case .settings: return "gearshape.fill"
        }
    }
}

// MARK: - ContentView

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedPage: AppPage = .map
    @State private var showSearch = false
    @State private var settingsNavigationDepth = 0

    /// 半屏相机
    @State private var showCameraSheet = false
    /// 半屏照片选择器
    @State private var showPhotoSheet = false
    /// 选图 / 拍照后，待处理的图片
    @State private var pendingImage: UIImage?

    /// 地图共享状态 —— 提升到 ContentView，页面切换时 cameraPosition / items 不丢失
    @State private var mapViewModel = MapViewModel()
    @State private var locationService = LocationService()

    /// 记录物品 ViewModel —— 融入底部栏
    @State private var captureViewModel = CaptureViewModel()

    /// 遮罩+浮层动画专用 Bool — 与 ViewModel 状态解耦，确保动画事务正确传播
    @State private var showRecordingOverlay = false

    /// 输入框焦点，用于键盘动画收起
    @FocusState private var isDescriptionFocused: Bool
    /// 照片卡片交互状态
    @State private var photoCardIndex = 0
    @State private var photoDragOffset: CGSize = .zero

    /// 是否正在记录中（底部栏变身）
    private var isRecording: Bool {
        switch captureViewModel.state {
        case .idle, .saved: return false
        default: return true
        }
    }

    /// 是否正在已有记录中添加更多图片（vs 首次选图）
    private var isAddingMorePhotos: Bool {
        if case .readyForInput = captureViewModel.state { return true }
        return false
    }

    /// 设置页有自己的顶栏，记录时 ContentView 顶栏覆盖上来（变灰不可点）
    private var showCustomTopBar: Bool {
        selectedPage != .settings || isRecording
    }

    /// 底部栏可见性：记录时始终显示
    private var showBottomBar: Bool {
        if isRecording { return true }
        if selectedPage == .settings && settingsNavigationDepth > 0 {
            return false
        }
        if selectedPage == .list && listBarHidden {
            return false
        }
        return true
    }

    /// 列表页滚动时隐藏底部栏
    @State private var listBarHidden = false

    // MARK: - Body

    var body: some View {
        ZStack {
            // 底层：页面内容
            pageContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // 记录时遮罩 — 始终存在，用 opacity 控制显隐（避免 transition 不可靠）
            Color.black
                .ignoresSafeArea()
                .opacity(showRecordingOverlay ? (colorScheme == .dark ? 0.55 : 0.35) : 0)
                .allowsHitTesting(showRecordingOverlay)
                .onTapGesture {
                    isDescriptionFocused = false
                    dismissRecording()
                }
                .animation(.spring(response: 0.55, dampingFraction: 0.82), value: showRecordingOverlay)

            // 顶层：自定义顶栏 — 记录时变灰不可交互，tap 穿透到遮罩退出
            if showCustomTopBar {
                VStack(spacing: 0) {
                    customTopBar
                    Spacer()
                }
                .opacity(isRecording ? 0.45 : 1)
                .animation(.spring(response: 0.55, dampingFraction: 0.82), value: isRecording)
            }

            // 记录浮层 — 始终存在，用 opacity + offset 控制显隐
            captureOverlay
                .opacity(showRecordingOverlay ? 1 : 0)
                .offset(y: showRecordingOverlay ? 0 : 120)
                .allowsHitTesting(showRecordingOverlay)
                .animation(.spring(response: 0.55, dampingFraction: 0.82), value: showRecordingOverlay)

            // 底部栏
            VStack(spacing: 0) {
                Spacer()
                bottomBarContent
                    .padding(.horizontal, 23)
                    .padding(.bottom, 18)
                    .offset(y: showBottomBar ? 0 : 80)
                    .opacity(showBottomBar ? 1 : 0)
                    .animation(.smooth(duration: 0.35), value: showBottomBar)
            }
        }
        // 同步 ViewModel 状态到动画 Bool
        .onChange(of: isRecording) { _, recording in
            showRecordingOverlay = recording
        }
        .fullScreenCover(isPresented: $showSearch) {
            SearchModalView()
        }
        // 相机半屏
        .sheet(isPresented: $showCameraSheet) {
            CameraHalfView { image in
                pendingImage = image
            }
            .presentationDetents([.fraction(0.65)])
            .presentationDragIndicator(.hidden)
        }
        // 照片半屏
        .sheet(isPresented: $showPhotoSheet) {
            PhotoHalfView { image in
                pendingImage = image
            }
            .presentationDragIndicator(.hidden)
        }
        // 选图回调
        .onChange(of: showCameraSheet) { _, showing in
            if !showing { handlePhotoCaptured() }
        }
        .onChange(of: showPhotoSheet) { _, showing in
            if !showing { handlePhotoCaptured() }
        }
        // 保存成功 → 刷新地图并回到搜索模式
        .onChange(of: captureViewModel.state) { _, newState in
            if case .saved = newState {
                mapViewModel.loadItems()
                photoCardIndex = 0
                photoDragOffset = .zero
                // 先播退出动画，动画完成后再 reset ViewModel
                dismissRecording(after: 0.6)
            }
        }
        // 语音识别结果回填
        .onChange(of: captureViewModel.speechService.isRecording) { _, recording in
            if !recording, !captureViewModel.speechService.transcript.isEmpty {
                captureViewModel.userContext = captureViewModel.speechService.transcript
            }
        }
        .onChange(of: selectedPage) { _, _ in
            listBarHidden = false
        }
    }

    // MARK: - Photo Captured Handler

    private func handlePhotoCaptured() {
        guard let image = pendingImage else { return }
        if isAddingMorePhotos {
            captureViewModel.addImage(image, gps: nil)
            photoCardIndex = max(captureViewModel.selectedImages.count - 1, 0)
        } else {
            captureViewModel.didSelectFirstImage(image, gps: nil)
            photoCardIndex = 0
        }
        pendingImage = nil
    }

    // MARK: - Dismiss Recording

    /// 退出记录：设 false → 动画自动播放 → 动画完成后重置 ViewModel
    private func dismissRecording(after delay: TimeInterval = 0) {
        photoCardIndex = 0
        photoDragOffset = .zero
        let dismiss = { showRecordingOverlay = false }
        let reset = { captureViewModel.reset() }
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: dismiss)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.6, execute: reset)
        } else {
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: reset)
        }
    }

    // MARK: - Custom Top Bar

    private var customTopBar: some View {
        HStack(alignment: .center) {
            Spacer()

            Menu {
                Picker("视图", selection: $selectedPage) {
                    ForEach(AppPage.allCases, id: \.self) { page in
                        Label(page.rawValue, systemImage: page.icon)
                            .tag(page)
                    }
                }
            } label: {
                Image(systemName: "line.horizontal.3.decrease")
                    .font(.title2)
                    .frame(width: 50, height: 50)
            }
            .glassEffect(.regular.interactive(), in: .circle)
            .tint(.primary)
            .disabled(isRecording)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 0)
    }

    // MARK: - Bottom Bar Content

    @ViewBuilder
    private var bottomBarContent: some View {
        switch captureViewModel.state {
        case .idle, .saved, .readyForInput:
            searchOrRecordBar
        case .analyzing:
            analyzingBar
        case .preview:
            previewBar
        case .saving:
            savingBar
        case .error:
            errorBar
        }
    }

    // MARK: - Unified Search / Record Bar

    /// ✨ 从胶囊右侧"切出" / "融入"的液态玻璃动画
    private var searchOrRecordBar: some View {
        let isInput = if case .readyForInput = captureViewModel.state { true } else { false }

        return HStack(spacing: 8) {
            plusMenuButton

            centerCapsule(isInput: isInput)

            if isInput {
                Button {
                    captureViewModel.proceedToAnalysis()
                } label: {
                    Image(systemName: "sparkles")
                        .font(.title3)
                        .frame(width: 50, height: 50)
                }
                .glassEffect(.regular.interactive(), in: .circle)
                .tint(.primary)
                .disabled(!captureViewModel.canProceed)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.01, anchor: .leading),
                    removal: .scale(scale: 0.01, anchor: .leading)
                ))
                .symbolEffect(.bounce.up.byLayer, options: .nonRepeating, value: isInput)
            }
        }
        .animation(.spring(duration: 0.6, bounce: 0.15), value: isInput)
    }

    // MARK: Center Capsule

    @ViewBuilder
    private func centerCapsule(isInput: Bool) -> some View {
        if isInput {
            // 描述输入
            HStack(spacing: 8) {
                ZStack(alignment: .leading) {
                    TextField("", text: $captureViewModel.userContext)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .focused($isDescriptionFocused)

                    if captureViewModel.userContext.isEmpty {
                        shimmerPlaceholder
                    }
                }

                Button {
                    if captureViewModel.speechService.isRecording {
                        captureViewModel.stopVoiceInput()
                    } else {
                        captureViewModel.startVoiceInput()
                    }
                } label: {
                    Image(systemName: captureViewModel.speechService.isRecording
                          ? "stop.fill"
                          : "mic.fill")
                        .foregroundStyle(
                            captureViewModel.speechService.isRecording
                            ? .red
                            : .primary
                        )
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            .glassEffect(.regular, in: .capsule)
        } else {
            // 搜索入口
            Button {
                showSearch = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    Text("搜索物品...")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "mic.fill")
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .frame(height: 50)
                .glassEffect(.regular, in: .capsule)
            }
            .buttonStyle(.plain)
            .tint(.primary)
        }
    }

    // MARK: - Shimmer Placeholder

    /// 文字渐变流光 — 2 根光带交替扫过，慢速丝滑无缝循环
    private var shimmerPlaceholder: some View {
        let isDark = colorScheme == .dark
        let dimOpacity: Double = isDark ? 0.10 : 0.18
        let peakOpacity: Double = isDark ? 0.52 : 0.65
        let bandHalf: Double = 0.12

        return TimelineView(.animation) { timeline in
            let seconds = timeline.date.timeIntervalSince1970
            let phase = seconds.truncatingRemainder(dividingBy: 8.0) / 8.0

            Text("简单描述一下...")
                .font(.body)
                .foregroundStyle(gradient(for: phase, dim: dimOpacity, peak: peakOpacity, bandHalf: bandHalf))
        }
        .allowsHitTesting(false)
    }

    /// 生成 2 光带梯度，位置包裹到 [0,1] 后排好序，首尾颜色一致确保无缝
    private func gradient(
        for phase: Double,
        dim dimOpacity: Double,
        peak peakOpacity: Double,
        bandHalf: Double
    ) -> LinearGradient {
        let wrap: (Double) -> Double = { ($0.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1) }

        var stops: [Gradient.Stop] = []
        for i in 0..<2 {
            let c = wrap(phase + Double(i) / 2)
            stops.append(.init(color: .primary.opacity(dimOpacity), location: wrap(c - bandHalf)))
            stops.append(.init(color: .primary.opacity(peakOpacity), location: c))
            stops.append(.init(color: .primary.opacity(dimOpacity), location: wrap(c + bandHalf)))
        }

        stops.sort { $0.location < $1.location }

        // 首尾颜色一致 → 边界无缝
        if let first = stops.first, first.location > 0.001 {
            stops.insert(.init(color: stops.last!.color, location: 0), at: 0)
        }
        if let last = stops.last, last.location < 0.999 {
            stops.append(.init(color: stops.first!.color, location: 1))
        }

        return LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing)
    }

    // MARK: - Shared + Button

    private var plusMenuButton: some View {
        Menu {
            Button {
                showPhotoSheet = true
            } label: {
                Label("照片", systemImage: "photo.on.rectangle")
            }
            Button {
                showCameraSheet = true
            } label: {
                Label("相机", systemImage: "camera.fill")
            }
        } label: {
            Image(systemName: "plus")
                .font(.title3)
                .fontWeight(.medium)
                .frame(width: 50, height: 50)
        }
        .glassEffect(.regular.interactive(), in: .circle)
        .tint(.primary)
    }

    // MARK: - Analyzing Bar

    private var analyzingBar: some View {
        HStack(spacing: 8) {
            ProgressView()
                .tint(.secondary)
            Text("AI 正在识别物品…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 18)
        .frame(height: 50)
        .glassEffect(.regular, in: .capsule)
    }

    // MARK: - Preview Bar

    private var previewBar: some View {
        HStack(spacing: 8) {
            // 名称输入
            HStack(spacing: 8) {
                if case .preview(let response) = captureViewModel.state,
                   let emoji = response.emoji {
                    Text(emoji)
                        .font(.title3)
                }
                TextField("物品名称", text: $captureViewModel.editedName)
                    .textFieldStyle(.plain)
                    .font(.body)
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            .glassEffect(.regular, in: .capsule)

            // 保存按钮
            Button {
                captureViewModel.confirmSave()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.down")
                    Text("保存")
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .padding(.horizontal, 14)
                .frame(height: 44)
            }
            .buttonStyle(.glassProminent)
            .tint(.blue)
        }
    }

    // MARK: - Saving Bar

    private var savingBar: some View {
        HStack(spacing: 8) {
            ProgressView()
                .tint(.secondary)
            Text("正在保存…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 18)
        .frame(height: 50)
        .glassEffect(.regular, in: .capsule)
    }

    // MARK: - Error Bar

    private var errorBar: some View {
        HStack(spacing: 8) {
            Button {
                captureViewModel.retry()
                photoCardIndex = 0
                photoDragOffset = .zero
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                    Text("重试")
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .padding(.horizontal, 14)
                .frame(height: 44)
            }
            .buttonStyle(.glassProminent)
            .tint(.blue)

            Spacer()

            Button {
                dismissRecording()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "xmark")
                    Text("关闭")
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .padding(.horizontal, 14)
                .frame(height: 44)
            }
            .glassEffect(.regular.interactive(), in: .capsule)
            .tint(.primary)
        }
    }

    // MARK: - Capture Overlay

    @ViewBuilder
    private var captureOverlay: some View {
        VStack(spacing: 0) {
            Spacer()
            captureOverlayContent
                .padding(.horizontal, 7)
        }
        // 留出底部栏空间：50(栏高) + 18(栏底边距) + 18(卡片与栏间距)
        .padding(.bottom, 86)
    }

    @ViewBuilder
    private var captureOverlayContent: some View {
        switch captureViewModel.state {
        case .readyForInput:
            readyForInputOverlay
        case .analyzing:
            analyzingOverlay
        case .preview(let response):
            previewOverlay(response: response)
        case .saving:
            savingOverlayView
        case .error(let message):
            errorOverlayView(message: message)
        default:
            EmptyView()
        }
    }

    // MARK: Ready For Input Overlay

    private var readyForInputOverlay: some View {
        let images = captureViewModel.selectedImages
        let cardSize: CGFloat = min(UIScreen.main.bounds.width - 80, 280)

        return PhotoCardStack(
            images: images,
            mainImageIndex: $photoCardIndex,
            dragOffset: $photoDragOffset,
            cardSize: cardSize,
            onRemove: { index in
                withAnimation(.smooth(duration: 0.25)) {
                    captureViewModel.removeImage(at: index)
                    // 删除后调整索引
                    if photoCardIndex >= captureViewModel.selectedImages.count {
                        photoCardIndex = max(captureViewModel.selectedImages.count - 1, 0)
                    }
                }
            }
        )
        .gesture(photoSwipeGesture)
    }

    private var photoSwipeGesture: some Gesture {
        DragGesture()
            .onChanged { photoDragOffset = $0.translation }
            .onEnded { value in
                let count = captureViewModel.selectedImages.count
                guard count > 0 else {
                    photoDragOffset = .zero
                    return
                }
                let threshold: CGFloat = 60
                var newIndex = photoCardIndex
                if value.translation.width < -threshold, newIndex < count - 1 {
                    newIndex += 1
                } else if value.translation.width > threshold, newIndex > 0 {
                    newIndex -= 1
                }
                newIndex = min(max(newIndex, 0), count - 1)

                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    photoCardIndex = newIndex
                    photoDragOffset = .zero
                }
            }
    }

    // MARK: Analyzing Overlay

    private var analyzingOverlay: some View {
        AnalysisOverlay(image: captureViewModel.selectedImages.first)
    }

    // MARK: Preview Overlay

    private func previewOverlay(response: AIResponse) -> some View {
        AIResultOverlay(
            response: response,
            editedName: $captureViewModel.editedName,
            onSave: { captureViewModel.confirmSave() }
        )
    }

    // MARK: Saving Overlay

    private var savingOverlayView: some View {
        SavingOverlay()
    }

    // MARK: Error Overlay

    private func errorOverlayView(message: String) -> some View {
        CaptureErrorOverlay(
            message: message,
            onRetry: {
                captureViewModel.retry()
                photoCardIndex = 0
                photoDragOffset = .zero
            },
            onCancel: {
                dismissRecording()
            }
        )
    }

    // MARK: - Page Content

    @ViewBuilder
    private var pageContent: some View {
        ZStack {
            // 地图始终保持在视图树中，切换页面时位置/缩放不丢失
            MapHomeView(viewModel: mapViewModel, locationService: locationService)
                .opacity(selectedPage == .map ? 1 : 0)
                .disabled(isRecording)

            if selectedPage == .list {
                ItemListView(
                    onDataChanged: {
                        mapViewModel.loadItems()
                    },
                    onBarVisibilityChange: { visible in
                        withAnimation(.smooth(duration: 0.35)) {
                            listBarHidden = !visible
                        }
                    }
                )
                .disabled(isRecording)
            }

            if selectedPage == .settings {
                SettingsView(
                    selectedPage: $selectedPage,
                    navigationDepth: $settingsNavigationDepth,
                    hideTopBar: isRecording
                )
                .disabled(isRecording)
            }
        }
    }
}

// MARK: - Search Modal

private struct SearchModalView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            Group {
                if searchText.isEmpty {
                    ContentUnavailableView(
                        "搜索物品",
                        systemImage: "magnifyingglass",
                        description: Text("输入关键词查找你记录过的物品")
                    )
                } else {
                    List {
                        Text("搜索结果")
                            .foregroundStyle(.secondary)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("搜索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .searchable(text: $searchText)
    }
}

#Preview {
    ContentView()
}
