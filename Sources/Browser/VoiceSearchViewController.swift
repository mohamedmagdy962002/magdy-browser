import Speech
import UIKit

/// Voice search: speech-to-text, then the recognised query goes to the omnibox flow.
final class VoiceSearchViewController: UIViewController {

    var onText: ((String) -> Void)?

    private let speech = SFSpeechRecognizer()
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let statusLabel = UILabel()
    private let resultLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.canvas
        title = "Voice Search"

        statusLabel.text = "Tap to speak"
        statusLabel.font = Theme.body(15)
        statusLabel.textColor = Theme.textSecondary
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        resultLabel.text = ""
        resultLabel.font = Theme.headline(22)
        resultLabel.textColor = Theme.textPrimary
        resultLabel.textAlignment = .center
        resultLabel.numberOfLines = 3
        resultLabel.translatesAutoresizingMaskIntoConstraints = false

        let micButton = UIButton(type: .system)
        micButton.setImage(UIImage(systemName: "mic.fill"), for: .normal)
        micButton.tintColor = .white
        micButton.backgroundColor = Theme.primary
        micButton.layer.cornerRadius = 38
        micButton.addTarget(self, action: #selector(micTapped), for: .touchUpInside)
        micButton.translatesAutoresizingMaskIntoConstraints = false

        let closeButton = UIBarButtonItem(
            barButtonSystemItem: .done, target: self, action: #selector(closeTapped)
        )
        navigationItem.rightBarButtonItem = closeButton

        view.addSubview(statusLabel)
        view.addSubview(resultLabel)
        view.addSubview(micButton)
        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 60),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            resultLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            resultLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            resultLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            micButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -60),
            micButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            micButton.widthAnchor.constraint(equalToConstant: 76),
            micButton.heightAnchor.constraint(equalToConstant: 76)
        ])
    }

    @objc private func closeTapped() {
        stopListening()
        dismiss(animated: true)
    }

    @objc private func micTapped() {
        if task != nil {
            stopListening()
            finish()
            return
        }
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                if status == .authorized {
                    self?.startListening()
                } else {
                    self?.statusLabel.text = "Speech permission denied — enable it in Settings"
                }
            }
        }
    }

    private func startListening() {
        statusLabel.text = "Listening…"
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            statusLabel.text = "Microphone unavailable"
            return
        }

        let input = audioEngine.inputNode
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request

        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
            request.append(buffer)
        }
        do {
            try audioEngine.start()
        } catch {
            stopListening()
            statusLabel.text = "Could not start the microphone"
            return
        }
        audioEngine.prepare()

        task = speech?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result, !result.bestTranscription.formattedString.isEmpty {
                self.resultLabel.text = result.bestTranscription.formattedString
            }
            if let result, result.isFinal, !result.bestTranscription.formattedString.isEmpty {
                self.onText?(result.bestTranscription.formattedString)
                self.stopListening()
                self.dismiss(animated: true)
                return
            }
            if error != nil, self.task != nil {
                self.stopListening()
                self.statusLabel.text = "Try again"
            }
        }
    }

    private func finish() {
        request?.endAudio()
        // The user tapped to stop: hand over whatever was transcribed so far.
        if let text = resultLabel.text, !text.isEmpty {
            onText?(text)
            stopListening()
            dismiss(animated: true)
            return
        }
        statusLabel.text = "Tap to speak"
    }

    private func stopListening() {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        statusLabel.text = "Tap to speak"
    }

    deinit {
        stopListening()
    }
}
