import UIKit

final class PrimaryButton: UIButton {
    init(title: String) {
        super.init(frame: .zero)
        setTitle(title, for: .normal)
        var configuration = UIButton.Configuration.filled()
        configuration.baseBackgroundColor = Theme.accent
        configuration.baseForegroundColor = Theme.onAccent
        configuration.cornerStyle = .small
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: Theme.Spacing.x3,
            leading: Theme.Spacing.x4,
            bottom: Theme.Spacing.x3,
            trailing: Theme.Spacing.x4
        )
        self.configuration = configuration
        titleLabel?.font = Theme.headline
        titleLabel?.adjustsFontForContentSizeCategory = true
        heightAnchor.constraint(greaterThanOrEqualToConstant: Theme.minimumTarget).isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.82 : 1 }
    }
}

final class SecondaryButton: UIButton {
    init(title: String) {
        super.init(frame: .zero)
        setTitle(title, for: .normal)
        var configuration = UIButton.Configuration.bordered()
        configuration.baseBackgroundColor = Theme.surface
        configuration.baseForegroundColor = Theme.accentText
        configuration.background.strokeColor = Theme.border
        configuration.background.strokeWidth = 1
        configuration.cornerStyle = .small
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: Theme.Spacing.x3,
            leading: Theme.Spacing.x4,
            bottom: Theme.Spacing.x3,
            trailing: Theme.Spacing.x4
        )
        self.configuration = configuration
        titleLabel?.font = Theme.headline
        titleLabel?.adjustsFontForContentSizeCategory = true
        heightAnchor.constraint(greaterThanOrEqualToConstant: Theme.minimumTarget).isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class IconButton: UIButton {
    init(systemName: String, accessibilityLabel: String) {
        super.init(frame: .zero)
        setImage(UIImage(systemName: systemName), for: .normal)
        var configuration = UIButton.Configuration.plain()
        configuration.baseForegroundColor = Theme.textPrimary
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: Theme.Spacing.x2,
            leading: Theme.Spacing.x2,
            bottom: Theme.Spacing.x2,
            trailing: Theme.Spacing.x2
        )
        self.configuration = configuration
        self.accessibilityLabel = accessibilityLabel
        tintColor = Theme.textPrimary
        widthAnchor.constraint(greaterThanOrEqualToConstant: Theme.minimumTarget).isActive = true
        heightAnchor.constraint(greaterThanOrEqualToConstant: Theme.minimumTarget).isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class FilterChip: UIButton {
    init(title: String) {
        super.init(frame: .zero)
        setTitle(title, for: .normal)
        var configuration = UIButton.Configuration.filled()
        configuration.baseBackgroundColor = Theme.raised
        configuration.baseForegroundColor = Theme.textSecondary
        configuration.cornerStyle = .small
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: Theme.Spacing.x2,
            leading: Theme.Spacing.x3,
            bottom: Theme.Spacing.x2,
            trailing: Theme.Spacing.x3
        )
        self.configuration = configuration
        titleLabel?.font = Theme.subhead
        titleLabel?.adjustsFontForContentSizeCategory = true
        heightAnchor.constraint(greaterThanOrEqualToConstant: Theme.minimumTarget).isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isSelected: Bool {
        didSet {
            updateAppearance()
            accessibilityTraits = isSelected ? [.button, .selected] : .button
        }
    }

    private func updateAppearance() {
        var configuration = self.configuration ?? UIButton.Configuration.filled()
        configuration.baseBackgroundColor = isSelected ? Theme.accentContainer : Theme.raised
        configuration.baseForegroundColor = isSelected ? Theme.textPrimary : Theme.textSecondary
        if isSelected {
            configuration.image = UIImage(systemName: "checkmark")
            configuration.imagePlacement = .leading
            configuration.imagePadding = Theme.Spacing.x1
        } else {
            configuration.image = nil
        }
        self.configuration = configuration
    }
}

final class MediaArtworkView: UIImageView {
    private let monogram = UILabel()

    var mediaTitle: String = "" {
        didSet {
            monogram.text = mediaTitle.isEmpty ? "M" : String(mediaTitle.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased()
            accessibilityLabel = mediaTitle.isEmpty ? "Media artwork" : "Artwork for \(mediaTitle)"
        }
    }

    override init(image: UIImage?) {
        super.init(image: image)
        backgroundColor = Theme.raised
        contentMode = .scaleAspectFill
        clipsToBounds = true
        layer.cornerRadius = Theme.Radius.control
        monogram.font = Theme.title
        monogram.textColor = Theme.textSecondary
        monogram.textAlignment = .center
        monogram.translatesAutoresizingMaskIntoConstraints = false
        addSubview(monogram)
        NSLayoutConstraint.activate([
            monogram.centerXAnchor.constraint(equalTo: centerXAnchor),
            monogram.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        isAccessibilityElement = true
        accessibilityTraits = .image
        mediaTitle = ""
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var image: UIImage? {
        didSet { monogram.isHidden = image != nil }
    }
}

final class EmptyStateView: UIView {
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let actionButton = SecondaryButton(title: "")

    var actionTitle: String? {
        didSet {
            actionButton.setTitle(actionTitle ?? "", for: .normal)
            actionButton.isHidden = actionTitle == nil
        }
    }

    var actionHandler: (() -> Void)? {
        didSet {
            actionButton.removeTarget(nil, action: nil, for: .touchUpInside)
            if actionHandler != nil {
                actionButton.addTarget(self, action: #selector(performAction), for: .touchUpInside)
            }
        }
    }

    init(systemName: String, title: String, message: String) {
        super.init(frame: .zero)
        iconView.image = UIImage(systemName: systemName)
        iconView.tintColor = Theme.accent
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = title
        titleLabel.font = Theme.title
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = Theme.textPrimary
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.text = message
        messageLabel.font = Theme.bodyStyle
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.textColor = Theme.textSecondary
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        actionButton.isHidden = true

        let stack = UIStackView(arrangedSubviews: [iconView, titleLabel, messageLabel, actionButton])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = Theme.Spacing.x3
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: Theme.Spacing.x6),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Theme.Spacing.x6),
            iconView.widthAnchor.constraint(equalToConstant: 40),
            iconView.heightAnchor.constraint(equalToConstant: 40)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func performAction() {
        actionHandler?()
    }
}
