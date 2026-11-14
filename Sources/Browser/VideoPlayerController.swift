import AVFoundation
import AVKit
import UIKit

/// In-app video player for videos found on a page.
/// Play/pause, scrubbing, speed, AirPlay, Picture in Picture, full video download
/// and clip recording straight from the player.
final class VideoPlayerController: UIViewController {

    private let url: URL
    private let title: String

    private let player = AVPlayer()
    private var playerLayer: AVPlayerLayer!
    private var pipController: AVPictureInPictureController?

    private let titleLabel = UILabel()
    private let playButton = UIButton(type: .system)
    private let currentLabel = UILabel()
    private let durationLabel = UILabel()
    private let scrubber = UISlider()
    private let controls = UIStackView()
    private let closeButton = UIButton(type: .system)
    private let downloadButton = UIButton(type: .system)
    private let recordButton = UIButton(type: .system)
    private let speedButton = UIButton(type: .system)
    private let routePicker = AVRoutePickerView()
    private let pipButton = UIButton(type: .system)

    private var timeObserver: Any?
    private var isScrubbing = false
    private var clipStart: Double = 0

    init(url: URL, title: String) {
        self.url = url
        self.title = title
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        buildUI()
        preparePlayer()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        player.pause()
    }

    // MARK: - Setup

    private func buildUI() {
        let container = PlayerSurfaceView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = .black
        view.addSubview(container)

        playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspect
        container.layer.addSublayer(playerLayer)

        titleLabel.text = title
        titleLabel.textColor = .white
        titleLabel.font = Theme.headline(17, weight: .semibold)
        titleLabel.numberOfLines = 2

        playButton.setImage(UIImage(systemName: "pause.fill"), for: .normal)
        playButton.tintColor = .white
        playButton.addTarget(self, action: #selector(togglePlayback), for: .touchUpInside)

        currentLabel.text = "0:00"
        currentLabel.textColor = .white
        currentLabel.font = Theme.body(12)
        durationLabel.text = "0:00"
        durationLabel.textColor = .white
        durationLabel.font = Theme.body(12)

        scrubber.minimumTrackTintColor = Theme.primary
        scrubber.maximumTrackTintColor = .white
        scrubber.addTarget(self, action: #selector(scrubStarted), for: .valueChanged)
        scrubber.addTarget(self, action: #selector(scrubEnded), for: .valueChanged)

        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.tintColor = .white
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        downloadButton.setImage(UIImage(systemName: "arrow.down.circle.fill"), for: .normal)
        downloadButton.tintColor = .white
        downloadButton.accessibilityLabel = "Download"
        downloadButton.addTarget(self, action: #selector(downloadTapped), for: .touchUpInside)

        recordButton.setImage(UIImage(systemName: "record.circle"), for: .normal)
        recordButton.tintColor = .white
        recordButton.accessibilityLabel = "Record clip"
        recordButton.addTarget(self, action: #selector(recordTapped), for: .touchUpInside)

        speedButton.setImage(UIImage(systemName: "speedometer"), for: .normal)
        speedButton.tintColor = .white
        speedButton.addTarget(self, action: #selector(speedTapped), for: .touchUpInside)

        pipButton.setImage(UIImage(systemName: "pip.enter"), for: .normal)
        pipButton.tintColor = .white
        pipButton.addTarget(self, action: #selector(pipTapped), for: .touchUpInside)

        routePicker.tintColor = .white
        routePicker.activeTintColor = Theme.primary
        routePicker.prioritizesVideoDevices = true

        let timeRow = UIStackView(arrangedSubviews: [currentLabel, scrubber, durationLabel])
        timeRow.axis = .horizontal
        timeRow.spacing = 10
        timeRow.alignment = .center

        let actionRow = UIStackView(arrangedSubviews: [
            downloadButton, recordButton, speedButton, pipButton, routePicker, playButton
        ])
        actionRow.axis = .horizontal
        actionRow.spacing = 18
        actionRow.alignment = .center
        actionRow.distribution = .equalSpacing

        controls.axis = .vertical
        controls.spacing = 14
        controls.translatesAutoresizingMaskIntoConstraints = false
        controls.addArrangedSubview(titleLabel)
        controls.addArrangedSubview(timeRow)
        controls.addArrangedSubview(actionRow)
        view.addSubview(controls)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: view.topAnchor),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            container.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.52),

            controls.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            controls.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            controls.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24)
        ])

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            closeButton.widthAnchor.constraint(equalToConstant: 30),
            closeButton.heightAnchor.constraint(equalToConstant: 30)
        ])
    }

