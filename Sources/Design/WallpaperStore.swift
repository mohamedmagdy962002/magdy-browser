import UIKit

/// Start-page wallpaper. The chosen image is copied into the app container so the
/// web view can reference it with a relative URL.
enum WallpaperStore {
    static let shared = WallpaperStore()

    private let selectionKey = "magdy.wallpaper"
    private static let fileName = "current-wallpaper.png"

    /// Wallpapers shipped in the bundle.
    static func available() -> [String] {
        guard let url = Bundle.main.url(forResource: "Wallpapers", withExtension: nil),
              let files = try? FileManager.default.contentsOfDirectory(atPath: url.path) else { return [] }
        return files.filter { $0.hasSuffix(".png") }.sorted()
    }

    var selectedName: String? {
        get { UserDefaults.standard.string(forKey: selectionKey) }
        set { UserDefaults.standard.set(newValue, forKey: selectionKey) }
    }

    /// Copies the chosen wallpaper into Documents and returns its relative file name.
    func materialiseSelection() -> String? {
        guard let name = selectedName,
              let source = Bundle.main.url(forResource: name, withExtension: nil, subdirectory: "Wallpapers") else { return nil }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let destination = docs.appendingPathComponent(Self.fileName)
        try? FileManager.default.removeItem(at: destination)
        try? FileManager.default.copyItem(at: source, to: destination)
        return Self.fileName
    }

    /// Base URL used when rendering the start page so relative resources resolve.
    var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    func clear() {
        selectedName = nil
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? FileManager.default.removeItem(at: docs.appendingPathComponent(Self.fileName))
    }
}
