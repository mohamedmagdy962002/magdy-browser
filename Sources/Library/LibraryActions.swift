import UIKit

struct LibraryAction {
    let title: String
    let image: UIImage?
    let isDestructive: Bool
    private let handler: () -> Void

    init(title: String, image: UIImage? = nil, isDestructive: Bool = false, handler: @escaping () -> Void) {
        self.title = title
        self.image = image
        self.isDestructive = isDestructive
        self.handler = handler
    }

    func perform() {
        handler()
    }

    func uiAction() -> UIAction {
        UIAction(title: title, image: image, attributes: isDestructive ? .destructive : []) { _ in perform() }
    }
}

enum LibraryActions {
    static func open(_ item: LibraryItem, from controller: UIViewController) {
        switch item.payload {
        case .download(let download):
            guard let current = DownloadManager.shared.items.first(where: { $0 === download }),
                  current.state == .finished,
                  let url = current.localURL,
                  FileManager.default.fileExists(atPath: url.path) else { return }
            openFile(url: url, title: current.fileName, from: controller, sourceView: controller.view)
        case .favorite(let favorite):
            guard let current = FavoritesStore.shared.favorites.first(where: { $0.url == favorite.url }),
                  let url = URL(string: current.url), url.isWebURL else { return }
            controller.appRouteHandler?.openWebURL(url)
        case .history(let entry):
            guard let current = HistoryStore.shared.entries.first(where: { $0.url == entry.url }),
                  let url = URL(string: current.url), url.isWebURL else { return }
            controller.appRouteHandler?.openWebURL(url)
        case .reading(let reading):
            guard let current = ReadingListStore.shared.items.first(where: { $0.id == reading.id }),
                  !current.paragraphs.isEmpty else { return }
            let article = ReaderMode.Article(title: current.title, paragraphs: current.paragraphs, url: current.url)
            controller.present(UINavigationController(rootViewController: ReaderViewController(article: article)), animated: true)
        case .none:
            guard let url = item.fileURL, FileManager.default.fileExists(atPath: url.path) else { return }
            openFile(url: url, title: item.title, from: controller, sourceView: controller.view)
        }
    }

    static func canOpen(_ item: LibraryItem) -> Bool {
        switch item.payload {
        case .download(let download):
            guard let current = currentDownload(download.id),
                  current.state == .finished,
                  let url = current.localURL else { return false }
            return FileManager.default.fileExists(atPath: url.path)
        case .favorite(let favorite):
            guard let current = FavoritesStore.shared.favorites.first(where: { $0.url == favorite.url }),
                  let url = URL(string: current.url) else { return false }
            return url.isWebURL
        case .history(let entry):
            guard let current = HistoryStore.shared.entries.first(where: { $0.url == entry.url }),
                  let url = URL(string: current.url) else { return false }
            return url.isWebURL
        case .reading(let reading):
            guard let current = ReadingListStore.shared.items.first(where: { $0.id == reading.id }) else { return false }
            return !current.paragraphs.isEmpty
        case .none:
            guard let url = item.fileURL else { return false }
            return FileManager.default.fileExists(atPath: url.path)
        }
    }

    private static func openFile(url: URL, title: String, from controller: UIViewController, sourceView: UIView?) {
        if playable(url) {
            let player = VideoPlayerController(url: url, title: title, isLocal: true)
            player.modalPresentationStyle = .fullScreen
            controller.present(player, animated: true)
        } else {
            share(url, from: controller, sourceView: sourceView)
        }
    }

    static func actions(for item: LibraryItem, from controller: UIViewController, sourceView: UIView?) -> [LibraryAction] {
        switch item.payload {
        case .download(let download):
            guard let current = DownloadManager.shared.items.first(where: { $0 === download }) else { return [] }
            return downloadActions(download: current, from: controller, sourceView: sourceView)
        case .favorite(let favorite):
            guard let current = FavoritesStore.shared.favorites.first(where: { $0.url == favorite.url }),
                  let url = URL(string: current.url), url.isWebURL else { return [] }
            return [
                action(L.t("open"), image: UIImage(systemName: "safari")) { [weak controller] in
                    controller?.appRouteHandler?.openWebURL(url)
                },
                action(L.t("share"), image: UIImage(systemName: "square.and.arrow.up")) { [weak controller, weak sourceView] in
                    guard let controller else { return }
                    share(url, from: controller, sourceView: sourceView)
                },
                action(L.t("remove"), image: UIImage(systemName: "star.slash"), isDestructive: true) {
                    if let index = FavoritesStore.shared.favorites.firstIndex(where: { $0.url == current.url }) {
                        FavoritesStore.shared.remove(at: index)
                    }
                }
            ]
        case .history(let entry):
            guard let current = HistoryStore.shared.entries.first(where: { $0.url == entry.url }),
                  let url = URL(string: current.url), url.isWebURL else { return [] }
            return [
                action(L.t("open"), image: UIImage(systemName: "safari")) { [weak controller] in
                    controller?.appRouteHandler?.openWebURL(url)
                },
                action(L.t("share"), image: UIImage(systemName: "square.and.arrow.up")) { [weak controller, weak sourceView] in
                    guard let controller else { return }
                    share(url, from: controller, sourceView: sourceView)
                },
                action(L.t("remove"), image: UIImage(systemName: "clock"), isDestructive: true) {
                    if let index = HistoryStore.shared.entries.firstIndex(where: { $0.url == current.url }) {
                        HistoryStore.shared.remove(at: index)
                    }
                }
            ]
        case .reading(let reading):
            guard let current = ReadingListStore.shared.items.first(where: { $0.id == reading.id }) else { return [] }
            var actions: [LibraryAction] = []
            if !current.paragraphs.isEmpty {
                actions.append(action(L.t("open"), image: UIImage(systemName: "text.book.closed")) { [weak controller] in
                    guard let controller else { return }
                    let article = ReaderMode.Article(title: current.title, paragraphs: current.paragraphs, url: current.url)
                    let reader = ReaderViewController(article: article)
                    controller.present(UINavigationController(rootViewController: reader), animated: true)
                })
            }
            actions.append(action(L.t("delete"), image: UIImage(systemName: "trash"), isDestructive: true) {
                ReadingListStore.shared.remove(current)
            })
            return actions
        case .none:
            guard let url = item.fileURL, FileManager.default.fileExists(atPath: url.path) else { return [] }
            return fileActions(url: url, title: item.title, from: controller, sourceView: sourceView)
        }
    }

