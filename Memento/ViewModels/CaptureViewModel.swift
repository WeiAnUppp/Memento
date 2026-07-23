//
//  CaptureViewModel.swift
//  Memento
//
//  Created by WeiAnUppp on 2026/7/21.
//

import SwiftUI
import CoreLocation

// MARK: - Capture State

enum CaptureState: Equatable {
    case idle
    case readyForInput       // 图片已选，等待用户填写表单
    case analyzing
    case backgroundAnalyzing // API 已发起，UI 已退出，后台运行中
    case preview(AIResponse)
    case saving
    case saved(Item)
    case error(String)
}

// MARK: - Capture ViewModel

@Observable
final class CaptureViewModel {
    var state: CaptureState = .idle

    // 多图支持
    var selectedImages: [UIImage] = []
    private var photoGPSs: [CLLocationCoordinate2D?] = []

    // 用户一句话描述（AI 分析前填写）
    var userContext: String = ""

    // AI 结果编辑
    var editedName: String = ""

    /// 后台分析相关
    var analyzingImage: UIImage?
    var analyzingStatusText: String = "AI 正在识别物品…"
    var analysisDidFail: Bool = false
    var analysisErrorMessage: String = ""
    var lastSavedItemCoordinate: CLLocationCoordinate2D?

    /// 是否正在后台分析
    var isBackgroundAnalyzing: Bool {
        if case .backgroundAnalyzing = state { return true }
        return false
    }

