import Foundation
import WebKit

/// A shipped filter list (Adblock Plus syntax).
struct FilterList: Decodable {
    let id: String
    let title: String
    let source: String
    let bytes: Int
    let domains: Int
}

/// Compiles the shipped filter lists into WebKit content rule lists and lets the
/// user switch individual lists on and off.
final class FilterListManager {
    static let shared = FilterListManager()

    private(set) var lists: [FilterList] = []
    private(set) var compiled: [String: WKContentRuleList] = [:]
    private var observers: [UUID: () -> Void] = [:]
    /// Domains the active lists block — used by the ad-block counter audit.
    private(set) var blockedDomains: Set<String> = []

    private let enabledKey = "magdy.filterLists.enabled"

    var onChange: (() -> Void)?

    var enabledIDs: Set<String> {
        get {
            let stored = UserDefaults.standard.stringArray(forKey: enabledKey)
            return Set(stored ?? ["easylist", "easyprivacy"])
        }
        set {
            UserDefaults.standard.set(Array(newValue).sorted(), forKey: enabledKey)
            onChange?()
        }
    }

    private init() {
        loadManifest()
    }

    // MARK: - Manifest

    private func loadManifest() {
        guard let url = Bundle.main.url(forResource: "manifest", withExtension: "json", subdirectory: "filters"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([FilterList].self, from: data) else { return }
        lists = decoded
    }

    // MARK: - Compilation

    /// Compiles every enabled list and hands the resulting rule lists to the observers.
    func compileEnabled(completion: ((_ ruleLists: [WKContentRuleList]) -> Void)? = nil) {
        let wanted = enabledIDs
        let pending = lists.filter { wanted.contains($0.id) && compiled[$0.id] == nil }

        guard !pending.isEmpty else {
            completion?(Array(compiled.values))
            return
        }

        let group = DispatchGroup()
        for list in pending {
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                guard let url = Bundle.main.url(forResource: list.id, withExtension: "txt", subdirectory: "filters"),
                      let text = try? String(contentsOf: url, encoding: .utf8) else {
                    group.leave()
                    return
                }
                let encoded = Self.encode(rules: Self.rules(from: text))
                WKContentRuleListStore.default().compileContentRuleList(
                    forIdentifier: "MagdyFilter.\(list.id)",
                    encodedContentRuleList: encoded
                ) { [weak self] ruleList, _ in
                    if let ruleList { self?.compiled[list.id] = ruleList }
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.collectBlockedDomains()
            let ruleLists = self.enabledIDs.compactMap { self.compiled[$0] }
            completion?(ruleLists)
            self.observers.values.forEach { $0() }
            self.onChange?()
        }
    }

    /// Compiles a user-added list that was downloaded by CustomFilterListStore.
    func compileCustomText(id: String, text: String) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let encoded = Self.encode(rules: Self.rules(from: text))
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: "MagdyFilter.\(id)",
                encodedContentRuleList: encoded
            ) { [weak self] ruleList, _ in
                guard let self, let ruleList else { return }
                self.compiled[id] = ruleList
                self.collectBlockedDomains()
                DispatchQueue.main.async {
                    self.observers.values.forEach { $0() }
                    self.onChange?()
                }
            }
        }
    }

    /// Removes a compiled custom list and tells observers to refresh.
    func removeRuleList(withIdentifier identifier: String) {
        compiled.removeValue(forKey: identifier)
        WKContentRuleListStore.default().removeContentRuleList(forIdentifier: "MagdyFilter.\(identifier)")
        collectBlockedDomains()
        observers.values.forEach { $0() }
        onChange?()
    }

    private func collectBlockedDomains() {
        var domains = Set<String>()
        for id in enabledIDs {
            guard let url = Bundle.main.url(forResource: id, withExtension: "txt", subdirectory: "filters"),
                  let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            Self.appendDomains(from: text, into: &domains)
        }
        for entry in CustomFilterListStore.shared.entries {
            guard let text = CustomFilterListStore.shared.storedText(for: entry) else { continue }
            Self.appendDomains(from: text, into: &domains)
        }
        blockedDomains = domains
    }

    private static func appendDomains(from text: String, into set: inout Set<String>) {
        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("!"), !line.hasPrefix("[") else { continue }
            if let domain = domain(in: line) {
                set.insert(domain)
            }
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

    /// Rule lists that should be attached to a web view right now.
    func activeRuleLists() -> [WKContentRuleList] {
        enabledIDs.compactMap { compiled[$0] }
    }

    // MARK: - Parsing

    /// Converts Adblock Plus syntax into WebKit content-rule JSON objects.
    static func rules(from text: String) -> [[String: Any]] {
        var rules: [[String: Any]] = []
        var seen = Set<String>()

        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("!") || line.hasPrefix("[") { continue }
            if line.hasPrefix("##") || line.hasPrefix("#@#") || line.hasPrefix("#?#") { continue }

            if line.hasPrefix("@@") {
                guard let domain = domain(in: String(line.dropFirst(2))) else { continue }
                let rule: [String: Any] = [
                    "trigger": ["url-filter": ".*", "if-domain": ["*\(domain)"]],
                    "action": ["type": "ignore-previous-rules"]
                ]
                if seen.insert("ignore-\(domain)").inserted { rules.append(rule) }
                continue
            }

            if let domain = domain(in: line) {
                let rule: [String: Any] = [
                    "trigger": ["url-filter": ".*", "if-domain": ["*\(domain)"]],
                    "action": ["type": "block"]
                ]
                if seen.insert(domain).inserted { rules.append(rule) }
                continue
            }

            if line.hasPrefix("/") {
                let body = String(line.dropFirst()).split(separator: "/", maxSplits: 1).first.map(String.init) ?? ""
                if body.isEmpty { continue }
                let rule: [String: Any] = [
                    "trigger": ["url-filter": body],
                    "action": ["type": "block"]
                ]
                rules.append(rule)
            }
        }
        return rules
    }

    private static func domain(in rule: String) -> String? {
        var body = rule
        for marker in ["$", "|", "^", "*", "/"] where body.contains(marker) {
            if let range = body.range(of: marker) {
                body = String(body[body.startIndex..<range.lowerBound])
            }
        }
        body = body.replacingOccurrences(of: "||", with: "")
        let parts = body.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        let candidate = parts.suffix(2).joined(separator: ".")
        guard candidate.contains(".") else { return nil }
        return candidate
    }

    private static func encode(rules: [[String: Any]]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: rules),
              let text = String(data: data, encoding: .utf8) else { return "[]" }
        return text
    }
}
