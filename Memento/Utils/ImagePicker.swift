//
//  ImagePicker.swift
//  Memento
//
//  Created by WeiAnUppp on 2026/7/21.
//

import SwiftUI
import UIKit
import Photos
import CoreLocation
import ImageIO

// MARK: - Image Picker (UIKit 桥接)

/// UIImagePickerController 的 SwiftUI 封装
/// 支持 .camera（相机）和 .photoLibrary（相册）
/// 自动提取照片 EXIF 中的 GPS 坐标
struct ImagePicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let onPicked: (UIImage, CLLocationCoordinate2D?) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                let gps = Self.extractGPS(from: info, sourceType: parent.sourceType)
                parent.onPicked(image, gps)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }

        // MARK: - GPS Extraction

        static func extractGPS(
            from info: [UIImagePickerController.InfoKey: Any],
            sourceType: UIImagePickerController.SourceType
        ) -> CLLocationCoordinate2D? {
            // 1. 从 EXIF metadata 提取（相机 / 某些相册图片）
            if let metadata = info[.mediaMetadata] as? [String: Any],
               let gps = metadata[kCGImagePropertyGPSDictionary as String] as? [String: Any],
               let coord = parseGPSDictionary(gps) {
                return coord
            }

            // 2. 从 PHAsset 提取（相册选图）
            if let asset = info[.phAsset] as? PHAsset,
               let location = asset.location {
                return location.coordinate
            }

            // 3. 从文件 URL 读取 EXIF
            if let imageURL = info[.imageURL] as? URL,
               let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
               let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
               let gps = props[kCGImagePropertyGPSDictionary as String] as? [String: Any],
               let coord = parseGPSDictionary(gps) {
                return coord
            }

            return nil
        }

        private static func parseGPSDictionary(_ gps: [String: Any]) -> CLLocationCoordinate2D? {
            guard let lat = gps[kCGImagePropertyGPSLatitude as String] as? Double,
                  let lon = gps[kCGImagePropertyGPSLongitude as String] as? Double,
                  let latRef = gps[kCGImagePropertyGPSLatitudeRef as String] as? String,
                  let lonRef = gps[kCGImagePropertyGPSLongitudeRef as String] as? String else {
                return nil
            }

            let latitude = latRef == "S" ? -lat : lat
            let longitude = lonRef == "W" ? -lon : lon

            return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }
}
