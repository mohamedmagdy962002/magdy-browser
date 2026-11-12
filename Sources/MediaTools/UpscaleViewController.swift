import UIKit

/// Re-encodes a downloaded video at 2x or 4x resolution.
final class UpscaleViewController: UIViewController {

    private let url: URL
    private let scaleControl = UISegmentedControl(items: ["2x", "4x"])
    private let progressView = UIProgressView(progressViewStyle: .default)
    private let statusLabel = UILabel()
    private let startButton = UIButton(type: .system)

    init(url: URL) {
        self.url = url
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Upscale"
        view.backgroundColor = .systemBackground
        buildUI()
    }

    private func buildUI() {
        let nameLabel = UILabel()
        nameLabel.text = url.lastPathComponent
        nameLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        nameLabel.numberOfLines = 2

        let subtitle = UILabel()
        subtitle.text = "Re-encode with a Lanczos resample. Output lands in Downloads."
        subtitle.font = .systemFont(ofSize: 14)
        subtitle.textColor = .secondaryLabel
        subtitle.numberOfLines = 0

        scaleControl.selectedSegmentIndex = 0

        statusLabel.text = "Ready"
        statusLabel.font = .systemFont(ofSize: 15)
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 0

        startButton.setTitle("Start upscaling", for: .normal)
        startButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        startButton.addTarget(self, action: #selector(start), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [
            nameLabel, subtitle, scaleControl, startButton, progressView, statusLabel
        ])
        stack.axis = .vertical
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])
    }

    @objc private func start() {
        let factor = scaleControl.selectedSegmentIndex == 0 ? 2.0 : 4.0
        let base = url.deletingPathExtension().lastPathComponent
        let destination = DownloadManager.shared.directory
            .appendingPathComponent("\(base)_upscaled\(factor)x.mp4")

        startButton.isEnabled = false
        statusLabel.text = "Upscaling…"
        progressView.progress = 0

        VideoUpscaler.upscale(
            source: url,
            destination: destination,
            scale: factor,
            progress: { [weak self] value in
                DispatchQueue.main.async { self?.progressView.progress = Float(value) }
            },
            completion: { [weak self] result in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.startButton.isEnabled = true
                    switch result {
                    case .success(let output):
                        self.progressView.progress = 1
                        self.statusLabel.text = "Saved \(output.lastPathComponent)"
                    case .failure(let error):
                        self.statusLabel.text = "Failed: \(error.localizedDescription)"
                    }
                }
            }
        )
    }
}
