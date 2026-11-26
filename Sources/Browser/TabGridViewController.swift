import UIKit
import WebKit

/// Grid tab switcher: normal + private sections, card close buttons,
/// swipe-left-to-close, grid search, and reopen.
final class TabGridViewController: UICollectionViewController {

    struct ClosedTab {
        let url: URL?
        let isPrivate: Bool
    }

    private let store: TabStore
    /// Highlighted card (violet border) — the browser's current tab.
    weak var activeTab: BrowserTab?
    private let onActivate: (BrowserTab) -> Void
    private let onNewTab: () -> Void
    private let onReopen: (ClosedTab) -> Void
    /// Called for every tab closed from the grid, so the browser can recover
    /// its active tab when the visible one is closed here.
    private let onClosed: (BrowserTab) -> Void
    private var searchController: UISearchController!
    /// Nil = all tabs; non-nil = filtered by the grid search field.
    private var filteredTabs: [BrowserTab]?
    private var sourceTabs: [BrowserTab] { filteredTabs ?? store.tabs }

    /// Normal tabs first, private tabs in their own section below.
    private var sections: [(title: String, tabs: [BrowserTab])] {
        var result: [(String, [BrowserTab])] = []
        let normal = sourceTabs.filter { !$0.isPrivate }
        let privateTabs = sourceTabs.filter { $0.isPrivate }
        if !normal.isEmpty || privateTabs.isEmpty { result.append(("Tabs", normal)) }
        if !privateTabs.isEmpty { result.append(("Private Tabs", privateTabs)) }
        return result
    }

    private func tab(at indexPath: IndexPath) -> BrowserTab {
        sections[indexPath.section].tabs[indexPath.item]
    }