    private static func downloadActions(
        download: DownloadItem,
        from controller: UIViewController,
        sourceView: UIView?
    ) -> [LibraryAction] {
        var actions: [LibraryAction] = []
        if download.state == .finished, let url = download.localURL, FileManager.default.fileExists(atPath: url.path) {
            actions = fileActions(url: url, title: download.fileName, from: controller, sourceView: sourceView)
        } else if let url = download.sourceURL {
            actions.append(action(L.t("share"), image: UIImage(systemName: "square.and.arrow.up")) { [weak controller, weak sourceView] in
                guard let controller else { return }
                share(url, from: controller, sourceView: sourceView)
            })
        }

        switch download.state {
        case .running:
            if download.task != nil && !download.isPausing {
                actions.append(action(L.t("pause"), image: UIImage(systemName: "pause")) {
                    guard let current = currentDownload(download.id) else { return }
                    DownloadManager.shared.pause(current)
                })
            }
            actions.append(action(L.t("cancel"), image: UIImage(systemName: "xmark")) {
                guard let current = currentDownload(download.id), current.state == .running else { return }
                DownloadManager.shared.cancel(current)
            })
        case .paused:
            actions.append(action(L.t("resume"), image: UIImage(systemName: "play")) {
                guard let current = currentDownload(download.id), current.state == .paused else { return }
                DownloadManager.shared.resume(current)
            })
        case .failed, .cancelled:
            if download.resumeData != nil {
                actions.append(action(L.t("resume"), image: UIImage(systemName: "arrow.clockwise")) {
                    guard let current = currentDownload(download.id),
                          current.state == .failed || current.state == .cancelled else { return }
                    DownloadManager.shared.resume(current)
                })
            }
        case .finished, .queued:
            if download.state == .queued {
                actions.append(action(L.t("cancel"), image: UIImage(systemName: "xmark")) {
                    guard let current = currentDownload(download.id), current.state == .queued else { return }
                    DownloadManager.shared.cancel(current)
                })
            }
        }
        actions.append(action(L.t("delete"), image: UIImage(systemName: "trash"), isDestructive: true) {
            guard let current = currentDownload(download.id) else { return }
            DownloadManager.shared.remove(current)
        })
        return actions
    }

    private static func currentDownload(_ id: UUID) -> DownloadItem? {
        DownloadManager.shared.items.first { $0.id == id }
    }

    private static func fileActions(
        url: URL,
        title: String,
        from controller: UIViewController,
        sourceView: UIView?
    ) -> [LibraryAction] {
        var actions = [action(L.t("open"), image: UIImage(systemName: playable(url) ? "play" : "doc")) { [weak controller, weak sourceView] in
            guard let controller else { return }
            openFile(url: url, title: title, from: controller, sourceView: sourceView)
        }]
        actions.append(action(L.t("share"), image: UIImage(systemName: "square.and.arrow.up")) { [weak controller, weak sourceView] in
            guard let controller else { return }
            share(url, from: controller, sourceView: sourceView)
        })
        return actions
    }

    private static func playable(_ url: URL) -> Bool {
        ["mp4", "mov", "m4v", "m4a", "mp3", "aac", "wav"].contains(url.pathExtension.lowercased())
    }

    private static func share(_ value: Any, from controller: UIViewController, sourceView: UIView?) {
        let sheet = UIActivityViewController(activityItems: [value], applicationActivities: nil)
        let source = sourceView ?? controller.view
        sheet.popoverPresentationController?.sourceView = source
        sheet.popoverPresentationController?.sourceRect = source?.bounds ?? .zero
        controller.present(sheet, animated: true)
    }

    private static func action(
        _ title: String,
        image: UIImage?,
        isDestructive: Bool = false,
        handler: @escaping () -> Void
    ) -> LibraryAction {
        LibraryAction(title: title, image: image, isDestructive: isDestructive, handler: handler)
    }
}
