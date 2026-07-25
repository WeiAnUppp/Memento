//
//  ItemDetailContent.swift
//  Memento
//
//  共享物品详情内容 — 列表页（AppStoreTransition 展开）和地图页（sheet）共用
//

import SwiftUI
import MapKit

// MARK: - ItemDetailContent

struct ItemDetailContent: View {
    let item: Item
    let safeArea: EdgeInsets
    var dismiss: (() -> Void)?           // nil = sheet 模式，不添加 tap-to-dismiss
    var onUpdate: () -> Void
    var onNavigateToMap: (() -> Void)?
    var onDeleteRequested: (() -> Void)?  // 删除后回调（sheet 模式用于关闭）
    var showMainImage: Bool = false      // true = 独立模式，顶部显示图片轮播

    @State private var selectedEmoji: String
    @State private var descriptionExpanded = false
    @State private var sceneExpanded = false
    @State private var locationName: String?
    @State private var currentImageIndex = 0

    // 系统 emoji 键盘（通过 UIViewRepresentable 强制切 emoji）
    @State private var emojiFieldFocused = false

    init(item: Item, safeArea: EdgeInsets,
         dismiss: (() -> Void)? = nil,
         onUpdate: @escaping () -> Void,
         onNavigateToMap: (() -> Void)? = nil,
         onDeleteRequested: (() -> Void)? = nil,
         showMainImage: Bool = false) {
        self.item = item
        self.safeArea = safeArea
        self.dismiss = dismiss
        self.onUpdate = onUpdate
        self.onNavigateToMap = onNavigateToMap
        self.onDeleteRequested = onDeleteRequested
        self.showMainImage = showMainImage
        _selectedEmoji = State(initialValue: item.emoji ?? "📦")
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection

            if showMainImage { mainImageCarousel }

            photoGridSection
            tagsSection
            descriptionSection
            sceneSection
            infoSection

            // 隐藏输入框：UIViewRepresentable 强制切 emoji 键盘
            EmojiCaptureField(isFocused: $emojiFieldFocused) { emoji in
                guard emoji != selectedEmoji else { return }
                selectedEmoji = emoji
                saveEmoji(emoji)
            }
            .frame(width: 0, height: 0)
            .opacity(0)

            mapSection
            actionButtons
        }
        .safeAreaPadding(showMainImage ? EdgeInsets() : safeArea)
        .contentShape(.rect)
        .onTapGesture { dismiss?() }
        .task { await geocodeLocation() }
    }

    // MARK: Main Image Carousel

    @ViewBuilder
    private var mainImageCarousel: some View {
        let paths = item.imagePaths
        if !paths.isEmpty {
            VStack(spacing: 8) {
                TabView(selection: $currentImageIndex) {
                    ForEach(Array(paths.enumerated()), id: \.offset) { index, imagePath in
                        if let url = DatabaseService.imageURL(for: imagePath),
                           let data = try? Data(contentsOf: url),
                           let uiImage = UIImage(data: data) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: 280)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .tag(index)
                        } else {
                            VStack(spacing: 8) {
                                Image(systemName: "photo.badge.exclamationmark")
                                    .font(.system(size: 40))
                                    .foregroundStyle(.secondary)
                                Text("图片加载失败")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: 280)
                            .tag(index)
                        }
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .frame(height: 300)
                .padding(.horizontal, 16)

                if paths.count > 1 {
                    Text("\(currentImageIndex + 1) / \(paths.count)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 12)
        }
    }

    // MARK: Header

    private var headerSection: some View {
        HStack(spacing: 12) {
            Button {
                emojiFieldFocused = true
            } label: {
                Text(selectedEmoji)
                    .font(.system(size: 36))
                    .frame(width: 52, height: 52)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.title2)
                    .bold()
                Text(subtitleText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
    }

    private var subtitleText: String {
        var parts: [String] = []
        if let loc = item.locationLabel, !loc.isEmpty {
            parts.append(loc)
        } else if let ds = item.displayScene, !ds.isEmpty {
            parts.append(String(ds.prefix(8)))
        } else if let scene = item.scene, !scene.isEmpty {
            parts.append(String(scene.prefix(8)))
        }
        parts.append(item.createdAt.friendlyChineseFormat)
        return parts.joined(separator: " · ")
    }

    // MARK: Photo Grid

    @ViewBuilder
    private var photoGridSection: some View {
        let paths = item.imagePaths
        // 主图已在 hero / 轮播中展示，这里只放其余照片
        let extraPaths = Array(paths.dropFirst())
        if !extraPaths.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(extraPaths.enumerated()), id: \.offset) { _, imagePath in
                        photoCell(for: imagePath)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 16)
        }
    }

    @ViewBuilder
    private func photoCell(for imagePath: String) -> some View {
        if let url = DatabaseService.imageURL(for: imagePath),
           let data = try? Data(contentsOf: url),
           let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.gray.opacity(0.15))
                .frame(width: 72, height: 72)
                .overlay {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
        }
    }

    // MARK: Tags

    @ViewBuilder
    private var tagsSection: some View {
        if !keywordTags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(keywordTags, id: \.self) { tag in
                        Text(tag)
                            .font(.subheadline)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.quaternary, in: Capsule())
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 16)
        }
    }

    // MARK: Description

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("描述").font(.subheadline).foregroundStyle(.secondary)

            Text(descriptionExpanded ? item.itemDescription : displaySummary)
                .font(.body)
                .lineLimit(descriptionExpanded ? nil : 2)
                .frame(maxWidth: .infinity, alignment: .leading)

            if item.itemDescription.count > 80 {
                Button {
                    withAnimation(.smooth(duration: 0.25)) { descriptionExpanded.toggle() }
                } label: {
                    Text(descriptionExpanded ? "收起 ▲" : "展开 ▼")
                        .font(.subheadline)
                }
                .foregroundStyle(.blue)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    private var displaySummary: String {
        if let dd = item.displayDescription, !dd.isEmpty { return dd }
        if let s = item.summary, !s.isEmpty { return s }
        return String(item.itemDescription.prefix(50))
    }

    // MARK: Scene

    @ViewBuilder
    private var sceneSection: some View {
        if let scene = item.scene, !scene.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("所在场景").font(.subheadline).foregroundStyle(.secondary)

                Text(sceneExpanded ? scene : displaySceneText)
                    .font(.body)
                    .lineLimit(sceneExpanded ? nil : 2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if scene.count > 50 {
                    Button {
                        withAnimation(.smooth(duration: 0.25)) { sceneExpanded.toggle() }
                    } label: {
                        Text(sceneExpanded ? "收起 ▲" : "展开 ▼")
                            .font(.subheadline)
                    }
                    .foregroundStyle(.blue)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    private var displaySceneText: String {
        if let ds = item.displayScene, !ds.isEmpty { return ds }
        return String((item.scene ?? "").prefix(30))
    }

    // MARK: Info

    private var infoSection: some View {
        VStack(spacing: 8) {
            if let loc = locationName {
                infoRow(icon: "location.fill", label: "位置", value: loc)
            } else {
                infoRow(icon: "location.fill", label: "位置",
                        value: String(format: "%.4f, %.4f", item.latitude, item.longitude))
            }
            infoRow(icon: "clock", label: "记录",
                    value: item.createdAt.friendlyChineseFormat)
            infoRow(icon: "pencil.line", label: "修改",
                    value: item.updatedAt.friendlyChineseFormat)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    private func infoRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(.secondary)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
            Spacer()
        }
    }

    // MARK: Map

    private var mapSection: some View {
        Map(initialPosition: .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: item.latitude, longitude: item.longitude),
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        ))) {
            Marker(item.name, coordinate: CLLocationCoordinate2D(
                latitude: item.latitude, longitude: item.longitude
            ))
        }
        .frame(height: 140)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .allowsHitTesting(false)
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.quaternary, lineWidth: 0.5)
        }
        .overlay {
            Color.clear
                .contentShape(RoundedRectangle(cornerRadius: 16))
                .onTapGesture {
                    dismiss?()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        onNavigateToMap?()
                    }
                }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    // MARK: Buttons

    private var actionButtons: some View {
        HStack(spacing: 16) {
            Button {
                // 编辑功能（可后续接入编辑页）
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "pencil")
                    Text("编辑")
                }
                .font(.headline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            }
            .background(.quaternary, in: Capsule())

            Button(role: .destructive) {
                handleDelete()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "trash")
                    Text("删除")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            }
            .background(.quaternary, in: Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    // MARK: Helpers

    private var keywordTags: [String] {
        guard let keywords = item.keywords,
              let data = keywords.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return []
        }
        return Array(dict.values).filter { !$0.isEmpty }
    }

    private func saveEmoji(_ emoji: String) {
        guard let id = item.id else { return }
        try? DatabaseService.shared.updateEmoji(id: id, emoji: emoji)
        onUpdate()
    }

    private func handleDelete() {
        guard let id = item.id else { return }
        DatabaseService.deleteImages(at: item.imagePaths)
        try? DatabaseService.shared.delete(id: id)
        dismiss?()
        onDeleteRequested?()
        onUpdate()
    }

    private func geocodeLocation() async {
        let location = CLLocation(latitude: item.latitude, longitude: item.longitude)
        guard let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location),
              let pm = placemarks.first else { return }
        var parts: [String] = []
        if let city = pm.locality { parts.append(city) }
        if let area = pm.subLocality { parts.append(area) }
        if let street = pm.thoroughfare { parts.append(street) }
        guard !parts.isEmpty else { return }
        await MainActor.run { locationName = parts.joined() }
    }
}

