import UIKit

enum LibraryFilter: Int, CaseIterable {
    case all
    case downloads
    case favorites
    case history
    case readingList
    case files

    var title: String {
        switch self {
        case .all: return L.t("library_all")
        case .downloads: return L.t("downloads")
        case .favorites: return L.t("favorites")
        case .history: return L.t("history")
        case .readingList: return L.t("reading_list")
        case .files: return L.t("library_files")
        }
    }

    var identifier: String {
        "library-filter-\(rawValue)"
    }

    var sources: Set<LibraryItemSource>? {
        switch self {
        case .all: return nil
        case .downloads: return [.downloads]
        case .favorites: return [.favorites]
        case .history: return [.history]
        case .readingList: return [.readingList]
        case .files: return [.artifacts]
        }
    }
}

extension LibraryItemSource {
    var libraryTitle: String {
        switch self {
        case .downloads: return L.t("downloads")
        case .favorites: return L.t("favorites")
        case .history: return L.t("history")
        case .readingList: return L.t("reading_list")
        case .artifacts: return L.t("library_files")
        }
    }
}

extension LibraryMediaKind {
    var libraryTitle: String {
        switch self {
        case .video: return L.t("media_video")
        case .audio: return L.t("media_audio")
        case .image: return L.t("media_image")
        case .document: return L.t("media_document")
        case .archive: return L.t("media_archive")
        case .application: return L.t("media_application")
        case .article: return L.t("media_article")
        case .web: return L.t("media_web")
        }
    }

    var symbol: String {
        switch self {
        case .video: return "play.rectangle"
        case .audio: return "waveform"
        case .image: return "photo"
        case .document: return "doc"
        case .archive: return "archivebox"
        case .application: return "app"
        case .article: return "text.book.closed"
        case .web: return "globe"
        }
    }
}

extension LibrarySnapshot.SortOrder {
    var title: String {
        switch self {
        case .recent: return L.t("library_sort_recent")
        case .name: return L.t("library_sort_name")
        case .size: return L.t("library_sort_size")
        }
    }
}

extension DownloadItem {
    static func libraryStateTitle(_ state: State) -> String {
        switch state {
        case .queued: return L.t("download_state_queued")
        case .running: return L.t("download_state_running")
        case .paused: return L.t("download_state_paused")
        case .finished: return L.t("download_state_finished")
        case .failed: return L.t("download_state_failed")
        case .cancelled: return L.t("download_state_cancelled")
        }
    }
}

final class LibraryHeaderView: UICollectionReusableView {
    private let summaryLabel = UILabel()
    private let searchBar = UISearchBar()
    private let filtersScrollView = UIScrollView()
    private let filtersStack = UIStackView()
    private var filterChips: [LibraryFilter: FilterChip] = [:]
    var onFilter: ((LibraryFilter) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)

        summaryLabel.font = Theme.subhead
        summaryLabel.textColor = Theme.textSecondary
        summaryLabel.adjustsFontForContentSizeCategory = true
        summaryLabel.translatesAutoresizingMaskIntoConstraints = false

        searchBar.searchBarStyle = .minimal
        searchBar.placeholder = L.t("library_search")
        searchBar.autocapitalizationType = .none
        searchBar.autocorrectionType = .no
        searchBar.accessibilityIdentifier = "library-search"
        searchBar.searchTextField.accessibilityIdentifier = "library-search"
        searchBar.searchTextField.backgroundColor = Theme.field
        searchBar.searchTextField.textColor = Theme.textPrimary
        searchBar.translatesAutoresizingMaskIntoConstraints = false

