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
/// frosted panel docked at the bottom, one row per action.
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

        let panel = Theme.liquidGlassView(corner: 28)
        panel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(panel)

        table.backgroundColor = .clear
        table.separatorStyle = .none
        table.alwaysBounceVertical = false
        table.register(UITableViewCell.self, forCellReuseIdentifier: "menuRow")
        table.dataSource = self
        table.delegate = self
        table.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView.addSubview(table)

        let height = min(CGFloat(items.count) * 48 + 16, 460)

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
            table.topAnchor.constraint(equalTo: panel.contentView.topAnchor, constant: 8),
            table.bottomAnchor.constraint(equalTo: panel.contentView.bottomAnchor)
        ])
        table.isScrollEnabled = items.count > 9
    }

    @objc private func close() { dismiss(animated: true) }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "menuRow", for: indexPath)
        let item = items[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.image = item.image
        content.imageProperties.tintColor = item.destructive ? .systemRed : Theme.primary
        content.text = item.title
        content.textProperties.font = Theme.body(15)
        content.textProperties.color = item.destructive ? .systemRed : Theme.textPrimary
        content.imageToTextPadding = 14
        cell.contentConfiguration = content
        cell.backgroundColor = .clear
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { 48 }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let item = items[indexPath.row]
        dismiss(animated: true) { item.handler() }
    }
}
