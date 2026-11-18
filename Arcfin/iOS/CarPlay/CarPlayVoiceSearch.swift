// SPDX-License-Identifier: AGPL-3.0-or-later

import AVFoundation
import CarPlay
import os
import Speech
import UIKit
import Telemetry

/// Search by Voice in the car: CarPlay's listening screen while the phone's speech recognizer
/// hears what to look for, then the results. Music pauses while it listens and carries on after.
@MainActor
final class CarPlayVoiceSearch {
    private static let log = Telemetry.logger(category: "CarPlayVoice")
    private let template: CPVoiceControlTemplate
    private let capture = SpeechCapture()
    private var resumesMusic = false
    private var isListening = false
    private var heard = ""
    private var finish: Task<Void, Never>?
    private weak var interface: CPInterfaceController?
    private let found: @MainActor (String) async -> Void

    init(found: @escaping @MainActor (String) async -> Void) {
        self.found = found
        let listening = CPVoiceControlState(identifier: "listening", titleVariants: [String(localized: "Listening…")],
                                            image: UIImage(systemName: "mic.fill"), repeats: true)
        let searching = CPVoiceControlState(identifier: "searching", titleVariants: [String(localized: "Searching…")],
                                            image: UIImage(systemName: "magnifyingglass"), repeats: true)
        template = CPVoiceControlTemplate(voiceControlStates: [listening, searching])
        if #available(iOS 26.4, *) {
            let cancel = CPButton(image: UIImage(systemName: "xmark") ?? UIImage()) { [weak self] _ in self?.stop(search: false) }
            cancel.title = String(localized: "Cancel")
            listening.actionButtons = [cancel]
        }
    }

    func start(in interface: CPInterfaceController?) {
        self.interface = interface
        Task { [weak self] in
            guard let self else { return }
            guard await Self.allowed() else {
                showAlert(String(localized: "Allow the microphone and speech recognition for Arcfin on your iPhone"))
                return
            }
            heard = ""
            resumesMusic = AppServices.music.isPlaying
            if resumesMusic { AppServices.music.pause() }
            // The microphone first: the listening screen only goes up once it's really listening.
            let capture = capture
            let deliver = Self.deliver(to: self)
            let started: Error? = await Task.detached {
                do {
                    try capture.start(deliver)
                    return nil
                } catch {
                    return error
                }
            }.value
            if let started {
                // iOS doesn't let an app start the microphone from the background, which is
                // where Arcfin usually is in the car: Siri is the way to ask then.
                let state = UIApplication.shared.applicationState
                Self.log.error("Voice search couldn't listen (app \(state == .active ? "open" : "in the background", privacy: .public)): \(started.localizedDescription, privacy: .public)")
                if resumesMusic { AppServices.music.resume() }
                showAlert(String(localized: "Voice search needs Arcfin open on your iPhone. You can also ask Siri: “Play … in Arcfin”."))
                return
            }
            isListening = true
            interface?.presentTemplate(template, animated: true, completion: nil)
            template.activateVoiceControlState(withIdentifier: "listening")
            // Nothing said at all: give up after a while.
            schedule(after: .seconds(8))
        }
    }

    /// What's heard, back on the main actor. Held only while listening: stopping lets go of it.
    private static func deliver(to search: CarPlayVoiceSearch) -> @Sendable (String, Bool) -> Void {
        { text, isFinal in
            Task { @MainActor in search.heard(text, isFinal: isFinal) }
        }
    }

    /// Each word heard pushes the end back; a short pause after speaking ends it.
    private func heard(_ text: String, isFinal: Bool) {
        if !text.isEmpty { heard = text }
        if isFinal { stop(search: true) } else { schedule(after: .milliseconds(1500)) }
    }

    private func schedule(after delay: Duration) {
        finish?.cancel()
        finish = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.stop(search: true)
        }
    }

    private func stop(search: Bool) {
        finish?.cancel()
        finish = nil
        guard isListening else { return }
        isListening = false
        let capture = capture
        let term = heard.trimmingCharacters(in: .whitespaces)
        Self.log.notice("Voice search heard \(term, privacy: .public)")
        let searches = search && !term.isEmpty
        if searches { template.activateVoiceControlState(withIdentifier: "searching") }
        Task {
            // The audio session blocks, so it's put back off the main actor, before music plays.
            await Task.detached { capture.stop() }.value
            if searches { await found(term) }
            interface?.dismissTemplate(animated: true, completion: nil)
            if resumesMusic { AppServices.music.resume() }
        }
    }

    private func showAlert(_ message: String) {
        let alert = CPAlertTemplate(titleVariants: [message], actions: [
            CPAlertAction(title: String(localized: "OK"), style: .cancel) { [weak self] _ in
                self?.interface?.dismissTemplate(animated: true, completion: nil)
            },
        ])
        interface?.presentTemplate(alert, animated: true, completion: nil)
    }

    /// Asks on the phone the first time; the car can't show the question.
    private static func allowed() async -> Bool {
        let speech: Bool = switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: true
        case .notDetermined: await withCheckedContinuation { done in
            SFSpeechRecognizer.requestAuthorization { done.resume(returning: $0 == .authorized) }
        }
        default: false
        }
        guard speech else { return false }
        return switch AVAudioApplication.shared.recordPermission {
        case .granted: true
        case .undetermined: await AVAudioApplication.requestRecordPermission()
        default: false
        }
    }
}

/// The microphone into the speech recognizer, off the main actor: the audio arrives on its own
/// thread.
nonisolated private final class SpeechCapture: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private(set) var isRunning = false

    func start(_ onText: @escaping @Sendable (String, Bool) -> Void) throws {
        guard let recognizer, recognizer.isAvailable else { throw URLError(.notConnectedToInternet) }
        let session = AVAudioSession.sharedInstance()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .search
        do {
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .allowBluetoothHFP])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let input = engine.inputNode
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
                request.append(buffer)
            }
            engine.prepare()
            try engine.start()
        } catch {
            // Back to how music had it.
            engine.inputNode.removeTap(onBus: 0)
            try? session.setCategory(.playback, mode: .default, policy: .longFormAudio)
            throw error
        }
        self.request = request
        isRunning = true
        task = recognizer.recognitionTask(with: request) { result, error in
            if let result { onText(result.bestTranscription.formattedString, result.isFinal) }
            else if error != nil { onText("", true) }
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        // Back to playing music the usual way.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, policy: .longFormAudio)
    }
}
