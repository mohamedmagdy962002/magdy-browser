import Foundation

/// Builds the start page: speed-dial tiles from favorites and frequently visited sites.
enum SpeedDialPage {

    struct Tile {
        let title: String
        let url: String
        let letter: String
        let color: String
    }

    static func tiles() -> [Tile] {
        var result: [Tile] = []
        var seen = Set<String>()

        for favorite in FavoritesStore.shared.favorites.prefix(8) {
            guard let host = URL(string: favorite.url)?.host, !seen.contains(host) else { continue }
            seen.insert(host)
            result.append(Tile(
                title: favorite.title.isEmpty ? host : favorite.title,
                url: favorite.url,
                letter: letter(for: host),
                color: color(for: host)
            ))
        }

        for top in HistoryStore.shared.topDomains(limit: 12) where result.count < 16 {
            guard !seen.contains(top.domain) else { continue }
            seen.insert(top.domain)
            result.append(Tile(
                title: top.title.isEmpty ? top.domain : top.title,
                url: "https://\(top.domain)",
                letter: letter(for: top.domain),
                color: color(for: top.domain)
            ))
        }
        return result
    }

    static func html() -> String {
        let tiles = tiles()
        let tileHTML = tiles.map { tile in
            let url = escape(tile.url)
            return """
            <a class="tile" href="\(url)">
              <span class="badge" style="background:\(tile.color)">\(escape(tile.letter))</span>
              <span class="label">\(escape(tile.title))</span>
              <span class="host">\(escape(URL(string: tile.url)?.host ?? tile.url))</span>
            </a>
            """
        }.joined(separator: "\n")

        let empty = tiles.isEmpty
            ? "<p class=\"empty\">Downloads and favorites you add will show up here as tiles.</p>"
            : ""

        return """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>
          body{font:-apple-system-body;margin:0;padding:24px;background:#f2f2f7;color:#111}
          h1{font-size:26px;margin:0 0 4px}
          p.note{color:#666;font-size:14px;margin:0 0 22px}
          p.empty{color:#8e8e93;font-size:14px}
          .grid{display:flex;flex-wrap:wrap;gap:14px}
          .tile{width:calc(33.333% - 10px);background:#fff;border-radius:16px;padding:14px 10px;
                text-decoration:none;color:#111;display:flex;flex-direction:column;align-items:center;
                box-shadow:0 1px 2px rgba(0,0,0,.08)}
          .badge{width:46px;height:46px;border-radius:14px;color:#fff;font-weight:700;font-size:22px;
                 display:flex;align-items:center;justify-content:center;margin-bottom:8px}
          .label{font-size:12px;font-weight:600;text-align:center;
                 overflow:hidden;text-overflow:ellipsis;white-space:nowrap;max-width:100%}
          .host{font-size:10px;color:#8e8e93;margin-top:2px;
                overflow:hidden;text-overflow:ellipsis;white-space:nowrap;max-width:100%}
        </style></head>
        <body>
          <h1>Magdy Browser</h1>
          <p class="note">\(escape(L.t("unlimited_note")))</p>
          <div class="grid">
          \(tileHTML)
          </div>
          \(empty)
        </body></html>
        """
    }

    private static func letter(for host: String) -> String {
        String(host.prefix(1)).uppercased()
    }

    private static func color(for host: String) -> String {
        let palette = ["#4A47F0", "#8A3FFC", "#0A84FF", "#30D158", "#FF9F0A", "#FF375F", "#64D2FF", "#BF5AF2"]
        let hash = host.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) }
        return palette[abs(hash) % palette.count]
    }

    static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
