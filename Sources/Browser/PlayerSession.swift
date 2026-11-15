import AVFoundation
import UIKit

/// Keeps an AVPlayer alive after the fullscreen player is dismissed so audio
/// keeps playing, and shows the Aloha-style "Video is playing" mini banner.
final class PlayerSession {
    static let shared = PlayerSession()

    private(set) var player: AVPlayer?
    private(set) var url: URL?
    private(set) var title: String?
    private(set) var cookies: [HTTPCookie] = []

    static let bannerChanged = Notification.Name("magdyPlayerSessionChanged")

    func adopt(_ player: AVPlayer, url: URL, title: String, cookies: [HTTPCookie]) {
        self.player = player
        self.url = url
        self.title = title
        self.cookies = cookies
        NotificationCenter.default.post(name: Self.bannerChanged, object: nil)
    }

    var isPlaying: Bool {
        player?.timeControlStatus == .playing || player?.timeControlStatus == .waitingToPlayAtSpecifiedRate
    }

    func stop() {
        player?.pause()
        player = nil
        url = nil
        title = nil
        NotificationCenter.default.post(name: Self.bannerChanged, object: nil)
    }
}

/// Aloha reference #3: ✕ · waveform · "Video is playing" · download · expand.
final class PlayerSessionBanner: UIView {

    var onStop: (() -> Void)?
    var onDownload: (() -> Void)?
    var onExpand: (() -> Void)?

    private let downloadButton = UIButton(type: .system)

    init() {
        super.init(frame: .zero)
        backgroundColor = Theme.card
        layer.cornerRadius = 14
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = Theme.hairline.cgColor
        Theme.cardShadow(self)
        isHidden = true

        let close = UIButton(type: .system, primaryAction: UIAction { [weak self] _ in self?.onStop?() })
        close.setImage(UIImage(systemName: "xmark"), for: .normal)
        close.tintColor = Theme.textSecondary

        let wave = UIImageView(image: UIImage(systemName: "waveform"))
        wave.tintColor = Theme.primary
        wave.contentMode = .scaleAspectFit

        let label = UILabel()
        label.text = "Video is playing"
        label.font = Theme.headline(14, weight: .semibold)
        label.textColor = Theme.textPrimary

        downloadButton.setImage(UIImage(systemName: "arrow.down.circle"), for: .normal)
        downloadButton.tintColor = Theme.textPrimary
        downloadButton.addTarget(self, action: #selector(downloadTapped), for: .touchUpInside)

        let expand = UIButton(type: .system, primaryAction: UIAction { [weak self] _ in self?.onExpand?() })
        expand.setImage(UIImage(systemName: "arrow.up.left.and.arrow.down.right"), for: .normal)
        expand.tintColor = Theme.textPrimary

        let row = UIStackView(arrangedSubviews: [close, wave, label, downloadButton, expand])
        row.axis = .horizontal
        row.spacing = 10
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            wave.widthAnchor.constraint(equalToConstant: 22),
            close.widthAnchor.constraint(equalToConstant: 26),
            downloadButton.widthAnchor.constraint(equalToConstant: 28),
            expand.widthAnchor.constraint(equalToConstant: 28)
        ])
        refreshDownloadBadge()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func refreshDownloadBadge() {
        guard let url = PlayerSession.shared.url else {
            downloadButton.tintColor = Theme.textPrimary
            return
        }
        let item = DownloadManager.shared.items.first {
            $0.sourceURL?.absoluteString == url.absoluteString
        }
        switch item?.state {
        case .running:
            let percent = Int((item?.progress ?? 0) * 100)
            downloadButton.tintColor = Theme.primary
            downloadButton.accessibilityValue = percent > 0 ? "\(percent)%" : "downloading"
        case .finished:
            downloadButton.tintColor = UIColor(hex: 0x30D158)
        case .failed, .cancelled, .paused:
            downloadButton.tintColor = UIColor(hex: 0xFF9F0A)
        default:
            downloadButton.tintColor = Theme.textPrimary
        }
    }

    @objc private func downloadTapped() {
        onDownload?()
    }
}
