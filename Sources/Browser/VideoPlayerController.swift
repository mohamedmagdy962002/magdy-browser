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
    /// True when playing a file already saved in Downloads.
    private let isLocal: Bool

    /// Reuses the session player so audio keeps playing seamlessly when the
    /// fullscreen UI is reopened from the "Video is playing" banner.
    private let player: AVPlayer
    private var playerLayer: AVPlayerLayer!
    private var pipController: AVPictureInPictureController?

    // Controls (fade in/out on tap).
    private let chrome = UIView()
    private let topBar = UIView()
    private var closeButton = UIButton(type: .system)
    private var shareButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private var centerRow = UIStackView()
    private var skipBackButton = UIButton(type: .system)
    private var playButton = UIButton(type: .system)
    private var skipForwardButton = UIButton(type: .system)
    private let bottomCard = UIView()
    private let currentLabel = UILabel()
    private let durationLabel = UILabel()
    private let scrubber = UISlider()
    private let downloadPill = UIButton(type: .system)
    private let pipButton = UIButton(type: .system)
    private let speedButton = UIButton(type: .system)
    private let routePicker = AVRoutePickerView()
    private var timeObserver: Any?
    private var itemStatusObserver: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var failureObserver: NSObjectProtocol?
    private var isScrubbing = false
    private var isTouchScrubbing = false
    private var scrubCommitWorkItem: DispatchWorkItem?
    private var rate: Float
    private var hideTimer: Timer?
    private var errorShown = false
    private var ownsAudioSession = false
    private let reusedPlayer: AVPlayer?
    // Stored so the gesture delegate can tell them apart.
    private var tapGesture: UITapGestureRecognizer!
    private var doubleTapGesture: UITapGestureRecognizer!
    private var swipeDownGesture: UIPanGestureRecognizer!

    init(url: URL, title: String, cookies: [HTTPCookie] = [], isLocal: Bool = false, existingPlayer: AVPlayer? = nil) {
        self.url = url
        self.pageTitle = title
        self.cookies = cookies
        self.isLocal = isLocal
        self.player = existingPlayer ?? AVPlayer()
        self.reusedPlayer = existingPlayer
        // Speed choice sticks across sessions.
        let saved = UserDefaults.standard.object(forKey: "magdy.playerRate") as? Float ?? 1.0
        rate = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0].contains(saved) ? saved : 1.0
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
        // Covering the player with a sheet leaves it in the presentation chain.
        // Only a real dismissal relinquishes this controller's playback duties.
        guard isBeingDismissed || (view.window == nil && parent == nil && presentingViewController == nil) else { return }
        tearDownPlayback()
    }

    deinit {
        tearDownPlayback()
    }

    private func tearDownPlayback() {
        hideTimer?.invalidate()
        hideTimer = nil
        scrubCommitWorkItem?.cancel()
        scrubCommitWorkItem = nil
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        itemStatusObserver?.invalidate()
        itemStatusObserver = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        if let failureObserver {
            NotificationCenter.default.removeObserver(failureObserver)
            self.failureObserver = nil
        }
        guard PlayerSession.shared.player !== player,
              pipController?.isPictureInPictureActive != true else { return }
        player.pause()
        deactivateAudioSessionIfOwned()
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

        // Tapping anywhere (except controls) toggles them; buttons keep their
        // own touches — the delegate below filters control areas out.
        let tap = UITapGestureRecognizer(target: self, action: #selector(toggleChrome))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        view.addGestureRecognizer(tap)
        tapGesture = tap
        // Double-tap left/right half of the video skips ±10s (YouTube-style).
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapSkip(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.cancelsTouchesInView = false
        doubleTap.delegate = self
        view.addGestureRecognizer(doubleTap)
        doubleTapGesture = doubleTap
        tap.require(toFail: doubleTap)

        // Swipe down on the video surface to close — never from the control
        // bars (dragging the scrubber must not drag the player down).
        let swipeDown = UIPanGestureRecognizer(target: self, action: #selector(swipeDownClose(_:)))
        swipeDown.cancelsTouchesInView = false
        swipeDown.delegate = self
        view.addGestureRecognizer(swipeDown)
        swipeDownGesture = swipeDown

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
        closeButton.accessibilityLabel = "Close video player"
        closeButton.accessibilityHint = "Closes the player while retaining eligible background playback"
        shareButton = topIcon("square.and.arrow.up", selector: #selector(shareTapped))
        shareButton.accessibilityLabel = "Share video"
        shareButton.accessibilityHint = "Opens sharing options for this video"

        // Aloha reference: one glass pill holding ✕ · centered title · share.
        // Equal-width spacers keep the title exactly centered.
        let spacerLeft = UIView()
        let spacerRight = UIView()
        let titleStack = UIStackView(arrangedSubviews: [
            closeButton, spacerLeft, titleLabel, spacerRight, shareButton
        ])
        titleStack.axis = .horizontal
        titleStack.alignment = .center
        titleStack.spacing = 8
        titleStack.translatesAutoresizingMaskIntoConstraints = false
        titleStack.backgroundColor = UIColor(white: 0, alpha: 0.42)
        titleStack.layer.cornerRadius = 18
        titleStack.layer.cornerCurve = .continuous
        titleStack.isLayoutMarginsRelativeArrangement = true
        titleStack.layoutMargins = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
        topBar.addSubview(titleStack)
        chrome.addSubview(topBar)
        topBar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            spacerLeft.widthAnchor.constraint(equalTo: spacerRight.widthAnchor)
        ])

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
        skipBackButton.accessibilityLabel = "Rewind 10 seconds"
        skipBackButton.accessibilityHint = "Moves playback backward by 10 seconds"
        playButton = transport("pause.fill", selector: #selector(togglePlayback), size: 44)
        playButton.accessibilityLabel = "Pause video"
        playButton.accessibilityHint = "Pauses playback"
        skipForwardButton = transport("goforward.10", selector: #selector(skipForwardTapped), size: 30)
        skipForwardButton.accessibilityLabel = "Forward 10 seconds"
        skipForwardButton.accessibilityHint = "Moves playback forward by 10 seconds"
        NSLayoutConstraint.activate([
            skipBackButton.widthAnchor.constraint(equalToConstant: 44),
            skipBackButton.heightAnchor.constraint(equalToConstant: 44),
            playButton.widthAnchor.constraint(equalToConstant: 44),
            playButton.heightAnchor.constraint(equalToConstant: 44),
            skipForwardButton.widthAnchor.constraint(equalToConstant: 44),
            skipForwardButton.heightAnchor.constraint(equalToConstant: 44)
        ])

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
        scrubber.accessibilityLabel = "Playback position"
        scrubber.accessibilityHint = "Swipe up or down to seek through the video"
        scrubber.addTarget(self, action: #selector(scrubStarted), for: .touchDown)
        scrubber.addTarget(self, action: #selector(scrubValueChanged), for: .valueChanged)
        scrubber.addTarget(
            self, action: #selector(scrubEnded),
            for: [.touchUpInside, .touchUpOutside, .touchCancel]
        )

        let timeRow = UIStackView(arrangedSubviews: [currentLabel, scrubber, durationLabel])
        timeRow.axis = .horizontal
        timeRow.spacing = 10
        timeRow.alignment = .center

        // Download pill: violet, icon with live % text under it (Aloha ref row).
        var pillConfig = UIButton.Configuration.plain()
        pillConfig.image = UIImage(systemName: "arrow.down")
        pillConfig.imagePlacement = .top
        pillConfig.imagePadding = 3
        pillConfig.title = "Download"
        pillConfig.baseForegroundColor = .white
        pillConfig.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = Theme.body(11, weight: .semibold)
            return outgoing
        }
        downloadPill.configuration = pillConfig
        downloadPill.addTarget(self, action: #selector(downloadTapped), for: .touchUpInside)

        pipButton.setImage(UIImage(systemName: "pip.enter"), for: .normal)
        pipButton.tintColor = .white
        pipButton.accessibilityLabel = "Picture in Picture"
        pipButton.accessibilityHint = "Shows the video in a floating window when supported"
        pipButton.addTarget(self, action: #selector(pipTapped), for: .touchUpInside)

        speedButton.setTitle(String(format: "%.2g×", rate), for: .normal)
        speedButton.accessibilityLabel = "Playback speed"
        speedButton.accessibilityHint = "Opens playback speed options"
        speedButton.setTitleColor(.white, for: .normal)
        speedButton.titleLabel?.font = Theme.headline(14, weight: .bold)
        speedButton.showsMenuAsPrimaryAction = true
        rebuildSpeedMenu()

        routePicker.tintColor = .white
        routePicker.activeTintColor = Theme.primary
        routePicker.prioritizesVideoDevices = true
        routePicker.accessibilityLabel = "Audio output"
        routePicker.accessibilityHint = "Chooses where video audio plays"

        // ⋯ opens pause/resume/cancel for a running download, or the options sheet.
        let moreButton = UIButton(type: .system)
        moreButton.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        moreButton.tintColor = .white
        moreButton.showsMenuAsPrimaryAction = true
        moreButton.accessibilityLabel = "More video options"
        moreButton.accessibilityHint = "Opens download, frame capture, and sharing options"
        moreButton.menu = UIMenu(children: [
            UIAction(title: "Download Options…", image: UIImage(systemName: "slider.horizontal.3")) { [weak self] _ in
                guard let self else { return }
                DownloadOptionsSheet.present(url: self.url, referer: nil, cookies: self.cookies, presenter: self)
            },
            UIAction(title: "Save Current Frame", image: UIImage(systemName: "camera.viewfinder")) { [weak self] _ in
                self?.grabFrameTapped()
            },
            UIAction(title: "Share", image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in
                self?.shareTapped()
            }
        ])
        // Real touch targets so the icons never feel dead.
        NSLayoutConstraint.activate([
            pipButton.widthAnchor.constraint(equalToConstant: 44),
            pipButton.heightAnchor.constraint(equalToConstant: 44),
            speedButton.widthAnchor.constraint(equalToConstant: 44),
            speedButton.heightAnchor.constraint(equalToConstant: 44),
            moreButton.widthAnchor.constraint(equalToConstant: 44),
            moreButton.heightAnchor.constraint(equalToConstant: 44)
        ])

        let actionRow = UIStackView(arrangedSubviews: [
            downloadPill, pipButton, speedButton, routePicker, moreButton
        ])
        actionRow.axis = .horizontal
        actionRow.alignment = .center
        actionRow.distribution = .equalSpacing

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

            // Pin the pill inside topBar so topBar gets a real height —
            // zero-height topBar makes ✕/share/grab unhit-testable.
            titleStack.topAnchor.constraint(equalTo: topBar.topAnchor),
            titleStack.leadingAnchor.constraint(equalTo: topBar.leadingAnchor),
            titleStack.trailingAnchor.constraint(equalTo: topBar.trailingAnchor),
            titleStack.bottomAnchor.constraint(equalTo: topBar.bottomAnchor),

            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),
            shareButton.widthAnchor.constraint(equalToConstant: 44),
            shareButton.heightAnchor.constraint(equalToConstant: 44),
            titleStack.heightAnchor.constraint(equalToConstant: 60),

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
        let item: AVPlayerItem
        if reusedPlayer != nil, let currentItem = player.currentItem {
            // Session player reopened from the banner — keep playing seamlessly.
            item = currentItem
        } else {
            if let reason = unsupportedStreamReason() {
                player.pause()
                playButton.isEnabled = false
                playButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
                playButton.accessibilityLabel = "Play video"
                pipButton.isEnabled = false
                toast(reason)
                return
            }
            item = AVPlayerItem(asset: makePlayerAsset())
            player.replaceCurrentItem(with: item)
        }
        if item.status == .failed || player.error != nil {
            handlePlaybackFailure(item.error ?? player.error)
            return
        }

        player.defaultRate = rate
        // Audio keeps playing over the lock screen and other apps' music.
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
            ownsAudioSession = true
        } catch {
            // AVPlayer may still activate its own session; playback can proceed.
        }
        // Local files resume where you left off.
        if isLocal {
            let saved = UserDefaults.standard.double(forKey: "magdy.playback.\(url.path)")
            if saved > 5 {
                item.seek(to: CMTime(seconds: saved, preferredTimescale: 600), completionHandler: nil)
                toast("Resumed at \(Self.format(saved))")
            }
        }

        itemStatusObserver = item.observe(\.status, options: [.new]) { [weak self] observedItem, _ in
            guard observedItem.status == .failed else { return }
            DispatchQueue.main.async {
                guard let self, self.player.currentItem === observedItem else { return }
                self.handlePlaybackFailure(observedItem.error)
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            guard let self, self.player.currentItem === item else { return }
            self.handlePlaybackEnd()
        }
        failureObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main
        ) { [weak self] notification in
            guard let self, self.player.currentItem === item else { return }
            let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            self.handlePlaybackFailure(error)
        }

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.4, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            if !self.isScrubbing {
                self.scrubber.value = Float(time.seconds)
            }
            self.currentLabel.text = Self.format(time.seconds)
            self.scrubber.accessibilityValue = Self.format(time.seconds)
            if let duration = self.player.currentItem?.duration.seconds, duration.isFinite {
                self.scrubber.maximumValue = Float(duration)
                self.durationLabel.text = Self.format(duration)
            }
            // Download % rides on the same tick (DownloadsViewController owns onChange).
            self.refreshDownloadPill()
            // Surface stream failures (DRM / 403) instead of a black screen.
            if let error = self.player.currentItem?.error {
                self.handlePlaybackFailure(error)
            }
            // Remember playback position for local files.
            if self.isLocal, time.seconds.isFinite {
                // Fully watched: reset so it starts from the top next time.
                if let duration = self.player.currentItem?.duration.seconds, duration.isFinite,
                   time.seconds >= duration - 2 {
                    UserDefaults.standard.set(0, forKey: "magdy.playback.\(self.url.path)")
                } else {
                    UserDefaults.standard.set(time.seconds, forKey: "magdy.playback.\(self.url.path)")
                }
            }
        }

        if AVPictureInPictureController.isPictureInPictureSupported() {
            pipController = AVPictureInPictureController(playerLayer: playerLayer)
            pipController?.canStartPictureInPictureAutomaticallyFromInline = true
        }
        player.play()
    }

    private func unsupportedStreamReason() -> String? {
        if url.scheme?.lowercased() == "blob" {
            return "Blob video URLs are temporary and cannot be played here. Try Media Tools."
        }
        let fileExtension = url.pathExtension.lowercased()
        if fileExtension == "mpd" {
            return "DASH streams are not supported by the built-in player. Try Media Tools."
        }
        if fileExtension == "mkv" {
            return "MKV streams are not supported by the built-in player. Try Media Tools."
        }
        if !isLocal, !["http", "https", "file"].contains(url.scheme?.lowercased() ?? "") {
            return "This video URL is not supported by the built-in player. Try Media Tools."
        }
        return nil
    }

    private func makePlayerAsset() -> AVURLAsset {
        guard !isLocal, ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            return AVURLAsset(url: url)
        }
        let applicableCookies = cookies
            .filter { $0.applies(to: url) }
            .sorted { $0.path.count > $1.path.count }
        guard !applicableCookies.isEmpty else { return AVURLAsset(url: url) }
        return AVURLAsset(
            url: url,
            options: [AVURLAssetHTTPCookiesKey: applicableCookies]
        )
    }

    private func deactivateAudioSessionIfOwned() {
        guard ownsAudioSession else { return }
        ownsAudioSession = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func handlePlaybackEnd() {
        player.pause()
        if isLocal {
            UserDefaults.standard.set(0, forKey: "magdy.playback.\(url.path)")
        }
        playButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
        playButton.accessibilityLabel = "Play video"
        playButton.accessibilityHint = "Resumes or restarts playback"
        if PlayerSession.shared.player === player {
            PlayerSession.shared.stop()
            ownsAudioSession = false
        } else if pipController?.isPictureInPictureActive != true {
            deactivateAudioSessionIfOwned()
        }
    }

    private func handlePlaybackFailure(_ error: Error?) {
        guard !errorShown else { return }
        errorShown = true
        player.pause()
        playButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
        playButton.accessibilityLabel = "Play video"
        playButton.accessibilityHint = "Retries playback"
        if PlayerSession.shared.player === player {
            PlayerSession.shared.stop()
            ownsAudioSession = false
        } else if pipController?.isPictureInPictureActive != true {
            deactivateAudioSessionIfOwned()
        }
        let detail = error?.localizedDescription ?? "This stream could not be played"
        toast("Stream error: \(detail). Try the Media Tools scanner.")
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        playerLayer.frame = view.bounds
    }

    // MARK: - Controls visibility

    @objc private func toggleChrome() {
        setControlsHidden(!chrome.isHidden)
    }

    /// Double-tap on the left half rewinds 10s, right half advances — YouTube-style.
    @objc private func doubleTapSkip(_ gesture: UITapGestureRecognizer) {
        let isLeft = gesture.location(in: view).x < view.bounds.midX
        skip(isLeft ? -10 : 10)
        toast(isLeft ? "« 10s" : "10s »")
    }

    private func setControlsHidden(_ hidden: Bool) {
        chrome.isHidden = false
        UIView.animate(
            withDuration: 0.22,
            animations: { self.chrome.alpha = hidden ? 0 : 1 },
            completion: { _ in self.chrome.isHidden = hidden }
        )
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
            playButton.accessibilityLabel = "Play video"
            playButton.accessibilityHint = "Resumes playback"
        } else {
            player.playImmediately(atRate: rate)
            playButton.setImage(UIImage(systemName: "pause.fill"), for: .normal)
            playButton.accessibilityLabel = "Pause video"
            playButton.accessibilityHint = "Pauses playback"
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
        hideTimer?.invalidate()
        let pictureInPictureIsActive = pipController?.isPictureInPictureActive == true
        let canRetainPlayback = !isLocal
            && player.timeControlStatus == .playing
            && player.currentItem?.status == .readyToPlay
            && player.currentItem?.error == nil
            && player.error == nil
        if canRetainPlayback {
            // Keep audio going; the browser shows the "Video is playing" banner.
            PlayerSession.shared.adopt(player, url: url, title: pageTitle, cookies: cookies)
        } else {
            player.pause()
            if PlayerSession.shared.player === player {
                PlayerSession.shared.stop(deactivateAudioSession: !pictureInPictureIsActive)
                ownsAudioSession = false
            } else if !pictureInPictureIsActive {
                deactivateAudioSessionIfOwned()
            }
        }
        dismissPlayer()
    }

    private func dismissPlayer() {
        guard !isBeingDismissed, let presenter = presentingViewController else { return }
        dismiss(animated: true) { [weak self] in
            // Only fall back when this presentation is still on screen. Calling
            // the presenter unconditionally can dismiss an unrelated screen.
            guard let self, self.view.window != nil else { return }
            presenter.dismiss(animated: true, completion: nil)
        }
    }

    @objc private func swipeDownClose(_ gesture: UIPanGestureRecognizer) {
        let down = gesture.translation(in: view).y
        if gesture.state == .began {
            gesture.view?.backgroundColor = .clear
        }
        if gesture.state == .changed, down > 0 {
            // Drag the whole player down like a sheet.
            view.transform = CGAffineTransform(translationX: 0, y: down)
        }
        if gesture.state == .ended {
            if down > 130 {
                closeTapped()
            } else {
                UIView.animate(withDuration: 0.25) { self.view.transform = .identity }
            }
        } else if gesture.state == .cancelled || gesture.state == .failed {
            UIView.animate(withDuration: 0.25) { self.view.transform = .identity }
        }
    }

    @objc private func scrubStarted() {
        isScrubbing = true
        isTouchScrubbing = true
        scrubCommitWorkItem?.cancel()
        hideTimer?.invalidate()
    }

    @objc private func scrubValueChanged() {
        // Accessibility adjustments can arrive without a touch-down. Keep the
        // preview stable and commit after adjustments settle, not per change.
        isScrubbing = true
        hideTimer?.invalidate()
        currentLabel.text = Self.format(Double(scrubber.value))
        scrubber.accessibilityValue = Self.format(Double(scrubber.value))
        guard !isTouchScrubbing else { return }
        scrubCommitWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.commitScrub() }
        scrubCommitWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    @objc private func scrubEnded() {
        scrubCommitWorkItem?.cancel()
        scrubCommitWorkItem = nil
        isTouchScrubbing = false
        commitScrub()
    }

    private func commitScrub() {
        guard isScrubbing else { return }
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
                UserDefaults.standard.set(value, forKey: "magdy.playerRate")
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
        if isLocal {
            presentSheet(UIActivityViewController(activityItems: [url], applicationActivities: nil))
            return
        }
        let existing = DownloadManager.shared.items.first {
            $0.sourceURL?.absoluteString == url.absoluteString
        }
        if let existing, [.running, .paused, .queued].contains(existing.state) {
            showDownloadMenu(for: existing)
            return
        }
        if let existing, existing.state == .finished, let localURL = existing.localURL {
            presentSheet(UIActivityViewController(activityItems: [localURL], applicationActivities: nil))
            return
        }
        DownloadOptionsSheet.present(
            url: url, referer: nil, cookies: cookies, presenter: self
        )
    }

    /// Pause / resume / cancel without leaving the player.
    private func showDownloadMenu(for item: DownloadItem) {
        let alert = UIAlertController(title: item.fileName, message: nil, preferredStyle: .actionSheet)
        if item.state == .running {
            alert.addAction(UIAlertAction(title: "Pause", style: .default) { _ in
                DownloadManager.shared.pause(item)
            })
        } else {
            alert.addAction(UIAlertAction(title: "Resume", style: .default) { _ in
                DownloadManager.shared.resume(item)
            })
        }
        alert.addAction(UIAlertAction(title: "Cancel download", style: .destructive) { _ in
            DownloadManager.shared.cancel(item)
        })
        alert.addAction(UIAlertAction(title: "Close", style: .cancel))
        alert.popoverPresentationController?.sourceView = downloadPill
        present(alert, animated: true)
    }

    /// Unique extra: saves the current frame as a JPG into Downloads.
    @objc private func grabFrameTapped() {
        guard let asset = player.currentItem?.asset else { return }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let time = player.currentTime()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var actual = CMTime.zero
            let frame = (try? generator.copyCGImage(at: time, actualTime: &actual))
                .map { UIImage(cgImage: $0) }
            DispatchQueue.main.async {
                guard let self else { return }
                guard let frame else {
                    self.toast("Frame grab is not supported for this stream")
                    return
                }
                let folder = DownloadManager.shared.directory
                let name = DownloadDestinationAllocator.availableName(
                    "frame-\(Int(Date().timeIntervalSince1970)).jpg", in: folder, reserve: true
                )
                let output = folder.appendingPathComponent(name)
                defer { DownloadDestinationAllocator.release(output) }
                guard let data = frame.jpegData(compressionQuality: 0.92) else {
                    self.toast("Could not encode the frame")
                    return
                }
                do {
                    try data.write(to: output, options: .atomic)
                    self.toast("Frame saved to Downloads")
                } catch {
                    self.toast("Could not save the frame")
                }
            }
        }
    }

    @objc private func shareTapped() {
        let items: [Any]
        if isLocal {
            items = [url]
        } else {
            let finished = DownloadManager.shared.items.first {
                $0.sourceURL?.absoluteString == url.absoluteString && $0.state == .finished
            }
            if let finished, let localURL = finished.localURL {
                items = [localURL]
            } else {
                items = ["\(pageTitle) — \(url.absoluteString)"]
            }
        }
        let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
        presentSheet(sheet)
    }

    /// Activity sheet with an iPad-safe popover anchor.
    private func presentSheet(_ sheet: UIActivityViewController) {
        sheet.popoverPresentationController?.sourceView = view
        sheet.popoverPresentationController?.sourceRect = CGRect(
            x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1
        )
        present(sheet, animated: true)
    }

    // MARK: - Download progress

    private func observeDownloads() {
        refreshDownloadPill()
    }

    private func refreshDownloadPill() {
        func pill(_ title: String, color: UIColor) {
            var config = downloadPill.configuration
            config?.title = title
            config?.baseForegroundColor = color
            downloadPill.configuration = config
        }
        if isLocal {
            pill("Saved ✓", color: UIColor(hex: 0x30D158))
            return
        }
        let item = DownloadManager.shared.items.first {
            $0.sourceURL?.absoluteString == url.absoluteString
        }
        switch item?.state {
        case .running:
            let percent = Int((item?.progress ?? 0) * 100)
            pill(percent > 0 ? "\(percent)%" : "…", color: .white)
        case .finished:
            pill("Saved ✓", color: UIColor(hex: 0x30D158))
        case .failed, .cancelled:
            pill("Retry", color: UIColor(hex: 0xFF9F0A))
        case .paused:
            pill("Paused", color: UIColor(hex: 0xFF9F0A))
        default:
            pill("Download", color: .white)
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

extension VideoPlayerController: UIGestureRecognizerDelegate {
    /// Taps on the control bars belong to the buttons alone; swipes only close
    /// when they start on the video surface itself.
    func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
        let point = gesture.location(in: view)
        let overControls = topBar.frame.contains(point)
            || bottomCard.frame.contains(point)
            || centerRow.frame.contains(point)
        if gesture === swipeDownGesture {
            return !overControls
        }
        // tap / double-tap: ignore while the controls are visible and the touch
        // landed on a control, so buttons never double-fire with toggleChrome.
        if gesture === tapGesture || gesture === doubleTapGesture {
            return !(chrome.alpha > 0.5 && overControls)
        }
        return true
    }
}

/// Plain surface that hosts the AVPlayerLayer.
final class PlayerSurfaceView: UIView {}