        filtersStack.axis = .horizontal
        filtersStack.alignment = .center
        filtersStack.spacing = Theme.Spacing.x2
        filtersStack.translatesAutoresizingMaskIntoConstraints = false
        filtersScrollView.addSubview(filtersStack)
        filtersScrollView.showsHorizontalScrollIndicator = false
        filtersScrollView.alwaysBounceHorizontal = true
        filtersScrollView.translatesAutoresizingMaskIntoConstraints = false
        for option in LibraryFilter.allCases {
            let chip = FilterChip(title: option.title)
            chip.tag = option.rawValue
            chip.accessibilityIdentifier = option.identifier
            chip.addTarget(self, action: #selector(selectFilter(_:)), for: .touchUpInside)
            filterChips[option] = chip
            filtersStack.addArrangedSubview(chip)
        }

        addSubview(summaryLabel)
        addSubview(searchBar)
        addSubview(filtersScrollView)
        NSLayoutConstraint.activate([
            summaryLabel.topAnchor.constraint(equalTo: topAnchor, constant: Theme.Spacing.x1),
            summaryLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Theme.Spacing.x6),
            summaryLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Theme.Spacing.x6),
            searchBar.topAnchor.constraint(equalTo: summaryLabel.bottomAnchor, constant: Theme.Spacing.x3),
            searchBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Theme.Spacing.x4),
            searchBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Theme.Spacing.x4),
            filtersScrollView.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: Theme.Spacing.x2),
            filtersScrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            filtersScrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            filtersScrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Theme.Spacing.x3),
            filtersStack.topAnchor.constraint(equalTo: filtersScrollView.contentLayoutGuide.topAnchor),
            filtersStack.bottomAnchor.constraint(equalTo: filtersScrollView.contentLayoutGuide.bottomAnchor),
            filtersStack.leadingAnchor.constraint(equalTo: filtersScrollView.contentLayoutGuide.leadingAnchor, constant: Theme.Spacing.x4),
            filtersStack.trailingAnchor.constraint(equalTo: filtersScrollView.contentLayoutGuide.trailingAnchor, constant: -Theme.Spacing.x4),
            filtersStack.heightAnchor.constraint(equalTo: filtersScrollView.frameLayoutGuide.heightAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        searchBar.delegate = nil
        onFilter = nil
    }

    var searchText: String {
        searchBar.text ?? ""
    }

    func clearSearch() {
        searchBar.text = ""
        searchBar.resignFirstResponder()
    }

    func configure(count: Int, filter: LibraryFilter, delegate: UISearchBarDelegate, onFilter: @escaping (LibraryFilter) -> Void) {
        summaryLabel.text = String(format: L.t("library_item_count"), count)
        summaryLabel.accessibilityIdentifier = "library-count"
        searchBar.placeholder = L.t("library_search")
        searchBar.delegate = delegate
        self.onFilter = onFilter

        for option in LibraryFilter.allCases {
            guard let chip = filterChips[option] else { continue }
            chip.setTitle(option.title, for: .normal)
            chip.isSelected = option == filter
            chip.accessibilityLabel = option.title
        }
        filtersScrollView.layoutIfNeeded()
        if let chip = filterChips[filter] {
            let bounds = chip.convert(chip.bounds, to: filtersScrollView)
            filtersScrollView.scrollRectToVisible(bounds, animated: false)
        }
    }

    @objc private func selectFilter(_ sender: UIButton) {
        onFilter?(LibraryFilter(rawValue: sender.tag) ?? .all)
    }
}

final class LibraryMediaCell: UICollectionViewCell {
    static let identifier = "library-media"