// MARK: - Emoji Keyboard Bridge

/// 强制弹出系统 emoji 键盘的 UITextField
fileprivate final class UIEmojiTextField: UITextField {

    override var textInputContextIdentifier: String? { "" }

    override var textInputMode: UITextInputMode? {
        for mode in UITextInputMode.activeInputModes where mode.primaryLanguage == "emoji" {
            return mode
        }
        return super.textInputMode
    }
}

/// UIViewRepresentable 桥接：点击后自动弹出 emoji 键盘，选完一个 emoji 即收起
fileprivate struct EmojiCaptureField: UIViewRepresentable {
    @Binding var isFocused: Bool
    var onEmojiSelected: (String) -> Void

    func makeUIView(context: Context) -> UIEmojiTextField {
        let field = UIEmojiTextField()
        field.delegate = context.coordinator
        field.textAlignment = .center
        return field
    }

    func updateUIView(_ uiView: UIEmojiTextField, context: Context) {
        if isFocused, !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        } else if !isFocused, uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: EmojiCaptureField

        init(_ parent: EmojiCaptureField) { self.parent = parent }

        func textField(_ textField: UITextField,
                       shouldChangeCharactersIn range: NSRange,
                       replacementString string: String) -> Bool {
            if !string.isEmpty, let char = string.last {
                parent.onEmojiSelected(String(char))
            }
            parent.isFocused = false
            return false
        }
    }
}
