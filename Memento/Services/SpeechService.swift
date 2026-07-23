//
//  SpeechService.swift
//  Memento
//
//  Created by WeiAnUppp on 2026/7/21.
//

import Foundation
import Speech
import AVFoundation

// MARK: - Speech Service

@Observable
final class SpeechService: NSObject, SFSpeechRecognizerDelegate {
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    var isRecording = false
    var transcript: String = ""
    var isAuthorized = false
    var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined

    override init() {
        super.init()
        speechRecognizer?.delegate = self
    }

    // MARK: - Authorization

    func requestAuthorization() async {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        await setAuthStatus(status)
    }

    @MainActor
    private func setAuthStatus(_ status: SFSpeechRecognizerAuthorizationStatus) {
        authorizationStatus = status
        isAuthorized = status == .authorized
    }

    // MARK: - Recording

    @MainActor
    func startRecording() throws {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw SpeechError.notAuthorized
        }

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else {
            throw SpeechError.requestFailed
        }
        recognitionRequest.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        isRecording = true
        transcript = ""

        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }

            // ⚠️ SFSpeechRecognizer 回调在后台线程，必须在主线程更新 @Observable 属性
            let text = result?.bestTranscription.formattedString ?? ""
            let isFinal = result?.isFinal ?? false

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                // 始终更新 transcript，即使 isRecording 已为 false（确保最终结果被捕获）
                if !text.isEmpty {
                    self.transcript = text
                }

                if error != nil || isFinal {
                    self.cleanupRecognition()
                }
            }
        }
    }

    func stopRecording() {
        // 停止音频引擎，发送结束信号
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        isRecording = false
        // 延迟清理 recognitionTask，给识别器时间交付最终结果
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.cleanupRecognition()
        }
    }

    private func cleanupRecognition() {
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
    }

    // MARK: - Clean Transcript

    /// 过滤语气词后的转录结果
    var cleanedTranscript: String {
        Self.removeFillerWords(transcript)
    }

    /// 移除中文常见语气词和填充词
    static func removeFillerWords(_ text: String) -> String {
        var result = text

        // 长短语优先匹配，避免"那个什么"被拆成"那个"+"什么"
        let phraseFillers: [String] = [
            "就是说呢", "就是说", "那个什么", "这个什么",
            "对不对", "对吧", "是吧", "那啥",
            "什么的", "反正", "然后呢",
        ]

        for phrase in phraseFillers {
            result = result.replacingOccurrences(of: phrase, with: "")
        }

        // 短填充词（按长度降序，避免短词先匹配破坏长词）
        let wordFillers: [String] = [
            "然后", "这个", "那个", "就是",
            "嗯", "啊", "哦", "呃", "唔", "诶", "哎",
            "哈", "呀", "呐", "嘛", "吧", "呢",
        ]

        for word in wordFillers {
            result = result.replacingOccurrences(of: word, with: "")
        }

        // 清理多余空格和标点残留
        result = result.replacingOccurrences(of: "，,", with: "，")
            .replacingOccurrences(of: "，，", with: "，")
            .replacingOccurrences(of: " 。", with: "。")
            .replacingOccurrences(of: "。。", with: "。")

        // 合并连续空格
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }

        // 去掉首尾空格和标点残留
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        let punctuationToTrim = CharacterSet(charactersIn: "\u{201C}\u{201D}\u{FF0C}\u{3002}\u{3001}\u{FF01}\u{FF1F}\u{FF1B}\u{FF1A}\u{2018}\u{2019}\u{2026}\u{2014}\u{00B7}")
        result = result.trimmingCharacters(in: punctuationToTrim)
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        return result
    }

    // MARK: - SFSpeechRecognizerDelegate

    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {}
}

// MARK: - Speech Error

enum SpeechError: LocalizedError {
    case notAuthorized
    case recognizerUnavailable
    case requestFailed

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "语音识别权限未授权，请在设置中开启"
        case .recognizerUnavailable:
            return "语音识别当前不可用"
        case .requestFailed:
            return "语音识别请求失败"
        }
    }
}
