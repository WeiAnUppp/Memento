//
//  CaptureView.swift
//  Memento
//
//  Created by WeiAnUppp on 2026/7/21.
//

import SwiftUI
import CoreLocation

// MARK: - Capture Flow View

/// 完整的拍照记录流程：
/// 外部通过 Menu 选择相机/照片 → 直接打开 → AI 分析 → 预览确认 → 保存
struct CaptureView: View {
    let sourceType: UIImagePickerController.SourceType?
    let preselectedImage: UIImage?
    let preselectedGPS: CLLocationCoordinate2D?

    @State private var viewModel = CaptureViewModel()
    @State private var showImagePicker = true

    let onDismiss: () -> Void

    /// 从系统相册选图（原有流程）
    init(sourceType: UIImagePickerController.SourceType, onDismiss: @escaping () -> Void) {
        self.sourceType = sourceType
        self.preselectedImage = nil
        self.preselectedGPS = nil
        self.onDismiss = onDismiss
    }

    /// 半屏相机已拍好照片，直接进入 AI 分析
    init(preselectedImage: UIImage, onDismiss: @escaping () -> Void) {
        self.sourceType = nil
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
            .navigationTitle("记录物品")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { onDismiss() }
                }
            }
        }
        .sheet(isPresented: $showImagePicker) {
            if let sourceType {
                ImagePicker(sourceType: sourceType) { image, gps in
                    viewModel.didSelectImage(image, gps: gps)
                }
            }
        }
        .onAppear {
            if let image = preselectedImage {
                showImagePicker = false
                viewModel.didSelectImage(image, gps: preselectedGPS)
            }
        }
        .interactiveDismissDisabled(viewModel.state != .idle)
    }

    // MARK: - Idle (等待 ImagePicker 返回)

    private var idleView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView("等待拍照…")
                .font(.subheadline)
            Spacer()
        }
    }

    // MARK: - Analyzing

    private var analyzingView: some View {
        VStack(spacing: 24) {
            Spacer()

            if let image = viewModel.selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .glassEffect(.clear, in: .rect(cornerRadius: 16))
            }

            ProgressView("AI 正在识别物品…")
                .font(.headline)
            Text("分析物品名称、特征、场景")
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
                // 图片
                if let image = viewModel.selectedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .glassEffect(.clear, in: .rect(cornerRadius: 16))
                }

                // AI 推荐图标
                if let emoji = response.emoji {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("AI 推荐图标").font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 10) {
                            Text(emoji)
                                .font(.largeTitle)
                                .frame(width: 48, height: 48)
                                .glassEffect(.regular, in: .circle)
                            Text("保存后可在地图详情页更换")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // 物品名称（可编辑）
                VStack(alignment: .leading, spacing: 4) {
                    Text("物品名称").font(.caption).foregroundStyle(.secondary)
                    TextField("物品名称", text: $viewModel.editedName)
                        .font(.title3)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .glassEffect(.regular, in: .rect(cornerRadius: 12))
                }

                // AI 描述（只读）
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI 描述").font(.caption).foregroundStyle(.secondary)
                    Text(response.description)
                        .font(.body)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassEffect(.regular, in: .rect(cornerRadius: 12))
                }

                // 场景
                if !response.scene.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("所在场景").font(.caption).foregroundStyle(.secondary)
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
                        Text("关键词").font(.caption).foregroundStyle(.secondary)
                        keywordsView(keywords: response.keywords)
                    }
                }

                // 备注（用户手动补充）
                VStack(alignment: .leading, spacing: 4) {
                    Text("备注（可选）").font(.caption).foregroundStyle(.secondary)
                    TextField("添加备注…", text: $viewModel.userNote)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .glassEffect(.regular, in: .rect(cornerRadius: 12))
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
                    Text(key).font(.caption).foregroundStyle(.secondary)
                    Text(keywords[key] ?? "").font(.caption).fontWeight(.medium)
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
    CaptureView(sourceType: .photoLibrary, onDismiss: {})
}