    private func preparePlayer() {
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
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
                self.durationLabel.text = Self.format(duration)
            }
        }

        if AVPictureInPictureController.isPictureInPictureSupported() {
            pipController = AVPictureInPictureController(playerLayer: playerLayer)
            pipController?.canStartPictureInPictureAutomaticallyFromInline = true
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        playerLayer.frame = (view.subviews.first as? PlayerSurfaceView)?.bounds ?? view.bounds
    }

    // MARK: - Actions

    @objc private func togglePlayback() {
        if player.timeControlStatus == .playing {
            player.pause()
            playButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
        } else {
            player.play()
            playButton.setImage(UIImage(systemName: "pause.fill"), for: .normal)
        }
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func scrubStarted() {
        isScrubbing = true
    }

    @objc private func scrubEnded() {
        isScrubbing = false
        player.seek(to: CMTime(seconds: Double(scrubber.value), preferredTimescale: 600))
    }

    @objc private func speedTapped() {
        let speeds: [Float] = [1.0, 1.25, 1.5, 2.0, 0.75, 0.5]
        let current = player.rate == 0 ? 1.0 : player.rate
        let next = speeds.first(where: { abs($0 - current) > 0.01 }) ?? speeds[0]
        player.rate = next
        toast("Speed \(next)x")
    }

    @objc private func pipTapped() {
        guard let pipController else { return }
        if pipController.isPictureInPictureActive {
            pipController.stopPictureInPicture()
        } else {
            pipController.startPictureInPicture()
        }
    }

    /// Downloads the whole video into the app's Downloads folder.
    @objc private func downloadTapped() {
        let name = url.lastPathComponent.isEmpty ? "video" : url.lastPathComponent
        if name.lowercased().contains("m3u8") {
            DownloadManager.shared.startHLS(url: url, referer: nil, cookies: [])
        } else {
            DownloadManager.shared.start(url: url, referer: nil, cookies: [])
        }
        toast("Downloading \(name)")
    }

    /// Records the clip that is currently playing into a .mp4 file.
    @objc private func recordTapped() {
        guard let item = player.currentItem else { return }
        let duration = item.duration.seconds
        guard duration.isFinite, duration > 1 else {
            toast("Nothing to record yet")
            return
        }
        let now = player.currentTime().seconds
        // Record up to 60 seconds ending at the current position.
        let end = now
        let start = max(0, now - 60)
        let output = DownloadManager.shared.directory
            .appendingPathComponent("clip-\(Int(Date().timeIntervalSince1970)).mp4")

        guard let session = AVAssetExportSession(asset: item.asset, presetName: AVAssetExportPresetHighestQuality) else {
            toast("Recording is not supported for this stream")
            return
        }
        session.outputURL = output
        session.outputFileType = .mp4
        session.timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            end: CMTime(seconds: end, preferredTimescale: 600)
        )
        session.shouldOptimizeForNetworkUse = true

        session.exportAsynchronously { [weak self] in
            DispatchQueue.main.async {
                if session.status == .completed {
                    self?.toast("Clip saved")
                } else {
                    self?.toast("Could not record this stream")
                }
            }
        }
    }

    // MARK: - Helpers

    private func toast(_ message: String) {
        let label = UILabel()
        label.text = message
        label.textColor = .white
        label.font = Theme.body(14, weight: .semibold)
        label.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        label.textAlignment = .center
        label.layer.cornerRadius = 12
        label.clipsToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -90),
            label.heightAnchor.constraint(equalToConstant: 34),
            label.widthAnchor.constraint(greaterThanOrEqualToConstant: 160)
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
