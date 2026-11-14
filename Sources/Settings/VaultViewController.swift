import PhotosUI
import UIKit

/// Private vault: media imported into the app sandbox, opened behind Face ID.
final class VaultStore {
    static let shared = VaultStore()

    private(set) var entries: [String] = []

    private let key = "magdy.vault.entries"

    var directory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Vault", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    init() {
        reload()
    }

    func reload() {
        let names = UserDefaults.standard.stringArray(forKey: key) ?? []
        entries = names.filter { FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path) }
    }

    func importItem(at source: URL) {
        let name = uniqueName(source.lastPathComponent)
        let destination = directory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.copyItem(at: source, to: destination)
            var names = UserDefaults.standard.stringArray(forKey: key) ?? []
            names.append(name)
            UserDefaults.standard.set(names, forKey: key)
            reload()
        } catch {
            // Ignore unreadable items.
        }
    }

    func remove(_ name: String) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        var names = UserDefaults.standard.stringArray(forKey: key) ?? []
        names.removeAll { $0 == name }
        UserDefaults.standard.set(names, forKey: key)
        reload()
    }

    func url(for name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    private func uniqueName(_ proposed: String) -> String {
        var candidate = proposed
        var counter = 1
        while FileManager.default.fileExists(atPath: directory.appendingPathComponent(candidate).path) {
            let ext = (proposed as NSString).pathExtension
            let base = (proposed as NSString).deletingPathExtension
            candidate = ext.isEmpty ? "\(base) (\(counter))" : "\(base) (\(counter)).\(ext)"
            counter += 1
        }
        return candidate
    }
}

/// Face-ID-gated grid of vault items, with import via the photo picker or Files.
final class VaultViewController: UICollectionViewController, PHPickerViewControllerDelegate {

    private let store = VaultStore.shared
    private var files: [String] = []

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
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        reload()
    }

    private func reload() {
        files = store.entries
        collectionView.reloadData()
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
        present(picker, animated: true)
    }

    // MARK: - PHPicker

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        for result in results {
            let provider = result.itemProvider
            let store = self.store
            if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async {
                        store.importItem(at: url)
                        self.reload()
                    }
                }
            } else if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { object, _ in
                    guard let image = object as? UIImage else { return }
                    DispatchQueue.main.async {
                        let name = "photo-\(Int(Date().timeIntervalSince1970)).png"
                        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
                        try? image.pngData()?.write(to: url)
                        store.importItem(at: url)
                        self.reload()
                    }
                }
            }
        }
    }

    // MARK: - Collection

    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        files.count
    }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! VaultCell
        cell.configure(url: store.url(for: files[indexPath.item]))
        return cell
    }

    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let url = store.url(for: files[indexPath.item])
        let preview = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        preview.completionWithItemsHandler = { _, _, _, _ in
            // Sharing hands the file out only while unlocked; nothing persists outside the sandbox.
        }
        present(preview, animated: true)
    }

    override func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        let name = files[indexPath.item]
        return UIContextMenuConfiguration(actionProvider: { _ in
            UIMenu(children: [
                UIAction(title: "Remove from Vault", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                    self?.store.remove(name)
                    self?.reload()
                }
            ])
        })
    }
}

import UniformTypeIdentifiers

extension VaultViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        for url in urls {
            store.importItem(at: url)
        }
        reload()
    }
}

final class VaultCell: UICollectionViewCell {
    let imageView = UIImageView()
    let label = UILabel()

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

    func configure(url: URL) {
        if (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType?.conforms(to: .movie)) == true {
            imageView.image = UIImage(systemName: "video.fill")
            imageView.tintColor = Theme.primary
            imageView.contentMode = .center
        } else {
            imageView.contentMode = .scaleAspectFill
            imageView.image = UIImage(contentsOfFile: url.path)
        }
        label.text = url.lastPathComponent
    }
}
