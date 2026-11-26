import UIKit
import AVFoundation
import WebKit

/// Extracts the readable article text from a page and renders it without clutter.
enum ReaderMode {

    struct Article {
        let title: String
        let paragraphs: [String]
        var url: String? = nil
    }

    enum ReaderError: LocalizedError {
        case nothingFound

        var errorDescription: String? {
            "No readable content found on this page."
        }
    }

    private static let extractionScript = """
    (function () {
      const clean = (node) => {
        node.querySelectorAll('script,style,nav,aside,header,footer,form,noscript,iframe').forEach(n => n.remove());
        return node;
      };
      const blocks = Array.from(document.querySelectorAll('article, main, [role="main"], section, div'));
      let best = null;
      let bestScore = 0;
      for (const block of blocks) {
        const text = (block.innerText || '').trim();
        if (text.length < 300) continue;
        const paragraphs = block.querySelectorAll('p').length;
        const links = block.querySelectorAll('a').length;
        const score = text.length + paragraphs * 120 - links * 40;
        if (score > bestScore) { bestScore = score; best = block; }
      }
      const root = best || document.body;
      if (!root) return JSON.stringify({ title: document.title, paragraphs: [], url: location.href });

      const seen = new Set();
      const paragraphs = [];
      root.querySelectorAll('p, h1, h2, h3, h4, li, blockquote, pre').forEach(el => {
        const text = (el.innerText || '').trim();
        if (text.length < 45) return;
        const key = text.slice(0, 80);
        if (seen.has(key)) return;
        seen.add(key);
        paragraphs.push(text);
      });
      return JSON.stringify({ title: (document.title || '').trim(), paragraphs: paragraphs, url: location.href });
    })();
    """

    static func extract(from webView: WKWebView, completion: @escaping (Result<Article, Error>) -> Void) {
        webView.evaluateJavaScript(extractionScript) { result, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let json = result as? String,
                  let data = json.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(Payload.self, from: data),
                  !decoded.paragraphs.isEmpty else {
                completion(.failure(ReaderError.nothingFound))
                return
            }
            completion(.success(Article(title: decoded.title, paragraphs: decoded.paragraphs, url: decoded.url)))
        }
    }

    private struct Payload: Decodable {
        let title: String
        let paragraphs: [String]
        let url: String?
    }
}

/// Full-screen reader view with read-aloud and save-to-reading-list.
final class ReaderViewController: UIViewController {
    private let article: ReaderMode.Article
    private let textView = UITextView()
    private let synthesizer = AVSpeechSynthesizer()
    private let speakButton = UIButton(type: .system)
    private let swipeDismissGesture = UIScreenEdgePanGestureRecognizer()
    private var isSpeaking = false
    private var ownsAudioSession = false

    init(article: ReaderMode.Article) {
        self.article = article
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        speakButton.setImage(UIImage(systemName: "speaker.wave.2"), for: .normal)
        speakButton.tintColor = .label
        speakButton.accessibilityLabel = "Read article aloud"
        speakButton.accessibilityHint = "Starts read-aloud"
        speakButton.addTarget(self, action: #selector(toggleSpeaking), for: .touchUpInside)
        speakButton.translatesAutoresizingMaskIntoConstraints = false

        let saveButton = UIButton(type: .system)
        saveButton.setImage(UIImage(systemName: "book"), for: .normal)
        saveButton.tintColor = .label
        saveButton.accessibilityLabel = "Save article"
        saveButton.accessibilityHint = "Saves this article to your reading list"
        saveButton.addTarget(self, action: #selector(saveToReadingList), for: .touchUpInside)
        saveButton.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            speakButton.widthAnchor.constraint(equalToConstant: 44),
            speakButton.heightAnchor.constraint(equalToConstant: 44),
            saveButton.widthAnchor.constraint(equalToConstant: 44),
            saveButton.heightAnchor.constraint(equalToConstant: 44)
        ])

        let speak = UIBarButtonItem(customView: speakButton)
        let save = UIBarButtonItem(customView: saveButton)
        let done = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(closeTapped))
        navigationItem.rightBarButtonItems = [done, save, speak]
        synthesizer.delegate = self

