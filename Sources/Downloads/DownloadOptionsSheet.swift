import UIKit
import AVFoundation

/// Stitch-styled sheet shown before a download starts: file name, resolution
/// (HLS variants when available) and destination folder.
final class DownloadOptionsSheet: UIViewController {

    private let url: URL
    private let referer: URL?
    private let cookies: [HTTPCookie]
    private var isHLS: Bool

    private let nameField = UITextField()
    private let chipsRow = UIScrollView()
    private var chips: [UIButton] = []
    private var chipURLs: [URL?] = []
    /// nil = "Best" (highest quality).
    private var selected: URL?
    private let folderButton = UIButton(type: .system)
    private let startButton = UIButton(type: .system)

    init(url: URL, referer: URL?, cookies: [HTTPCookie]) {
        self.url = url
        self.referer = referer
        self.cookies = cookies
        self.isHLS = url.pathExtension.lowercased() == "m3u8" || url.absoluteString.contains(".m3u8")
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Entry point used by the player and the link context menu.
    static func present(
        url: URL, referer: URL?, cookies: [HTTPCookie],
        presenter: UIViewController, defaultName: String? = nil
    ) {
        let sheet = DownloadOptionsSheet(url: url, referer: referer, cookies: cookies)
        let nav = UINavigationController(rootViewController: sheet)
        if let page = nav.sheetPresentationController {
            page.detents = [.medium(), .large()]
            page.prefersGrabberVisible = true
        }
        presenter.present(nav, animated: true)
        sheet.setup(defaultName: defaultName)
    }

    // MARK: - UI

    private func setup(defaultName: String?) {
        view.backgroundColor = Theme.canvas
        title = "Download"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close, target: self, action: #selector(closeTapped)
        )

        nameField.text = defaultName?.isEmpty == false ? defaultName : DownloadOptionsSheet.suggestedName(url)
        nameField.font = Theme.body(15)
        nameField.textColor = Theme.textPrimary
        nameField.backgroundColor = Theme.card
        nameField.layer.cornerRadius = Theme.cornerSmall
        nameField.layer.borderWidth = 1
        nameField.layer.borderColor = Theme.hairline.cgColor
        nameField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 1))
        nameField.leftViewMode = .always

        let nameLabel = sectionLabel("File name")
        let resolutionLabel = sectionLabel("Resolution")
        chipsRow.showsHorizontalScrollIndicator = false
        chipsRow.translatesAutoresizingMaskIntoConstraints = false

        let folderLabel = sectionLabel("Save to")
        folderButton.setTitle(DownloadManager.shared.folderDisplayName(), for: .normal)
        folderButton.titleLabel?.font = Theme.body(14, weight: .semibold)
        folderButton.setTitleColor(Theme.primary, for: .normal)
        folderButton.setImage(UIImage(systemName: "folder"), for: .normal)
        folderButton.tintColor = Theme.primary
        folderButton.imageEdgeInsets = UIEdgeInsets(top: 0, left: -6, bottom: 0, right: 4)
        folderButton.addTarget(self, action: #selector(chooseFolderTapped), for: .touchUpInside)
        let folderRow = UIStackView(arrangedSubviews: [UIView(), folderButton])
        folderRow.axis = .horizontal

        startButton.setTitle("Start Download", for: .normal)
        startButton.setTitleColor(.white, for: .normal)
        startButton.titleLabel?.font = Theme.headline(16, weight: .semibold)
        startButton.layer.cornerRadius = 16
        startButton.layer.cornerCurve = .continuous
        startButton.translatesAutoresizingMaskIntoConstraints = false
        startButton.heightAnchor.constraint(equalToConstant: 50).isActive = true
        // Solid periwinkle — the gradient helper sized to zero bounds and left
        // the button invisible on this sheet.
        startButton.backgroundColor = Theme.primary
        Theme.fabShadow(startButton)
        startButton.addTarget(self, action: #selector(startTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [
            nameLabel, nameField, resolutionLabel, chipsRow, folderLabel, folderRow, startButton
        ])
        stack.axis = .vertical
        stack.spacing = 10
        stack.setCustomSpacing(16, after: resolutionLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Theme.gutter),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Theme.gutter),
            startButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            chipsRow.heightAnchor.constraint(equalToConstant: 44)
        ])

        loadResolutions()
    }

    private func sectionLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = Theme.headline(13, weight: .semibold)
        label.textColor = Theme.textSecondary
        return label
    }

    private static func suggestedName(_ url: URL) -> String {
        let base = url.lastPathComponent
        let cleaned = base.isEmpty || base == "/" ? "video.mp4" : base
        return cleaned.contains("?") ? String(cleaned.split(separator: "?")[0]) : cleaned
    }

    // MARK: - Resolutions

    private func loadResolutions() {
        func addBest() {
            addChips([("Best quality", nil)])
        }
        guard isHLS else {
            addBest()
            return
        }
        HLSDownloader.variants(playlist: url, cookies: cookies, referer: referer) { [weak self] options in
            DispatchQueue.main.async {
                guard let self else { return }
                if options.isEmpty {
                    addBest()
                } else {
                    self.addChips([("Best quality", nil)] + options.map { ($0.label, $0.url) })
                }
            }
        }
    }

    private func addChips(_ options: [(String, URL?)]) {
        for chip in chips { chip.removeFromSuperview() }
        chips.removeAll()
        chipURLs = options.map { $0.1 }
        var previous: UIButton?
        for (index, option) in options.enumerated() {
            let chip = UIButton(type: .system)
            chip.setTitle(option.0, for: .normal)
            chip.titleLabel?.font = Theme.body(13, weight: .semibold)
            chip.layer.cornerRadius = 14
            chip.layer.borderWidth = 1
            chip.contentEdgeInsets = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
            chip.tag = index
            chip.addTarget(self, action: #selector(chipTapped(_:)), for: .touchUpInside)
            chipsRow.addSubview(chip)
            chip.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                chip.topAnchor.constraint(equalTo: chipsRow.topAnchor),
                chip.bottomAnchor.constraint(equalTo: chipsRow.bottomAnchor),
                chip.leadingAnchor.constraint(
                    equalTo: previous?.trailingAnchor ?? chipsRow.leadingAnchor, constant: previous == nil ? 0 : 8
                )
            ])
            if index == 0 { select(chip) }
            chips.append(chip)
            previous = chip
        }
        if let last = previous {
            last.trailingAnchor.constraint(equalTo: chipsRow.trailingAnchor, constant: -8).isActive = true
        }
    }

    @objc private func chipTapped(_ sender: UIButton) {
        select(sender)
    }

    private func select(_ chip: UIButton) {
        selected = chipURLs[chip.tag]
        for other in chips {
            other.backgroundColor = Theme.card
            other.setTitleColor(Theme.textPrimary, for: .normal)
            other.layer.borderColor = Theme.hairline.cgColor
        }
        chip.backgroundColor = Theme.primary
        chip.setTitleColor(.white, for: .normal)
        chip.layer.borderColor = UIColor.clear.cgColor
    }

    // MARK: - Actions

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func chooseFolderTapped() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.delegate = self
        present(picker, animated: true)
    }

    @objc private func startTapped() {
        let raw = nameField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = raw.isEmpty ? DownloadOptionsSheet.suggestedName(url) : raw
        let target = selected ?? url
        let isVariant = selected != nil
        if isVariant || isHLS {
            DownloadManager.shared.startHLS(url: target, referer: referer, cookies: cookies, fileName: name)
        } else {
            DownloadManager.shared.start(url: target, referer: referer, cookies: cookies, fileName: name)
        }
        dismiss(animated: true)
    }
}

extension DownloadOptionsSheet: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let folder = urls.first else { return }
        let hasAccess = folder.startAccessingSecurityScopedResource()
        defer { if hasAccess { folder.stopAccessingSecurityScopedResource() } }
        do {
            let bookmark = try folder.bookmarkData(options: .minimalBookmark)
            UserDefaults.standard.set(bookmark, forKey: DownloadManager.folderBookmarkKey)
            UserDefaults.standard.set(folder.lastPathComponent, forKey: DownloadManager.folderBookmarkKey + ".name")
            folderButton.setTitle(folder.lastPathComponent, for: .normal)
        } catch {
            folderButton.setTitle("Downloads", for: .normal)
        }
    }
}
