import UIKit

/// Media tools for files in the Downloads folder: MP3 tag editing and video upscaling.
final class MediaToolsViewController: UITableViewController {
    private var files: [URL] = []

    private static let audioExtensions = ["mp3", "m4a", "aac", "wav", "flac", "m4b"]
    private static let videoExtensions = ["mp4", "mov", "m4v", "webm", "mkv"]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Media Tools"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Refresh", style: .plain, target: self, action: #selector(refresh)
        )
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
        content.secondaryText = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let url = files[indexPath.row]
        let ext = url.pathExtension.lowercased()

        if Self.audioExtensions.contains(ext) {
            navigationController?.pushViewController(TagEditorViewController(url: url), animated: true)
        } else {
            navigationController?.pushViewController(UpscaleViewController(url: url), animated: true)
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        files.isEmpty ? "Downloaded audio and video files show up here." : nil
    }
}
