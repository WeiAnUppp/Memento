//
//  CaptureView.swift
//  Memento
//
//  Created by WeiAnUppp on 2026/7/21.
//

import SwiftUI
import CoreLocation

// MARK: - Capture Flow View（半屏）

/// 选图 → 填写描述 → AI 分析 → 预览确认 → 保存
/// 支持多张图片，卡片堆叠滑动切换
struct CaptureView: View {
    let preselectedImage: UIImage?
    let preselectedGPS: CLLocationCoordinate2D?

    @State private var viewModel = CaptureViewModel()
    @State private var showAddPhotoMenu = false
    @State private var showAddCamera = false
    @State private var showAddPhotoLibrary = false
    @State private var mainImageIndex = 0

    /// 卡片拖拽偏移
    @State private var dragOffset: CGSize = .zero

    let onDismiss: () -> Void

    init(preselectedImage: UIImage, onDismiss: @escaping () -> Void) {
        self.preselectedImage = preselectedImage
        self.preselectedGPS = nil
        self.onDismiss = onDismiss
    }

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            switch viewModel.state {
            case .idle:
                idleView
            case .readyForInput:
                readyForInputView
            case .analyzing:
                analyzingView
            case .preview(let response):
                previewView(response: response)
            case .saving:
                savingView
            case .saved:
                Color.clear.onAppear { onDismiss() }
            case .error(let message):
                errorView(message: message)
            }
        }
        // 顶部工具栏（覆盖在内容上）
        .overlay(alignment: .top) {
            if viewModel.state == .readyForInput {
                topBar
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
            }
        }
        // 嵌套 sheet
        .sheet(isPresented: $showAddCamera) {
            CameraHalfView { image in viewModel.addImage(image, gps: nil) }
                .presentationDetents([.fraction(0.65)])
                .presentationDragIndicator(.hidden)
        }
        .sheet(isPresented: $showAddPhotoLibrary) {
            PhotoHalfView { image in viewModel.addImage(image, gps: nil) }
                .presentationDragIndicator(.hidden)
        }
        .confirmationDialog("添加图片", isPresented: $showAddPhotoMenu) {
            Button("相机") { showAddCamera = true }
            Button("照片") { showAddPhotoLibrary = true }
            Button("取消", role: .cancel) {}
        }
        .onAppear {
            if let image = preselectedImage {
                viewModel.didSelectFirstImage(image, gps: preselectedGPS)
            }
        }
        .interactiveDismissDisabled(viewModel.state == .analyzing || viewModel.state == .saving)
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button {
                viewModel.reset()
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 50, height: 50)
            }
            .glassEffect(.regular.interactive(), in: .circle)
            .tint(.primary)

            Spacer()

            Button {
                showAddPhotoMenu = true
            } label: {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 50, height: 50)
            }
            .glassEffect(.regular.interactive(), in: .circle)
            .tint(.primary)
        }
    }

    // MARK: - Idle

    private var idleView: some View {
        VStack {
            Spacer()
            ProgressView("等待拍照…").font(.subheadline)
            Spacer()
        }
    }

    // MARK: - Ready For Input

    private var readyForInputView: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 76)

            // 卡片堆叠区
            cardStackSection

            Spacer()

            // 输入 + 按钮区
            VStack(spacing: 12) {
                inputCard

                Button {
                    viewModel.proceedToAnalysis()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                        Text("开始识别")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .font(.headline)
                }
                .buttonStyle(.glassProminent)
                .tint(.blue)
                .controlSize(.extraLarge)
                .disabled(!viewModel.canProceed)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Card Stack

    private var cardStackSection: some View {
        let cardWidth: CGFloat = 280
        let cardHeight: CGFloat = 280

        return VStack(spacing: 12) {
            if viewModel.selectedImages.isEmpty {
                RoundedRectangle(cornerRadius: 24)
                    .fill(.quaternary)
                    .frame(width: cardWidth, height: cardHeight)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.system(size: 40))
                            .foregroundStyle(.tertiary)
                    }
            } else {
                cardStack(cardWidth: cardWidth, cardHeight: cardHeight)

                // 页码指示器
                if viewModel.selectedImages.count > 1 {
                    HStack(spacing: 6) {
                        ForEach(0..<viewModel.selectedImages.count, id: \.self) { index in
                            Capsule()
                                .fill(index == mainImageIndex ? .blue : .secondary.opacity(0.3))
                                .frame(width: index == mainImageIndex ? 16 : 6, height: 6)
                                .animation(.spring(response: 0.3), value: mainImageIndex)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cardStack(cardWidth: CGFloat, cardHeight: CGFloat) -> some View {
        let count = viewModel.selectedImages.count
        let safeIndex = min(mainImageIndex, count - 1)

        ZStack {
            // 渲染当前卡 + 后面最多 2 张
            ForEach(0..<min(3, count - safeIndex), id: \.self) { offset in
                let index = safeIndex + offset
                let isTop = offset == 0

                cardView(
                    image: viewModel.selectedImages[index],
                    width: cardWidth,
                    height: cardHeight,
                    depth: offset,
                    isTop: isTop
                )
                .zIndex(Double(-offset))
            }
        }
        .frame(width: cardWidth, height: cardHeight)
    }

    private func cardView(image: UIImage, width: CGFloat, height: CGFloat,
                          depth: Int, isTop: Bool) -> some View {
        let scale: CGFloat = depth == 0 ? 1 : 1 - CGFloat(depth) * 0.05
        let yOffset: CGFloat = CGFloat(depth) * 10
        let rotation: Double = depth == 0 ? 0 : Double(depth) * 2.5
        let opacity: Double = depth == 0 ? 1 : 0.5 - Double(depth) * 0.2

        return Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
            .scaleEffect(scale)
            .offset(y: yOffset)
            .rotationEffect(.degrees(rotation))
            .opacity(opacity)
            .offset(x: isTop ? dragOffset.width : 0)
            .rotationEffect(.degrees(isTop ? dragOffset.width / 20 : 0))
            .gesture(isTop ? swipeGesture : nil)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: mainImageIndex)
    }

    // MARK: - Swipe Gesture

    private var swipeGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                dragOffset = value.translation
            }
            .onEnded { value in
                let threshold: CGFloat = 60
                let count = viewModel.selectedImages.count

                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    if value.translation.width < -threshold, mainImageIndex < count - 1 {
                        mainImageIndex += 1
                    } else if value.translation.width > threshold, mainImageIndex > 0 {
                        mainImageIndex -= 1
                    }
                    dragOffset = .zero
                }
            }
    }

    // MARK: - Input Card

    private var inputCard: some View {
        HStack(alignment: .center, spacing: 10) {
            voiceButton

            TextField("描述一下这个物品…", text: $viewModel.userContext)
                .textFieldStyle(.plain)
                .font(.title3)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    // MARK: - Voice Button

    private var voiceButton: some View {
        Button {
            if viewModel.speechService.isRecording {
                viewModel.stopVoiceInput()
            } else {
                viewModel.startVoiceInput()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(viewModel.speechService.isRecording ? Color.red : Color.blue)
                    .frame(width: 44, height: 44)

                if viewModel.speechService.isRecording {
                    Circle()
                        .stroke(.red.opacity(0.4), lineWidth: 3)
                        .frame(width: 52, height: 52)
                        .scaleEffect(1.3)
                        .opacity(0)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: false), value: viewModel.speechService.isRecording)

                    Image(systemName: "stop.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)
                } else {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
        }
        .buttonStyle(.plain)
        .onChange(of: viewModel.speechService.isRecording) { _, recording in
            if !recording, !viewModel.speechService.transcript.isEmpty {
                viewModel.userContext = viewModel.speechService.transcript
            }
        }
    }

    // MARK: - Analyzing

    private var analyzingView: some View {
        VStack(spacing: 24) {
            Spacer()

            if !viewModel.selectedImages.isEmpty {
                Image(uiImage: viewModel.selectedImages[0])
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
            }

            ProgressView("AI 正在识别物品…")
                .font(.headline)
            Text("结合你提供的信息分析物品特征")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(24)
    }

    // MARK: - Preview

    private func previewView(response: AIResponse) -> some View {
        VStack(spacing: 0) {
            // 顶部关闭按钮
            HStack {
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .glassEffect(.regular.interactive(), in: .circle)
                .tint(.primary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 图片
                    if let firstImage = viewModel.selectedImages.first {
                        Image(uiImage: firstImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .frame(maxWidth: .infinity)
                    }

                    if let emoji = response.emoji {
                        HStack(spacing: 8) {
                            Text(emoji).font(.largeTitle)
                            Text("AI 推荐图标").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }

                    TextField("物品名称", text: $viewModel.editedName)
                        .font(.title3).bold()
                        .textFieldStyle(.plain)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("描述").font(.subheadline).foregroundStyle(.secondary)
                        Text(response.description).font(.body)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassEffect(.regular, in: .rect(cornerRadius: 12))
                    }

                    if !response.scene.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("场景").font(.subheadline).foregroundStyle(.secondary)
                            Text(response.scene).font(.body)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .glassEffect(.regular, in: .rect(cornerRadius: 12))
                        }
                    }

                    if !response.keywords.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("关键词").font(.subheadline).foregroundStyle(.secondary)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 8)], spacing: 8) {
                                ForEach(Array(response.keywords.keys), id: \.self) { key in
                                    HStack(spacing: 4) {
                                        Text(key).font(.subheadline).foregroundStyle(.secondary)
                                        Text(response.keywords[key] ?? "").font(.subheadline).fontWeight(.medium)
                                    }
                                    .padding(.horizontal, 10).padding(.vertical, 4)
                                    .glassEffect(.regular, in: .capsule)
                                }
                            }
                        }
                    }

                    Button {
                        viewModel.confirmSave()
                    } label: {
                        Label("保存物品", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.blue)
                    .controlSize(.extraLarge)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
    }

    // MARK: - Saving

    private var savingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView("正在保存…").font(.headline)
            Spacer()
        }
    }

    // MARK: - Error

    private func errorView(message: String) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48)).foregroundStyle(.orange)
            Text("出错了").font(.title2).fontWeight(.semibold)
            Text(message).font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 32)

            HStack(spacing: 12) {
                Button("重试") { viewModel.retry() }
                    .buttonStyle(.glassProminent).tint(.blue)
                Button("返回") { viewModel.reset() }
                    .buttonStyle(.glass).tint(.primary)
            }
            .controlSize(.extraLarge)
            Spacer()
        }
    }
}

#Preview {
    CaptureView(preselectedImage: UIImage(systemName: "photo")!, onDismiss: {})
}