    init(
        store: TabStore,
        activeTab: BrowserTab?,
        onActivate: @escaping (BrowserTab) -> Void,
        onNewTab: @escaping () -> Void,
        onReopen: @escaping (ClosedTab) -> Void,
        onClosed: @escaping (BrowserTab) -> Void
    ) {
        self.store = store
        self.activeTab = activeTab
        self.onActivate = onActivate
        self.onNewTab = onNewTab
        self.onReopen = onReopen
        self.onClosed = onClosed
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 12
        layout.minimumLineSpacing = 12
        layout.sectionInset = UIEdgeInsets(top: 12, left: 16, bottom: 80, right: 16)
        layout.headerReferenceSize = CGSize(width: 0, height: 30)
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
        collectionView.register(TabSectionHeader.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "header")
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "plus"), style: .plain, target: self, action: #selector(newTabTapped)
        )
        navigationItem.rightBarButtonItem?.accessibilityIdentifier = "new-tab"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Done", style: .done, target: self, action: #selector(doneTapped)
        )
        navigationItem.leftBarButtonItem?.accessibilityIdentifier = "tab-grid-done"
        // Grid search: filters cards by page title or URL.
        searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search tabs"
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        guard let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout else { return }
        let available = collectionView.bounds.width - layout.sectionInset.left - layout.sectionInset.right
        let columns = max(2, min(4, Int((available + layout.minimumInteritemSpacing) / 182)))
        let width = (available - layout.minimumInteritemSpacing * CGFloat(columns - 1)) / CGFloat(columns)
        let size = CGSize(width: width, height: max(180, width * 1.24))
        if layout.itemSize != size {
            layout.itemSize = size
            collectionView.collectionViewLayout.invalidateLayout()
        }
    }

    @objc private func newTabTapped() {
        onNewTab()
        dismiss(animated: true)
    }

    @objc private func doneTapped() {
        dismiss(animated: true)
    }

    override func numberOfSections(in collectionView: UICollectionView) -> Int {
        sections.count
    }

    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        sections[section].tabs.count
    }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! TabCardCell
        let tab = tab(at: indexPath)
        cell.configure(
            id: tab.id,
            title: tab.title,
            host: tab.displayURL?.host ?? "Start page",
            isPrivate: tab.isPrivate
        )
        cell.onClose = { [weak self] in self?.closeTab(tab) }
        cell.cardContent.onActivate = { [weak self] in self?.activate(tab) }
        // Violet border marks the browser's current tab.
        cell.isActive = tab === activeTab
        tab.webView.takeSnapshot(with: nil) { image, _ in
            if let image, collectionView.cellForItem(at: indexPath) === cell, cell.tabID == tab.id {
                cell.snapshotView.image = image
            }
        }
        return cell
    }

    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        activate(tab(at: indexPath))
    }

    private func activate(_ tab: BrowserTab) {
        onActivate(tab)
        dismiss(animated: true)
    }

    override func collectionView(
        _ collectionView: UICollectionView,
        viewForSupplementaryElementOfKind kind: String,
        at indexPath: IndexPath
    ) -> UICollectionReusableView {
        let header = collectionView.dequeueReusableSupplementaryView(
            ofKind: kind, withReuseIdentifier: "header", for: indexPath
        ) as! TabSectionHeader
        header.label.text = sections[indexPath.section].title
        return header
    }

    // Implemented without `override`: UICollectionViewController inherits
    // UICollectionViewDelegate conformance, optional methods are plain implementations.
    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        referenceSizeForHeaderInSection section: Int
    ) -> CGFloat {
        // Single "Tabs" section needs no label — cards explain themselves.
        (sections.count == 1 && sections[0].title == "Tabs") ? 0 : 30
    }

    private func closeTab(_ tab: BrowserTab) {
        onReopen(ClosedTab(url: tab.sessionURL, isPrivate: tab.isPrivate))
        store.close(tab)
        onClosed(tab)
        filteredTabs = filteredTabs?.filter { $0 !== tab }
        collectionView.reloadData()
    }

    override func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        let tab = tab(at: indexPath)
        return UIContextMenuConfiguration(actionProvider: { [weak self] _ in
            UIMenu(children: [
                UIAction(title: "Close Tab", image: UIImage(systemName: "xmark")) { _ in
                    self?.closeTab(tab)
                },
                UIAction(title: "Close All Tabs", image: UIImage(systemName: "xmark.circle"), attributes: .destructive) { [weak self] _ in
                    guard let self else { return }
                    let active = self.activeTab
                    let closedActive = active.map { item in self.store.tabs.contains { $0 === item } } ?? false
                    for item in self.store.tabs {
                        self.onReopen(ClosedTab(url: item.sessionURL, isPrivate: item.isPrivate))
                    }
                    self.store.closeAll()
                    if closedActive, let active {
                        self.onClosed(active)
                    }
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

/// Small caps section label above the card group.
final class TabSectionHeader: UICollectionReusableView {
    let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = Theme.headline(13, weight: .semibold)
        label.textColor = Theme.textSecondary
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

final class TabCardView: UIView {
    var onActivate: (() -> Void)?

    override func accessibilityActivate() -> Bool {
        guard let onActivate else { return false }
        onActivate()
        return true
    }
}

/// Card with snapshot, title, close button and left-swipe-to-close.
final class TabCardCell: UICollectionViewCell, UIGestureRecognizerDelegate {
    /// Swipeable, borderable card face (the grid draws active borders here).
    let cardContent = TabCardView()
    let snapshotView = UIImageView()
    let titleLabel = UILabel()
    let hostLabel = UILabel()
    let privateBadge = UIImageView(image: UIImage(systemName: "eye.slash.fill"))
    private let closeButton = UIButton(type: .system)
    private let swipeReveal = UIView()
    private let trashIcon = UIImageView(image: UIImage(systemName: "trash.fill"))
    private(set) var tabID: UUID?
    var onClose: (() -> Void)?
    var isActive = false {
        didSet { updateBorder() }
    }

    private func updateBorder() {
        cardContent.layer.borderWidth = isActive ? 2 : 1
        cardContent.layer.borderColor = (isActive
            ? Theme.primary
            : Theme.hairline).resolvedColor(with: traitCollection).cgColor
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        // Red reveal layer behind the card face.
        swipeReveal.backgroundColor = UIColor.systemRed.withAlphaComponent(0.92)
        swipeReveal.layer.cornerRadius = Theme.corner
        swipeReveal.layer.cornerCurve = .continuous
        swipeReveal.isHidden = true
        trashIcon.tintColor = .white
        trashIcon.contentMode = .center
        swipeReveal.addSubview(trashIcon)
        swipeReveal.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(swipeReveal)

        // Card face: holds everything that slides on swipe.
        cardContent.backgroundColor = Theme.card
        cardContent.layer.cornerRadius = Theme.corner
        cardContent.layer.cornerCurve = .continuous
        cardContent.layer.shadowColor = UIColor.black.cgColor
        cardContent.layer.shadowOpacity = 0.08
        cardContent.layer.shadowRadius = 8
        cardContent.layer.shadowOffset = CGSize(width: 0, height: 3)
        cardContent.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(cardContent)

        snapshotView.contentMode = .scaleAspectFill
        snapshotView.clipsToBounds = true
        snapshotView.backgroundColor = Theme.canvas
        snapshotView.translatesAutoresizingMaskIntoConstraints = false
        snapshotView.layer.cornerRadius = 12
        snapshotView.layer.cornerCurve = .continuous

        titleLabel.font = Theme.body(13, weight: .semibold)
        titleLabel.textColor = Theme.textPrimary
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 1
        hostLabel.font = Theme.body(11)
        hostLabel.textColor = Theme.textSecondary
        hostLabel.adjustsFontForContentSizeCategory = true
        hostLabel.numberOfLines = 1
        cardContent.isAccessibilityElement = true
        cardContent.accessibilityTraits = .button

        let textStack = UIStackView(arrangedSubviews: [titleLabel, hostLabel])
        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false

        privateBadge.tintColor = Theme.primary
        privateBadge.isHidden = true
        privateBadge.translatesAutoresizingMaskIntoConstraints = false

        // Floating ✕ on the snapshot's top-right corner.
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = Theme.textPrimary
        closeButton.backgroundColor = Theme.card
        closeButton.layer.cornerRadius = 22
        closeButton.layer.cornerCurve = .continuous
        closeButton.layer.shadowColor = UIColor.black.cgColor
        closeButton.layer.shadowOpacity = 0.15
        closeButton.layer.shadowRadius = 4
        closeButton.layer.shadowOffset = CGSize(width: 0, height: 1)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.accessibilityLabel = "Close tab"
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        isAccessibilityElement = false
        accessibilityElements = [cardContent, closeButton]

        cardContent.addSubview(snapshotView)
        cardContent.addSubview(textStack)
        cardContent.addSubview(privateBadge)
        cardContent.addSubview(closeButton)

        NSLayoutConstraint.activate([
            swipeReveal.topAnchor.constraint(equalTo: contentView.topAnchor),
            swipeReveal.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            swipeReveal.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            swipeReveal.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            cardContent.topAnchor.constraint(equalTo: contentView.topAnchor),
            cardContent.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            cardContent.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            cardContent.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            trashIcon.trailingAnchor.constraint(equalTo: swipeReveal.trailingAnchor, constant: -18),
            trashIcon.centerYAnchor.constraint(equalTo: swipeReveal.centerYAnchor),
            trashIcon.widthAnchor.constraint(equalToConstant: 22),
            trashIcon.heightAnchor.constraint(equalToConstant: 22),

            snapshotView.topAnchor.constraint(equalTo: cardContent.topAnchor, constant: 8),
            snapshotView.leadingAnchor.constraint(equalTo: cardContent.leadingAnchor, constant: 8),
            snapshotView.trailingAnchor.constraint(equalTo: cardContent.trailingAnchor, constant: -8),
            snapshotView.heightAnchor.constraint(equalTo: cardContent.heightAnchor, multiplier: 0.68),

            textStack.topAnchor.constraint(equalTo: snapshotView.bottomAnchor, constant: 6),
            textStack.leadingAnchor.constraint(equalTo: cardContent.leadingAnchor, constant: 10),
            textStack.trailingAnchor.constraint(equalTo: cardContent.trailingAnchor, constant: -10),

            privateBadge.topAnchor.constraint(equalTo: snapshotView.topAnchor, constant: 10),
            privateBadge.leadingAnchor.constraint(equalTo: snapshotView.leadingAnchor, constant: 10),
            privateBadge.widthAnchor.constraint(equalToConstant: 22),
            privateBadge.heightAnchor.constraint(equalToConstant: 22),

            closeButton.topAnchor.constraint(equalTo: snapshotView.topAnchor, constant: 1),
            closeButton.trailingAnchor.constraint(equalTo: snapshotView.trailingAnchor, constant: -1),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44)
        ])

        // Horizontal left-swipe on the card face reveals the red close zone;
        // vertical movement stays with the collection's scroll.
        let pan = UIPanGestureRecognizer(target: self, action: #selector(swiped(_:)))
        pan.delegate = self
        cardContent.addGestureRecognizer(pan)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if let pan = gestureRecognizer as? UIPanGestureRecognizer {
            let velocity = pan.velocity(in: self)
            return abs(velocity.x) > abs(velocity.y) && velocity.x < 0
        }
        return true
    }

    @objc private func closeTapped() { onClose?() }

    @objc private func swiped(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .changed:
            let offset = max(min(0, gesture.translation(in: self).x), -96)
            cardContent.transform = CGAffineTransform(translationX: offset, y: 0)
            swipeReveal.isHidden = false
        case .ended, .cancelled:
            let x = gesture.translation(in: self).x
            if x < -70 {
                onClose?()
            } else {
                let reset = { self.cardContent.transform = .identity }
                if UIAccessibility.isReduceMotionEnabled {
                    reset()
                } else {
                    UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0, options: []) {
                        reset()
                    }
                }
                swipeReveal.isHidden = true
            }
        default:
            break
        }
    }

    func configure(id: UUID, title: String, host: String?, isPrivate: Bool) {
        tabID = id
        titleLabel.text = title
        hostLabel.text = host ?? "Start page"
        privateBadge.isHidden = !isPrivate
        cardContent.accessibilityIdentifier = "tab-card-\(id.uuidString)"
        cardContent.accessibilityLabel = "\(isPrivate ? "Private tab. " : "")\(title). \(host ?? "Start page")"
        closeButton.accessibilityIdentifier = "tab-close-\(id.uuidString)"
        cardContent.transform = .identity
        swipeReveal.isHidden = true
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        tabID = nil
        snapshotView.image = nil
        onClose = nil
        cardContent.onActivate = nil
        isActive = false
        cardContent.transform = .identity
        swipeReveal.isHidden = true
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateBorder()
    }
}
