//
//  SearchResultView.swift
//  Memento
//
//  Created by WeiAnUppp on 2026/7/21.
//

import SwiftUI
import AVFoundation

// MARK: - Search Result View

/// 搜索结果列表，处理空态 / 搜索中 / 结果 / 无结果 / 错误等状态
struct SearchResultView: View {
    let results: [SearchResult]
    let isSearching: Bool
    let hasSearched: Bool
    let searchError: String?
    let suggestionText: String?
    let onResultSelected: (Item) -> Void
    let onRetry: () -> Void

    @State private var ttsSpeaker = AVSpeechSynthesizer()
    @State private var displayedCharCount = 0
    @State private var typewriterTimer: Timer?

    var body: some View {
        Group {
            if isSearching {
                searchingState
            } else if searchError != nil {
                emptyState
            } else if hasSearched && results.isEmpty {
                noResultsState
            } else if !results.isEmpty {
                resultsList
            } else {
                emptyState
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .onAppear {
            if let text = suggestionText, !text.isEmpty {
                displayedCharCount = text.count
            }
        }
        .onChange(of: suggestionText) { _, newText in
            startTypewriter(for: newText)
        }
        .onDisappear {
            typewriterTimer?.invalidate()
            ttsSpeaker.stopSpeaking(at: .immediate)
        }
    }

    // MARK: - Typewriter

    private func startTypewriter(for text: String?) {
        typewriterTimer?.invalidate()
        ttsSpeaker.stopSpeaking(at: .immediate)
        displayedCharCount = 0
        guard let text, !text.isEmpty else { return }

        let total = text.count
        let interval = 0.04
        var i = 0
        typewriterTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { timer in
            i += 1
            displayedCharCount = min(i, total)
            if i >= total {
                timer.invalidate()
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView(
            "搜索物品",
            systemImage: "magnifyingglass",
            description: Text("随心问，我会帮你找到它。")
        )
    }

    // MARK: - Searching

    private var searchingState: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
            Text("正在理解你的描述…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("AI 分析查询 + 本地检索中")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - No Results

    private var noResultsState: some View {
        ContentUnavailableView {
            Label("未找到相关物品", systemImage: "questionmark.circle")
        } description: {
            Text("试试这些方法：\n• 用更简短的关键词（如「手机」而非「我前天用的那个手机」）\n• 描述颜色、形状或位置\n• 检查时间范围是否太窄")
        } actions: {
            Button("清空重试") {
                onRetry()
            }
            .buttonStyle(.glassProminent)
            .tint(.blue)
            .controlSize(.small)
        }
    }

    // MARK: - Error

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.orange)

            Text("搜索出错")
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button("重试") {
                onRetry()
            }
            .buttonStyle(.glassProminent)
            .tint(.blue)
            .controlSize(.small)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Results List

    @State private var showWeakResults = false

    private var strongResults: [SearchResult] { results.filter { $0.isStrong } }
    private var weakResults: [SearchResult] { results.filter { !$0.isStrong } }

    private var resultsList: some View {
        ScrollView {
            VStack(spacing: 0) {
                // AI 总结卡片（打字效果 + 自适应高度）
                if let suggestion = suggestionText, !suggestion.isEmpty {
                    aiSummaryCard(text: suggestion)
                        .padding(.bottom, 20)
                }

                // 结果网格：双列卡片，和列表页样式完全一致
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 15),
                        GridItem(.flexible(), spacing: 15)
                    ],
                    spacing: 15
                ) {
                    ForEach(strongResults) { result in
                        resultCard(result)
                    }
                }
                .padding(.horizontal, 15)

                // 弱相关折叠区
                if !weakResults.isEmpty {
                    weakSectionHeader
                        .padding(.horizontal, 15)
                        .padding(.top, 24)

                    if showWeakResults {
                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: 15),
                                GridItem(.flexible(), spacing: 15)
                            ],
                            spacing: 15
                        ) {
                            ForEach(weakResults) { result in
                                resultCard(result)
                            }
                        }
                        .padding(.horizontal, 15)
                        .padding(.top, 4)
                    }
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
    }

    private func resultCard(_ result: SearchResult) -> some View {
        let item = result.item
        return AppStoreTransition(
            config: .init(cardCornerRadius: 16)
        ) { isExpanded, dismiss in
            if isExpanded {
                expandedHero(for: item, dismiss: dismiss)
            } else {
                ItemGridCard(item: item)
            }
        } content: { safeArea, dismiss in
            ItemDetailContent(
                item: item,
                safeArea: safeArea,
                dismiss: dismiss,
                onUpdate: {},
                onNavigateToMap: { [onResultSelected] in
                    onResultSelected(item)
                }
            )
        }
        .frame(height: 200)
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

    private var weakSectionHeader: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { showWeakResults.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: showWeakResults ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                Text("可能相关（\(weakResults.count)）")
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
                if !showWeakResults {
                    Text("置信度较低")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(.secondary)
            .textCase(nil)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 10)
    }

    // MARK: - AI Summary Card

    private func aiSummaryCard(text: String) -> some View {
        let prefix = String(text.prefix(displayedCharCount))
        let isTyping = displayedCharCount < text.count

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.blue)
                    .font(.subheadline)
                Text("AI 总结")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.blue)
                if isTyping {
                    Text("输入中…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                // 手动播报/停止
                Button {
                    if ttsSpeaker.isSpeaking {
                        ttsSpeaker.stopSpeaking(at: .immediate)
                    } else {
                        speak(text)
                    }
                } label: {
                    Image(systemName: ttsSpeaker.isSpeaking ? "stop.fill" : "speaker.wave.2")
                        .font(.title3)
                        .foregroundStyle(ttsSpeaker.isSpeaking ? .red : .blue)
                }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.15), value: ttsSpeaker.isSpeaking)
            }

            Text(prefix)
                .font(.body)
                .foregroundStyle(.primary)
                + (isTyping ? Text("|").foregroundStyle(.blue) : Text(""))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.blue.opacity(0.15), lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    private func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = 0.5
        ttsSpeaker.speak(utterance)
    }
}

// MARK: - Preview

#Preview {
    SearchResultView(
        results: [],
        isSearching: false,
        hasSearched: false,
        searchError: nil,
        suggestionText: nil,
        onResultSelected: { _ in },
        onRetry: {}
    )
}
