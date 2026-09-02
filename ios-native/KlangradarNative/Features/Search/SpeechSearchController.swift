import AVFoundation
import Speech
import SwiftUI

@MainActor
final class SpeechSearchController: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var errorMessage: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale.current)
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var hasInstalledTap = false
    // Zwischen Antippen und `isRecording = true` liegen zwei `await`-Punkte
    // (Spracherkennungs- und Mikrofon-Berechtigung) — ein zweiter Tap in
    // diesem Fenster rief bislang `start()` ein zweites Mal parallel auf und
    // installierte einen zweiten Tap auf demselben Bus. AVAudioEngine wirft
    // dafür KEINEN Swift-Error, sondern eine Objective-C-Exception
    // ("required condition is false") — das `do/catch` unten fängt das
    // nicht ab, die App stürzt hart ab. Dieser Guard verhindert die
    // Überlappung von Anfang an.
    private var isStarting = false

    func toggle(into query: Binding<String>) async {
        if isRecording { stop() } else { await start(into: query) }
    }

    private func start(into query: Binding<String>) async {
        guard !isStarting, !isRecording else { return }
        isStarting = true
        defer { isStarting = false }
        errorMessage = nil
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Die Spracherkennung ist momentan nicht verfügbar."
            return
        }
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speechStatus == .authorized else {
            errorMessage = "Bitte erlaube Klangradar die Spracherkennung in den iPhone-Einstellungen."
            return
        }
        let microphoneAllowed: Bool
        if #available(iOS 17.0, *) {
            microphoneAllowed = await AVAudioApplication.requestRecordPermission()
        } else {
            microphoneAllowed = await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
            }
        }
        guard microphoneAllowed else {
            errorMessage = "Bitte erlaube Klangradar den Mikrofonzugriff in den iPhone-Einstellungen."
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            recognitionRequest = request
            let input = audioEngine.inputNode
            // Defensiv: falls durch einen früheren Fehlerpfad noch ein Tap
            // hängt, würde installTap() sonst hart abstürzen statt zu werfen.
            if hasInstalledTap {
                input.removeTap(onBus: 0)
                hasInstalledTap = false
            }
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw SpeechSearchError.invalidAudioFormat
            }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
            hasInstalledTap = true
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    if let result { query.wrappedValue = result.bestTranscription.formattedString }
                    if error != nil || result?.isFinal == true { self?.stop() }
                }
            }
        } catch {
            errorMessage = "Die Aufnahme konnte nicht gestartet werden."
            stop()
        }
    }

    func stop() {
        guard isRecording || recognitionRequest != nil else { return }
        audioEngine.stop()
        if hasInstalledTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInstalledTap = false
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func dismissError() { errorMessage = nil }
}

private enum SpeechSearchError: Error {
    case invalidAudioFormat
}
