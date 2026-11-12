import Foundation
import WebKit

/// Compiles the bundled filter lists into WKContentRuleLists and hands them to web views.
final class ContentBlocker {
    static let shared = ContentBlocker()

    private(set) var ruleLists: [WKContentRuleList] = []
    private var observers: [UUID: () -> Void] = [:]
    private var didLoad = false

    /// Called whenever new rule lists become available.
    var onReady: (() -> Void)?

    func load() {
        guard !didLoad else { return }
        didLoad = true

        // Small curated lists apply instantly; the large upstream lists compile in the background.
        for identifier in ["ads", "trackers"] {
            guard let url = Bundle.main.url(forResource: "blocklist_\(identifier)", withExtension: "json"),
                  let encoded = try? String(contentsOf: url, encoding: .utf8) else { continue }
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: "MagdyBlockList.\(identifier)",
                encodedContentRuleList: encoded
            ) { [weak self] list, _ in
                guard let self, let list else { return }
                self.ruleLists.append(list)
                self.broadcast()
            }
        }

        // Upstream filter lists (EasyList, EasyPrivacy, regionals).
        FilterListManager.shared.compileEnabled { [weak self] compiled in
            guard let self else { return }
            for list in compiled where !self.ruleLists.contains(where: { $0.identifier == list.identifier }) {
                self.ruleLists.append(list)
            }
            self.broadcast()
        }
    }

    func apply(to controller: WKUserContentController) {
        for list in ruleLists {
            controller.add(list)
        }
    }

    func observe(_ block: @escaping () -> Void) -> UUID {
        let id = UUID()
        observers[id] = block
        return id
    }

    func removeObserver(_ id: UUID) {
        observers.removeValue(forKey: id)
    }

    private func broadcast() {
        onReady?()
        observers.values.forEach { $0() }
    }
}
