import UIKit

enum StartDashboardSection: Hashable {
    case ready, downloads, favorites, recent, empty

    var title: String {
        switch self {
        case .ready: return L.t("dashboard_ready_to_play")
        case .downloads: return L.t("dashboard_active_downloads")
        case .favorites: return L.t("favorites")
        case .recent: return L.t("dashboard_recent_activity")
        case .empty: return ""
        }
    }
}

final class StartDashboardViewController: UIViewController, UICollectionViewDelegate {
    private enum Item: Hashable {
        case library(LibraryItem.Identity)
        case empty
    }

    private typealias DataSource = UICollectionViewDiffableDataSource<StartDashboardSection, Item>

    private static let headerKind = "start-dashboard-header"
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: Self.makeLayout())
    private lazy var dataSource = makeDataSource()
    private lazy var aggregator = LibraryAggregator()
    private let wallpaper = UIImageView()
    private let scrim = UIView()
    private let dateFormatter = DateFormatter()
    private var itemsByID: [LibraryItem.Identity: LibraryItem] = [:]
    private var isPrivate = false

    var onSearch: (() -> Void)?
    var onDownloadVideo: (() -> Void)?
    var onQuickAction: ((String) -> Void)?
    var onOpenItem: ((LibraryItem) -> Void)?
    var actionsForItem: ((LibraryItem, UIView?) -> [LibraryAction])?
    var onSeeAll: ((StartDashboardSection) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.accessibilityIdentifier = "start-dashboard"
        view.backgroundColor = Theme.canvas

        wallpaper.contentMode = .scaleAspectFill
        wallpaper.clipsToBounds = true
        wallpaper.isAccessibilityElement = false
        wallpaper.translatesAutoresizingMaskIntoConstraints = false
        scrim.backgroundColor = Theme.canvas.withAlphaComponent(0.92)
        scrim.isAccessibilityElement = false
        scrim.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.delegate = self
        collectionView.accessibilityIdentifier = "start-dashboard-collection"
        collectionView.translatesAutoresizingMaskIntoConstraints = false

        collectionView.register(LibraryMediaCell.self, forCellWithReuseIdentifier: LibraryMediaCell.identifier)
        collectionView.register(DashboardEmptyCell.self, forCellWithReuseIdentifier: DashboardEmptyCell.reuseIdentifier)
        collectionView.register(
            DashboardHeaderView.self,
            forSupplementaryViewOfKind: Self.headerKind,
            withReuseIdentifier: DashboardHeaderView.reuseIdentifier
        )
        collectionView.register(
            DashboardSectionHeaderView.self,
            forSupplementaryViewOfKind: Self.headerKind,
            withReuseIdentifier: DashboardSectionHeaderView.reuseIdentifier
        )

        view.addSubview(wallpaper)
        view.addSubview(scrim)
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            wallpaper.topAnchor.constraint(equalTo: view.topAnchor),
            wallpaper.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            wallpaper.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            wallpaper.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrim.topAnchor.constraint(equalTo: wallpaper.topAnchor),
            scrim.bottomAnchor.constraint(equalTo: wallpaper.bottomAnchor),
            scrim.leadingAnchor.constraint(equalTo: wallpaper.leadingAnchor),
            scrim.trailingAnchor.constraint(equalTo: wallpaper.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        aggregator.onChange = { [weak self] in self?.rebuild(animated: false) }
        rebuild(animated: false)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadWallpaper()
        aggregator.refresh()
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard collectionView === self.collectionView,
              let itemID = dataSource.itemIdentifier(for: indexPath),
              case .library(let id) = itemID,
              let item = itemsByID[id] else { return }
        collectionView.deselectItem(at: indexPath, animated: false)
        onOpenItem?(item)
    }

    func configure(isPrivate: Bool) {
        guard self.isPrivate != isPrivate else { return }
        self.isPrivate = isPrivate
        if isViewLoaded {
            rebuild(animated: false)
        }
    }

    func refreshLocalizedContent() {
        guard isViewLoaded else { return }
        rebuild(animated: false)
        refreshVisibleViews()
    }

    private func loadWallpaper() {
        guard let name = WallpaperStore.shared.selectedName,
              let url = Bundle.main.url(forResource: name, withExtension: nil, subdirectory: "Wallpapers") else {
            wallpaper.image = nil
            return
        }
        wallpaper.image = UIImage(contentsOfFile: url.path)
    }

    private func rebuild(animated: Bool) {
        guard isViewLoaded else { return }
        let allItems = aggregator.snapshot.items(sort: .recent)
        let ready = allItems.filter {
            ($0.source == .downloads || $0.source == .artifacts)
                && ($0.kind == .video || $0.kind == .audio)
                && $0.isAvailable
        }.prefix(4)
        let activeDownloads = allItems.filter {
            guard $0.source == .downloads else { return false }
            guard let state = $0.state else { return false }
            return state == .running || state == .paused || state == .queued
        }.prefix(4)
        let favorites = allItems.filter { $0.source == .favorites }.prefix(4)
        let recent = isPrivate ? [] : allItems.filter { $0.source == .history }.prefix(4)

        let groups: [(StartDashboardSection, [LibraryItem])] = isPrivate
            ? [(.favorites, Array(favorites))]
            : [(.ready, Array(ready)), (.downloads, Array(activeDownloads)), (.favorites, Array(favorites)), (.recent, Array(recent))]
        let visibleGroups = groups.filter { !$0.1.isEmpty }

        itemsByID = visibleGroups.reduce(into: [LibraryItem.Identity: LibraryItem]()) { result, group in
            for item in group.1 {
                result[item.id] = item
            }
        }

        var snapshot = NSDiffableDataSourceSnapshot<StartDashboardSection, Item>()
        if visibleGroups.isEmpty {
            snapshot.appendSections([.empty])
            snapshot.appendItems([.empty], toSection: .empty)
        } else {
            snapshot.appendSections(visibleGroups.map(\.0))
            for (section, items) in visibleGroups {
                snapshot.appendItems(items.map { .library($0.id) }, toSection: section)
            }
        }
        dataSource.apply(snapshot, animatingDifferences: animated) { [weak self] in
            self?.refreshVisibleViews()
        }
    }

    private func refreshVisibleViews() {
        for indexPath in collectionView.indexPathsForVisibleItems {
            guard let itemID = dataSource.itemIdentifier(for: indexPath) else { continue }
            let cell = collectionView.cellForItem(at: indexPath)
            switch itemID {
            case .library(let id):
                guard let item = itemsByID[id], let mediaCell = cell as? LibraryMediaCell else { continue }
                mediaCell.configure(
                    with: item,
                    actions: actionsForItem?(item, mediaCell) ?? [],
                    dateFormatter: dateFormatter
                )
            case .empty:
                (cell as? DashboardEmptyCell)?.configure()
            }
        }
        refreshVisibleSupplementaryViews()
    }

    private func refreshVisibleSupplementaryViews() {
        for indexPath in collectionView.indexPathsForVisibleSupplementaryElements(ofKind: Self.headerKind) {
            guard let view = collectionView.supplementaryView(
                forElementKind: Self.headerKind,
                at: indexPath
            ) else { continue }
            configureSupplementaryView(view, at: indexPath)
        }
    }

    private func makeDataSource() -> DataSource {
        let dataSource = UICollectionViewDiffableDataSource<StartDashboardSection, Item>(collectionView: collectionView) { [weak self] collectionView, indexPath, itemID in
            guard let self else { return nil }
            switch itemID {
            case .library(let id):
                guard let item = itemsByID[id] else { return nil }
                let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: LibraryMediaCell.identifier,
                    for: indexPath
                ) as? LibraryMediaCell
                cell?.configure(
                    with: item,
                    actions: actionsForItem?(item, cell) ?? [],
                    dateFormatter: dateFormatter
                )
                return cell
            case .empty:
                let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: DashboardEmptyCell.reuseIdentifier,
                    for: indexPath
                ) as? DashboardEmptyCell
                cell?.configure()
                return cell
            }
        }
        dataSource.supplementaryViewProvider = { [weak self] collectionView, _, indexPath in
            guard let self else { return nil }
            let sections = self.dataSource.snapshot().sectionIdentifiers
            let isHero = sections.indices.contains(indexPath.section) && sections[indexPath.section] == sections.first
            let identifier = isHero ? DashboardHeaderView.reuseIdentifier : DashboardSectionHeaderView.reuseIdentifier
            let view = collectionView.dequeueReusableSupplementaryView(
                ofKind: Self.headerKind,
                withReuseIdentifier: identifier,
                for: indexPath
            )
            configureSupplementaryView(view, at: indexPath)
            return view
        }
        return dataSource
    }

    private func configureSupplementaryView(_ view: UICollectionReusableView, at indexPath: IndexPath) {
        let sections = dataSource.snapshot().sectionIdentifiers
        guard sections.indices.contains(indexPath.section) else { return }
        let section = sections[indexPath.section]
        if section == sections.first, let header = view as? DashboardHeaderView {
            header.onSearch = onSearch
            header.onDownloadVideo = onDownloadVideo
            header.onQuickAction = onQuickAction
            header.onFirstSectionAction = { [weak self] in self?.onSeeAll?(section) }
            header.configure(isPrivate: isPrivate, section: section)
        } else if let header = view as? DashboardSectionHeaderView {
            header.configure(title: section.title) { [weak self] in self?.onSeeAll?(section) }
        }
    }

    private static func makeLayout() -> UICollectionViewCompositionalLayout {
        let configuration = UICollectionViewCompositionalLayoutConfiguration()
        configuration.interSectionSpacing = Theme.Spacing.x3
        return UICollectionViewCompositionalLayout(sectionProvider: { sectionIndex, environment in
            let columns = environment.container.contentSize.width >= 720 ? 2 : 1
            let itemInsets = NSDirectionalEdgeInsets(
                top: 0,
                leading: Theme.Spacing.x4,
                bottom: 0,
                trailing: Theme.Spacing.x4
            )
            let itemSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0 / CGFloat(columns)),
                heightDimension: .estimated(112)
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            item.contentInsets = itemInsets
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1),
                    heightDimension: .estimated(112)
                ),
                subitem: item,
                count: columns
            )
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = Theme.Spacing.x1
            section.contentInsets = NSDirectionalEdgeInsets(
                top: 0,
                leading: 0,
                bottom: Theme.Spacing.x5,
                trailing: 0
            )
            let headerSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .estimated(sectionIndex == 0 ? 390 : 52)
            )
            if sectionIndex == 0 {
                section.boundarySupplementaryItems = [
                    NSCollectionLayoutBoundarySupplementaryItem(
                        layoutSize: headerSize,
                        elementKind: headerKind,
                        alignment: .top
                    )
                ]
            } else {
                section.supplementaryItems = [
                    NSCollectionLayoutSupplementaryItem(
                        layoutSize: headerSize,
                        elementKind: headerKind,
                        alignment: .top
                    )
                ]
            }
            return section
        }, configuration: configuration)
    }
}

