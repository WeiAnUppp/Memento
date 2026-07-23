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
        // 将识别结果填入输入框
        if !speechService.transcript.isEmpty {
            userContext = speechService.transcript
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

    /// 用户确认表单，开始 AI 分析
    func proceedToAnalysis() {
        guard canProceed else { return }
        Task { await analyzeImages() }
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
            state = .saved(item)
        } catch {
            state = .error("保存失败: \(error.localizedDescription)")
        }
    }

    // MARK: - Retry / Reset

    func retry() {
        let images = selectedImages
        let gps = photoGPSs
        reset()
        selectedImages = images
        photoGPSs = gps
        // 保持 readyForInput 以便用户可以修改表单后重试
    }

    func reset() {
        state = .idle
        selectedImages = []
        photoGPSs = []
        userContext = ""
        editedName = ""
    }

    // MARK: - Private

    private func analyzeImages() async {
        state = .analyzing

        // 转换所有图片为 base64
        let base64List = selectedImages.compactMap { image -> String? in
            guard let data = image.jpegData(compressionQuality: 0.8) else { return nil }
            return data.base64EncodedString()
        }

        guard !base64List.isEmpty else {
            state = .error("图片处理失败")
            return
        }

        do {
            let response = try await aiService.analyzeImages(
                base64Images: base64List,
                userContext: userContext
            )
            editedName = response.name
            state = .preview(response)
        } catch {
            state = .error("AI 识别失败: \(error.localizedDescription)")
        }
    }
}

// MARK: - Helpers

private func jsonString(from dict: [String: String]) -> String? {
    guard let data = try? JSONEncoder().encode(dict) else { return nil }
    return String(data: data, encoding: .utf8)
}
