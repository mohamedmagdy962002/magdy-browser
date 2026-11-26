import ImageIO
import PhotosUI
import UIKit
import UniformTypeIdentifiers

/// Private vault: media imported into the app sandbox, opened behind device-owner authentication.
final class VaultStore {
    static let shared = VaultStore()

    private(set) var entries: [String] = []

    private let key = "magdy.vault.entries"
    private let queue = DispatchQueue(label: "com.magdy.vault", qos: .utility)

    var directory: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PrivateVault", isDirectory: true)
    }

    init() {
        reload()
    }

    /// Reads and validates the manifest off the main thread, then publishes a UI snapshot.
    func reload(completion: (([String]) -> Void)? = nil) {
        queue.async {
            let names: [String]
            do {
                _ = try self.protectedDirectory()
                self.migrateLegacyItemsIfNeeded()
                names = try self.readNames()
            } catch {
                names = []
            }
            DispatchQueue.main.async {
                self.entries = names
                completion?(names)
            }
        }
    }

    /// Performs the copy on the caller's background queue. Returns false without
    /// leaving a partial destination when the import cannot be completed.
    @discardableResult
    func importItem(at source: URL) -> Bool {
        queue.sync { () -> Bool in
            guard source.isFileURL, self.isBasename(source.lastPathComponent) else { return false }
            do {
                let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true else { return false }
                let vault = try protectedDirectory()
                let name = try uniqueName(source.lastPathComponent, in: vault)
                let destination = vault.appendingPathComponent(name)
                var copied = false
                do {
                    try FileManager.default.copyItem(at: source, to: destination)
                    copied = true
                    try protect(destination)
                    var names = try readNames()
                    names.append(name)
                    UserDefaults.standard.set(names, forKey: key)
                    publish(names)
                    return true
                } catch {
                    if copied { try? FileManager.default.removeItem(at: destination) }
                    return false
                }
            } catch {
                return false
            }
        }
    }

    func remove(_ name: String, completion: (() -> Void)? = nil) {
        queue.async {
            if self.isBasename(name) {
                let destination = self.directory.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: destination.path) {
                    try? FileManager.default.removeItem(at: destination)
                }
                if let names = try? self.readNames() {
                    UserDefaults.standard.set(names, forKey: self.key)
                    self.publish(names)
                }
            }
            DispatchQueue.main.async { completion?() }
        }
    }

    func url(for name: String) -> URL? {
        isBasename(name) ? directory.appendingPathComponent(name) : nil
    }

    private func protectedDirectory() throws -> URL {
        let vault = directory
        try FileManager.default.createDirectory(
            at: vault,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        try protect(vault)
        return vault
    }

    private func protect(_ url: URL) throws {
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: url.path
        )
    }

    private func readNames() throws -> [String] {
        let stored = (UserDefaults.standard.stringArray(forKey: key) ?? []).filter { isBasename($0) }
        let diskURLs = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: []
        )
        let disk = diskURLs.filter { url in
            guard isBasename(url.lastPathComponent) else { return false }
            do {
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true else { return false }
                try protect(url)
                return true
            } catch {
                return false
            }
        }.map(\.lastPathComponent)

        let diskSet = Set(disk)
        let storedSet = Set(stored)
        var seen = Set<String>()
        let ordered = stored.filter { seen.insert($0).inserted && diskSet.contains($0) }
        let recovered = disk.filter { !storedSet.contains($0) }.sorted()
        let names = ordered + recovered
        UserDefaults.standard.set(names, forKey: key)
        return names
    }

    private func uniqueName(_ proposed: String, in vault: URL) throws -> String {
        var candidate = proposed
        var counter = 1
        while FileManager.default.fileExists(atPath: vault.appendingPathComponent(candidate).path) {
            let ext = (proposed as NSString).pathExtension
            let base = (proposed as NSString).deletingPathExtension
            candidate = ext.isEmpty ? "\(base) (\(counter))" : "\(base) (\(counter)).\(ext)"
            counter += 1
        }
        return candidate
    }

    private func isBasename(_ name: String) -> Bool {
        guard !name.isEmpty, name != ".", name != "..",
              !name.contains("/"), !name.contains("\\"), !name.utf8.contains(0),
              (name as NSString).pathComponents.count == 1,
              (name as NSString).lastPathComponent == name else { return false }
        return true
    }

    private func publish(_ names: [String]) {
        DispatchQueue.main.async { self.entries = names }
    }

    /// Moves readable files from the old shared Documents/Vault location into
    /// protected Library/PrivateVault. Invalid entries and symlinks are never followed.
    private func migrateLegacyItemsIfNeeded() {
        let manager = FileManager.default
        let legacy = manager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Vault", isDirectory: true)
        guard manager.fileExists(atPath: legacy.path), let vault = try? protectedDirectory() else { return }

        do {
            let sources = try manager.contentsOfDirectory(
                at: legacy,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                options: []
            )
            var names = (UserDefaults.standard.stringArray(forKey: key) ?? []).filter { isBasename($0) }
            for source in sources {
                let name = source.lastPathComponent
                guard isBasename(name) else { continue }
                let values: URLResourceValues
                do {
                    values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                } catch {
                    continue
                }
                guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
                let destinationName: String
                do {
                    destinationName = try uniqueName(name, in: vault)
                } catch {
                    continue
                }
                let destination = vault.appendingPathComponent(destinationName)
                do {
                    try manager.moveItem(at: source, to: destination)
                    do {
                        try protect(destination)
                    } catch {
                        try? manager.moveItem(at: destination, to: source)
                        continue
                    }
                    if !names.contains(destinationName) { names.append(destinationName) }
                    UserDefaults.standard.set(names, forKey: key)
                } catch {
                    // Keep the source in place if the move failed.
                }
            }
            if try manager.contentsOfDirectory(atPath: legacy.path).isEmpty {
                try manager.removeItem(at: legacy)
            }
        } catch {
            // A later reload can retry; no legacy path is used for new imports.
        }
    }
}

