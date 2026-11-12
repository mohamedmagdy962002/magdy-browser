import Foundation

final class TabStore {
    private(set) var tabs: [BrowserTab] = []

    func newTab(privateMode: Bool) -> BrowserTab {
        let tab = BrowserTab(isPrivate: privateMode)
        tabs.append(tab)
        return tab
    }

    func close(_ tab: BrowserTab) {
        tabs.removeAll { $0 === tab }
    }

    func closeAll() {
        tabs.removeAll()
    }
}
