import UIKit

/// One row in the glass menu — built directly from the browser's action list
/// (UIAction's handler isn't publicly invokable, so we carry our own closure).
struct GlassMenuItem {
    let title: String
    let image: UIImage?
    let destructive: Bool
    let handler: () -> Void
}

/// Liquid-glass replacement for the native ⋯ pull-down menu: dimmed backdrop,
/// frosted panel docked at the bottom, one tinted-icon row per action.
final class GlassMenuSheet: UIViewController, UITableViewDataSource, UITableViewDelegate {

    private let items: [GlassMenuItem]
    private let table = UITableView(frame: .zero, style: .plain)

    init(items: [GlassMenuItem]) {
        self.items = items
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()

        let dim = UIButton(type: .system)
        dim.backgroundColor = UIColor.black.withAlphaComponent(0.30)
        dim.addTarget(self, action: #selector(close), for: .touchUpInside)
        dim.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dim)

        let panel = Theme.liquidGlassView(corner: 30)
        panel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(panel)

        table.backgroundColor = .clear
        table.separatorStyle = .none
        table.alwaysBounceVertical = false
        table.rowHeight = 52
        table.register(MenuRowCell.self, forCellReuseIdentifier: "menuRow")
        table.dataSource = self
        table.delegate = self
        table.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView.addSubview(table)

        let height = min(CGFloat(items.count) * 52 + 12, 480)

        NSLayoutConstraint.activate([
            dim.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dim.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dim.topAnchor.constraint(equalTo: view.topAnchor),
            dim.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            panel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            panel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            panel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            panel.heightAnchor.constraint(equalToConstant: height),

            table.leadingAnchor.constraint(equalTo: panel.contentView.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: panel.contentView.trailingAnchor),
            table.topAnchor.constraint(equalTo: panel.contentView.topAnchor, constant: 6),
            table.bottomAnchor.constraint(equalTo: panel.contentView.bottomAnchor)
        ])
        table.isScrollEnabled = items.count > 8
    }

    @objc private func close() { dismiss(animated: true) }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "menuRow", for: indexPath) as! MenuRowCell
        cell.configure(items[indexPath.row], showSeparator: indexPath.row < items.count - 1)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let item = items[indexPath.row]
        dismiss(animated: true) { item.handler() }
    }
}

/// Tinted icon tile + label, hairline inset separator, 52pt touch row.
final class MenuRowCell: UITableViewCell {

    private let tile = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let separator = UIView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        backgroundColor = .clear
        selectionStyle = .default

        tile.layer.cornerRadius = 9
        tile.layer.cornerCurve = .continuous
        tile.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(tile)

        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        tile.addSubview(iconView)

        titleLabel.font = Theme.body(15)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        separator.backgroundColor = Theme.hairline
        separator.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(separator)

        NSLayoutConstraint.activate([
            tile.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            tile.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            tile.widthAnchor.constraint(equalToConstant: 30),
            tile.heightAnchor.constraint(equalToConstant: 30),

            iconView.centerXAnchor.constraint(equalTo: tile.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: tile.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            titleLabel.leadingAnchor.constraint(equalTo: tile.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -14),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            separator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 56),
            separator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ item: GlassMenuItem, showSeparator: Bool) {
        iconView.image = item.image
        let red = item.destructive
        tile.backgroundColor = red
            ? UIColor.systemRed.withAlphaComponent(0.12)
            : Theme.primary.withAlphaComponent(0.10)
        iconView.tintColor = red ? .systemRed : Theme.primary
        titleLabel.text = item.title
        titleLabel.textColor = red ? .systemRed : Theme.textPrimary
        separator.isHidden = !showSeparator
    }

    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: animated)
        contentView.backgroundColor = highlighted ? Theme.primary.withAlphaComponent(0.08) : .clear
    }
}
