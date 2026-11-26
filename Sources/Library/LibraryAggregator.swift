import Foundation
import UIKit

final class LibraryAggregator {
    private(set) var snapshot: LibrarySnapshot
    var onChange: (() -> Void)?
    private let center: NotificationCenter
    private var observers: [NSObjectProtocol] = []
    private var folderAccess: DownloadManager.FolderAccess?
    private var refreshWorkItem: DispatchWorkItem?
    private var pendingCompletions: [() -> Void] = []

    init(center: NotificationCenter = .default) {
        self.center = center
        folderAccess = DownloadManager.shared.retainReadOnlyLibraryFolder()
        snapshot = Self.makeSnapshot(customFolder: folderAccess?.url)
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
        refreshWorkItem?.cancel()
        for observer in observers {
            center.removeObserver(observer)
        }
    }

    func refresh(completion: (() -> Void)? = nil) {
        if let completion {
            pendingCompletions.append(completion)
        }
        guard refreshWorkItem == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.refreshWorkItem = nil
            self.folderAccess = DownloadManager.shared.retainReadOnlyLibraryFolder()
            self.snapshot = Self.makeSnapshot(customFolder: self.folderAccess?.url)
            self.onChange?()
            let completions = self.pendingCompletions
            self.pendingCompletions.removeAll()
            completions.forEach { $0() }
        }
        refreshWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }

    private static func makeSnapshot(customFolder: URL?) -> LibrarySnapshot {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
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
