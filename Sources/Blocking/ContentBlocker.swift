import Foundation
import WebKit

/// Compiles the bundled filter lists into WKContentRuleLists and hands them to web views.
final class ContentBlocker {
    static let shared = ContentBlocker()

    private(set) var ruleLists: [WKContentRuleList] = []
    private var didLoad = false

    /// Called once the lists finished compiling.
    var onReady: (() -> Void)?

    func load() {
        guard !didLoad else { return }
        didLoad = true

        let identifiers = ["ads", "trackers"]
        for identifier in identifiers {
            guard let url = Bundle.main.url(forResource: "blocklist_\(identifier)", withExtension: "json"),
                  let data = try? Data(contentsOf: url) else { continue }
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: "MagdyBlockList.\(identifier)",
                encodedContentRuleList: data
            ) { [weak self] list, _ in
                guard let self, let list else { return }
                self.ruleLists.append(list)
                self.onReady?()
            }
        }
    }

    func apply(to controller: WKUserContentController) {
        controller.addAll(ruleLists)
    }
}
