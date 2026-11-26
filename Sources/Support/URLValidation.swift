import Foundation

extension URL {
    static func webURL(from rawValue: String) -> URL? {
        let text = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if let url = URL(string: text), url.isWebURL { return url }
        let hasExplicitScheme = text.range(
            of: "^[A-Za-z][A-Za-z0-9+.-]*://",
            options: .regularExpression
        ) != nil
        guard !hasExplicitScheme else { return nil }
        let url = URL(string: "https://\(text)")
        return url?.isWebURL == true ? url : nil
    }

    var isWebURL: Bool {
        guard let scheme = scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = host, !host.isEmpty else { return false }
        return true
    }
}
