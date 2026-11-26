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

    private var timeControlObserver: NSKeyValueObservation?
    private var itemStatusObserver: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var failureObserver: NSObjectProtocol?

    func adopt(_ player: AVPlayer, url: URL, title: String, cookies: [HTTPCookie]) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.adopt(player, url: url, title: title, cookies: cookies) }
            return
        }
        removePlaybackObservers()
        if self.player !== player {
            self.player?.pause()
        }
        self.player = player
        self.url = url
        self.title = title
        self.cookies = cookies

        let item = player.currentItem
        timeControlObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] observedPlayer, _ in
            guard observedPlayer.timeControlStatus == .paused else { return }
            DispatchQueue.main.async {
                guard let self, self.player === observedPlayer else { return }
                self.stop()
            }
        }
        itemStatusObserver = item?.observe(\.status, options: [.new]) { [weak self] observedItem, _ in
            guard observedItem.status == .failed else { return }
            DispatchQueue.main.async {
                guard let self, self.player?.currentItem === observedItem else { return }
                self.stop()
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] notification in
            guard let self,
                  let item = notification.object as? AVPlayerItem,
                  self.player?.currentItem === item else { return }
            self.stop()
        }
        failureObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main
        ) { [weak self] notification in
            guard let self,
                  let item = notification.object as? AVPlayerItem,
                  self.player?.currentItem === item else { return }
            self.stop()
        }

        if item?.status == .failed || player.error != nil {
            stop()
            return
        }
        NotificationCenter.default.post(name: Self.bannerChanged, object: nil)
    }

    var isPlaying: Bool {
        guard let player, player.error == nil,
              let item = player.currentItem,
              item.error == nil, item.status == .readyToPlay else { return false }
        return player.timeControlStatus == .playing || player.timeControlStatus == .waitingToPlayAtSpecifiedRate
    }

    func stop() {
        stop(deactivateAudioSession: true)
    }

    func stop(deactivateAudioSession: Bool) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.stop(deactivateAudioSession: deactivateAudioSession) }
            return
        }
        removePlaybackObservers()
        player?.pause()
        player = nil
        url = nil
        title = nil
        cookies = []
        if deactivateAudioSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        NotificationCenter.default.post(name: Self.bannerChanged, object: nil)
    }

    private func removePlaybackObservers() {
        timeControlObserver?.invalidate()
        timeControlObserver = nil
        itemStatusObserver?.invalidate()
        itemStatusObserver = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        if let failureObserver {
            NotificationCenter.default.removeObserver(failureObserver)
        }
        failureObserver = nil
    }

    deinit {
        removePlaybackObservers()
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
        close.accessibilityLabel = "Stop video"
        close.accessibilityHint = "Stops playback and hides the video banner"

        let wave = UIImageView(image: UIImage(systemName: "waveform"))
        wave.tintColor = Theme.primary
        wave.contentMode = .scaleAspectFit
        wave.isAccessibilityElement = false

        let label = UILabel()
        label.text = "Video is playing"
        label.font = Theme.headline(14, weight: .semibold)
        label.textColor = Theme.textPrimary

        downloadButton.setImage(UIImage(systemName: "arrow.down.circle"), for: .normal)
        downloadButton.tintColor = Theme.textPrimary
        downloadButton.accessibilityLabel = "Video download"
        downloadButton.accessibilityHint = "Shows download options for this video"
        downloadButton.addTarget(self, action: #selector(downloadTapped), for: .touchUpInside)

        let expand = UIButton(type: .system, primaryAction: UIAction { [weak self] _ in self?.onExpand?() })
        expand.setImage(UIImage(systemName: "arrow.up.left.and.arrow.down.right"), for: .normal)
        expand.tintColor = Theme.textPrimary
        expand.accessibilityLabel = "Expand video player"
        expand.accessibilityHint = "Opens the full-screen video player"

        let row = UIStackView(arrangedSubviews: [close, wave, label, downloadButton, expand])
        row.axis = .horizontal
        row.spacing = 10
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            wave.widthAnchor.constraint(equalToConstant: 22),
            close.widthAnchor.constraint(equalToConstant: 44),
            close.heightAnchor.constraint(equalToConstant: 44),
            downloadButton.widthAnchor.constraint(equalToConstant: 44),
            downloadButton.heightAnchor.constraint(equalToConstant: 44),
            expand.widthAnchor.constraint(equalToConstant: 44),
            expand.heightAnchor.constraint(equalToConstant: 44)
        ])
        refreshDownloadBadge()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func refreshDownloadBadge() {
        guard let url = PlayerSession.shared.url else {
            downloadButton.tintColor = Theme.textPrimary
            downloadButton.accessibilityValue = nil
            return
        }
        let item = DownloadManager.shared.items.first {
            $0.sourceURL?.absoluteString == url.absoluteString
        }
        downloadButton.accessibilityValue = nil
        switch item?.state {
        case .running:
            let percent = Int((item?.progress ?? 0) * 100)
            downloadButton.tintColor = Theme.primary
            downloadButton.accessibilityValue = percent > 0 ? "\(percent)%" : "Downloading"
        case .finished:
            downloadButton.tintColor = UIColor(hex: 0x30D158)
            downloadButton.accessibilityValue = "Download finished"
        case .failed, .cancelled, .paused:
            downloadButton.tintColor = UIColor(hex: 0xFF9F0A)
            downloadButton.accessibilityValue = "Download needs attention"
        default:
            downloadButton.tintColor = Theme.textPrimary
        }
    }

    @objc private func downloadTapped() {
        onDownload?()
    }
}
