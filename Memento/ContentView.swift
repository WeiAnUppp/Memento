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

    /// 设置页使用原生大标题导航栏，不需要自定义顶栏
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

            // 记录时轻微遮罩
            if isRecording {
                Color.black.opacity(0.12)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            // 顶层：自定义顶栏
            if showCustomTopBar {
                VStack(spacing: 0) {
                    customTopBar
                    Spacer()
                }
            }

            // 记录浮层 — 在底部栏上方
            if isRecording {
                captureOverlay
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

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
        .animation(.smooth(duration: 0.35), value: isRecording)
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
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    withAnimation(.spring(duration: 0.6, bounce: 0.15)) {
                        captureViewModel.reset()
                    }
                }
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
        withAnimation(.spring(duration: 0.6, bounce: 0.2)) {
            if isAddingMorePhotos {
                captureViewModel.addImage(image, gps: nil)
                photoCardIndex = max(captureViewModel.selectedImages.count - 1, 0)
            } else {
                captureViewModel.didSelectFirstImage(image, gps: nil)
                photoCardIndex = 0
            }
        }
        pendingImage = nil
    }

    // MARK: - Custom Top Bar

    private var customTopBar: some View {
        HStack(alignment: .center) {
            Spacer()

            if isRecording {
                Button {
                    withAnimation(.spring(duration: 0.6, bounce: 0.15)) {
                        captureViewModel.reset()
                        photoCardIndex = 0
                        photoDragOffset = .zero
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 50, height: 50)
                }
                .glassEffect(.regular.interactive(), in: .circle)
                .tint(.primary)
            } else {
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
            }
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
                TextField("描述一下这个物品…", text: $captureViewModel.userContext)
                    .textFieldStyle(.plain)
                    .font(.body)

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
                withAnimation(.spring(duration: 0.6, bounce: 0.15)) {
                    captureViewModel.reset()
                    photoCardIndex = 0
                    photoDragOffset = .zero
                }
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
                withAnimation(.spring(duration: 0.6, bounce: 0.15)) {
                    captureViewModel.reset()
                    photoCardIndex = 0
                    photoDragOffset = .zero
                }
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
                .allowsHitTesting(selectedPage == .map && !isRecording)

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
                .opacity(isRecording ? 0.6 : 1)
                .allowsHitTesting(!isRecording)
            }

            if selectedPage == .settings {
                SettingsView(
                    selectedPage: $selectedPage,
                    navigationDepth: $settingsNavigationDepth
                )
                .opacity(isRecording ? 0.6 : 1)
                .allowsHitTesting(!isRecording)
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
