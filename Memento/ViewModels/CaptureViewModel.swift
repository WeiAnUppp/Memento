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

    // 多图支持（最多5张）
    static let maxImageCount = 5
    var selectedImages: [UIImage] = []
    private var photoGPSs: [CLLocationCoordinate2D?] = []
    /// 每张图的拍摄时间（相册取 EXIF/PHAsset，相机为 nil=保存时刻）。第一张决定记录时间。
    private var photoDates: [Date?] = []

    /// 是否还能添加更多图片
    var canAddMoreImages: Bool {
        selectedImages.count < Self.maxImageCount
    }

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

    /// 添加新图片（相机拍照或相册选图），最多 maxImageCount 张
    /// ⚠️ 入口即缩到 1024px —— 全分辨率图留在数组里会 OOM
    func addImage(_ image: UIImage, gps: CLLocationCoordinate2D?, takenAt: Date? = nil) {
        guard selectedImages.count < Self.maxImageCount else { return }
        let resized = image.resized(maxDimension: 1024) ?? image
        selectedImages.append(resized)
        photoGPSs.append(gps)
        photoDates.append(takenAt)
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
        if index < photoDates.count {
            photoDates.remove(at: index)
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

        // 启动后台分析（detached 避免继承 MainActor 导致主线程阻塞）
        Task.detached(priority: .userInitiated) { [weak self] in
            await self?.performBackgroundAnalysis(images: images, context: context, gps: gps)
        }
    }

    /// 兼容旧接口：直接传第一张图（来自外部调用）
    func didSelectFirstImage(_ image: UIImage, gps: CLLocationCoordinate2D?, takenAt: Date? = nil) {
        selectedImages = [image]
        photoGPSs = [gps]
        photoDates = [takenAt]
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
        let name = editedName.isEmpty ? response.name : editedName
        let images = selectedImages
        let gpsList = photoGPSs
        let dates = photoDates
        let context = userContext

        // 重活放后台，不阻塞主线程（否则页面卡顿）
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            // 保存所有图片到磁盘（入口已缩到1024px）
            var imagePaths: [String] = []
            for image in images {
                if let data = image.jpegData(compressionQuality: 0.85) {
                    if let path = try? DatabaseService.saveImage(data) {
                        imagePaths.append(path)
                    }
                }
            }

            // GPS
            let lat: Double
            let lon: Double
            if let gps = gpsList.first, let coord = gps {
                lat = coord.latitude
                lon = coord.longitude
            } else if let loc = self.locationService.currentLocation {
                lat = loc.coordinate.latitude
                lon = loc.coordinate.longitude
            } else {
                lat = 0
                lon = 0
            }

            let imagePathJSON = imagePaths.isEmpty
                ? nil
                : (try? JSONEncoder().encode(imagePaths)).flatMap { String(data: $0, encoding: .utf8) }

            let nearbyStr: String? = {
                guard let objs = response.nearbyObjects else { return nil }
                let cleaned = objs
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                return cleaned.isEmpty ? nil : cleaned.joined(separator: "、")
            }()

            var item = Item(
                name: name,
                itemDescription: response.description,
                keywords: jsonString(from: response.keywords),
                scene: response.scene.isEmpty ? nil : response.scene,
                nearbyObjects: nearbyStr,
                userNote: context.isEmpty ? nil : context,
                latitude: lat,
                longitude: lon,
                emoji: response.emoji,
                imagePath: imagePathJSON,
                createdAt: dates.first.flatMap { $0 } ?? Date(),
                updatedAt: Date()
            )

            let text = self.embeddingService.embeddingText(
                from: item.name,
                description: item.itemDescription,
                keywords: item.keywords,
                scene: item.scene,
                nearbyObjects: item.nearbyObjects
            )
            let embedding = self.embeddingService.vector(for: text)

            do {
                let id = try self.dbService.insert(item, embedding: embedding)
                item.id = id
                await MainActor.run {
                    self.lastSavedItemCoordinate = item.coordinate
                    self.state = .saved(item)
                }
            } catch {
                await MainActor.run {
                    self.state = .error("保存失败: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Retry / Reset

    func retry() {
        let images = selectedImages
        let gps = photoGPSs
        let dates = photoDates
        let context = userContext
        reset()
        selectedImages = images
        photoGPSs = gps
        photoDates = dates
        userContext = context
        state = .readyForInput
    }

    func reset() {
        state = .idle
        selectedImages = []
        photoGPSs = []
        photoDates = []
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
        // 图片压缩策略：
        // - 第1张（主物品）：1024px + 0.8 质量 → 保证识别精度
        // - 其余（环境补充）：512px + 0.6 质量 → 够看清场景即可，防 OOM / 请求体过大
        let base64List: [String] = images.enumerated().compactMap { index, image in
            let maxDim: CGFloat = index == 0 ? 1024 : 512
            let quality: CGFloat = index == 0 ? 0.8 : 0.6
            let resized = image.resized(maxDimension: maxDim) ?? image
            guard let data = resized.jpegData(compressionQuality: quality) else { return nil }
            return data.base64EncodedString()
        }

        guard !base64List.isEmpty else {
            await MainActor.run {
                analysisDidFail = true
                analysisErrorMessage = "图片处理失败"
                state = .error("图片处理失败")
            }
            return
        }

        do {
            let response = try await aiService.analyzeImages(
                base64Images: base64List,
                userContext: context
            )

            // 确认仍在后台分析状态（未被取消）
            guard case .backgroundAnalyzing = state else { return }

            await MainActor.run { editedName = response.name }
            saveItem(with: response)
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
