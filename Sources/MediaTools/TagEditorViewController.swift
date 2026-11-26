import PhotosUI
import UIKit

/// Edits the ID3 metadata of an audio file (title, artist, album, year, genre, track, comment, artwork).
final class TagEditorViewController: UIViewController {

    private let url: URL
    private var tag = ID3Tag()
    private var artworkData: Data?
    private var artworkMimeType = "image/jpeg"
    private let writeQueue = DispatchQueue(label: "com.magdy.id3.write", qos: .utility)

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let artworkView = UIImageView()
    private var fields: [String: UITextField] = [:]

    init(url: URL) {
        self.url = url
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Edit Tags"
        view.backgroundColor = .systemGroupedBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .save, target: self, action: #selector(save)
        )
        buildForm()
        loadTag()
    }

    // MARK: - Form

    private func buildForm() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        let card = UIStackView()
        card.axis = .vertical
        card.spacing = 12
        card.backgroundColor = .secondarySystemGroupedBackground
        card.layer.cornerRadius = 14
        card.isLayoutMarginsRelativeArrangement = true
        card.layoutMargins = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

        for (key, placeholder) in [
            ("title", "Title"), ("artist", "Artist"), ("album", "Album"),
            ("year", "Year"), ("genre", "Genre"), ("track", "Track"), ("comment", "Comment")
        ] {
            card.addArrangedSubview(makeRow(key: key, placeholder: placeholder))
        }

        artworkView.contentMode = .scaleAspectFill
        artworkView.clipsToBounds = true
        artworkView.layer.cornerRadius = 8
        artworkView.backgroundColor = .tertiarySystemFill
        artworkView.translatesAutoresizingMaskIntoConstraints = false
        artworkView.heightAnchor.constraint(equalToConstant: 96).isActive = true
        artworkView.widthAnchor.constraint(equalToConstant: 96).isActive = true

        let artworkButton = UIButton(type: .system)
        artworkButton.setTitle("Choose artwork", for: .normal)
        artworkButton.addTarget(self, action: #selector(pickArtwork), for: .touchUpInside)

        let artworkRow = UIStackView(arrangedSubviews: [artworkView, artworkButton])
        artworkRow.axis = .horizontal
        artworkRow.spacing = 16
        artworkRow.alignment = .center
        card.addArrangedSubview(artworkRow)

        stack.addArrangedSubview(card)
        scrollView.addSubview(stack)
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -16)
        ])
    }

    private func makeRow(key: String, placeholder: String) -> UIStackView {
        let label = UILabel()
        label.text = placeholder
        label.font = .systemFont(ofSize: 15)
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.widthAnchor.constraint(equalToConstant: 90).isActive = true

        let field = UITextField()
        field.placeholder = placeholder
        field.borderStyle = .roundedRect
        field.autocorrectionType = .no
        field.clearButtonMode = .whileEditing
        fields[key] = field

        let row = UIStackView(arrangedSubviews: [label, field])
        row.axis = .horizontal
        row.spacing = 12
        return row
    }

    // MARK: - Data

    private func loadTag() {
        do {
            tag = try ID3.read(from: url)
        } catch {
            tag = ID3Tag()
        }
        artworkMimeType = tag.artworkMimeType
        fields["title"]?.text = tag.title
        fields["artist"]?.text = tag.artist
        fields["album"]?.text = tag.album
        fields["year"]?.text = tag.year
        fields["genre"]?.text = tag.genre
        fields["track"]?.text = tag.track
        fields["comment"]?.text = tag.comment

        if let data = tag.artwork, let image = UIImage(data: data) {
            artworkData = data
            artworkView.image = image
        }
    }

    @objc private func pickArtwork() {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }

    @objc private func save() {
        var updated = ID3Tag()
        updated.title = fields["title"]?.text ?? ""
        updated.artist = fields["artist"]?.text ?? ""
        updated.album = fields["album"]?.text ?? ""
        updated.year = fields["year"]?.text ?? ""
        updated.genre = fields["genre"]?.text ?? ""
        updated.track = fields["track"]?.text ?? ""
        updated.comment = fields["comment"]?.text ?? ""
        updated.artwork = artworkData
        updated.artworkMimeType = artworkMimeType
        let targetURL = url
        navigationItem.rightBarButtonItem?.isEnabled = false

        writeQueue.async { [weak self] in
            var failure: Error?
            do {
                try ID3.write(updated, to: targetURL)
            } catch {
                failure = error
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.navigationItem.rightBarButtonItem?.isEnabled = true
                if let failure {
                    self.showAlert(title: "Failed", message: failure.localizedDescription)
                } else {
                    self.showAlert(title: "Saved", message: "Tags written to \(targetURL.lastPathComponent).")
                }
            }
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - Artwork picker

extension TagEditorViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        dismiss(animated: true)
        guard let provider = results.first?.itemProvider else { return }
        provider.loadDataRepresentation(forTypeIdentifier: "public.image") { [weak self] data, _ in
            guard let data, let image = UIImage(data: data) else { return }
            let resized = self?.resize(image, maxDimension: 700)
            guard let resized, let jpeg = resized.jpegData(compressionQuality: 0.85) else { return }
            DispatchQueue.main.async {
                self?.artworkData = jpeg
                self?.artworkMimeType = "image/jpeg"
                self?.artworkView.image = resized
            }
        }
    }

    private func resize(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension else { return image }
        let ratio = maxDimension / longest
        let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
