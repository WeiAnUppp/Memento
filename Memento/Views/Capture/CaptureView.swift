//
//  CaptureView.swift
//  Memento
//
//  Created by WeiAnUppp on 2026/7/21.
//

import SwiftUI

// MARK: - Capture Flow View

struct CaptureView: View {
    let preselectedImage: UIImage?
    @State private var viewModel = CaptureViewModel()
    @State private var mainImageIndex = 0
    @State private var dragOffset: CGSize = .zero
    @State private var showAddPhotoMenu = false
    @State private var showAddCamera = false
    @State private var showAddPhotoLibrary = false

    let onDismiss: () -> Void

    init(preselectedImage: UIImage, onDismiss: @escaping () -> Void) {
        self.preselectedImage = preselectedImage
        self.onDismiss = onDismiss
    }

    var body: some View {
        NavigationStack {
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
            .navigationTitle("记录物品")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        viewModel.reset()
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .tint(.primary)
                }
                if case .readyForInput = viewModel.state {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showAddPhotoMenu = true } label: {
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .tint(.primary)
                    }
                }
            }
        }
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
                viewModel.didSelectFirstImage(image, gps: nil)
            }
        }
        .interactiveDismissDisabled(viewModel.state == .analyzing || viewModel.state == .saving)
    }

    // MARK: - Idle

    private var idleView: some View {
        VStack { Spacer(); ProgressView().font(.subheadline); Spacer() }
    }

    // MARK: - Ready For Input

    private var readyForInputView: some View {
        VStack(spacing: 0) {
            Spacer()

            // 卡片堆叠
            cardStackSection

            Spacer()

            // 输入 + 按钮
            VStack(spacing: 16) {
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
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Card Stack Section

    private var cardStackSection: some View {
        let images = viewModel.selectedImages
        let count = images.count
        let safeIndex = min(max(mainImageIndex, 0), max(count - 1, 0))
        let cardSize: CGFloat = min(UIScreen.main.bounds.width - 60, 300)

        return VStack(spacing: 16) {
            if images.isEmpty {
                RoundedRectangle(cornerRadius: 24)
                    .fill(.quaternary)
                    .frame(width: cardSize, height: cardSize)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.system(size: 44))
                            .foregroundStyle(.tertiary)
                    }
            } else {
                // 堆叠卡片
                ZStack {
                    let maxDepth = min(3, count - safeIndex)
                    ForEach(0..<maxDepth, id: \.self) { offset in
                        let idx = safeIndex + offset
                        if idx < count {
                            cardView(image: images[idx],
                                     size: cardSize,
                                     depth: offset,
                                     isTop: offset == 0)
                            .zIndex(Double(-offset))
                        }
                    }
                }
                .frame(width: cardSize, height: cardSize)

                // 页码
                if count > 1 {
                    HStack(spacing: 6) {
                        ForEach(0..<count, id: \.self) { index in
                            Capsule()
                                .fill(index == safeIndex ? .blue : .secondary.opacity(0.3))
                                .frame(width: index == safeIndex ? 16 : 6, height: 6)
                                .animation(.spring(response: 0.3), value: safeIndex)
                        }
                    }
                }
            }
        }
    }

    private func cardView(image: UIImage, size: CGFloat, depth: Int, isTop: Bool) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.12), radius: 10, y: 5)
            .scaleEffect(depth == 0 ? 1 : 1 - CGFloat(depth) * 0.04)
            .offset(y: CGFloat(depth) * 8)
            .rotationEffect(.degrees(depth == 0 ? 0 : Double(depth) * 2))
            .opacity(depth == 0 ? 1 : 0.45 - Double(depth) * 0.15)
            .offset(x: isTop ? dragOffset.width : 0)
            .rotationEffect(.degrees(isTop ? dragOffset.width / 25 : 0))
            .gesture(isTop ? swipeGesture : nil)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: mainImageIndex)
    }

    // MARK: - Swipe Gesture

    private var swipeGesture: some Gesture {
        DragGesture()
            .onChanged { dragOffset = $0.translation }
            .onEnded { value in
                let count = viewModel.selectedImages.count
                guard count > 0 else {
                    dragOffset = .zero
                    return
                }
                let threshold: CGFloat = 60
                var newIndex = mainImageIndex
                if value.translation.width < -threshold, newIndex < count - 1 { newIndex += 1 }
                else if value.translation.width > threshold, newIndex > 0 { newIndex -= 1 }
                newIndex = min(max(newIndex, 0), count - 1)

                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    mainImageIndex = newIndex
                    dragOffset = .zero
                }
            }
    }

    // MARK: - Input Card

    private var inputCard: some View {
        HStack(spacing: 10) {
            voiceButton
            TextField("简单描述一下...", text: $viewModel.userContext)
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
            viewModel.speechService.isRecording
                ? viewModel.stopVoiceInput()
                : viewModel.startVoiceInput()
        } label: {
            ZStack {
                Circle()
                    .fill(viewModel.speechService.isRecording ? .red : .blue)
                    .frame(width: 44, height: 44)

                Group {
                    if viewModel.speechService.isRecording {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 18, weight: .medium))
                    } else {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 20, weight: .medium))
                    }
                }
                .foregroundStyle(.white)
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
            if let first = viewModel.selectedImages.first {
                Image(uiImage: first)
                    .resizable().scaledToFit()
                    .frame(maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
            }
            ProgressView("AI 正在识别物品…").font(.headline)
            Text("结合你提供的信息分析物品特征")
                .font(.subheadline).foregroundStyle(.secondary)
            Spacer()
        }.padding(24)
    }

    // MARK: - Preview

    private func previewView(response: AIResponse) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let first = viewModel.selectedImages.first {
                    Image(uiImage: first)
                        .resizable().scaledToFit()
                        .frame(maxHeight: 220)
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
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .glassEffect(.regular, in: .rect(cornerRadius: 12))
                }

                if !response.scene.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("场景").font(.subheadline).foregroundStyle(.secondary)
                        Text(response.scene).font(.body)
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
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
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                }
                .buttonStyle(.glassProminent).tint(.blue).controlSize(.extraLarge)
            }
            .padding(20)
        }
    }

    // MARK: - Saving

    private var savingView: some View {
        VStack { Spacer(); ProgressView("正在保存…").font(.headline); Spacer() }
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
                Button("重试") { viewModel.retry() }.buttonStyle(.glassProminent).tint(.blue)
                Button("返回") { viewModel.reset() }.buttonStyle(.glass).tint(.primary)
            }.controlSize(.extraLarge)
            Spacer()
        }
    }
}

#Preview {
    CaptureView(preselectedImage: UIImage(systemName: "photo")!, onDismiss: {})
}