        swipeDismissGesture.edges = .left
        swipeDismissGesture.cancelsTouchesInView = true
        swipeDismissGesture.addTarget(self, action: #selector(swipeToDismiss(_:)))
        view.addGestureRecognizer(swipeDismissGesture)

        textView.isEditable = false
        textView.adjustsFontForContentSizeCategory = true
        textView.textContainerInset = UIEdgeInsets(top: 24, left: 20, bottom: 40, right: 20)
        textView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(textView)

        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        textView.attributedText = render()
    }

    private func render() -> NSAttributedString {
        let output = NSMutableAttributedString()
        let titleStyle = NSMutableParagraphStyle()
        titleStyle.paragraphSpacing = 18

        let title = NSMutableAttributedString(
            string: article.title.isEmpty ? L.t("reader_mode") : article.title + "\n\n",
            attributes: [
                .font: UIFont.systemFont(ofSize: 26, weight: .bold),
                .foregroundColor: UIColor.label,
                .paragraphStyle: titleStyle
            ]
        )
        output.append(title)

        let bodyStyle = NSMutableParagraphStyle()
        bodyStyle.lineSpacing = 7
        bodyStyle.paragraphSpacing = 14

        for paragraph in article.paragraphs {
            output.append(NSAttributedString(
                string: paragraph + "\n",
                attributes: [
                    .font: UIFont.systemFont(ofSize: 18),
                    .foregroundColor: UIColor.label,
                    .paragraphStyle: bodyStyle
                ]
            ))
        }
        return output
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopSpeechAndAudio()
    }

    @objc private func closeTapped() {
        stopSpeechAndAudio()
        view.transform = .identity
        dismiss(animated: true)
    }

    @objc private func swipeToDismiss(_ gesture: UIScreenEdgePanGestureRecognizer) {
        let translation = gesture.translation(in: view).x
        if gesture.state == .changed, translation > 0 {
            view.transform = CGAffineTransform(translationX: min(translation, view.bounds.width * 0.35), y: 0)
        } else if gesture.state == .ended {
            if translation > 80 || gesture.velocity(in: view).x > 500 {
                closeTapped()
            } else {
                UIView.animate(withDuration: 0.25) { self.view.transform = .identity }
            }
        } else if gesture.state == .cancelled || gesture.state == .failed {
            UIView.animate(withDuration: 0.25) { self.view.transform = .identity }
        }
    }

    private func stopSpeechAndAudio() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        if isViewLoaded {
            updateSpeechControl()
        }
        if ownsAudioSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            ownsAudioSession = false
        }
    }

    private func updateSpeechControl() {
        let symbol = isSpeaking ? "speaker.slash" : "speaker.wave.2"
        speakButton.setImage(UIImage(systemName: symbol), for: .normal)
        speakButton.accessibilityLabel = isSpeaking ? "Stop reading aloud" : "Read article aloud"
        speakButton.accessibilityHint = isSpeaking ? "Stops read-aloud" : "Starts read-aloud"
    }

    @objc private func toggleSpeaking() {
        if synthesizer.isSpeaking || isSpeaking {
            stopSpeechAndAudio()
            return
        }
        // Playback category keeps read-aloud audible with the mute switch on.
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
            ownsAudioSession = true
        } catch {
            return
        }
        let text = article.paragraphs.joined(separator: ". ")
        let utterance = AVSpeechUtterance(string: article.title + ". " + text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
        isSpeaking = true
        updateSpeechControl()
    }

    @objc private func saveToReadingList() {
        ReadingListStore.shared.add(title: article.title, url: article.url ?? "", paragraphs: article.paragraphs)
        let alert = UIAlertController(title: nil, message: "Saved to Reading List", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L.t("done"), style: .default))
        present(alert, animated: true)
    }

    deinit {
        stopSpeechAndAudio()
    }
}

extension ReaderViewController: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in self?.stopSpeechAndAudio() }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in self?.stopSpeechAndAudio() }
    }
}