final class DashboardHeaderView: UICollectionReusableView {
    static let reuseIdentifier = "start-dashboard-hero"

    private let brandRow = UIStackView()
    private let mark = UILabel()
    private let wordmark = UILabel()
    private let privateBadge = UIButton(type: .system)
    private let searchButton = SecondaryButton(title: "")
    private let downloadButton = PrimaryButton(title: "")
    private let quickActionsScrollView = UIScrollView()
    private let quickActionsStack = UIStackView()
    private let firstSectionRow = UIStackView()
    private let firstSectionTitle = UILabel()
    private let firstSectionAction = UIButton(type: .system)
    private let noteLabel = UILabel()

    var onSearch: (() -> Void)?
    var onDownloadVideo: (() -> Void)?
    var onQuickAction: ((String) -> Void)?
    var onFirstSectionAction: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.canvas

        brandRow.axis = .horizontal
        brandRow.alignment = .center
        brandRow.spacing = Theme.Spacing.x3
        brandRow.translatesAutoresizingMaskIntoConstraints = false

        mark.text = "M"
        mark.font = Theme.title
        mark.textColor = Theme.onAccent
        mark.textAlignment = .center
        mark.backgroundColor = Theme.accent
        mark.layer.cornerRadius = 12
        mark.clipsToBounds = true
        mark.isAccessibilityElement = false
        mark.translatesAutoresizingMaskIntoConstraints = false

