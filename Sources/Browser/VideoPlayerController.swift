import AVFoundation
import AVKit
import UIKit

/// In-app video player in the Aloha style, dressed in the Magdy design:
/// fullscreen dark canvas, glassy bottom pill, violet download pill with live
/// progress. Unique extras: ±10s skip, speed menu, frame grab, tap-to-hide controls.
final class VideoPlayerController: UIViewController {

    private let url: URL
    private let pageTitle: String
    private let cookies: [HTTPCookie]

    private let player = AVPlayer()
    private var playerLayer: AVPlayerLayer!
    private var pipController: AVPictureInPictureController?

    // Controls (fade in/out on tap).
    private let chrome = UIView()
    private let topBar = UIView()
    private let closeButton = UIButton(type: .system)
    private let shareButton = UIButton(type: .system)
    private let grabButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let centerRow = UIStackView()
    private let skipBackButton = UIButton(type: .system)
    private let playButton = UIButton(type: .system)
    private let skipForwardButton = UIButton(type: .system)
    private let bottomCard = UIView()
    private let currentLabel = UILabel()
    private let durationLabel = UILabel()
    private let scrubber = UISlider()
    private let downloadPill = UIButton(type: .system)
    private let pipButton = UIButton(type: .system)
    private let speedButton = UIButton(type: .system)
    private let routePicker = AVRoutePickerView()

    private var timeObserver: Any?
    private var isScrubbing = false
    private var rate: Float = 1.0
    private var hideTimer: Timer?

    init(url: URL, title: String, cookies: [HTTPCookie] = []) {
        self.url = url
        self.pageTitle = title
        self.cookies = cookies
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(hex: 0x05060A)
        buildUI()
        preparePlayer()
        observeDownloads()
        setControlsHidden(false)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        player.pause()
    }

    // MARK: - Setup

