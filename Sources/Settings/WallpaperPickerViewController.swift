import UIKit

/// Grid of the bundled wallpapers for the start page.
final class WallpaperPickerViewController: UICollectionViewController {

    private let store = WallpaperStore.shared
    private var files: [String] = []

    init() {
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 150, height: 300)
        layout.minimumInteritemSpacing = 12
        layout.minimumLineSpacing = 12
        layout.sectionInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        super.init(collectionViewLayout: layout)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Wallpaper"
        files = WallpaperStore.available()

        collectionView.register(WallpaperCell.self, forCellWithReuseIdentifier: "cell")
        collectionView.backgroundColor = Theme.canvas
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: L.t("cancel"), style: .plain, target: self, action: #selector(closeTapped)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "None", style: .plain, target: self, action: #selector(clearTapped)
        )
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func clearTapped() {
        store.clear()
        dismiss(animated: true)
    }

    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        files.count
    }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! WallpaperCell
        let name = files[indexPath.item]
        if let url = Bundle.main.url(forResource: name, withExtension: nil, subdirectory: "Wallpapers"),
           let image = UIImage(contentsOfFile: url.path) {
            cell.imageView.image = image
        }
        cell.imageView.layer.borderWidth = name == store.selectedName ? 3 : 0
        cell.imageView.layer.borderColor = Theme.primary.cgColor
        return cell
    }

    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        store.selectedName = files[indexPath.item]
        _ = store.materialiseSelection()
        dismiss(animated: true)
    }
}

final class WallpaperCell: UICollectionViewCell {
    let imageView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = Theme.corner
        imageView.layer.cornerCurve = .continuous
        imageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
