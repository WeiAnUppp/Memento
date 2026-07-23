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
                guard let self, self.isRecording else { return }
                self.transcript = text

                if error != nil || isFinal {
                    self.stopRecording()
                }
            }
        }
    }

    func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isRecording = false
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