    private func buildUI() {
        // Video surface fills the screen behind everything.
        let container = PlayerSurfaceView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = .black
        view.addSubview(container)
        playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspect
        container.layer.addSublayer(playerLayer)

        // Tapping anywhere (except buttons) toggles the controls.
        let tap = UITapGestureRecognizer(target: self, action: #selector(toggleChrome))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)

        view.addSubview(chrome)
        chrome.translatesAutoresizingMaskIntoConstraints = false

        // Top bar: close · title · frame-grab · share.
        titleLabel.text = pageTitle
        titleLabel.textColor = .white
        titleLabel.font = Theme.headline(16, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 2

        func topIcon(_ systemName: String, selector: Selector) -> UIButton {
            let button = UIButton(type: .system)
            button.setImage(UIImage(systemName: systemName), for: .normal)
            button.tintColor = .white
            button.addTarget(self, action: selector, for: .touchUpInside)
            return button
        }
        closeButton = topIcon("xmark", selector: #selector(closeTapped))
        grabButton = topIcon("camera.viewfinder", selector: #selector(grabFrameTapped))
        grabButton.accessibilityLabel = "Save current frame"
        shareButton = topIcon("square.and.arrow.up", selector: #selector(shareTapped))

        let titleStack = UIStackView(arrangedSubviews: [
            closeButton, titleLabel, grabButton, shareButton
        ])
        titleStack.axis = .horizontal
        titleStack.alignment = .top
        titleStack.spacing = 12
        titleStack.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(titleStack)
        chrome.addSubview(topBar)
        topBar.translatesAutoresizingMaskIntoConstraints = false

        // Center transport: −10s · play · +10s.
        func transport(_ systemName: String, selector: Selector, size: CGFloat) -> UIButton {
            let button = UIButton(type: .system)
            let config = UIImage.SymbolConfiguration(pointSize: size, weight: .medium)
            button.setImage(UIImage(systemName: systemName, withConfiguration: config), for: .normal)
            button.tintColor = .white
            button.addTarget(self, action: selector, for: .touchUpInside)
            return button
        }
        skipBackButton = transport("gobackward.10", selector: #selector(skipBackTapped), size: 30)
        playButton = transport("pause.fill", selector: #selector(togglePlayback), size: 44)
        skipForwardButton = transport("goforward.10", selector: #selector(skipForwardTapped), size: 30)

        centerRow = UIStackView(arrangedSubviews: [skipBackButton, playButton, skipForwardButton])
        centerRow.axis = .horizontal
        centerRow.spacing = 46
        centerRow.alignment = .center
        centerRow.translatesAutoresizingMaskIntoConstraints = false
        chrome.addSubview(centerRow)

        // Bottom glassy pill card: scrub row + action row.
        bottomCard.backgroundColor = Theme.glass
        bottomCard.layer.cornerRadius = 26
        bottomCard.layer.cornerCurve = .continuous
        bottomCard.layer.borderWidth = 1
        bottomCard.layer.borderColor = Theme.hairline.cgColor
        bottomCard.translatesAutoresizingMaskIntoConstraints = false
        chrome.addSubview(bottomCard)

        currentLabel.text = "0:00"
        currentLabel.textColor = .white
        currentLabel.font = Theme.body(12, weight: .medium)
        durationLabel.text = "0:00"
        durationLabel.textColor = Theme.textSecondary
        durationLabel.font = Theme.body(12, weight: .medium)

        scrubber.minimumTrackTintColor = Theme.primary
        scrubber.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.25)
        scrubber.thumbTintColor = .white
        scrubber.addTarget(self, action: #selector(scrubStarted), for: .valueChanged)
        scrubber.addTarget(self, action: #selector(scrubEnded), for: .valueChanged)

        let timeRow = UIStackView(arrangedSubviews: [currentLabel, scrubber, durationLabel])
        timeRow.axis = .horizontal
        timeRow.spacing = 10
        timeRow.alignment = .center

        // Download pill: violet, shows live % while downloading.
        downloadPill.setTitle("Download", for: .normal)
        downloadPill.setTitleColor(.white, for: .normal)
        downloadPill.titleLabel?.font = Theme.headline(13, weight: .semibold)
        downloadPill.backgroundColor = Theme.primary
        downloadPill.layer.cornerRadius = 14
        downloadPill.layer.cornerCurve = .continuous
        downloadPill.contentEdgeInsets = UIEdgeInsets(top: 9, left: 16, bottom: 9, right: 16)
        downloadPill.addTarget(self, action: #selector(downloadTapped), for: .touchUpInside)

        pipButton.setImage(UIImage(systemName: "pip.enter"), for: .normal)
        pipButton.tintColor = .white
        pipButton.addTarget(self, action: #selector(pipTapped), for: .touchUpInside)

        speedButton.setTitle("1×", for: .normal)
        speedButton.setTitleColor(.white, for: .normal)
        speedButton.titleLabel?.font = Theme.headline(14, weight: .bold)
        speedButton.showsMenuAsPrimaryAction = true
        rebuildSpeedMenu()

        routePicker.tintColor = .white
        routePicker.activeTintColor = Theme.primary
        routePicker.prioritizesVideoDevices = true

        let actionRow = UIStackView(arrangedSubviews: [
            downloadPill, UIView(), pipButton, speedButton, routePicker
        ])
        actionRow.axis = .horizontal
        actionRow.alignment = .center
        actionRow.spacing = 16

        let cardStack = UIStackView(arrangedSubviews: [timeRow, actionRow])
        cardStack.axis = .vertical
        cardStack.spacing = 12
        cardStack.translatesAutoresizingMaskIntoConstraints = false
        bottomCard.addSubview(cardStack)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: view.topAnchor),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            chrome.topAnchor.constraint(equalTo: view.topAnchor),
            chrome.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            chrome.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            chrome.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            topBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6),
            topBar.leadingAnchor.constraint(equalTo: chrome.leadingAnchor, constant: 18),
            topBar.trailingAnchor.constraint(equalTo: chrome.trailingAnchor, constant: -18),

            closeButton.widthAnchor.constraint(equalToConstant: 34),
            grabButton.widthAnchor.constraint(equalToConstant: 34),
            shareButton.widthAnchor.constraint(equalToConstant: 34),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: closeButton.trailingAnchor, constant: 4),

            centerRow.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            centerRow.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),

            bottomCard.leadingAnchor.constraint(equalTo: chrome.leadingAnchor, constant: 14),
            bottomCard.trailingAnchor.constraint(equalTo: chrome.trailingAnchor, constant: -14),
            bottomCard.bottomAnchor.constraint(equalTo: chrome.safeAreaLayoutGuide.bottomAnchor, constant: -14),
            cardStack.topAnchor.constraint(equalTo: bottomCard.topAnchor, constant: 14),
            cardStack.leadingAnchor.constraint(equalTo: bottomCard.leadingAnchor, constant: 18),
            cardStack.trailingAnchor.constraint(equalTo: bottomCard.trailingAnchor, constant: -18),
            cardStack.bottomAnchor.constraint(equalTo: bottomCard.bottomAnchor, constant: -14)
        ])
    }

    private func preparePlayer() {
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        player.defaultRate = rate
        player.play()

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.4, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            if !self.isScrubbing {
                self.scrubber.value = Float(time.seconds)
            }
            self.currentLabel.text = Self.format(time.seconds)
            if let duration = self.player.currentItem?.duration.seconds, duration.isFinite {
                self.scrubber.maximumValue = Float(duration)
                self.durationLabel.text = Self.format(duration)
            }
            // Download % rides on the same tick (DownloadsViewController owns onChange).
            self.refreshDownloadPill()
        }

        if AVPictureInPictureController.isPictureInPictureSupported() {
            pipController = AVPictureInPictureController(playerLayer: playerLayer)
            pipController?.canStartPictureInPictureAutomaticallyFromInline = true
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        playerLayer.frame = view.bounds
    }

    // MARK: - Controls visibility

    @objc private func toggleChrome() {
        setControlsHidden(!chrome.isHidden)
    }

    private func setControlsHidden(_ hidden: Bool) {
        chrome.isHidden = !hidden
        chrome.alpha = hidden ? 0 : 1
        UIView.animate(withDuration: 0.22) { self.chrome.alpha = hidden ? 0 : 1 }
        chrome.isHidden = hidden
        hideTimer?.invalidate()
        if !hidden {
            hideTimer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: false) { [weak self] _ in
                self?.setControlsHidden(true)
            }
        }
    }

    // MARK: - Actions

    @objc private func togglePlayback() {
        if player.timeControlStatus == .playing {
            player.pause()
            playButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
        } else {
            player.playImmediately(atRate: rate)
            playButton.setImage(UIImage(systemName: "pause.fill"), for: .normal)
        }
        setControlsHidden(false)
    }

    @objc private func skipBackTapped() { skip(-10) }
    @objc private func skipForwardTapped() { skip(10) }

    private func skip(_ seconds: Double) {
        let target = max(0, player.currentTime().seconds + seconds)
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        setControlsHidden(false)
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func scrubStarted() {
        isScrubbing = true
        hideTimer?.invalidate()
    }

    @objc private func scrubEnded() {
        isScrubbing = false
        player.seek(to: CMTime(seconds: Double(scrubber.value), preferredTimescale: 600))
        setControlsHidden(false)
    }

    @objc private func pipTapped() {
        guard let pipController else {
            toast("Picture in Picture is not available for this stream")
            return
        }
        if pipController.isPictureInPictureActive {
            pipController.stopPictureInPicture()
        } else {
            pipController.startPictureInPicture()
        }
    }

    private func rebuildSpeedMenu() {
        let speeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
        let actions = speeds.map { value in
            UIAction(title: String(format: "%.2g×", value), state: abs(value - rate) < 0.01 ? .on : .off) { [weak self] _ in
                guard let self else { return }
                self.rate = value
                self.player.defaultRate = value
                if self.player.timeControlStatus == .playing { self.player.rate = value }
                self.speedButton.setTitle(String(format: "%.2g×", value), for: .normal)
                self.rebuildSpeedMenu()
            }
        }
        speedButton.menu = UIMenu(title: "Playback speed", children: actions)
    }

    /// Aloha-style: start the download and show live progress on the pill.
    @objc private func downloadTapped() {
        let existing = DownloadManager.shared.items.first {
            $0.sourceURL?.absoluteString == url.absoluteString
        }
        if let existing, existing.state == .running || existing.state == .paused {
            toast("Already downloading — see Downloads")
            return
        }
        if let existing, existing.state == .finished, let localURL = existing.localURL {
            let sheet = UIActivityViewController(activityItems: [localURL], applicationActivities: nil)
            present(sheet, animated: true)
            return
        }
        if url.pathExtension.lowercased() == "m3u8" || url.absoluteString.contains(".m3u8") {
            DownloadManager.shared.startHLS(url: url, referer: nil, cookies: cookies)
        } else {
            DownloadManager.shared.start(url: url, referer: nil, cookies: cookies)
        }
        toast("Downloading…")
    }

    /// Unique extra: saves the current frame as a JPG into Downloads.
    @objc private func grabFrameTapped() {
        guard let asset = player.currentItem?.asset else { return }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let time = player.currentTime()
        generator.copyCGImage(at: time, actualTime: nil) { [weak self] image, _ in
            DispatchQueue.main.async {
                guard let self, let cgImage = image else {
                    self?.toast("Frame grab is not supported for this stream")
                    return
                }
                let uiImage = UIImage(cgImage: cgImage)
                let output = DownloadManager.shared.directory
                    .appendingPathComponent("frame-\(Int(Date().timeIntervalSince1970)).jpg")
                guard let data = uiImage.jpegData(compressionQuality: 0.92) else {
                    self.toast("Could not encode the frame")
                    return
                }
                do {
                    try data.write(to: output)
                    self.toast("Frame saved to Downloads")
                } catch {
                    self.toast("Could not save the frame")
                }
            }
        }
    }

    @objc private func shareTapped() {
        let items: [Any]
        let finished = DownloadManager.shared.items.first {
            $0.sourceURL?.absoluteString == url.absoluteString && $0.state == .finished
        }
        if let finished, let localURL = finished.localURL {
            items = [localURL]
        } else {
            items = ["\(pageTitle) — \(url.absoluteString)"]
        }
        let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
        present(sheet, animated: true)
    }

    // MARK: - Download progress

    private func observeDownloads() {
        refreshDownloadPill()
    }

    private func refreshDownloadPill() {
        let item = DownloadManager.shared.items.first {
            $0.sourceURL?.absoluteString == url.absoluteString
        }
        switch item?.state {
        case .running:
            let percent = Int((item?.progress ?? 0) * 100)
            downloadPill.setTitle(percent > 0 ? "\(percent)%" : "…", for: .normal)
            downloadPill.backgroundColor = Theme.primary.withAlphaComponent(0.55)
        case .finished:
            downloadPill.setTitle("Saved ✓", for: .normal)
            downloadPill.backgroundColor = UIColor(hex: 0x30D158)
        case .failed, .cancelled:
            downloadPill.setTitle("Retry", for: .normal)
            downloadPill.backgroundColor = Theme.primary
        case .paused:
            downloadPill.setTitle("Paused", for: .normal)
            downloadPill.backgroundColor = UIColor(hex: 0xFF9F0A)
        default:
            break
        }
    }

    // MARK: - Helpers

    private func toast(_ message: String) {
        let label = UILabel()
        label.text = message
        label.textColor = .white
        label.font = Theme.body(14, weight: .semibold)
        label.backgroundColor = UIColor(hex: 0x181920).withAlphaComponent(0.94)
        label.layer.cornerRadius = 12
        label.layer.cornerCurve = .continuous
        label.layer.borderWidth = 1
        label.layer.borderColor = Theme.hairline.cgColor
        label.textAlignment = .center
        label.clipsToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -110),
            label.heightAnchor.constraint(equalToConstant: 36),
            label.widthAnchor.constraint(greaterThanOrEqualToConstant: 170)
        ])
        UIView.animate(withDuration: 0.25, delay: 1.6, options: []) {
            label.alpha = 0
        } completion: { _ in
            label.removeFromSuperview()
        }
    }

    private static func format(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = Int(seconds)
        let minutes = total / 60
        let remainder = total % 60
        return String(format: "%d:%02d", minutes, remainder)
    }
}

/// Plain surface that hosts the AVPlayerLayer.
final class PlayerSurfaceView: UIView {}
