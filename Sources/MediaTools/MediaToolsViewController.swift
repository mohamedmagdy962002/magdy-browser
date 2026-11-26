import UIKit

/// Media tools for files in the Downloads folder: MP3 tag editing and video upscaling.
final class MediaToolsViewController: UITableViewController {
    private var files: [URL] = []

    private static let audioExtensions = ["mp3", "m4a", "aac", "wav", "flac", "m4b"]
    private static let videoExtensions = ["mp4", "mov", "m4v", "webm", "mkv"]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L.t("media")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.backgroundColor = Theme.canvas
        tableView.separatorStyle = .none
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Refresh", style: .plain, target: self, action: #selector(refresh)
        )
        buildHeader()
    }

    /// Gradient call-to-action card from the Stitch design.
    private func buildHeader() {
        let header = UIView(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: 132))

        let card = UIView()
        card.backgroundColor = Theme.primary
        card.layer.cornerRadius = Theme.corner
        card.layer.cornerCurve = .continuous
        card.translatesAutoresizingMaskIntoConstraints = false
        Theme.fabShadow(card)

        let titleLabel = UILabel()
        titleLabel.text = "Video Downloader"
        titleLabel.textColor = .white
        titleLabel.font = Theme.headline(20, weight: .bold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let subtitleLabel = UILabel()
        subtitleLabel.text = "Paste any page link to pull the video"
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.85)
        subtitleLabel.font = Theme.body(14)
        subtitleLabel.numberOfLines = 2
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        let chevron = UIImageView(image: UIImage(systemName: "arrow.down.circle.fill"))
        chevron.tintColor = .white
        chevron.contentMode = .scaleAspectFit
        chevron.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(titleLabel)
        card.addSubview(subtitleLabel)
        card.addSubview(chevron)
        header.addSubview(card)

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: header.topAnchor, constant: 12),
            card.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            card.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16),
            card.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -12),
            card.heightAnchor.constraint(equalToConstant: 92),

            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -12),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -12),

            chevron.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            chevron.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 28),
            chevron.heightAnchor.constraint(equalToConstant: 28)
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(openDownloader))
        card.addGestureRecognizer(tap)
        card.isUserInteractionEnabled = true

        tableView.tableHeaderView = header
    }

    @objc private func openDownloader() {
        let controller = VideoDownloaderViewController()
        let navigation = UINavigationController(rootViewController: controller)
        if let sheet = navigation.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
        }
        present(navigation, animated: true)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Only resize when needed — reassigning tableHeaderView every layout pass
        // loops forever on UITableViewController (reassign re-triggers layout).
        if let header = tableView.tableHeaderView, header.frame.size.height != 132 {
            header.frame.size.height = 132
            tableView.tableHeaderView = header
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refresh()
    }

    @objc private func refresh() {
        let directory = DownloadManager.shared.directory
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        files = contents
            .filter {
                let ext = $0.pathExtension.lowercased()
                return Self.audioExtensions.contains(ext) || Self.videoExtensions.contains(ext)
            }
            .sorted {
                let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left > right
            }
        tableView.reloadData()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        files.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let url = files[indexPath.row]
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0

        var content = cell.defaultContentConfiguration()
        content.text = url.lastPathComponent
        content.textProperties.font = Theme.body(15, weight: .semibold)
        content.secondaryText = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
        content.secondaryTextProperties.color = Theme.textSecondary
        cell.contentConfiguration = content
        cell.backgroundColor = Theme.card
        cell.layer.cornerRadius = Theme.corner
        cell.layer.cornerCurve = .continuous
        cell.selectionStyle = .none
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let url = files[indexPath.row]
        let ext = url.pathExtension.lowercased()

        if ext == "mp3" {
            navigationController?.pushViewController(TagEditorViewController(url: url), animated: true)
        } else if Self.videoExtensions.contains(ext) {
            navigationController?.pushViewController(UpscaleViewController(url: url), animated: true)
        } else {
            let player = VideoPlayerController(url: url, title: url.lastPathComponent, isLocal: true)
            player.modalPresentationStyle = .fullScreen
            present(player, animated: true)
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        files.isEmpty ? "Downloaded audio and video files show up here." : nil
    }
}
