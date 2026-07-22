//
//  CameraHalfView.swift
//  Memento
//
//  Created by WeiAnUppp on 2026/7/22.
//

import SwiftUI
import AVFoundation

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
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data)
        else {
            errorMessage = "拍照失败"
            return
        }
        capturedImage = image
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

    let onPhotoCaptured: (UIImage) -> Void

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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                onPhotoCaptured(cropToPreview(image))
                dismiss()
            }
            }
        }
    }

    // MARK: - Crop to Preview

    /// 按预览实际可见区域裁剪照片，实现即拍即所得
    private func cropToPreview(_ image: UIImage) -> UIImage {
        guard previewSize.width > 0, previewSize.height > 0 else { return image }

        let imageSize = image.size
        let viewAspect = previewSize.width / previewSize.height
        let imageAspect = imageSize.width / imageSize.height

        let targetSize: CGSize
        let drawOrigin: CGPoint

        if imageAspect > viewAspect {
            // 图片比预览宽 → 裁左右
            targetSize = CGSize(width: imageSize.height * viewAspect, height: imageSize.height)
            drawOrigin = CGPoint(x: -(imageSize.width - targetSize.width) / 2, y: 0)
        } else {
            // 图片比预览高 → 裁上下
            targetSize = CGSize(width: imageSize.width, height: imageSize.width / viewAspect)
            drawOrigin = CGPoint(x: 0, y: -(imageSize.height - targetSize.height) / 2)
        }

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            image.draw(at: drawOrigin)
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
    CameraHalfView { _ in }
}
