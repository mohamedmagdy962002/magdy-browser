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
    private(set) var exceptionDomains: Set<String> = []
    /// Persisted IDs for enabled custom lists, using the same IDs as `compiled`.
    private(set) var activeCustomIDs: Set<String> = []
    private(set) var failedIDs: Set<String> = []
    private var domainGeneration: UInt64 = 0

    private let enabledKey = "magdy.filterLists.enabled"
    private let customEnabledKey = "magdy.customFilterLists.enabled"

    var onChange: (() -> Void)?

    var enabledIDs: Set<String> {
        get {
            let stored = UserDefaults.standard.stringArray(forKey: enabledKey)
            return Set(stored ?? ["easylist", "easyprivacy"])
        }
        set {
            UserDefaults.standard.set(Array(newValue).sorted(), forKey: enabledKey)
            collectBlockedDomains()
            notifyChange()
        }
    }

    private init() {
        loadManifest()
        loadCustomState()
    }

    // MARK: - Manifest

    private func loadManifest() {
        guard let url = Bundle.main.url(forResource: "manifest", withExtension: "json", subdirectory: "filters"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([FilterList].self, from: data) else { return }
        lists = decoded
    }

    private func loadCustomState() {
        let known = customIdentifiers
        if let stored = UserDefaults.standard.stringArray(forKey: customEnabledKey) {
            activeCustomIDs = Set(stored).intersection(known)
            saveCustomState()
        } else {
            // Existing custom subscriptions remain enabled when the new key is absent.
            activeCustomIDs = known
            saveCustomState()
        }
    }

    private var customIdentifiers: Set<String> {
        Set(CustomFilterListStore.shared.entries.map { "custom.\($0.id.uuidString)" })
    }

    private func saveCustomState() {
        UserDefaults.standard.set(Array(activeCustomIDs).sorted(), forKey: customEnabledKey)
    }

    /// Enables or disables a stored custom subscription and persists that choice.
    func setCustomList(_ id: String, enabled: Bool) {
        guard customIdentifiers.contains(id) else { return }
        if enabled {
            activeCustomIDs.insert(id)
        } else {
            activeCustomIDs.remove(id)
        }
        saveCustomState()
        collectBlockedDomains()
        if enabled, compiled[id] == nil {
            compileStoredCustomList(id) { [weak self] _ in
                self?.collectBlockedDomains()
                self?.notifyChange()
            }
        }
        notifyChange()
    }

    // MARK: - Compilation

    /// Compiles every enabled shipped and stored custom list.
    func compileEnabled(completion: ((_ ruleLists: [WKContentRuleList]) -> Void)? = nil) {
        collectBlockedDomains()
        let wanted = UserDefaultsKey.bool(UserDefaultsKey.strongBlocking, default: true) ? enabledIDs : []
        let wantedCustom = activeCustomIDs.intersection(customIdentifiers)
        let pending = lists.filter { wanted.contains($0.id) && compiled[$0.id] == nil }
        let pendingCustom = wantedCustom.filter { compiled[$0] == nil }

        guard !pending.isEmpty || !pendingCustom.isEmpty else {
            completion?(activeRuleLists())
            notifyChange()
            return
        }

        let group = DispatchGroup()
        for list in pending {
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                guard let url = Bundle.main.url(forResource: list.id, withExtension: "txt", subdirectory: "filters"),
                      let text = try? String(contentsOf: url, encoding: .utf8) else {
                    DispatchQueue.main.async { self.failedIDs.insert(list.id) }
                    group.leave()
                    return
                }
                let encoded = Self.encode(rules: Self.rules(from: text))
                WKContentRuleListStore.default().compileContentRuleList(
                    forIdentifier: "MagdyFilter.\(list.id)",
                    encodedContentRuleList: encoded
                ) { [weak self] ruleList, _ in
                    DispatchQueue.main.async {
                        if let ruleList {
                            self?.compiled[list.id] = ruleList
                            self?.failedIDs.remove(list.id)
                        } else {
                            self?.failedIDs.insert(list.id)
                        }
                        group.leave()
                    }
                }
            }
        }

        for id in pendingCustom {
            group.enter()
            compileStoredCustomList(id) { _ in
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.collectBlockedDomains()
            completion?(self.activeRuleLists())
            self.notifyChange()
        }
    }

    /// Compiles a user-added list that was downloaded by CustomFilterListStore.
    func compileCustomText(id: String, text: String, completion: ((Bool) -> Void)? = nil) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let encoded = Self.encode(rules: Self.rules(from: text))
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: "MagdyFilter.\(id)",
                encodedContentRuleList: encoded
            ) { [weak self] ruleList, _ in
                DispatchQueue.main.async {
                    guard let self else { completion?(false); return }
                    if let ruleList {
                        self.compiled[id] = ruleList
                        self.failedIDs.remove(id)
                    } else {
                        self.failedIDs.insert(id)
                    }
                    self.collectBlockedDomains()
                    self.notifyChange()
                    completion?(ruleList != nil)
                }
            }
        }
    }

    private func compileStoredCustomList(_ id: String, completion: ((Bool) -> Void)? = nil) {
        guard let entry = CustomFilterListStore.shared.entries.first(where: { "custom.\($0.id.uuidString)" == id }) else {
            completion?(false)
            return
        }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let text = CustomFilterListStore.shared.storedText(for: entry) else {
                DispatchQueue.main.async {
                    self?.failedIDs.insert(id)
                    completion?(false)
                }
                return
            }
            let encoded = Self.encode(rules: Self.rules(from: text))
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: "MagdyFilter.\(id)",
                encodedContentRuleList: encoded
            ) { [weak self] ruleList, _ in
                DispatchQueue.main.async {
                    if let ruleList {
                        self?.compiled[id] = ruleList
                        self?.failedIDs.remove(id)
                    } else {
                        self?.failedIDs.insert(id)
                    }
                    completion?(ruleList != nil)
                }
            }
        }
    }

    /// Removes a compiled list (including its custom enabled state) and tells observers to refresh.
    func removeRuleList(withIdentifier identifier: String) {
        compiled.removeValue(forKey: identifier)
        failedIDs.remove(identifier)
        if activeCustomIDs.remove(identifier) != nil {
            saveCustomState()
        }
        WKContentRuleListStore.default().removeContentRuleList(forIdentifier: "MagdyFilter.\(identifier)", completionHandler: nil)
        collectBlockedDomains()
        notifyChange()
    }

    private func collectBlockedDomains() {
        domainGeneration &+= 1
        let generation = domainGeneration
        let strong = UserDefaultsKey.bool(UserDefaultsKey.strongBlocking, default: true)
        let enabled = enabledIDs
        let customEntries = CustomFilterListStore.shared.entries
        let customIDs = activeCustomIDs
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var domains = Set<String>()
            var exceptions = Set<String>()
            if strong {
                for id in enabled {
                    guard let url = Bundle.main.url(forResource: id, withExtension: "txt", subdirectory: "filters"),
                          let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                    Self.appendDomains(from: text, into: &domains, exceptions: &exceptions)
                }
            }
            for entry in customEntries {
                let id = "custom.\(entry.id.uuidString)"
                guard customIDs.contains(id),
                      let text = CustomFilterListStore.shared.storedText(for: entry) else { continue }
                Self.appendDomains(from: text, into: &domains, exceptions: &exceptions)
            }
            DispatchQueue.main.async {
                guard let self, generation == self.domainGeneration else { return }
                self.exceptionDomains = exceptions
                self.blockedDomains = domains.subtracting(exceptions)
            }
        }
    }

    private static func appendDomains(from text: String, into set: inout Set<String>, exceptions: inout Set<String>) {
        for raw in text.split(separator: "\n") {
            guard let parsed = parsedRule(raw) else { continue }
            guard let domain = parsed.host, parsed.hostOnly else { continue }
            if parsed.isException {
                exceptions.insert(domain)
            } else {
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
        var lists: [WKContentRuleList] = []
        if UserDefaultsKey.bool(UserDefaultsKey.strongBlocking, default: true) {
            for list in self.lists where enabledIDs.contains(list.id) {
                if let ruleList = compiled[list.id] { lists.append(ruleList) }
            }
        }
        for entry in CustomFilterListStore.shared.entries {
            let id = "custom.\(entry.id.uuidString)"
            if activeCustomIDs.contains(id), let ruleList = compiled[id] { lists.append(ruleList) }
        }
        return lists
    }

    private func notifyChange() {
        observers.values.forEach { $0() }
        onChange?()
    }

    // MARK: - Parsing

    private struct ParsedRule {
        let pattern: String
        let options: String?
        let isException: Bool
        let host: String?
        let hostOnly: Bool
    }

    /// Converts common Adblock Plus syntax into WebKit content-rule JSON objects.
    static func rules(from text: String) -> [[String: Any]] {
        var rules: [[String: Any]] = []
        var seen = Set<String>()

        for raw in text.split(separator: "\n") {
            guard let parsed = parsedRule(raw) else { continue }
            let dedupeKey = "\(parsed.isException ? "ignore" : "block")|\(parsed.pattern)|\(parsed.options ?? "")"
            guard seen.insert(dedupeKey).inserted else { continue }

            var trigger: [String: Any] = [:]
            let hasDomainOption = parsed.options?.split(separator: ",").contains {
                String($0).trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("domain=")
            } == true
            if let host = parsed.host, parsed.hostOnly, !hasDomainOption {
                // A domain rule must retain every label: ads.google.com must not
                // broaden to google.com (or the public suffix co.uk).
                trigger["url-filter"] = ".*"
                trigger["if-domain"] = ["*\(host)"]
            } else if let regex = regexFilter(for: parsed.pattern) {
                trigger["url-filter"] = regex
            } else {
                continue
            }
            guard Self.options(parsed.options, into: &trigger) else { continue }
            rules.append([
                "trigger": trigger,
                "action": ["type": parsed.isException ? "ignore-previous-rules" : "block"]
            ])
        }
        return rules.filter { ($0["action"] as? [String: String])?["type"] == "block" }
            + rules.filter { ($0["action"] as? [String: String])?["type"] == "ignore-previous-rules" }
    }

    private static func parsedRule(_ raw: Substring) -> ParsedRule? {
        var body = String(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty,
              !body.hasPrefix("!"),
              !body.hasPrefix("["),
              !body.hasPrefix("##"),
              !body.hasPrefix("#@#"),
              !body.hasPrefix("#?#") else { return nil }

        let isException = body.hasPrefix("@@")
        if isException { body.removeFirst(2) }

        let options: String?
        if let separator = body.firstIndex(of: "$") {
            options = String(body[body.index(after: separator)...])
            body = String(body[..<separator])
        } else {
            options = nil
        }
        guard !body.isEmpty,
              body.range(of: "##") == nil,
              body.range(of: "#@#") == nil,
              body.range(of: "#?#") == nil else { return nil }
        let host = hostRule(in: body)
        return ParsedRule(pattern: body, options: options, isException: isException, host: host?.domain, hostOnly: host?.hostOnly == true)
    }

    private static func hostRule(in pattern: String) -> (domain: String, hostOnly: Bool)? {
        var body = pattern
        let hasHostAnchor = body.hasPrefix("||")
        let hasStartAnchor = body.hasPrefix("|")
        if hasHostAnchor {
            body.removeFirst(2)
        } else if hasStartAnchor {
            body.removeFirst()
        }

        let separators = CharacterSet(charactersIn: "/^*|?#")
        let end = body.rangeOfCharacter(from: separators)?.lowerBound ?? body.endIndex
        let candidate = String(body[..<end])
        let remainder = String(body[end...])
        guard remainder.allSatisfy({ $0 == "^" || $0 == "|" }), !remainder.contains("|") else { return nil }
        guard hasHostAnchor || !hasStartAnchor else { return nil }

        let domain = candidate.lowercased()
        guard domain.contains("."), !domain.contains(":"), !domain.contains(" ") else { return nil }
        let labels = domain.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2,
              labels.allSatisfy({ !$0.isEmpty && $0.count <= 63 && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" } }) else { return nil }
        return (domain, true)
    }

    private static func regexFilter(for pattern: String) -> String? {
        if pattern.hasPrefix("/"), pattern.count > 2 {
            let contents = pattern.dropFirst()
            if let closing = contents.lastIndex(of: "/") {
                let regex = String(contents[..<closing])
                if !regex.isEmpty { return regex }
            }
        }

        var body = pattern
        var result = ""
        if body.hasPrefix("||") {
            body.removeFirst(2)
            result = "^https?://(?:[^/?#]+\\.)?"
        } else if body.hasPrefix("|") {
            body.removeFirst()
            result = "^"
        }

        let hasEndAnchor = body.hasSuffix("|")
        if hasEndAnchor { body.removeLast() }
        let regexSpecials = CharacterSet(charactersIn: ".^$+?()[]{}|\\")
        for character in body {
            switch character {
            case "*": result += ".*"
            case "^": result += "[^a-zA-Z0-9_.%\\-]"
            default:
                result += character.unicodeScalars.contains { regexSpecials.contains($0) } ? "\\\(character)" : String(character)
            }
        }
        if hasEndAnchor { result += "$" }
        return result.isEmpty ? nil : result
    }

    @discardableResult
    private static func options(_ raw: String?, into trigger: inout [String: Any]) -> Bool {
        guard let raw else { return true }
        let resourceTypes = [
            "script": "script", "image": "image", "stylesheet": "style-sheet", "font": "font",
            "media": "media", "xhr": "raw", "xmlhttprequest": "raw", "document": "document",
            "subdocument": "document", "popup": "popup", "other": "other", "websocket": "raw"
        ]
        var types: [String] = []
        var domains: [String] = []
        var unlessDomains: [String] = []
        var loadTypes: [String] = []
        var hasNegatedType = false

        for part in raw.split(separator: ",") {
            let option = String(part).trimmingCharacters(in: .whitespaces).lowercased()
            if option.hasPrefix("~"), resourceTypes[String(option.dropFirst())] != nil {
                hasNegatedType = true
            } else if let type = resourceTypes[option], !types.contains(type) {
                types.append(type)
            } else if option.hasPrefix("domain=") {
                for value in option.dropFirst("domain=".count).split(separator: "|") {
                    let isException = value.hasPrefix("~")
                    var domain = String(isException ? value.dropFirst() : value)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .lowercased()
                    if domain.hasPrefix("*.") { domain.removeFirst(2) }
                    if domain.hasPrefix("*") { domain.removeFirst() }
                    domain = domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
                    guard !domain.isEmpty, !domain.contains("/"), !domain.contains(" ") else { continue }
                    let escapedDomain = domain.replacingOccurrences(of: ".", with: "\\.")
                    let topURLPattern = "^https?://(?:[^/?#]+\\.)?\(escapedDomain)(?::[0-9]+)?(?:[/?#]|$)"
                    if isException {
                        if !unlessDomains.contains(topURLPattern) { unlessDomains.append(topURLPattern) }
                    } else {
                        if !domains.contains(topURLPattern) { domains.append(topURLPattern) }
                    }
                }
            } else if option == "third-party" || option == "~third-party" {
                let type = option == "third-party" ? "third-party" : "first-party"
                if !loadTypes.contains(type) { loadTypes.append(type) }
            }
        }
        guard !hasNegatedType else { return false }
        if !types.isEmpty { trigger["resource-type"] = types }
        if !domains.isEmpty { trigger["if-top-url"] = domains }
        if !unlessDomains.isEmpty { trigger["unless-top-url"] = unlessDomains }
        if !loadTypes.isEmpty { trigger["load-type"] = loadTypes }
        return true
    }

    private static func encode(rules: [[String: Any]]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: rules),
              let text = String(data: data, encoding: .utf8) else { return "[]" }
        return text
    }
}
