import Foundation
import WebKit

/// Compiles the enabled filter lists into WKContentRuleLists and hands them to web views.
final class ContentBlocker {
    static let shared = ContentBlocker()

    private(set) var ruleLists: [WKContentRuleList] = []
    private var observers: [UUID: () -> Void] = [:]
    private var bundledRuleLists: [String: WKContentRuleList] = [:]
    private var compilingBundledLists: Set<String> = []
    private var failedBundledIDs: Set<String> = []
    private var didLoad = false

    var hasCompilationFailures: Bool {
        !failedBundledIDs.isEmpty || !FilterListManager.shared.failedIDs.isEmpty
    }

    /// Called whenever new rule lists become available.
    var onReady: (() -> Void)?

    func load() {
        guard !didLoad else { return }
        didLoad = true

        // Reconcile both shipped and custom subscriptions, including stored custom
        // text that has not been compiled since the previous launch.
        FilterListManager.shared.onChange = { [weak self] in
            DispatchQueue.main.async {
                self?.reconcileRuleLists()
            }
        }
        FilterListManager.shared.compileEnabled { [weak self] _ in
            DispatchQueue.main.async {
                self?.reconcileRuleLists()
            }
        }
        compileEnabledBundledLists()
    }

    /// Re-reads blocking preferences and updates existing tabs through observers.
    func refresh() {
        if !didLoad {
            load()
            return
        }
        FilterListManager.shared.compileEnabled()
        compileEnabledBundledLists()
        reconcileRuleLists()
    }

    private func compileEnabledBundledLists() {
        for identifier in ["ads", "trackers"] where isBundledListEnabled(identifier) {
            guard bundledRuleLists[identifier] == nil,
                  !compilingBundledLists.contains(identifier),
                  let url = Bundle.main.url(forResource: "blocklist_\(identifier)", withExtension: "json"),
                  let encoded = try? String(contentsOf: url, encoding: .utf8) else { continue }
            compilingBundledLists.insert(identifier)
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: "MagdyBlockList.\(identifier)",
                encodedContentRuleList: encoded
            ) { [weak self] list, _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.compilingBundledLists.remove(identifier)
                    if let list {
                        self.bundledRuleLists[identifier] = list
                        self.failedBundledIDs.remove(identifier)
                    } else {
                        self.failedBundledIDs.insert(identifier)
                    }
                    self.reconcileRuleLists()
                }
            }
        }
    }

    private func isBundledListEnabled(_ identifier: String) -> Bool {
        switch identifier {
        case "ads": return UserDefaultsKey.bool(UserDefaultsKey.blockAds, default: true)
        case "trackers": return UserDefaultsKey.bool(UserDefaultsKey.blockTrackers, default: true)
        default: return false
        }
    }

    private func reconcileRuleLists() {
        // Rebuild in stable precedence order: bundled lists first, then shipped
        // and custom subscriptions. Disabled lists detach from existing tabs.
        var reconciled: [WKContentRuleList] = []
        for identifier in ["ads", "trackers"] where isBundledListEnabled(identifier) {
            if let list = bundledRuleLists[identifier] { reconciled.append(list) }
        }
        for list in FilterListManager.shared.activeRuleLists() {
            reconciled.append(list)
        }
        ruleLists = reconciled
        broadcast()
    }

    func apply(to controller: WKUserContentController) {
        for list in ruleLists {
            guard !list.identifier.hasPrefix("MagdyBlockList.")
                    || isBundledListEnabled(String(list.identifier.dropFirst("MagdyBlockList.".count))) else { continue }
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