        wordmark.text = "Magdy"
        wordmark.font = Theme.title
        wordmark.textColor = Theme.textPrimary
        wordmark.adjustsFontForContentSizeCategory = true
        wordmark.accessibilityIdentifier = "start-title"
        wordmark.translatesAutoresizingMaskIntoConstraints = false

        var badgeConfiguration = UIButton.Configuration.tinted()
        badgeConfiguration.baseBackgroundColor = Theme.accentContainer
        badgeConfiguration.baseForegroundColor = Theme.accentText
        badgeConfiguration.cornerStyle = .capsule
        badgeConfiguration.contentInsets = NSDirectionalEdgeInsets(
            top: Theme.Spacing.x1,
            leading: Theme.Spacing.x3,
            bottom: Theme.Spacing.x1,
            trailing: Theme.Spacing.x3
        )
        privateBadge.configuration = badgeConfiguration
        privateBadge.isUserInteractionEnabled = false
        privateBadge.titleLabel?.font = Theme.footnote
        privateBadge.titleLabel?.adjustsFontForContentSizeCategory = true
        privateBadge.setContentHuggingPriority(.required, for: .horizontal)
        privateBadge.translatesAutoresizingMaskIntoConstraints = false

        brandRow.addArrangedSubview(mark)
        brandRow.addArrangedSubview(wordmark)
        brandRow.addArrangedSubview(privateBadge)

