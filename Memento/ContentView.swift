//
//  ContentView.swift
//  Memento
//
//  Created by WeiAnUppp on 2026/7/21.
//

import SwiftUI
import UIKit
import CoreLocation

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
    @State private var listRefreshTrigger = 0
    @State private var showSearch = false
    @State private var launchSearchWithVoice = false
    @State private var settingsNavigationDepth = 0

    /// 半屏相机
    @State private var showCameraSheet = false
    /// 半屏照片选择器
    @State private var showPhotoSheet = false
    /// 选图 / 拍照后，待处理的图片
    @State private var pendingImage: UIImage?
    /// 图片 EXIF GPS（如有）
    @State private var pendingImageGPS: CLLocationCoordinate2D?
    /// 照片拍摄时间（相册取 PHAsset.creationDate，相机取 nil=现在）
    @State private var pendingImageDate: Date?

    /// 地图共享状态 —— 提升到 ContentView，页面切换时 cameraPosition / items 不丢失
    @State private var mapViewModel = MapViewModel()
    @State private var locationService = LocationService()

    /// 记录物品 ViewModel —— 融入底部栏
    @State private var captureViewModel = CaptureViewModel()

    /// 搜索 ViewModel —— 提升到 ContentView，搜索结果在页面切换后保留
    @State private var searchViewModel = SearchViewModel()

    /// 遮罩+浮层动画专用 Bool — 与 ViewModel 状态解耦，确保动画事务正确传播
    @State private var showRecordingOverlay = false

    /// 输入框焦点，用于键盘动画收起
    @FocusState private var isDescriptionFocused: Bool
    /// 照片卡片交互状态
    @State private var photoCardIndex = 0
    @State private var photoDragOffset: CGSize = .zero
    /// 麦克风录音最大时长保护（秒）
    private let maxRecordingDuration: TimeInterval = 60

    /// 是否正在记录中（底部栏变身）
    private var isRecording: Bool {
        switch captureViewModel.state {
        case .idle, .saved, .backgroundAnalyzing: return false
        default: return true
        }
    }

    /// 是否正在已有记录中添加更多图片（vs 首次选图）
    private var isAddingMorePhotos: Bool {
        if case .readyForInput = captureViewModel.state { return true }
        return false
    }

    /// 设置页有自己的顶栏，不需要 ContentView 覆盖
    private var showCustomTopBar: Bool {
        selectedPage != .settings
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

    /// 后台分析进度 sheet
    @State private var showAnalysisProgress = false

    /// ✨ 按钮退出动画分步控制
    @State private var sparklesAnimatingOut = false

    /// 旋转圆点显示 — 独立于 ViewModel 状态，支持平滑消失动画
    @State private var showSpinningDots = false
    /// 旋转圆点完成收拢动画触发
    @State private var dotsCompleting = false
    /// 玻璃按钮容器缩放（消失动画用）
    @State private var glassButtonScale: CGFloat = 1
    /// 玻璃按钮容器透明度（消失动画用）
    @State private var glassButtonOpacity: Double = 1

    // MARK: - Body

    var body: some View {
        ZStack {
            // 底层：页面内容
            pageContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // 记录时遮罩 — 全屏灰色
            // 键盘弹出 → 先收键盘；无图片 → 可退出；有图片 → 不可退出
            Color.black
                .ignoresSafeArea()
                .opacity(showRecordingOverlay ? (colorScheme == .dark ? 0.5 : 0.3) : 0)
                .animation(.spring(response: 0.55, dampingFraction: 0.82), value: showRecordingOverlay)
                .onTapGesture {
                    if isDescriptionFocused {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                            isDescriptionFocused = false
                        }
                    } else if captureViewModel.selectedImages.isEmpty {
                        dismissRecording()
                    }
                }
                .allowsHitTesting(showRecordingOverlay)

            // 顶层：自定义顶栏 — 记录时半透明但仍可交互
            if showCustomTopBar {
                VStack(spacing: 0) {
                    customTopBar
                    Spacer()
                }
                .opacity(isRecording ? 0.65 : 1)
                .allowsHitTesting(true)
                .animation(.spring(response: 0.55, dampingFraction: 0.82), value: isRecording)
            }

            // 后台分析旋转图标 — 始终在所有页面可见
            if showSpinningDots {
                VStack(spacing: 0) {
                    HStack {
                        SpinningDotsButton(
                            action: { showAnalysisProgress = true },
                            isCompleting: $dotsCompleting,
                            onCompletionFinished: {
                                showSpinningDots = false
                            }
                        )
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    Spacer()
                }
                .scaleEffect(glassButtonScale)
                .opacity(glassButtonOpacity)
                .transition(.scale.combined(with: .opacity))
            }

            // 记录浮层 — 始终存在，用 opacity + offset 控制显隐
            captureOverlay
                .opacity(showRecordingOverlay ? 1 : 0)
                .offset(y: showRecordingOverlay ? 0 : 120)
                .animation(.spring(response: 0.55, dampingFraction: 0.82), value: showRecordingOverlay)
                .simultaneousGesture(TapGesture().onEnded {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                        isDescriptionFocused = false
                    }
                })

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
            SearchModalView(
                viewModel: searchViewModel,
                autoStartVoice: launchSearchWithVoice,
                onResultSelected: { item in
                    mapViewModel.focusOnItem(item)
                    selectedPage = .map
                }
            )
        }
        .onChange(of: showSearch) { _, showing in
            if !showing { launchSearchWithVoice = false }
        }
        // 后台分析进度 sheet
        .sheet(isPresented: $showAnalysisProgress) {
            AnalysisProgressSheet(
                image: captureViewModel.analyzingImage,
                statusText: captureViewModel.analyzingStatusText
            )
        }
        // 相机半屏
        .sheet(isPresented: $showCameraSheet) {
            CameraHalfView { image, gps, date in
                pendingImage = image
                pendingImageGPS = gps
                pendingImageDate = date
            }
            .presentationDetents([.fraction(0.65)])
            .presentationDragIndicator(.hidden)
        }
        // 照片半屏
        .sheet(isPresented: $showPhotoSheet) {
            PhotoHalfView { image, gps, date in
                pendingImage = image
                pendingImageGPS = gps
                pendingImageDate = date
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
        // 保存成功 → 刷新地图，自动定位，清理状态
        .onChange(of: captureViewModel.state) { _, newState in
            switch newState {
            case .backgroundAnalyzing:
                // 录音 UI 立即关闭（isRecording 已为 false，showRecordingOverlay 自动跟随）
                break
            case .saved(let item):
                // 增分插入而非整表重查 —— 保存瞬间主线程零阻塞，地图立即出针
                mapViewModel.addSavedItem(item)
                listRefreshTrigger += 1
                photoCardIndex = 0
                photoDragOffset = .zero
                showAnalysisProgress = false
                // 先等旋转圆点消失动画播完（0.35s），再跳 GPS，避免两个动画抢主线程
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    mapViewModel.focusOnItem(item)
                }
                if showRecordingOverlay {
                    dismissRecording(after: 0.6)
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        captureViewModel.reset()
                    }
                }
            case .error where captureViewModel.analysisDidFail:
                // 后台分析失败 → 静默重置
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    captureViewModel.reset()
                }
            default:
                break
            }
        }
        // 语音识别结果回填（使用过滤语气词后的文本）
        .onChange(of: captureViewModel.speechService.isRecording) { _, recording in
            if !recording {
                let cleaned = captureViewModel.speechService.cleanedTranscript
                if !cleaned.isEmpty {
                    captureViewModel.userContext = cleaned
                }
            }
        }
        .onChange(of: selectedPage) { _, _ in
            listBarHidden = false
        }
        .onChange(of: captureViewModel.state) { _, newState in
            if case .readyForInput = newState {
                sparklesAnimatingOut = false
            }
        }
        .onChange(of: captureViewModel.isBackgroundAnalyzing) { _, showing in
            if showing {
                dotsCompleting = false
                glassButtonScale = 1
                glassButtonOpacity = 1
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    showSpinningDots = true
                }
            } else if showSpinningDots {
                // 不直接隐藏，先同时触发圆点收拢 + 玻璃缩放淡出
                dotsCompleting = true
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    glassButtonScale = 0.01
                    glassButtonOpacity = 0
                }
            }
        }
    }

    // MARK: - Photo Captured Handler

    private func handlePhotoCaptured() {
        guard let image = pendingImage else { return }
        let gps = pendingImageGPS
        let date = pendingImageDate
        if isAddingMorePhotos {
            captureViewModel.addImage(image, gps: gps, takenAt: date)
            photoCardIndex = max(captureViewModel.selectedImages.count - 1, 0)
        } else {
            captureViewModel.didSelectFirstImage(image, gps: gps, takenAt: date)
            photoCardIndex = 0
        }
        pendingImage = nil
        pendingImageGPS = nil
        pendingImageDate = nil
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
        case .idle, .saved, .saving, .readyForInput, .backgroundAnalyzing:
            searchOrRecordBar
        case .analyzing:
            analyzingBar
        case .preview:
            previewBar
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

            if isInput && !sparklesAnimatingOut {
                Button {
                    // 阶段 0：键盘先收起（如果正在输入）
                    if isDescriptionFocused {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                            isDescriptionFocused = false
                        }
                    }

                    // 阶段 1：键盘开始下落后，✨ 缩进胶囊
                    let sparkleDelay = isDescriptionFocused ? 0.18 : 0.0
                    DispatchQueue.main.asyncAfter(deadline: .now() + sparkleDelay) {
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.72)) {
                            sparklesAnimatingOut = true
                        }

                        // 阶段 2：✨ 缩回后，胶囊展开为搜索栏
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                                captureViewModel.proceedToAnalysis()
                            }
                        }
                    }
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
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: isInput)
        .animation(.spring(response: 0.22, dampingFraction: 0.72), value: sparklesAnimatingOut)
    }

    // MARK: Center Capsule

    @ViewBuilder
    private func centerCapsule(isInput: Bool) -> some View {
        if isInput {
            HStack(spacing: 8) {
                ZStack(alignment: .leading) {
                    TextField("", text: $captureViewModel.userContext)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .focused($isDescriptionFocused)
                        .disabled(captureViewModel.speechService.isRecording)

                    if captureViewModel.userContext.isEmpty && !captureViewModel.speechService.isRecording {
                        Text("简单描述一下...")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                    if captureViewModel.speechService.isRecording {
                        InlineSoundWave()
                            .allowsHitTesting(false)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 1.1).combined(with: .opacity),
                                removal: .scale(scale: 0.92).combined(with: .opacity)
                            ))
                    }
                }
                .frame(maxWidth: .infinity)
                .animation(.spring(response: 0.45, dampingFraction: 0.78), value: captureViewModel.speechService.isRecording)

                // 有文字 → 清空按钮 | 录音中 → 停止 | 默认 → 麦克风
                let hasText = !captureViewModel.userContext.isEmpty
                let isRec = captureViewModel.speechService.isRecording
                let iconName = hasText && !isRec
                    ? "xmark.circle.fill"
                    : (isRec ? "stop.fill" : "mic")
                let iconColor: Color = isRec
                    ? .red
                    : (hasText ? .secondary : .secondary)

                Button {
                    if isRec {
                        captureViewModel.stopVoiceInput()
                    } else if hasText {
                        captureViewModel.userContext = ""
                    } else {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                            isDescriptionFocused = false
                        }
                        captureViewModel.startVoiceInput()
                        DispatchQueue.main.asyncAfter(deadline: .now() + maxRecordingDuration) { [weak captureViewModel = captureViewModel] in
                            guard captureViewModel?.speechService.isRecording == true else { return }
                            captureViewModel?.stopVoiceInput()
                        }
                    }
                } label: {
                    Image(systemName: iconName)
                        .foregroundStyle(iconColor)
                        .contentTransition(.opacity)
                        .padding(.vertical, 12)
                        .padding(.leading, 14)
                        .padding(.trailing, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            .glassEffect(.regular, in: .capsule)
        } else {
            // 搜索入口 — 左：打开搜索弹窗 / 右：语音搜索
            HStack(spacing: 0) {
                // 左侧：搜索文字区域 → 打开搜索弹窗
                Button {
                    showSearch = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        Text("搜索物品...")
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)

                // 右侧：麦克风按钮 → 语音搜索
                Button {
                    launchSearchWithVoice = true
                    showSearch = true
                } label: {
                    Image(systemName: "mic")
                        .foregroundStyle(.secondary)
                        .padding(.leading, 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            .glassEffect(.regular, in: .capsule)
        }
    }

    // MARK: - Shared + Button

    @ViewBuilder
    private var plusMenuButton: some View {
        let canAdd = captureViewModel.canAddMoreImages
        if canAdd {
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
        } else {
            Image(systemName: "plus")
                .font(.title3)
                .fontWeight(.medium)
                .frame(width: 50, height: 50)
                .glassEffect(.regular, in: .circle)
                .foregroundStyle(.secondary)
                .opacity(0.4)
        }
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
            EmptyView()
        case .error(let message):
            errorOverlayView(message: message)
        case .idle, .backgroundAnalyzing, .saved:
            EmptyView()
        }
    }

    // MARK: Ready For Input Overlay

    private var readyForInputOverlay: some View {
        let images = captureViewModel.selectedImages
        let cardSize: CGFloat = min(Self.screenWidth - 80, 280)

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
                    },
                    onNavigateToMap: { item in
                        mapViewModel.focusOnItem(item)
                        selectedPage = .map
                    },
                    refreshTrigger: listRefreshTrigger
                )
                .disabled(isRecording)
            }

            if selectedPage == .settings {
                SettingsView(
                    selectedPage: $selectedPage,
                    navigationDepth: $settingsNavigationDepth
                )
                .disabled(isRecording)
            }
        }
    }

    /// iOS 26 替代 UIScreen.main，从 window scene 获取屏幕尺寸
    private static var screenWidth: CGFloat {
        UIApplication.shared
            .connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.screen.bounds.width ?? 390
    }
}

