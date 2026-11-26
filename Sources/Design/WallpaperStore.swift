import UIKit

/// Start-page wallpaper. The chosen image is copied into the app container so the
/// web view can reference it with a relative URL.
final class WallpaperStore {
    static let shared = WallpaperStore()

    private let selectionKey = "magdy.wallpaper"
    private static let fileNames = ["current-wallpaper.png", "current-wallpaper.jpg"]

    private init() {}

    /// Wallpapers shipped in the bundle.
    static func available() -> [String] {
        guard let url = Bundle.main.url(forResource: "Wallpapers", withExtension: nil),
              let files = try? FileManager.default.contentsOfDirectory(atPath: url.path) else { return [] }
        return files.filter { ["png", "jpg", "jpeg"].contains(($0 as NSString).pathExtension.lowercased()) }.sorted()
    }

    var selectedName: String? {
        get {
            guard let stored = UserDefaults.standard.string(forKey: selectionKey) else { return nil }
            if stored.lowercased().hasSuffix(".png") {
                let stem = (stored as NSString).deletingPathExtension
                if Bundle.main.url(forResource: stem, withExtension: "jpg", subdirectory: "Wallpapers") != nil {
                    let migrated = "\(stem).jpg"
                    UserDefaults.standard.set(migrated, forKey: selectionKey)
                    return migrated
                }
            }
            return stored
        }
        set { UserDefaults.standard.set(newValue, forKey: selectionKey) }
    }

    /// Copies the chosen wallpaper into Documents and returns its relative file name.
    func materialiseSelection() -> String? {
        guard let name = selectedName,
              let source = Bundle.main.url(forResource: name, withExtension: nil, subdirectory: "Wallpapers") else { return nil }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileName = "current-wallpaper.\(source.pathExtension.lowercased())"
        let destination = docs.appendingPathComponent(fileName)
        for staleName in Self.fileNames where staleName != fileName {
            try? FileManager.default.removeItem(at: docs.appendingPathComponent(staleName))
        }
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.copyItem(at: source, to: destination)
            return fileName
        } catch {
            return nil
        }
    }

    /// Base URL used when rendering the start page so relative resources resolve.
    var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    func clear() {
        selectedName = nil
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        for fileName in Self.fileNames {
            try? FileManager.default.removeItem(at: docs.appendingPathComponent(fileName))
        }
    }
}