    /// 是否可以进入 AI 分析
    var canProceed: Bool {
        !selectedImages.isEmpty
        && !userContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private let aiService = AIService()
    private let dbService = DatabaseService.shared
    private let embeddingService = EmbeddingService()
    private let locationService = LocationService()
    let speechService = SpeechService()

    var showVoiceError: String?

    init() {
        locationService.requestPermission()
        Task { await speechService.requestAuthorization() }
    }

    // MARK: - Voice

    func startVoiceInput() {
        showVoiceError = nil
        do {
            try speechService.startRecording()
        } catch {
            showVoiceError = error.localizedDescription
        }
    }

    func stopVoiceInput() {
        speechService.stopRecording()
        let cleaned = speechService.cleanedTranscript
        if !cleaned.isEmpty {
            userContext = cleaned
        }
    }

    // MARK: - Public API

    /// 添加新图片（相机拍照或相册选图）
    func addImage(_ image: UIImage, gps: CLLocationCoordinate2D?) {
        selectedImages.append(image)
        photoGPSs.append(gps)
        if case .idle = state {
            state = .readyForInput
        }
    }

    /// 移除指定位置的图片
    func removeImage(at index: Int) {
        guard index < selectedImages.count else { return }
        selectedImages.remove(at: index)
        if index < photoGPSs.count {
            photoGPSs.remove(at: index)
        }
        // 如果图片全部被删除，回到 idle
        if selectedImages.isEmpty {
            state = .idle
        }
    }

    /// 用户确认表单，开始 AI 后台分析（UI 立即退出）
    func proceedToAnalysis() {
        guard canProceed else { return }

        // 捕获当前数据
        let images = selectedImages
        let context = userContext
        let gps = photoGPSs.first ?? nil

        analyzingImage = images.first
        analyzingStatusText = "AI 正在识别物品…"
        analysisDidFail = false
        analysisErrorMessage = ""

        // 立即退出记录 UI
        state = .backgroundAnalyzing

        // 启动后台分析
        Task { await performBackgroundAnalysis(images: images, context: context, gps: gps) }
    }

    /// 兼容旧接口：直接传第一张图（来自外部调用）
    func didSelectFirstImage(_ image: UIImage, gps: CLLocationCoordinate2D?) {
        selectedImages = [image]
        photoGPSs = [gps]
        state = .readyForInput
    }

    // MARK: - Save

    func confirmSave() {
        guard case .preview(let response) = state else { return }
        saveItem(with: response)
    }

    // MARK: - Core Save

    /// 保存物品到数据库（前台预览保存 & 后台自动保存共用）
    private func saveItem(with response: AIResponse) {
        state = .saving

        let name = editedName.isEmpty ? response.name : editedName

        // 保存所有图片到磁盘
        var imagePaths: [String] = []
        for image in selectedImages {
            if let data = image.jpegData(compressionQuality: 0.85) {
                if let path = try? DatabaseService.saveImage(data) {
                    imagePaths.append(path)
                }
            }
        }

        // 优先使用第一张照片的 EXIF GPS
        let lat: Double
        let lon: Double
        if let gps = photoGPSs.first, let coord = gps {
            lat = coord.latitude
            lon = coord.longitude
        } else if let loc = locationService.currentLocation {
            lat = loc.coordinate.latitude
            lon = loc.coordinate.longitude
        } else {
            lat = 0
            lon = 0
        }

        // imagePaths → JSON 字符串
        let imagePathJSON = imagePaths.isEmpty
            ? nil
            : (try? JSONEncoder().encode(imagePaths)).flatMap { String(data: $0, encoding: .utf8) }

        var item = Item(
            name: name,
            itemDescription: response.description,
            keywords: jsonString(from: response.keywords),
            scene: response.scene.isEmpty ? nil : response.scene,
            userNote: userContext.isEmpty ? nil : userContext,
            latitude: lat,
            longitude: lon,
            emoji: response.emoji,
            imagePath: imagePathJSON,
            createdAt: Date(),
            updatedAt: Date()
        )

        // 生成 embedding
        let text = embeddingService.embeddingText(
            from: item.name,
            description: item.itemDescription,
            keywords: item.keywords,
            scene: item.scene
        )
        let embedding = embeddingService.vector(for: text)

        do {
            let id = try dbService.insert(item, embedding: embedding)
            item.id = id
            lastSavedItemCoordinate = item.coordinate
            state = .saved(item)
        } catch {
            state = .error("保存失败: \(error.localizedDescription)")
        }
    }

    // MARK: - Retry / Reset

    func retry() {
        let images = selectedImages
        let gps = photoGPSs
        let context = userContext
        reset()
        selectedImages = images
        photoGPSs = gps
        userContext = context
        state = .readyForInput
    }

    func reset() {
        state = .idle
        selectedImages = []
        photoGPSs = []
        userContext = ""
        editedName = ""
        analyzingImage = nil
        analyzingStatusText = "AI 正在识别物品…"
        analysisDidFail = false
        analysisErrorMessage = ""
        lastSavedItemCoordinate = nil
    }

    // MARK: - Private

    /// 后台执行 AI 分析 + 自动保存
    private func performBackgroundAnalysis(
        images: [UIImage],
        context: String,
        gps: CLLocationCoordinate2D?
    ) async {
        // 转换所有图片为 base64
        let base64List = images.compactMap { image -> String? in
            guard let data = image.jpegData(compressionQuality: 0.8) else { return nil }
            return data.base64EncodedString()
        }

        guard !base64List.isEmpty else {
            analysisDidFail = true
            analysisErrorMessage = "图片处理失败"
            state = .error("图片处理失败")
            return
        }

        do {
            let response = try await aiService.analyzeImages(
                base64Images: base64List,
                userContext: context
            )

            // 确认仍在后台分析状态（未被取消）
            guard case .backgroundAnalyzing = state else { return }

            await MainActor.run {
                editedName = response.name
                saveItem(with: response)
            }
        } catch {
            guard case .backgroundAnalyzing = state else { return }
            await MainActor.run {
                analysisDidFail = true
                analysisErrorMessage = error.localizedDescription
                state = .error("AI 识别失败: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Helpers

private func jsonString(from dict: [String: String]) -> String? {
    guard let data = try? JSONEncoder().encode(dict) else { return nil }
    return String(data: data, encoding: .utf8)
}