        searchButton.setImage(UIImage(systemName: "magnifyingglass"), for: .normal)
        searchButton.accessibilityIdentifier = "start-search"
        searchButton.addTarget(self, action: #selector(performSearch), for: .touchUpInside)
        searchButton.translatesAutoresizingMaskIntoConstraints = false

        downloadButton.setImage(UIImage(systemName: "arrow.down.circle.fill"), for: .normal)
        downloadButton.accessibilityIdentifier = "download-video"
        downloadButton.addTarget(self, action: #selector(performDownload), for: .touchUpInside)
        downloadButton.translatesAutoresizingMaskIntoConstraints = false

        quickActionsStack.axis = .horizontal
        quickActionsStack.alignment = .center
        quickActionsStack.spacing = Theme.Spacing.x2
        quickActionsStack.translatesAutoresizingMaskIntoConstraints = false
        quickActionsScrollView.showsHorizontalScrollIndicator = false
        quickActionsScrollView.alwaysBounceHorizontal = true
        quickActionsScrollView.translatesAutoresizingMaskIntoConstraints = false
        quickActionsScrollView.addSubview(quickActionsStack)

        for spec in Self.quickActions {
            let button = UIButton(type: .system)
            var configuration = UIButton.Configuration.plain()
            configuration.image = UIImage(systemName: spec.symbol)
            configuration.imagePlacement = .top
            configuration.imagePadding = Theme.Spacing.x1
            configuration.baseBackgroundColor = Theme.surface
            configuration.baseForegroundColor = Theme.textPrimary
            configuration.background.strokeColor = Theme.hairline
            configuration.background.strokeWidth = 1
            configuration.cornerStyle = .small
            configuration.contentInsets = NSDirectionalEdgeInsets(
                top: Theme.Spacing.x2,
                leading: Theme.Spacing.x3,
                bottom: Theme.Spacing.x2,
                trailing: Theme.Spacing.x3
            )
            button.configuration = configuration
            button.tag = spec.tag
            button.titleLabel?.font = Theme.footnote
            button.titleLabel?.adjustsFontForContentSizeCategory = true
            button.accessibilityIdentifier = spec.identifier
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 60).isActive = true
            button.addTarget(self, action: #selector(performQuickAction(_:)), for: .touchUpInside)
            quickActionsStack.addArrangedSubview(button)
        }

        firstSectionRow.axis = .horizontal
        firstSectionRow.alignment = .center
        firstSectionRow.isHidden = true
        firstSectionRow.translatesAutoresizingMaskIntoConstraints = false
        firstSectionTitle.font = Theme.headline
        firstSectionTitle.textColor = Theme.textPrimary
        firstSectionTitle.adjustsFontForContentSizeCategory = true
        firstSectionTitle.numberOfLines = 0
        firstSectionTitle.translatesAutoresizingMaskIntoConstraints = false
        firstSectionAction.titleLabel?.font = Theme.subhead
        firstSectionAction.titleLabel?.adjustsFontForContentSizeCategory = true
        firstSectionAction.tintColor = Theme.accentText
        firstSectionAction.accessibilityIdentifier = "start-see-all"
        firstSectionAction.setContentHuggingPriority(.required, for: .horizontal)
        firstSectionAction.addTarget(self, action: #selector(performFirstSectionAction), for: .touchUpInside)
        firstSectionAction.translatesAutoresizingMaskIntoConstraints = false
        firstSectionRow.addArrangedSubview(firstSectionTitle)
        firstSectionRow.addArrangedSubview(firstSectionAction)

        noteLabel.font = Theme.footnote
        noteLabel.textColor = Theme.textSecondary
        noteLabel.adjustsFontForContentSizeCategory = true
        noteLabel.numberOfLines = 0
        noteLabel.translatesAutoresizingMaskIntoConstraints = false

        let content = UIStackView(arrangedSubviews: [
            brandRow, searchButton, downloadButton, quickActionsScrollView, firstSectionRow, noteLabel
        ])
        content.axis = .vertical
        content.spacing = Theme.Spacing.x3
        content.translatesAutoresizingMaskIntoConstraints = false

        addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor, constant: Theme.Spacing.x5),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Theme.Spacing.x4),
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Theme.Spacing.x4),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Theme.Spacing.x4),
            mark.widthAnchor.constraint(equalToConstant: 44),
            mark.heightAnchor.constraint(equalToConstant: 44),
            quickActionsScrollView.heightAnchor.constraint(equalToConstant: 60),
            firstSectionAction.heightAnchor.constraint(greaterThanOrEqualToConstant: Theme.minimumTarget),
            firstSectionTitle.trailingAnchor.constraint(lessThanOrEqualTo: firstSectionAction.leadingAnchor, constant: -Theme.Spacing.x2),
            quickActionsStack.topAnchor.constraint(equalTo: quickActionsScrollView.contentLayoutGuide.topAnchor),
            quickActionsStack.bottomAnchor.constraint(equalTo: quickActionsScrollView.contentLayoutGuide.bottomAnchor),
            quickActionsStack.leadingAnchor.constraint(equalTo: quickActionsScrollView.contentLayoutGuide.leadingAnchor),
            quickActionsStack.trailingAnchor.constraint(equalTo: quickActionsScrollView.contentLayoutGuide.trailingAnchor),
            quickActionsStack.heightAnchor.constraint(equalTo: quickActionsScrollView.frameLayoutGuide.heightAnchor)
        ])
        configure(isPrivate: false, section: .empty)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onSearch = nil
        onDownloadVideo = nil
        onQuickAction = nil
        onFirstSectionAction = nil
    }

    func configure(isPrivate: Bool, section: StartDashboardSection) {
        searchButton.setTitle(L.t("dashboard_search"), for: .normal)
        downloadButton.setTitle(L.t("dashboard_download_video"), for: .normal)
        privateBadge.setTitle(L.t("dashboard_private"), for: .normal)
        privateBadge.isHidden = !isPrivate
        privateBadge.accessibilityLabel = L.t("dashboard_private")
        privateBadge.accessibilityTraits = .staticText
        noteLabel.text = L.t("unlimited_note")
        firstSectionTitle.text = section.title
        firstSectionAction.setTitle(L.t("dashboard_see_all"), for: .normal)
        firstSectionRow.isHidden = section == .empty
        for case let button as UIButton in quickActionsStack.arrangedSubviews {
            let spec = Self.quickActions.first { $0.tag == button.tag }
            button.setTitle(spec.map { L.t($0.titleKey) } ?? "", for: .normal)
            button.accessibilityLabel = spec.map { L.t($0.titleKey) } ?? ""
        }
    }

    private struct QuickAction {
        let tag: Int
        let titleKey: String
        let symbol: String
        let identifier: String
    }

    private static let quickActions = [
        QuickAction(tag: 0, titleKey: "dashboard_private", symbol: "hand.raised.fill", identifier: "dashboard-private"),
        QuickAction(tag: 1, titleKey: "dashboard_scan_qr", symbol: "qrcode.viewfinder", identifier: "dashboard-qr"),
        QuickAction(tag: 2, titleKey: "dashboard_voice", symbol: "mic.fill", identifier: "dashboard-voice"),
        QuickAction(tag: 3, titleKey: "dashboard_downloads", symbol: "arrow.down.to.line", identifier: "dashboard-downloads")
    ]

    @objc private func performSearch() {
        onSearch?()
    }

    @objc private func performDownload() {
        onDownloadVideo?()
    }

    @objc private func performFirstSectionAction() {
        onFirstSectionAction?()
    }

    @objc private func performQuickAction(_ sender: UIButton) {
        let action: String
        switch sender.tag {
        case 0: action = "private"
        case 1: action = "qr"
        case 2: action = "voice"
        default: action = "downloads"
        }
        onQuickAction?(action)
    }
}

