//
//  CaptureView.swift
//  Memento
//
//  Created by WeiAnUppp on 2026/7/21.
//

import SwiftUI
import CoreLocation

// MARK: - Capture Flow View

/// 完整的记录流程：
/// 选图 → 强制填写物品信息 → AI 分析（含用户上下文）→ 预览确认 → 保存
/// 支持多张图片（多角度拍摄同一物品）
struct CaptureView: View {
    let preselectedImage: UIImage?
    let preselectedGPS: CLLocationCoordinate2D?

    @State private var viewModel = CaptureViewModel()
    @State private var showAddPhotoMenu = false
    @State private var showAddCamera = false
    @State private var showAddPhotoLibrary = false

    /// 大图预览索引
    @State private var mainImageIndex = 0

    let onDismiss: () -> Void

    init(preselectedImage: UIImage, onDismiss: @escaping () -> Void) {
        self.preselectedImage = preselectedImage
        self.preselectedGPS = nil
        self.onDismiss = onDismiss
    }

    var body: some View {
        NavigationStack {
            Group {
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
                    Color.clear
                        .onAppear { onDismiss() }
                case .error(let message):
                    errorView(message: message)
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        viewModel.reset()
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 36, height: 36)
                    }
                    .glassEffect(.regular.interactive(), in: .circle)
                    .tint(.primary)
                }
                if case .readyForInput = viewModel.state {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showAddPhotoMenu = true
                        } label: {
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 17, weight: .semibold))
                                .frame(width: 36, height: 36)
                        }
                        .glassEffect(.regular.interactive(), in: .circle)
                        .tint(.primary)
                    }
                }
            }
        }
        // 嵌套 sheet：在 CaptureView 内部添加更多图片
        .sheet(isPresented: $showAddCamera) {
            CameraHalfView { image in
                viewModel.addImage(image, gps: nil)
            }
            .presentationDetents([.fraction(0.65)])
            .presentationDragIndicator(.hidden)
        }
        .sheet(isPresented: $showAddPhotoLibrary) {
            PhotoHalfView { image in
                viewModel.addImage(image, gps: nil)
            }
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
        .interactiveDismissDisabled(viewModel.state != .idle && viewModel.state != .readyForInput)
    }

    private var navigationTitle: String {
        switch viewModel.state {
        case .readyForInput: return "记录物品"
        case .analyzing: return "识别中…"
        case .preview: return "确认信息"
        case .saving: return "保存中…"
        case .saved: return "完成"
        case .error: return "出错了"
        case .idle: return "记录物品"
        }
    }

    // MARK: - Idle (等待选图)

    private var idleView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView("等待拍照…")
                .font(.subheadline)
            Spacer()
        }
    }

    // MARK: - Ready For Input（选图后、AI 分析前）

    private var readyForInputView: some View {
        VStack(spacing: 0) {
            // Hero 图片区
            heroImageSection
                .padding(.horizontal, 16)
                .padding(.top, 8)

            // 缩略图条（仅2张以上）
            if viewModel.selectedImages.count > 1 {
                thumbnailStrip
                    .padding(.top, 12)
                    .padding(.horizontal, 16)
            }

            // 语音 + 文字输入区
            inputCard
                .padding(.horizontal, 16)
                .padding(.top, 20)

            Spacer()

            // 底部操作按钮
            VStack(spacing: 12) {
                if let error = viewModel.showVoiceError {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                        .transition(.opacity)
                }

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
                .animation(.easeInOut, value: viewModel.canProceed)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Hero Image

    private var heroImageSection: some View {
        let safeIndex = min(mainImageIndex, max(0, viewModel.selectedImages.count - 1))

        return ZStack(alignment: .bottomLeading) {
            if !viewModel.selectedImages.isEmpty {
                Image(uiImage: viewModel.selectedImages[safeIndex])
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .animation(.easeInOut(duration: 0.3), value: mainImageIndex)

                // 底部渐变
                LinearGradient(
                    colors: [.clear, .black.opacity(0.35)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 20))

                // 添加照片按钮
                Button {
                    showAddPhotoMenu = true
                } label: {
                    Label("添加照片", systemImage: "plus")
                        .font(.subheadline)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                }
                .glassEffect(.regular.interactive(), in: .capsule)
                .tint(.primary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .bottomTrailing)

                // 页码指示器
                HStack(spacing: 6) {
                    ForEach(0..<viewModel.selectedImages.count, id: \.self) { index in
                        Circle()
                            .fill(index == mainImageIndex ? .white : .white.opacity(0.4))
                            .frame(width: 6, height: 6)
                    }
                }
                .padding(.leading, 14)
                .padding(.bottom, 14)
            }
        }
        .frame(height: 260)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Thumbnail Strip

    private var thumbnailStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(viewModel.selectedImages.enumerated()), id: \.offset) { index, image in
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) { mainImageIndex = index }
                    } label: {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(index == mainImageIndex ? .blue : .clear, lineWidth: 2.5)
                            )
                            .opacity(index == mainImageIndex ? 1 : 0.6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Input Card

    private var inputCard: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                // 语音按钮
                voiceButton

                // 文字输入
                TextField("描述一下这个物品…", text: $viewModel.userContext)
                    .textFieldStyle(.plain)
                    .font(.title3)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
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
                    // 录音中的动画
                    Circle()
                        .stroke(.red.opacity(0.4), lineWidth: 3)
                        .frame(width: 52, height: 52)
                        .scaleEffect(viewModel.speechService.isRecording ? 1.3 : 1)
                        .opacity(viewModel.speechService.isRecording ? 0 : 0.6)
                        .animation(
                            .easeInOut(duration: 0.8).repeatForever(autoreverses: false),
                            value: viewModel.speechService.isRecording
                        )

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
                    .frame(maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .glassEffect(.clear, in: .rect(cornerRadius: 16))
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

    // MARK: - Preview & Confirm

    private func previewView(response: AIResponse) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 多图展示
                if !viewModel.selectedImages.isEmpty {
                    VStack(spacing: 8) {
                        TabView(selection: $mainImageIndex) {
                            ForEach(Array(viewModel.selectedImages.enumerated()), id: \.offset) { index, image in
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxHeight: 260)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                    .tag(index)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .always))
                        .frame(height: 280)
                    }
                }

                // AI 推荐图标
                if let emoji = response.emoji {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("AI 推荐图标").font(.subheadline).foregroundStyle(.secondary)
                        HStack(spacing: 10) {
                            Text(emoji)
                                .font(.largeTitle)
                                .frame(width: 48, height: 48)
                                .glassEffect(.regular, in: .circle)
                            Text("保存后可在地图详情页更换")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // 物品名称（可编辑）
                VStack(alignment: .leading, spacing: 4) {
                    Text("物品名称").font(.subheadline).foregroundStyle(.secondary)
                    TextField("物品名称", text: $viewModel.editedName)
                        .font(.title3)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .glassEffect(.regular, in: .rect(cornerRadius: 12))
                }

                // AI 描述（只读）
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI 描述").font(.subheadline).foregroundStyle(.secondary)
                    Text(response.description)
                        .font(.body)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassEffect(.regular, in: .rect(cornerRadius: 12))
                }

                // 场景
                if !response.scene.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("所在场景").font(.subheadline).foregroundStyle(.secondary)
                        Text(response.scene)
                            .font(.body)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassEffect(.regular, in: .rect(cornerRadius: 12))
                    }
                }

                // 关键词
                if !response.keywords.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("关键词").font(.subheadline).foregroundStyle(.secondary)
                        keywordsView(keywords: response.keywords)
                    }
                }

                // 保存按钮
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
                .padding(.top, 8)
            }
            .padding(20)
        }
    }

    // MARK: - Keywords Tags

    private func keywordsView(keywords: [String: String]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 8)], spacing: 8) {
            ForEach(Array(keywords.keys), id: \.self) { key in
                HStack(spacing: 4) {
                    Text(key).font(.subheadline).foregroundStyle(.secondary)
                    Text(keywords[key] ?? "").font(.subheadline).fontWeight(.medium)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .glassEffect(.regular, in: .capsule)
            }
        }
    }

    // MARK: - Saving

    private var savingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView("正在保存…")
                .font(.headline)
            Spacer()
        }
    }

    // MARK: - Error

    private func errorView(message: String) -> some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("出错了")
                .font(.title2)
                .fontWeight(.semibold)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            HStack(spacing: 12) {
                Button("重试") {
                    viewModel.retry()
                }
                .buttonStyle(.glassProminent)
                .tint(.blue)

                Button("返回") {
                    viewModel.reset()
                }
                .buttonStyle(.glass)
                .tint(.primary)
            }
            .controlSize(.extraLarge)

            Spacer()
        }
    }
}

#Preview {
    CaptureView(preselectedImage: UIImage(systemName: "photo")!, onDismiss: {})
}