/// Device-owner-authenticated grid of vault items, with import via the photo picker or Files.
final class VaultViewController: UICollectionViewController, PHPickerViewControllerDelegate {

    private let store = VaultStore.shared
    private var files: [String] = []
    private var isUnlocked = false
    private var reloadGeneration = 0

    init() {
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 110, height: 110)
        layout.minimumInteritemSpacing = 10
        layout.minimumLineSpacing = 10
        layout.sectionInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        super.init(collectionViewLayout: layout)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Private Vault"
        collectionView.register(VaultCell.self, forCellWithReuseIdentifier: "cell")
        collectionView.backgroundColor = Theme.canvas
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "plus"), style: .plain, target: self, action: #selector(importTapped)
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(protectBeforeBackground), name: UIApplication.willResignActiveNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func markUnlocked() {
        isUnlocked = true
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if isUnlocked {
            reload()
        } else {
            authenticateVault()
        }
    }

    private func reload() {
        guard isUnlocked else { return }
        reloadGeneration &+= 1
        let generation = reloadGeneration
        store.reload { [weak self] names in
            guard let self, self.isUnlocked, generation == self.reloadGeneration else { return }
            self.files = names
            self.collectionView.reloadData()
        }
    }

    @objc private func protectBeforeBackground() {
        guard isViewLoaded, view.window != nil else { return }
        reloadGeneration &+= 1
        isUnlocked = false
        files.removeAll()
        collectionView.reloadData()
        authenticateVault()
    }

    @objc private func handleDidEnterBackground() {
        protectBeforeBackground()
    }

    @objc private func handleWillEnterForeground() {
        guard isViewLoaded, view.window != nil, !isUnlocked else { return }
        authenticateVault()
    }

    private func authenticateVault() {
        let presenter = view.window?.rootViewController ?? navigationController ?? self
        AppLock.gate(
            viewController: presenter,
            reason: "Unlock your Private Vault",
            onCancelled: { [weak self] in
                self?.navigationController?.dismiss(animated: true)
            },
            onUnlocked: { [weak self] in
                self?.isUnlocked = true
                self?.reload()
            }
        )
    }

    @objc private func importTapped() {
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Photo Library", style: .default) { [weak self] _ in
            self?.openPhotoPicker()
        })
        sheet.addAction(UIAlertAction(title: "Files", style: .default) { [weak self] _ in
            self?.openFilePicker()
        })
        sheet.addAction(UIAlertAction(title: L.t("cancel"), style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.barButtonItem = navigationItem.leftBarButtonItem
        }
        present(sheet, animated: true)
    }

    private func openPhotoPicker() {
        var config = PHPickerConfiguration()
        config.filter = PHPickerFilter.any(of: [.images, .videos])
        config.selectionLimit = 0
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }

    private func openFilePicker() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.image, .movie, .audio], asCopy: true)
        picker.delegate = self
        if let popover = picker.popoverPresentationController {
            popover.barButtonItem = navigationItem.leftBarButtonItem
            popover.sourceRect = view.bounds
            popover.sourceView = view
        }
        present(picker, animated: true)
    }

    // MARK: - PHPicker

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        for result in results {
            let provider = result.itemProvider
            if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { [weak self] url, _ in
                    guard let self, let url else { return }
                    let staged = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString + "." + url.pathExtension)
                    do {
                        try FileManager.default.copyItem(at: url, to: staged)
                    } catch {
                        return
                    }
                    DispatchQueue.global(qos: .utility).async {
                        self.finishImport(at: staged, removeSourceWhenDone: true)
                    }
                }
            } else if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
                    guard let self, let image = object as? UIImage else { return }
                    DispatchQueue.global(qos: .utility).async {
                        let staged = FileManager.default.temporaryDirectory
                            .appendingPathComponent("photo-\(UUID().uuidString).png")
                        defer { try? FileManager.default.removeItem(at: staged) }
                        guard let data = image.pngData(),
                              (try? data.write(to: staged, options: .atomic)) != nil else { return }
                        self.finishImport(at: staged, removeSourceWhenDone: false)
                    }
                }
            }
        }
    }

    /// Called only from a background queue. Provider staging files are always removed.
    private func finishImport(at source: URL, removeSourceWhenDone: Bool) {
        let imported = store.importItem(at: source)
        if removeSourceWhenDone {
            try? FileManager.default.removeItem(at: source)
        }
        DispatchQueue.main.async { [weak self] in
            if imported { self?.reload() }
        }
    }

    // MARK: - Collection

    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        files.count
    }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! VaultCell
        if let url = store.url(for: files[indexPath.item]) {
            cell.configure(url: url)
        }
        return cell
    }

    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let url = store.url(for: files[indexPath.item]) else { return }
        let preview = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        preview.completionWithItemsHandler = { _, _, _, _ in
            // Sharing hands the file out only while unlocked; nothing persists outside the sandbox.
        }
        if let popover = preview.popoverPresentationController {
            popover.sourceView = collectionView.cellForItem(at: indexPath) ?? collectionView
            popover.sourceRect = popover.sourceView?.bounds ?? collectionView.bounds
        }
        present(preview, animated: true)
    }

    override func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        let name = files[indexPath.item]
        return UIContextMenuConfiguration(actionProvider: { _ in
            UIMenu(children: [
                UIAction(title: "Remove from Vault", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                    self?.store.remove(name) { [weak self] in self?.reload() }
                }
            ])
        })
    }
}

