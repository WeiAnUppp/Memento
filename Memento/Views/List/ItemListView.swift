//
//  ItemListView.swift
//  Memento
//
//  Created by 胡杰 on 2026/7/21.
//

import SwiftUI
import MapKit

struct ItemListView: View {
    var onDataChanged: (() -> Void)?
    var onBarVisibilityChange: ((Bool) -> Void)?
    let onNavigateToMap: ((Item) -> Void)?
    var refreshTrigger: Int = 0

    @State private var items: [Item] = []
    @State private var barHidden = false

    private let dbService = DatabaseService.shared

    var body: some View {
        Group {
            if items.isEmpty {
                emptyView
            } else {
                gridView
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .onAppear { loadItems() }
        .onChange(of: refreshTrigger) { _ in loadItems() }
    }

    // MARK: - Grid

    private var gridView: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 15),
                    GridItem(.flexible(), spacing: 15)
                ],
                spacing: 15
            ) {
                ForEach(items) { item in
                    AppStoreTransition(
                        config: .init(cardCornerRadius: 16)
                    ) { isExpanded, dismiss in
                        if isExpanded {
                            expandedHero(for: item, dismiss: dismiss)
                        } else {
                            ItemGridCard(item: item)
                        }
                    } content: { safeArea, dismiss in
                        detailContent(for: item, safeArea: safeArea, dismiss: dismiss)
                    }
                    .frame(height: 200)
                    .contextMenu {
                        Button {
                            // 编辑（暂不实现）
                        } label: {
                            Label("编辑", systemImage: "pencil")
                        }

                        Button(role: .destructive) {
                            deleteItem(item)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal, 15)
        }
        .contentMargins(.top, 56, for: .scrollContent)
        .refreshable {
            loadItems()
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y
        } action: { _, newValue in
            let shouldHide = newValue > 80
            if shouldHide != barHidden {
                barHidden = shouldHide
                onBarVisibilityChange?(!shouldHide)
            }
        }
    }

    // MARK: - Expanded Hero

    private func expandedHero(for item: Item, dismiss: (() -> Void)?) -> some View {
        Group {
            if let firstPath = item.imagePaths.first,
               let url = DatabaseService.imageURL(for: firstPath),
               let data = try? Data(contentsOf: url),
               let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        Text(item.emoji ?? "📦")
                            .font(.system(size: 64))
                    }
            }
        }
        .overlay {
            if let dismiss {
                Rectangle()
                    .foregroundStyle(.clear)
                    .contentShape(.rect)
                    .onTapGesture { dismiss() }
                    .transition(.identity)
            }
        }
    }

    // MARK: - Detail Content

    private func detailContent(for item: Item, safeArea: EdgeInsets, dismiss: @escaping () -> Void) -> some View {
        ItemDetailContent(
            item: item,
            safeArea: safeArea,
            dismiss: dismiss,
            onUpdate: { loadItems(); onDataChanged?() },
            onNavigateToMap: { [onNavigateToMap] in
                onNavigateToMap?(item)
            }
        )
    }

    // MARK: - Empty State

    private var emptyView: some View {
        ContentUnavailableView {
            Label("暂无物品", systemImage: "tray")
        } description: {
            Text("拍照记录你的第一个物品")
        }
    }

    // MARK: - Data

    private func loadItems() {
        do {
            items = try dbService.fetchAll()
        } catch {
            print("[ItemListView] 加载失败: \(error)")
        }
    }

    private func deleteItem(_ item: Item) {
        guard let id = item.id else { return }

        DatabaseService.deleteImages(at: item.imagePaths)

        do {
            try dbService.delete(id: id)
            items.removeAll { $0.id == id }
            onDataChanged?()
        } catch {
            print("[ItemListView] 删除失败: \(error)")
        }
    }
}

// MARK: - ItemDetailContent

private struct ItemDetailContent: View {
    let item: Item
    let safeArea: EdgeInsets
    var dismiss: () -> Void
    var onUpdate: () -> Void
    var onNavigateToMap: (() -> Void)?

    @State private var selectedEmoji: String
    @State private var descriptionExpanded = false
    @State private var sceneExpanded = false
    @State private var locationName: String?

    // 系统 emoji 键盘（通过 UIViewRepresentable 强制切 emoji）
    @State private var emojiFieldFocused = false

    init(item: Item, safeArea: EdgeInsets,
         dismiss: @escaping () -> Void,
         onUpdate: @escaping () -> Void,
         onNavigateToMap: (() -> Void)? = nil) {
        self.item = item
        self.safeArea = safeArea
        self.dismiss = dismiss
        self.onUpdate = onUpdate
        self.onNavigateToMap = onNavigateToMap
        _selectedEmoji = State(initialValue: item.emoji ?? "📦")
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection
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
        .safeAreaPadding(safeArea)
        .contentShape(.rect)
        .onTapGesture { dismiss() }
        .task { await geocodeLocation() }
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
        // AI 生成的极简位置标签（2-6字），如"家里客厅"
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
        // 主图已在顶部展示，这里只放其余照片
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
                    dismiss()
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
                Text("编辑")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
            .background(.quaternary, in: Capsule())

            Button {
                handleDelete()
            } label: {
                Text("删除")
                    .font(.headline)
                    .foregroundStyle(.red)
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
        dismiss()
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
private final class UIEmojiTextField: UITextField {

    override var textInputContextIdentifier: String? { "" }

    override var textInputMode: UITextInputMode? {
        for mode in UITextInputMode.activeInputModes where mode.primaryLanguage == "emoji" {
            return mode
        }
        return super.textInputMode
    }
}

/// UIViewRepresentable 桥接：点击后自动弹出 emoji 键盘，选完一个 emoji 即收起
private struct EmojiCaptureField: UIViewRepresentable {
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
            // 只取用户输入的第一个字符作为 emoji
            if !string.isEmpty, let char = string.last {
                parent.onEmojiSelected(String(char))
            }
            parent.isFocused = false
            return false
        }
    }
}
