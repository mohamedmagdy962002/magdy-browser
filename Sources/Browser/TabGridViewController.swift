import UIKit
import WebKit

/// Grid tab switcher with live page snapshots, close actions and reopen.
final class TabGridViewController: UICollectionViewController {

    struct ClosedTab {
        let url: URL?
        let isPrivate: Bool
    }

    private let store: TabStore
    private let onActivate: (BrowserTab) -> Void
    private let onNewTab: () -> Void
    private let onReopen: (ClosedTab) -> Void
    /// Called for every tab closed from the grid, so the browser can recover
    /// its active tab when the visible one is closed here.
    private let onClosed: (BrowserTab) -> Void
    private var searchController: UISearchController!
    /// Nil = all tabs; non-nil = filtered by the grid search field.
    private var filteredTabs: [BrowserTab]?
    private var visibleTabs: [BrowserTab] { filteredTabs ?? store.tabs }

    init(
        store: TabStore,
        onActivate: @escaping (BrowserTab) -> Void,
        onNewTab: @escaping () -> Void,
        onReopen: @escaping (ClosedTab) -> Void,
        onClosed: @escaping (BrowserTab) -> Void
    ) {
        self.store = store
        self.onActivate = onActivate
        self.onNewTab = onNewTab
        self.onReopen = onReopen
        self.onClosed = onClosed
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 170, height: 210)
        layout.minimumInteritemSpacing = 12
        layout.minimumLineSpacing = 12
        layout.sectionInset = UIEdgeInsets(top: 16, left: 16, bottom: 80, right: 16)
        super.init(collectionViewLayout: layout)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Tabs"
        collectionView.backgroundColor = Theme.canvas
        collectionView.alwaysBounceVertical = true
        collectionView.register(TabCardCell.self, forCellWithReuseIdentifier: "cell")
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "plus"), style: .plain, target: self, action: #selector(newTabTapped)
        )
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Done", style: .done, target: self, action: #selector(doneTapped)
        )
        // Grid search: filters cards by page title or URL.
        searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search tabs"
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
    }

    @objc private func newTabTapped() {
        onNewTab()
        dismiss(animated: true)
    }

    @objc private func doneTapped() {
        dismiss(animated: true)
    }

    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        visibleTabs.count
    }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! TabCardCell
        let tab = visibleTabs[indexPath.item]
        cell.titleLabel.text = tab.title
        cell.hostLabel.text = tab.displayURL?.host ?? "Start page"
        cell.setPrivate(tab.isPrivate)
        tab.webView.takeSnapshot(with: nil) { image, _ in
            if let image, collectionView.cellForItem(at: indexPath) === cell {
                cell.snapshotView.image = image
            }
        }
        return cell
    }

    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        onActivate(visibleTabs[indexPath.item])
        dismiss(animated: true)
    }

    // Implemented without `override`: UICollectionViewController inherits
    // UICollectionViewDelegate conformance, optional methods are plain implementations.
    func collectionView(
        _ collectionView: UICollectionView,
        trailingSwipeActionsConfigurationForItemAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let tab = visibleTabs[indexPath.item]
        let close = UIContextualAction(style: .destructive, title: "Close") { [weak self] _, _, completion in
            guard let self else { return }
            self.onReopen(ClosedTab(url: tab.displayURL, isPrivate: tab.isPrivate))
            self.store.close(tab)
            self.onClosed(tab)
            self.filteredTabs = self.filteredTabs?.filter { $0 !== tab }
            collectionView.reloadData()
            completion(true)
        }
        return UISwipeActionsConfiguration(actions: [close])
    }

    override func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        let tab = visibleTabs[indexPath.item]
        return UIContextMenuConfiguration(actionProvider: { _ in
            UIMenu(children: [
                UIAction(title: "Close Tab", image: UIImage(systemName: "xmark")) { [weak self] _ in
                    guard let self else { return }
                    self.onReopen(ClosedTab(url: tab.displayURL, isPrivate: tab.isPrivate))
                    self.store.close(tab)
                    self.onClosed(tab)
                    self.filteredTabs = self.filteredTabs?.filter { $0 !== tab }
                    collectionView.reloadData()
                },
                UIAction(title: "Close All Tabs", image: UIImage(systemName: "xmark.circle"), attributes: .destructive) { [weak self] _ in
                    guard let self else { return }
                    for item in self.store.tabs {
                        self.onReopen(ClosedTab(url: item.displayURL, isPrivate: item.isPrivate))
                        self.onClosed(item)
                    }
                    self.store.closeAll()
                    self.filteredTabs = nil
                    collectionView.reloadData()
                }
            ])
        })
    }
}

extension TabGridViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        let text = (searchController.searchBar.text ?? "").lowercased()
        filteredTabs = text.isEmpty ? nil : store.tabs.filter { tab in
            tab.title.lowercased().contains(text)
                || tab.displayURL?.absoluteString.lowercased().contains(text) == true
        }
        collectionView.reloadData()
    }
}

final class TabCardCell: UICollectionViewCell {
    let snapshotView = UIImageView()
    let titleLabel = UILabel()
    let hostLabel = UILabel()
    let privateBadge = UIImageView(image: UIImage(systemName: "eye.slash.fill"))

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = Theme.card
        layer.cornerRadius = Theme.corner
        layer.cornerCurve = .continuous
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.08
        layer.shadowRadius = 8
        layer.shadowOffset = CGSize(width: 0, height: 3)

        snapshotView.contentMode = .scaleAspectFill
        snapshotView.clipsToBounds = true
        snapshotView.backgroundColor = Theme.canvas
        snapshotView.translatesAutoresizingMaskIntoConstraints = false
        snapshotView.layer.cornerRadius = 12
        snapshotView.layer.cornerCurve = .continuous

        titleLabel.font = Theme.body(13, weight: .semibold)
        titleLabel.textColor = Theme.textPrimary
        titleLabel.numberOfLines = 1
        hostLabel.font = Theme.body(11)
        hostLabel.textColor = Theme.textSecondary
        hostLabel.numberOfLines = 1
        privateBadge.tintColor = Theme.primary
        privateBadge.isHidden = true
        privateBadge.translatesAutoresizingMaskIntoConstraints = false

        let textStack = UIStackView(arrangedSubviews: [titleLabel, hostLabel])
        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(snapshotView)
        contentView.addSubview(textStack)
        contentView.addSubview(privateBadge)
        NSLayoutConstraint.activate([
            snapshotView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            snapshotView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            snapshotView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            snapshotView.heightAnchor.constraint(equalTo: contentView.heightAnchor, multiplier: 0.68),

            textStack.topAnchor.constraint(equalTo: snapshotView.bottomAnchor, constant: 6),
            textStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
            textStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),

            privateBadge.topAnchor.constraint(equalTo: snapshotView.topAnchor, constant: 6),
            privateBadge.trailingAnchor.constraint(equalTo: snapshotView.trailingAnchor, constant: -6)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setPrivate(_ isPrivate: Bool) {
        privateBadge.isHidden = !isPrivate
    }
}