extension VaultViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        for url in urls {
            DispatchQueue.global(qos: .utility).async { [weak self] in
                guard let self else { return }
                let hasAccess = url.startAccessingSecurityScopedResource()
                defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
                self.finishImport(at: url, removeSourceWhenDone: false)
            }
        }
    }
}

final class VaultCell: UICollectionViewCell {
    let imageView = UIImageView()
    let label = UILabel()
    private var loadToken = UUID()

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = Theme.corner
        imageView.layer.cornerCurve = .continuous
        imageView.translatesAutoresizingMaskIntoConstraints = false
        label.font = Theme.body(10)
        label.textColor = Theme.textSecondary
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(imageView)
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.heightAnchor.constraint(equalTo: contentView.heightAnchor, multiplier: 0.78),
            label.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 4),
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func prepareForReuse() {
        super.prepareForReuse()
        loadToken = UUID()
        imageView.image = nil
        label.text = nil
    }

    func configure(url: URL) {
        loadToken = UUID()
        let token = loadToken
        label.text = url.lastPathComponent
        imageView.image = UIImage(systemName: "photo")
        imageView.tintColor = Theme.textSecondary
        imageView.contentMode = .center

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let isMovie = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType?.conforms(to: .movie)) == true
            let thumbnail = isMovie ? nil : Self.thumbnail(at: url)
            DispatchQueue.main.async {
                guard let self, self.loadToken == token else { return }
                if isMovie {
                    self.imageView.image = UIImage(systemName: "video.fill")
                    self.imageView.tintColor = Theme.primary
                    self.imageView.contentMode = .center
                } else if let thumbnail {
                    self.imageView.image = thumbnail
                    self.imageView.tintColor = nil
                    self.imageView.contentMode = .scaleAspectFill
                } else {
                    self.imageView.image = UIImage(systemName: "doc.fill")
                    self.imageView.tintColor = Theme.textSecondary
                    self.imageView.contentMode = .center
                }
            }
        }
    }

    private static func thumbnail(at url: URL) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: 220,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}
