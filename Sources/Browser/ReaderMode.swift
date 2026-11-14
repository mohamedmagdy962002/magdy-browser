import UIKit
import AVFoundation
import WebKit

/// Extracts the readable article text from a page and renders it without clutter.
enum ReaderMode {

    struct Article {
        let title: String
        let paragraphs: [String]
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
      if (!root) return JSON.stringify({ title: document.title, paragraphs: [] });

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
      return JSON.stringify({ title: (document.title || '').trim(), paragraphs: paragraphs });
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
            completion(.success(Article(title: decoded.title, paragraphs: decoded.paragraphs)))
        }
    }

    private struct Payload: Decodable {
        let title: String
        let paragraphs: [String]
    }
}

/// Full-screen reader view with read-aloud and save-to-reading-list.
final class ReaderViewController: UIViewController {
    private let article: ReaderMode.Article
    private let textView = UITextView()
    private let synthesizer = AVSpeechSynthesizer()
    private var isSpeaking = false

    init(article: ReaderMode.Article) {
        self.article = article
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let speak = UIBarButtonItem(
            image: UIImage(systemName: "speaker.wave.2"), style: .plain, target: self, action: #selector(toggleSpeaking)
        )
        let save = UIBarButtonItem(
            image: UIImage(systemName: "book"), style: .plain, target: self, action: #selector(saveToReadingList)
        )
        let done = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(closeTapped))
        navigationItem.rightBarButtonItems = [done, save, speak]
        synthesizer.delegate = self

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

    @objc private func closeTapped() {
        synthesizer.stopSpeaking(at: .immediate)
        dismiss(animated: true)
    }

    @objc private func toggleSpeaking() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
            isSpeaking = false
            navigationItem.rightBarButtonItems?.first?.image = UIImage(systemName: "speaker.wave.2")
            return
        }
        let text = article.paragraphs.joined(separator: ". ")
        let utterance = AVSpeechUtterance(string: article.title + ". " + text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
        isSpeaking = true
        navigationItem.rightBarButtonItems?.first?.image = UIImage(systemName: "speaker.slash")
    }

    @objc private func saveToReadingList() {
        ReadingListStore.shared.add(title: article.title, url: "", paragraphs: article.paragraphs)
        let alert = UIAlertController(title: nil, message: "Saved to Reading List", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L.t("done"), style: .default))
        present(alert, animated: true)
    }
}

extension ReaderViewController: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        isSpeaking = false
        navigationItem.rightBarButtonItems?.first?.image = UIImage(systemName: "speaker.wave.2")
    }
}
