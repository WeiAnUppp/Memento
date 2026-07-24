//
//  CameraHalfView.swift
//  Memento
//
//  Created by WeiAnUppp on 2026/7/22.
//

import SwiftUI
import AVFoundation
import CoreLocation
import ImageIO

// MARK: - Flash Mode

enum CameraFlashMode: CaseIterable {
    case off, on, auto

    var icon: String {
        switch self {
        case .off:  return "bolt.slash.fill"
        case .on:   return "bolt.fill"
        case .auto: return "bolt.badge.automatic"
        }
    }

    var avMode: AVCaptureDevice.FlashMode {
        switch self {
        case .off:  return .off
        case .on:   return .on
        case .auto: return .auto
        }
    }
}

// MARK: - Camera Model

@Observable
final class CameraModel: NSObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()

    var capturedImage: UIImage?
    var capturedGPS: CLLocationCoordinate2D?
    var isAuthorized = false
    var isSessionReady = false
    var errorMessage: String?

    var flashMode: CameraFlashMode = .auto

    // MARK: - Setup

    func requestAndSetup() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            isAuthorized = true
            setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.isAuthorized = granted
                    if granted { self?.setupSession() }
                }
            }
        default:
            isAuthorized = false
            errorMessage = "相机权限未授权，请在设置中开启"
        }
    }

    private func setupSession() {
        guard !isSessionReady else { return }

        session.beginConfiguration()
        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .back
        ),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else {
            session.commitConfiguration()
            errorMessage = "无法访问相机"
            return
        }

        session.addInput(input)

        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            // 速度优先：牺牲极限画质换取更短的快门→出图延迟（记录物品无需超高画质）
            photoOutput.maxPhotoQualityPrioritization = .speed
        }

        session.commitConfiguration()
        isSessionReady = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }

    // MARK: - Flash

    func cycleFlashMode() {
        switch flashMode {
        case .off:  flashMode = .on
        case .on:   flashMode = .auto
        case .auto: flashMode = .off
        }
    }

    // MARK: - Capture

    func capture() {
        let settings = AVCapturePhotoSettings()
        settings.flashMode = flashMode.avMode
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func stop() {
        guard isSessionReady else { return }
        session.stopRunning()
        isSessionReady = false
    }

    // MARK: - AVCapturePhotoCaptureDelegate

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard error == nil else {
            errorMessage = "拍照失败"
            return
        }
        // 用 cgImageRepresentation 直接获取位图，跳过 JPEG 编解码（全分辨率编解码极慢）
        // 但 CGImage 不含 EXIF 方向，需从 metadata 读取后手动纠正
        let orientation = Self.imageOrientation(from: photo.metadata)
        if let cgImage = photo.cgImageRepresentation() {
            capturedImage = UIImage(cgImage: cgImage, scale: 1.0, orientation: orientation)
        } else if let data = photo.fileDataRepresentation(),
                  let image = UIImage(data: data) {
            capturedImage = image
        } else {
            errorMessage = "拍照失败"
            return
        }
        // GPS 从照片元数据直接读，不需要先编码再解码
        capturedGPS = Self.extractGPS(from: photo.metadata)
    }

    /// 从 AVCapturePhoto metadata 字典中提取 GPS
    static func extractGPS(from metadata: [String: Any]) -> CLLocationCoordinate2D? {
        guard let gps = metadata[kCGImagePropertyGPSDictionary as String] as? [String: Any],
              let lat = gps[kCGImagePropertyGPSLatitude as String] as? Double,
              let lon = gps[kCGImagePropertyGPSLongitude as String] as? Double,
              let latRef = gps[kCGImagePropertyGPSLatitudeRef as String] as? String,
              let lonRef = gps[kCGImagePropertyGPSLongitudeRef as String] as? String
        else { return nil }

        return CLLocationCoordinate2D(
            latitude: latRef == "S" ? -lat : lat,
            longitude: lonRef == "W" ? -lon : lon
        )
    }

    /// 从照片 metadata 中读取 EXIF 方向，转为 UIImage.Orientation
    static func imageOrientation(from metadata: [String: Any]) -> UIImage.Orientation {
        guard let raw = metadata[kCGImagePropertyOrientation as String] as? UInt32 else {
            return .up
        }
        // EXIF 方向值 → UIImage.Orientation（1-8 映射）
        switch raw {
        case 1: return .up
        case 2: return .upMirrored
        case 3: return .down
        case 4: return .downMirrored
        case 5: return .leftMirrored
        case 6: return .right
        case 7: return .rightMirrored
        case 8: return .left
        default: return .up
        }
    }
}

// MARK: - Preview View (UIKit)

final class PreviewView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}

// MARK: - Camera Preview (SwiftUI Bridge)

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

// MARK: - Half-Screen Camera View

