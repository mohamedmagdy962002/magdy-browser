import Foundation
import UIKit

final class LibraryAggregator {
    private(set) var snapshot: LibrarySnapshot
    var onChange: (() -> Void)?
    private let center: NotificationCenter
    private var observers: [NSObjectProtocol] = []

    init(center: NotificationCenter = .default) {
        self.center = center
        snapshot = Self.makeSnapshot()
        let names: [Notification.Name] = [
            .magdyDownloadsChanged,
            .magdyLibraryChanged,
            UIApplication.didBecomeActiveNotification
        ]
        observers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refresh()
            }
        }
    }

    deinit {
        for observer in observers {
            center.removeObserver(observer)
        }
    }

    func refresh() {
        snapshot = Self.makeSnapshot()
        onChange?()
    }

    private static func makeSnapshot() -> LibrarySnapshot {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return DownloadManager.shared.withReadOnlyLibraryFolder { customFolder in
            var files = LibraryFileRecord.read(in: documents)
            if let customFolder {
                files.append(contentsOf: LibraryFileRecord.read(in: customFolder))
            }
            let downloadsFolder = documents.appendingPathComponent("Downloads", isDirectory: true)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: downloadsFolder.path, isDirectory: &isDirectory), isDirectory.boolValue {
                files.append(contentsOf: LibraryFileRecord.read(in: downloadsFolder))
            }
            return LibrarySnapshot.make(
                downloads: DownloadManager.shared.items,
                favorites: FavoritesStore.shared.favorites,
                history: HistoryStore.shared.entries,
                readingList: ReadingListStore.shared.items,
                localFiles: files
            )
        }
    }
}
