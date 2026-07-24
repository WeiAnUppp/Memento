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

    var body: some View {
        Group {
            if isSearching {
                searchingState
            } else if let error = searchError {
                errorState(error)
            } else if hasSearched && results.isEmpty {
                noResultsState
            } else if !results.isEmpty {
                resultsList
            } else {
                emptyState
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView(
            "搜索物品",
            systemImage: "magnifyingglass",
            description: Text("随心问，我会帮你找到它\n比如「黑色的钥匙」「昨天放的那个」「键盘旁边的」\n「用来充电的」「卧室里最大的盒子」")
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
        VStack(spacing: 0) {
            // TTS 播报栏
            if let suggestion = suggestionText, !suggestion.isEmpty {
                ttsBar(text: suggestion)
            }

            // 结果列表：高置信直接展示，弱相关折叠进"可能相关"
            List {
                ForEach(strongResults) { result in
                    resultRow(result)
                }

                if !weakResults.isEmpty {
                    Section {
                        if showWeakResults {
                            ForEach(weakResults) { result in
                                resultRow(result)
                            }
                        }
                    } header: {
                        weakSectionHeader
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func resultRow(_ result: SearchResult) -> some View {
        Button {
            onResultSelected(result.item)
        } label: {
            SearchResultCard(result: result)
        }
        .buttonStyle(.plain)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
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
        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 4, trailing: 16))
    }

    // MARK: - TTS Bar

    private func ttsBar(text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(.blue)
                .font(.subheadline)

            Text(text)
                .font(.subheadline)
                .lineLimit(1)

            Spacer()

            Button {
                ttsSpeaker.stopSpeaking(at: .immediate)
                speak(text)
            } label: {
                Image(systemName: "speaker.wave.2")
                    .font(.title3)
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = 0.5
        ttsSpeaker.speak(utterance)
    }
}

// MARK: - Search Result Card

/// 搜索结果卡片：缩略图 + 名称/描述 + 匹配标签 + 场景·时间 + 匹配度
struct SearchResultCard: View {
    let result: SearchResult
    let item: Item

    init(result: SearchResult) {
        self.result = result
        self.item = result.item
    }

    var body: some View {
        HStack(spacing: 14) {
            // 左侧：缩略图
            thumbnailView

            // 中间：名称 + 描述 + 匹配标签 + 场景·时间
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.headline)
                    .lineLimit(1)

                Text(item.itemDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                // 匹配原因标签行
                matchReasonTags

                locationAndDate
            }

            Spacer()

            // 右侧：匹配度
            scoreBadge
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.quaternary, lineWidth: 0.5)
        )
    }

    // MARK: - Match Reason Tags

    @ViewBuilder
    private var matchReasonTags: some View {
        if let details = result.matchDetails {
            HStack(spacing: 6) {
                // 名称命中 → 蓝色标签
                if details.nameMatched {
                    matchChip("名称匹配", color: .blue)
                }

                // 其他命中字段
                ForEach(otherMatchChips(from: details), id: \.self) { label in
                    matchChip(label, color: .secondary)
                }

                // 时间标签 → 橙色
                if let timeLabel = details.timeRelevance {
                    matchChip(timeLabel, color: .orange)
                }

                // 位置距离 → 绿色
                if let dist = details.locationDistance {
                    matchChip(formatDistance(dist), color: .green)
                }
            }
        }
    }

    private func matchChip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(color.opacity(0.10))
            )
    }

    private func fieldLabel(_ field: String) -> String {
        switch field {
        case "description": return "特征匹配"
        case "keywords": return "关键词"
        case "scene": return "场景匹配"
        case "userNote": return "备注"
        default: return ""
        }
    }

    private func otherMatchChips(from details: SearchResult.MatchDetails) -> [String] {
        details.matchedFields
            .filter { $0 != "name" }
            .prefix(2)
            .compactMap { fieldLabel($0) }
            .filter { !$0.isEmpty }
    }

    private func formatDistance(_ km: Double) -> String {
        if km < 1 { return "<1km" }
        if km < 10 { return String(format: "%.1fkm", km) }
        return String(format: "%.0fkm", km)
    }

    // MARK: - Thumbnail

    @ViewBuilder
    private var thumbnailView: some View {
        let paths = item.imagePaths
        if let firstPath = paths.first,
           let url = DatabaseService.imageURL(for: firstPath),
           let data = try? Data(contentsOf: url),
           let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(.quaternary)
                .frame(width: 64, height: 64)
                .overlay {
                    Text(item.emoji ?? "📦")
                        .font(.system(size: 28))
                }
        }
    }

    // MARK: - Location & Date

    private var locationAndDate: some View {
        HStack(spacing: 4) {
            if let scene = item.scene, !scene.isEmpty {
                Text(scene)
            }
            if item.scene?.isEmpty == false {
                Text("·")
                    .foregroundStyle(.tertiary)
            }
            Text(item.createdAt.friendlyChineseFormat)
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    // MARK: - Score Badge

    @ViewBuilder
    private var scoreBadge: some View {
        if result.isBrowse {
            // 浏览模式是"列举"，不是"匹配"，展示时间标签而非误导性的百分比
            let label = result.matchDetails?.timeRelevance ?? "浏览"
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.12))
                )
        } else {
            let pct = Int(result.score * 100)
            let color: Color = {
                if result.score >= 0.7 { return .green }
                if result.score >= 0.4 { return .orange }
                return .secondary
            }()

            Text("\(pct)%")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(color.opacity(0.12))
                )
        }
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