// MARK: - Search Modal

private struct SearchModalView: View {
    @Bindable var viewModel: SearchViewModel
    let autoStartVoice: Bool
    let onResultSelected: (Item) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isSearchFocused: Bool
    @State private var selectedSegment = 0

    /// 麦克风录音最大时长保护（秒）
    private let maxRecordingDuration: TimeInterval = 60

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // 搜索输入栏
                    searchInputBar
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                    // 分段选择：最近搜索 / 搜索结果
                    segmentTabs
                        .padding(.horizontal, 16)
                        .padding(.top, 12)

                    // 内容区
                    if selectedSegment == 0 {
                        recentSearchesList
                            .frame(maxHeight: .infinity)
                    } else {
                        SearchResultView(
                            results: viewModel.results,
                            isSearching: viewModel.isSearching,
                            hasSearched: viewModel.hasSearched,
                            searchError: viewModel.searchError,
                            suggestionText: viewModel.suggestionText,
                            onResultSelected: { item in
                                dismiss()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                    onResultSelected(item)
                                }
                            },
                            onRetry: {
                                viewModel.performSearch()
                            }
                        )
                        .frame(maxHeight: .infinity)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    isSearchFocused = false
                }
            }
            .navigationTitle("搜索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                    }
                }
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear {
            isSearchFocused = true
            if !viewModel.results.isEmpty {
                selectedSegment = 1
            }
            if autoStartVoice {
                // 给 SpeechService 一点时间检查授权状态
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    viewModel.startVoiceInput()
                    DispatchQueue.main.asyncAfter(deadline: .now() + maxRecordingDuration) { [weak viewModel = viewModel] in
                        guard viewModel?.speechService.isRecording == true else { return }
                        viewModel?.stopVoiceInput()
                    }
                }
            }
        }
        .alert("搜索出错", isPresented: Binding(
            get: { viewModel.searchError != nil },
            set: { if !$0 { viewModel.searchError = nil } }
        )) {
            Button("取消", role: .cancel) {
                viewModel.searchError = nil
            }
            Button("重试") {
                viewModel.performSearch()
            }
        } message: {
            Text(viewModel.searchError ?? "")
        }
        // 搜索时自动切到搜索结果
        .onChange(of: viewModel.hasSearched) { _, searched in
            if searched { selectedSegment = 1 }
        }
        // 语音识别结果回填
        .onChange(of: viewModel.speechService.isRecording) { _, recording in
            if !recording {
                let cleaned = viewModel.speechService.cleanedTranscript
                if !cleaned.isEmpty {
                    viewModel.queryText = cleaned
                    selectedSegment = 1
                    viewModel.performSearch()
                }
            }
        }
        .onDisappear {
            viewModel.queryText = ""
        }
    }

    // MARK: - Segment Tabs

    private var segmentTabs: some View {
        Picker("搜索模式", selection: $selectedSegment) {
            Text("最近搜索").tag(0)
            Text("搜索结果").tag(1)
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Recent Searches List

    private var recentSearchesList: some View {
        Group {
            if viewModel.recentSearches.isEmpty {
                ContentUnavailableView(
                    "搜索物品",
                    systemImage: "magnifyingglass",
                    description: Text("随心问，我会帮你找到它。")
                )
            } else {
                List {
                    Section {
                        ForEach(viewModel.recentSearches, id: \.self) { query in
                            Button {
                                viewModel.queryText = query
                                selectedSegment = 1
                                viewModel.performSearch()
                            } label: {
                                HStack {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .foregroundStyle(.secondary)
                                        .font(.subheadline)
                                    Text(query)
                                        .font(.body)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { indexSet in
                            for i in indexSet {
                                viewModel.deleteRecentSearch(viewModel.recentSearches[i])
                            }
                        }
                    } header: {
                        if !viewModel.recentSearches.isEmpty {
                            HStack {
                                Text("最近搜索")
                                Spacer()
                                Button("清空") {
                                    withAnimation { viewModel.clearRecentSearches() }
                                }
                                .font(.subheadline)
                                .foregroundStyle(.blue)
                            }
                            .textCase(nil)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    // MARK: - Search Input Bar

    /// 复用记录物品的输入设计：玻璃胶囊 + 文字输入 + 麦克风 + shimmer 占位符
    private var searchInputBar: some View {
        HStack(spacing: 8) {
            // 搜索图标
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            // 输入区域
            ZStack(alignment: .leading) {
                TextField("", text: $viewModel.queryText)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .focused($isSearchFocused)
                    .disabled(viewModel.speechService.isRecording)
                    .onSubmit {
                        selectedSegment = 1
                        viewModel.performSearch()
                    }

                // 占位符：空态 shimmer，录音中声波
                if viewModel.queryText.isEmpty && !viewModel.speechService.isRecording {
                    searchShimmerPlaceholder
                }
                if viewModel.speechService.isRecording {
                    InlineSoundWave()
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity)

            // 右侧按钮：有文字→清空 | 录音中→停止 | 默认→麦克风
            let hasText = !viewModel.queryText.isEmpty
            let isRec = viewModel.speechService.isRecording
            let iconName = hasText && !isRec
                ? "xmark.circle.fill"
                : (isRec ? "stop.fill" : "mic")
            let iconColor: Color = isRec
                ? .red
                : .secondary

            Button {
                if isRec {
                    viewModel.stopVoiceInput()
                } else if hasText {
                    viewModel.queryText = ""
                } else {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                        isSearchFocused = false
                    }
                    viewModel.startVoiceInput()
                    DispatchQueue.main.asyncAfter(deadline: .now() + maxRecordingDuration) { [weak viewModel = viewModel] in
                        guard viewModel?.speechService.isRecording == true else { return }
                        viewModel?.stopVoiceInput()
                    }
                }
            } label: {
                Image(systemName: iconName)
                    .foregroundStyle(iconColor)
                    .contentTransition(.opacity)
                    .padding(.vertical, 12)
                    .padding(.trailing, 14)
                    .padding(.leading, 4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 10)
        .frame(height: 50)
        .glassEffect(.regular, in: .capsule)
    }

    // MARK: - Shimmer Placeholder

    private var searchShimmerPlaceholder: some View {
        Text("描述你想找的物品...")
            .font(.body)
            .foregroundStyle(.secondary)
            .allowsHitTesting(false)
    }
}

#Preview {
    ContentView()
}
