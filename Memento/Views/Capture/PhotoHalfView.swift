//
//  PhotoHalfView.swift
//  Memento
//
//  Created by WeiAnUppp on 2026/7/22.
//

import SwiftUI
import Photos
import CoreLocation

// MARK: - Photo Half View

/// 半屏照片选择器，照片铺满、顶栏透明、按钮液态玻璃浮于照片之上
struct PhotoHalfView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDetent: PresentationDetent = .fraction(0.65)
    @State private var assets: [PHAsset] = []
    @State private var isLoading = true
    @State private var authDenied = false

    private let imageManager = PHCachingImageManager()

    /// 回调带上照片的拍摄时间（PHAsset.creationDate），供记录时间使用；相机场景传 nil。
    let onPhotoSelected: (UIImage, CLLocationCoordinate2D?, Date?) -> Void

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            if isLoading {
                ProgressView()
            } else if authDenied {
                ContentUnavailableView(
                    "无法访问照片",
                    systemImage: "lock.shield",
                    description: Text("请在设置中允许忆物访问照片库")
                )
            } else if assets.isEmpty {
                ContentUnavailableView(
                    "没有照片",
                    systemImage: "photo.on.rectangle",
                    description: Text("你的照片库中还没有图片")
                )
            } else {
                photoGrid
            }

            // 透明顶栏，液态玻璃按钮浮于照片之上
            VStack {
                topBar
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                Spacer()
            }
        }
        .ignoresSafeArea(.all)
        .presentationDetents([.fraction(0.65), .large], selection: $selectedDetent)
        .presentationDragIndicator(.hidden)
        .onAppear { loadPhotos() }
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
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    selectedDetent = selectedDetent == .large ? .fraction(0.65) : .large
                }
            } label: {
                Image(systemName: selectedDetent == .large
                      ? "arrow.down.right.and.arrow.up.left"
                      : "photo.stack")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 50, height: 50)
            }
            .glassEffect(.regular.interactive(), in: .circle)
            .tint(.primary)
        }
    }

    // MARK: - Photo Grid

    private var photoGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3),
                spacing: 2
            ) {
                ForEach(assets, id: \.localIdentifier) { asset in
                    AssetThumbnail(asset: asset, manager: imageManager)
                        .aspectRatio(1, contentMode: .fill)
                        .clipped()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            requestFullImage(for: asset)
                        }
                }
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Load Photos

    private func loadPhotos() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited:
            fetchAssets()
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                if newStatus == .authorized || newStatus == .limited {
                    fetchAssets()
                } else {
                    DispatchQueue.main.async { authDenied = true; isLoading = false }
                }
            }
        default:
            authDenied = true
            isLoading = false
        }
    }

    private func fetchAssets() {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = 200

        let result = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        var fetched: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in
            fetched.append(asset)
        }

        DispatchQueue.main.async {
            assets = fetched
            isLoading = false
        }
    }

    // MARK: - Select Photo

    private func requestFullImage(for asset: PHAsset) {
        let gps = asset.location?.coordinate
        let takenAt = asset.creationDate   // 照片真实拍摄时间

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true

        // 不再请求 PHImageManagerMaximumSize（可达数千万像素、解码慢）：
        // 记录物品只需 ~1024px，请求 2048 上限已留足缩放余量，解码更快。
        let request = CGFloat(2048)
        imageManager.requestImage(
            for: asset,
            targetSize: CGSize(width: request, height: request),
            contentMode: .aspectFit,
            options: options
        ) { image, info in
            guard let image else { return }
            // 忽略 opportunistic 低清预览帧，只处理最终高清帧
            let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            if degraded { return }
            // 缩到 ≤1024px 放后台，避免主线程 addImage 二次缩图卡顿
            DispatchQueue.global(qos: .userInitiated).async {
                let resized = image.resized(maxDimension: 1024) ?? image
                DispatchQueue.main.async {
                    onPhotoSelected(resized, gps, takenAt)
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Asset Thumbnail

struct AssetThumbnail: View {
    let asset: PHAsset
    let manager: PHCachingImageManager

    @State private var thumbnail: UIImage?

    var body: some View {
        ZStack {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            }
            Rectangle()
                .fill(.gray.opacity(0.12))
        }
        .onAppear { loadThumbnail() }
        .onDisappear { thumbnail = nil }
    }

    private func loadThumbnail() {
        guard thumbnail == nil else { return }

        let screenWidth = UIScreen.main.bounds.width
        let itemWidth = (screenWidth - 4) / 3
        let targetSize = CGSize(width: itemWidth * UIScreen.main.scale,
                                 height: itemWidth * UIScreen.main.scale)

        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .exact

        manager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { image, info in
            let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            if !degraded || thumbnail == nil {
                DispatchQueue.main.async { thumbnail = image }
            }
        }
    }
}

#Preview {
    PhotoHalfView { _, _, _ in }
}