struct CameraHalfView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var camera = CameraModel()
    @State private var captureScale: CGFloat = 1
    @State private var previewSize: CGSize = .zero

    /// 第三个参数为照片拍摄时间；相机现拍即当前时刻，传 nil 让上层用 now。
    let onPhotoCaptured: (UIImage, CLLocationCoordinate2D?, Date?) -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack {
            Color.black.ignoresSafeArea()

            if camera.isSessionReady {
                CameraPreview(session: camera.session)
                    .ignoresSafeArea(.all)
            } else if let error = camera.errorMessage {
                errorState(error)
            } else {
                ProgressView().tint(.white)
            }

            VStack(spacing: 0) {
                topBar
                Spacer()
                shutterButton
                    .padding(.bottom, 50)
            }
        }
        .ignoresSafeArea(.all)
        .onAppear {
            previewSize = geometry.size
            camera.requestAndSetup()
        }
        .onChange(of: geometry.size) { _, newSize in
            previewSize = newSize
        }
        .onDisappear { camera.stop() }
        .onChange(of: camera.capturedImage) { _, image in
            guard let image else { return }
            let gps = camera.capturedGPS
            let size = previewSize
            // 裁剪+缩图放后台；拍照完成后第一时间回传，不等人为延迟
            DispatchQueue.global(qos: .userInitiated).async {
                // 一次性裁剪 + 缩到 ≤1024px，主线程 addImage 的缩图变成 no-op，消除卡顿
                let cropped = Self.cropToPreview(image, previewSize: size, maxDimension: 1024)
                DispatchQueue.main.async {
                    onPhotoCaptured(cropped, gps, nil)
                    dismiss()
                }
            }
            }
        }
    }

    // MARK: - Crop to Preview

    /// 按预览实际可见区域裁剪照片，同时缩到 maxDimension，一次渲染完成（即拍即所得）。
    /// 关键优化：
    /// - `scale = 1` 避免默认按屏幕 3x 放大渲染（12MP 图 ×3 极慢且占内存）
    /// - 裁剪与缩图合并成一遍绘制，省去后续 addImage 里的二次缩图（消除主线程卡顿）
    static func cropToPreview(_ image: UIImage, previewSize: CGSize, maxDimension: CGFloat) -> UIImage {
        guard previewSize.width > 0, previewSize.height > 0 else { return image }

        let imageSize = image.size
        let viewAspect = previewSize.width / previewSize.height
        let imageAspect = imageSize.width / imageSize.height

        // 1) 计算按预览比例裁剪后的可见区域尺寸
        let cropSize: CGSize
        if imageAspect > viewAspect {
            // 图片比预览宽 → 裁左右
            cropSize = CGSize(width: imageSize.height * viewAspect, height: imageSize.height)
        } else {
            // 图片比预览高 → 裁上下
            cropSize = CGSize(width: imageSize.width, height: imageSize.width / viewAspect)
        }

        // 2) 叠加缩放：裁剪区域长边压到 maxDimension 以内
        let cropMax = max(cropSize.width, cropSize.height)
        let scale = cropMax > maxDimension ? maxDimension / cropMax : 1
        let outputSize = CGSize(width: cropSize.width * scale, height: cropSize.height * scale)

        // 3) 把整图按 scale 画到画布，居中定位使裁剪窗对齐画面中心
        let drawSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let drawOrigin = CGPoint(
            x: -(drawSize.width - outputSize.width) / 2,
            y: -(drawSize.height - outputSize.height) / 2
        )

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1   // 不按屏幕 3x 放大
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: outputSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: drawOrigin, size: drawSize))
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 50, height: 50)
            }
            .glassEffect(.regular.interactive(), in: .circle)
            .tint(.primary)

            Spacer()

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    camera.cycleFlashMode()
                }
            } label: {
                Image(systemName: camera.flashMode.icon)
                    .font(.system(size: 18))
                    .frame(width: 50, height: 50)
            }
            .glassEffect(.regular.interactive(), in: .circle)
            .tint(camera.flashMode == .off ? Color.secondary : Color.yellow)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    // MARK: - Shutter Button

    private var shutterButton: some View {
        Button {
            capturePhoto()
        } label: {
            ZStack {
                Circle()
                    .stroke(.white, lineWidth: 5)
                    .frame(width: 68, height: 68)
                Circle()
                    .fill(.white)
                    .frame(width: 54, height: 54)
            }
            .frame(width: 68, height: 68)
        }
        .glassEffect(.regular.interactive(), in: .circle)
        .scaleEffect(captureScale)
        .disabled(!camera.isSessionReady)
    }

    // MARK: - Capture Logic

    private func capturePhoto() {
        withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
            captureScale = 0.88
        }

        camera.capture()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                captureScale = 1
            }
        }
    }

    // MARK: - Error State

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.metering.none")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    CameraHalfView { _, _, _ in }
}