    private let card = UIView()
    private let artwork = MediaArtworkView(image: nil)
    private let kindBadge = UIView()
    private let kindIcon = UIImageView()
    private let titleLabel = UILabel()
    private let metadataLabel = UILabel()
    private let detailLabel = UILabel()
    private let progressView = UIProgressView(progressViewStyle: .bar)
    private let moreButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)

        card.backgroundColor = Theme.card
        card.layer.cornerRadius = Theme.Radius.media
        card.layer.borderWidth = 1
        card.layer.borderColor = Theme.hairline.cgColor
        card.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(card)

        artwork.translatesAutoresizingMaskIntoConstraints = false
        artwork.isAccessibilityElement = false
        card.addSubview(artwork)

        kindBadge.backgroundColor = Theme.accentContainer
        kindBadge.layer.cornerRadius = 8
        kindBadge.translatesAutoresizingMaskIntoConstraints = false
        artwork.addSubview(kindBadge)
        kindIcon.image = UIImage(systemName: "doc")
        kindIcon.tintColor = Theme.accentText
        kindIcon.contentMode = .scaleAspectFit
        kindIcon.translatesAutoresizingMaskIntoConstraints = false
        kindBadge.addSubview(kindIcon)

        titleLabel.font = Theme.headline
        titleLabel.textColor = Theme.textPrimary
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 2
        metadataLabel.font = Theme.subhead
        metadataLabel.textColor = Theme.textSecondary
        metadataLabel.adjustsFontForContentSizeCategory = true
        metadataLabel.numberOfLines = 2
        detailLabel.font = Theme.footnote
        detailLabel.textColor = Theme.textTertiary
        detailLabel.adjustsFontForContentSizeCategory = true
        detailLabel.numberOfLines = 1

        let textStack = UIStackView(arrangedSubviews: [titleLabel, metadataLabel, detailLabel])
        textStack.axis = .vertical
        textStack.alignment = .leading
        textStack.spacing = Theme.Spacing.x1
        textStack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(textStack)

        progressView.trackTintColor = Theme.raised
        progressView.progressTintColor = Theme.accent
        progressView.layer.cornerRadius = 2
        progressView.clipsToBounds = true
        progressView.isAccessibilityElement = false
        progressView.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(progressView)

        var configuration = UIButton.Configuration.plain()
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
        configuration.baseForegroundColor = Theme.textSecondary
        moreButton.configuration = configuration
        moreButton.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        moreButton.accessibilityLabel = L.t("library_actions")
        moreButton.showsMenuAsPrimaryAction = true
        moreButton.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(moreButton)

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Theme.Spacing.x1),
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Theme.Spacing.x4),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Theme.Spacing.x4),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Theme.Spacing.x1),
            artwork.topAnchor.constraint(equalTo: card.topAnchor, constant: Theme.Spacing.x3),
            artwork.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Theme.Spacing.x3),
            artwork.widthAnchor.constraint(equalToConstant: 72),
            artwork.heightAnchor.constraint(equalToConstant: 72),
            kindBadge.trailingAnchor.constraint(equalTo: artwork.trailingAnchor, constant: -6),
            kindBadge.bottomAnchor.constraint(equalTo: artwork.bottomAnchor, constant: -6),
            kindBadge.widthAnchor.constraint(equalToConstant: 22),
            kindBadge.heightAnchor.constraint(equalToConstant: 22),
            kindIcon.topAnchor.constraint(equalTo: kindBadge.topAnchor, constant: 5),
            kindIcon.leadingAnchor.constraint(equalTo: kindBadge.leadingAnchor, constant: 5),
            kindIcon.trailingAnchor.constraint(equalTo: kindBadge.trailingAnchor, constant: -5),
            kindIcon.bottomAnchor.constraint(equalTo: kindBadge.bottomAnchor, constant: -5),
            textStack.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            textStack.leadingAnchor.constraint(equalTo: artwork.trailingAnchor, constant: Theme.Spacing.x3),
            textStack.trailingAnchor.constraint(equalTo: moreButton.leadingAnchor, constant: -Theme.Spacing.x1),
            textStack.topAnchor.constraint(greaterThanOrEqualTo: card.topAnchor, constant: Theme.Spacing.x3),
            textStack.bottomAnchor.constraint(lessThanOrEqualTo: progressView.topAnchor, constant: -Theme.Spacing.x1),
            progressView.leadingAnchor.constraint(equalTo: textStack.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: textStack.trailingAnchor),
            progressView.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -Theme.Spacing.x3),
            progressView.heightAnchor.constraint(equalToConstant: 4),
            moreButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -Theme.Spacing.x1),
            moreButton.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            moreButton.widthAnchor.constraint(greaterThanOrEqualToConstant: Theme.minimumTarget),
            moreButton.heightAnchor.constraint(greaterThanOrEqualToConstant: Theme.minimumTarget)
        ])

        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet { card.backgroundColor = isHighlighted ? Theme.raised : Theme.card }
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        card.layer.borderColor = context.nextFocusedView === self ? Theme.accent.cgColor : Theme.hairline.cgColor
        card.layer.borderWidth = context.nextFocusedView === self ? 2 : 1
    }

    func configure(with item: LibraryItem, actions: [LibraryAction], dateFormatter: DateFormatter) {
        artwork.image = nil
        artwork.mediaTitle = item.title
        kindIcon.image = UIImage(systemName: item.kind.symbol)
        titleLabel.text = item.title
        metadataLabel.text = "\(item.source.libraryTitle) · \(item.kind.libraryTitle)"
        detailLabel.text = LibraryMediaCell.detail(for: item, dateFormatter: dateFormatter)
        moreButton.isHidden = actions.isEmpty
        moreButton.menu = actions.isEmpty ? nil : UIMenu(children: actions.map { $0.uiAction() })
        accessibilityCustomActions = actions.map { action in
            UIAccessibilityCustomAction(name: action.title) { _ in
                action.perform()
                return true
            }
        }
        var accessibilityParts = [item.source.libraryTitle, item.kind.libraryTitle, detailLabel.text ?? ""]
        if let progress = item.progress, item.state == .running {
            progressView.isHidden = false
            progressView.progress = Float(progress)
            accessibilityParts.append(String(format: L.t("library_progress"), Int((progress * 100).rounded())))
        } else {
            progressView.isHidden = true
            progressView.progress = 0
        }
        let canOpen = LibraryActions.canOpen(item)
        accessibilityLabel = item.title
        accessibilityValue = accessibilityParts.filter { !$0.isEmpty }.joined(separator: ", ")
        accessibilityHint = canOpen ? L.t("library_open_hint") : nil
        accessibilityTraits = canOpen ? .button : []
    }

    private static func detail(for item: LibraryItem, dateFormatter: DateFormatter) -> String {
        var parts: [String] = []
        if let subtitle = item.subtitle, !subtitle.isEmpty {
            parts.append(subtitle)
        }
        if item.fileSize > 0 {
            parts.append(ByteCountFormatter.string(fromByteCount: item.fileSize, countStyle: .file))
        }
        if !item.isAvailable, item.state == .finished || item.source == .readingList {
            parts.append(L.t("library_unavailable"))
        } else if let state = item.state {
            parts.append(DownloadItem.libraryStateTitle(state))
        } else if item.date > .distantPast {
            parts.append(dateFormatter.string(from: item.date))
        }
        return parts.joined(separator: " · ")
    }
}
