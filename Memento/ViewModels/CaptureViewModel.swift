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
    var selectedImage: UIImage?
    var editedName: String = ""
    var userNote: String = ""

    /// 照片 EXIF 中的 GPS（优先使用），nil 时回退到设备 GPS
    private var photoGPS: CLLocationCoordinate2D?

    private let aiService = AIService()
    private let dbService = DatabaseService.shared
    private let embeddingService = EmbeddingService()
    private let locationService = LocationService()

    init() {
        locationService.requestPermission()
    }

    // MARK: - Public API

    func didSelectImage(_ image: UIImage, gps: CLLocationCoordinate2D?) {
        selectedImage = image
        photoGPS = gps
        Task { await analyzeImage(image) }
    }

    func confirmSave() {
        guard case .preview(let response) = state else { return }
        state = .saving

        let name = editedName.isEmpty ? response.name : editedName

        // 保存图片到磁盘
        let imagePath: String?
        if let image = selectedImage,
           let data = image.jpegData(compressionQuality: 0.85) {
            imagePath = try? DatabaseService.saveImage(data)
        } else {
            imagePath = nil
        }

        // 优先照片 EXIF GPS，其次设备 GPS，最后 0,0
        let lat: Double
        let lon: Double
        if let gps = photoGPS {
            lat = gps.latitude
            lon = gps.longitude
        } else if let loc = locationService.currentLocation {
            lat = loc.coordinate.latitude
            lon = loc.coordinate.longitude
        } else {
            lat = 0
            lon = 0
        }

        var item = Item(
            name: name,
            itemDescription: response.description,
            keywords: jsonString(from: response.keywords),
            scene: response.scene.isEmpty ? nil : response.scene,
            userNote: userNote.isEmpty ? nil : userNote,
            latitude: lat,
            longitude: lon,
            imagePath: imagePath,
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

    func retry() {
        if let image = selectedImage {
            let gps = photoGPS
            state = .idle
            didSelectImage(image, gps: gps)
        } else {
            state = .idle
        }
    }

    func reset() {
        state = .idle
        selectedImage = nil
        photoGPS = nil
        editedName = ""
        userNote = ""
    }

    // MARK: - Private

    private func analyzeImage(_ image: UIImage) async {
        state = .analyzing

        guard let data = image.jpegData(compressionQuality: 0.8) else {
            state = .error("图片处理失败")
            return
        }

        let base64 = data.base64EncodedString()

        do {
            let response = try await aiService.analyzeImage(base64Image: base64)
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
