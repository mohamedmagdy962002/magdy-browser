import UIKit

final class LibraryViewController: UIViewController {
    private enum Section {
        case media
    }

    private enum EmptyMode {
        case emptyLibrary
        case noResults
    }

    private typealias DataSource = UICollectionViewDiffableDataSource<Section, LibraryItem.Identity>

    private lazy var aggregator = LibraryAggregator()
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: Self.makeLayout())
    private lazy var dataSource = makeDataSource()
    private let refreshControl = UIRefreshControl()
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
    private var filter: LibraryFilter = .all
    private var sort: LibrarySnapshot.SortOrder = .recent
    private var visibleItems: [LibraryItem] = []
    private var itemLookup: [LibraryItem.Identity: LibraryItem] = [:]
    private var emptyMode: EmptyMode?
    private var emptyView: EmptyStateView?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L.t("library")
        navigationController?.navigationBar.prefersLargeTitles = true
        view.accessibilityIdentifier = "library-screen"
        view.backgroundColor = Theme.canvas

        collectionView.accessibilityIdentifier = "library-collection"
        collectionView.backgroundColor = Theme.canvas
        collectionView.alwaysBounceVertical = true
        collectionView.delegate = self
        collectionView.register(LibraryMediaCell.self, forCellWithReuseIdentifier: LibraryMediaCell.identifier)
        collectionView.register(
            LibraryHeaderView.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: "library-header"
        )
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        refreshControl.addTarget(self, action: #selector(refreshLibrary), for: .valueChanged)
        collectionView.refreshControl = refreshControl
        collectionView.collectionViewLayout = Self.makeLayout()

        let sortButton = IconButton(systemName: "arrow.up.arrow.down", accessibilityLabel: L.t("library_sort"))
        sortButton.accessibilityIdentifier = "library-sort"
        sortButton.showsMenuAsPrimaryAction = true
        sortButton.menu = sortMenu()
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(customView: manageButton()),
            UIBarButtonItem(customView: sortButton)
        ]

        aggregator.onChange = { [weak self] in self?.rebuild() }
        rebuild(animated: false)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        aggregator.refresh()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        collectionView.collectionViewLayout.invalidateLayout()
    }

    func refreshLocalizedContent() {
        guard isViewLoaded else { return }
        title = L.t("library")
        if let sortButton = navigationItem.rightBarButtonItems?.last?.customView as? IconButton {
            sortButton.accessibilityLabel = L.t("library_sort")
            sortButton.menu = sortMenu()
        }
        if let manageButton = navigationItem.rightBarButtonItems?.first?.customView as? IconButton {
            manageButton.accessibilityLabel = L.t("library_manage")
            manageButton.menu = manageMenu()
        }
        refreshVisibleHeader()
        emptyMode = nil
        rebuild(animated: false)
    }

    @objc private func refreshLibrary() {
        aggregator.refresh { [weak self] in
            self?.refreshControl.endRefreshing()
        }
    }

    private func makeDataSource() -> DataSource {
        let source = DataSource(collectionView: collectionView) { [weak self] collectionView, indexPath, identity in
            guard let self,
                  let item = self.itemLookup[identity],
                  let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: LibraryMediaCell.identifier,
                    for: indexPath
                  ) as? LibraryMediaCell else { return nil }
            self.configure(cell, with: item)
            return cell
        }
        source.supplementaryViewProvider = { [weak self] collectionView, _, _ in
            guard let header = collectionView.dequeueReusableSupplementaryView(
                ofKind: UICollectionView.elementKindSectionHeader,
                withReuseIdentifier: "library-header",
                for: IndexPath(item: 0, section: 0)
            ) as? LibraryHeaderView else { return nil }
            self?.configure(header)
            return header
        }
        return source
    }

    private func rebuild(animated: Bool = true) {
        visibleItems = aggregator.snapshot.items(query: currentQuery, sources: filter.sources, sort: sort)
        itemLookup = Dictionary(uniqueKeysWithValues: visibleItems.map { ($0.id, $0) })
        updateEmptyState()

        var snapshot = NSDiffableDataSourceSnapshot<Section, LibraryItem.Identity>()
        snapshot.appendSections([.media])
        snapshot.appendItems(visibleItems.map(\.id), toSection: .media)
        let shouldAnimate = animated && !UIAccessibility.isReduceMotionEnabled
        dataSource.apply(snapshot, animatingDifferences: shouldAnimate) { [weak self] in
            guard let self else { return }
            self.refreshVisibleHeader()
            for indexPath in self.collectionView.indexPathsForVisibleItems {
                if let identity = self.dataSource.itemIdentifier(for: indexPath),
                   let item = self.itemLookup[identity],
                   let cell = self.collectionView.cellForItem(at: indexPath) as? LibraryMediaCell {
                    self.configure(cell, with: item)
                }
            }
        }
    }

    private var currentQuery: String {
        guard let header = visibleHeader() else { return "" }
        return header.searchText
    }

    private func configure(_ cell: LibraryMediaCell, with item: LibraryItem) {
        cell.configure(
            with: item,
            actions: LibraryActions.actions(for: item, from: self, sourceView: cell),
            dateFormatter: dateFormatter
        )
    }

    private func configure(_ header: LibraryHeaderView) {
        header.configure(
            count: visibleItems.count,
            filter: filter,
            delegate: self
        ) { [weak self] filter in
            self?.filter = filter
            self?.rebuild(animated: false)
        }
    }

    private func refreshVisibleHeader() {
        if let header = visibleHeader() {
            configure(header)
        }
    }

    private func visibleHeader() -> LibraryHeaderView? {
        guard let header = collectionView.supplementaryView(
            forElementKind: UICollectionView.elementKindSectionHeader,
            at: IndexPath(item: 0, section: 0)
        ) as? LibraryHeaderView else { return nil }
        return header
    }

    private func updateEmptyState() {
        let mode: EmptyMode = visibleItems.isEmpty ? (currentQuery.isEmpty && filter == .all ? .emptyLibrary : .noResults) : .noResults
        if visibleItems.isEmpty, emptyMode != mode {
            emptyView?.removeFromSuperview()
            let empty = EmptyStateView(
                systemName: mode == .emptyLibrary ? "rectangle.stack" : "magnifyingglass",
                title: L.t(mode == .emptyLibrary ? "library_empty_title" : "library_no_results_title"),
                message: L.t(mode == .emptyLibrary ? "library_empty_message" : "library_no_results_message")
            )
            empty.accessibilityIdentifier = mode == .emptyLibrary ? "library-empty" : "library-no-results"
            empty.actionTitle = mode == .noResults ? L.t("library_show_all") : nil
            empty.actionHandler = mode == .noResults ? { [weak self] in self?.showAll() } : nil
            collectionView.backgroundView = empty
            emptyView = empty
            emptyMode = mode
        } else if visibleItems.isEmpty, let emptyView {
            collectionView.backgroundView = emptyView
        } else {
            emptyView?.isHidden = true
        }
        emptyView?.isHidden = !visibleItems.isEmpty
    }

    private func showAll() {
        filter = .all
        visibleHeader()?.clearSearch()
        rebuild(animated: false)
    }

    private func manageButton() -> IconButton {
        let button = IconButton(systemName: "ellipsis.circle", accessibilityLabel: L.t("library_manage"))
        button.accessibilityIdentifier = "library-manage"
        button.showsMenuAsPrimaryAction = true
        button.menu = manageMenu()
        return button
    }

    private func manageMenu() -> UIMenu {
        let download = UIAction(title: L.t("downloads"), image: UIImage(systemName: "arrow.down.circle")) { [weak self] _ in
            self?.appRouteHandler?.navigate(to: .downloads)
        }
        let favorite = UIAction(title: L.t("favorites"), image: UIImage(systemName: "star")) { [weak self] _ in
            self?.appRouteHandler?.navigate(to: .favorites)
        }
        let history = UIAction(title: L.t("history"), image: UIImage(systemName: "clock.arrow.circlepath")) { [weak self] _ in
            self?.appRouteHandler?.navigate(to: .history)
        }
        let reading = UIAction(title: L.t("reading_list"), image: UIImage(systemName: "text.book.closed")) { [weak self] _ in
            self?.navigationController?.pushViewController(ReadingListViewController(), animated: true)
        }
        return UIMenu(title: L.t("your_collection"), children: [download, favorite, history, reading])
    }

    private func sortMenu() -> UIMenu {
        let actions = LibrarySnapshot.SortOrder.allCases.map { order in
            UIAction(title: order.title, state: order == sort ? .on : .off) { [weak self] _ in
                self?.sort = order
                self?.rebuild(animated: false)
                if let button = self?.navigationItem.rightBarButtonItems?.last?.customView as? IconButton {
                    button.menu = self?.sortMenu()
                }
            }
        }
        return UIMenu(title: L.t("library_sort"), children: actions)
    }

    private static func makeLayout() -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { _, environment in
            let columns = environment.container.contentSize.width >= 720 ? 2 : 1
            let itemSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0 / CGFloat(columns)),
                heightDimension: .estimated(112)
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1),
                    heightDimension: .estimated(112)
                ),
                subitem: item,
                count: columns
            )
            group.interItemSpacing = .fixed(Theme.Spacing.x3)
            let headerSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .estimated(154)
            )
            let header = NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: headerSize,
                elementKind: UICollectionView.elementKindSectionHeader,
                alignment: .top
            )
            let section = NSCollectionLayoutSection(group: group)
            section.boundarySupplementaryItems = [header]
            section.interGroupSpacing = Theme.Spacing.x2
            section.contentInsets = NSDirectionalEdgeInsets(
                top: Theme.Spacing.x2,
                leading: 0,
                bottom: Theme.Spacing.x8,
                trailing: 0
            )
            return section
        }
    }
}

extension LibraryViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let identity = dataSource.itemIdentifier(for: indexPath),
              let item = itemLookup[identity] else { return }
        LibraryActions.open(item, from: self)
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        view.endEditing(true)
    }
}

extension LibraryViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        rebuild(animated: false)
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }

    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searchBar.text = ""
        searchBar.resignFirstResponder()
        rebuild(animated: false)
    }
}