final class DashboardSectionHeaderView: UICollectionReusableView {
    static let reuseIdentifier = "start-dashboard-section"

    private let titleLabel = UILabel()
    private let actionButton = UIButton(type: .system)
    private var onAction: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.canvas

        titleLabel.font = Theme.headline
        titleLabel.textColor = Theme.textPrimary
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        actionButton.titleLabel?.font = Theme.subhead
        actionButton.titleLabel?.adjustsFontForContentSizeCategory = true
        actionButton.tintColor = Theme.accentText
        actionButton.accessibilityIdentifier = "start-section-see-all"
        actionButton.addTarget(self, action: #selector(performAction), for: .touchUpInside)
        actionButton.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleLabel)
        addSubview(actionButton)
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: Theme.Spacing.x3),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Theme.Spacing.x2),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Theme.Spacing.x4),
            actionButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            actionButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Theme.Spacing.x4),
            actionButton.heightAnchor.constraint(greaterThanOrEqualToConstant: Theme.minimumTarget),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: actionButton.leadingAnchor, constant: -Theme.Spacing.x2)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onAction = nil
    }

    func configure(title: String, onAction: @escaping () -> Void) {
        titleLabel.text = title
        actionButton.setTitle(L.t("dashboard_see_all"), for: .normal)
        self.onAction = onAction
    }

    @objc private func performAction() {
        onAction?()
    }
}

final class DashboardEmptyCell: UICollectionViewCell {
    static let reuseIdentifier = "start-dashboard-empty"

    private let emptyView = EmptyStateView(
        systemName: "play.rectangle.on.rectangle",
        title: L.t("dashboard_empty"),
        message: L.t("dashboard_empty_message")
    )

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        emptyView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(emptyView)
        NSLayoutConstraint.activate([
            emptyView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Theme.Spacing.x3),
            emptyView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Theme.Spacing.x3),
            emptyView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Theme.Spacing.x4),
            emptyView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Theme.Spacing.x4),
            emptyView.heightAnchor.constraint(greaterThanOrEqualToConstant: 180)
        ])
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure() {
        emptyView.configure(title: L.t("dashboard_empty"), message: L.t("dashboard_empty_message"))
    }
}
