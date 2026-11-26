#if os(iOS)
import Foundation
import Observation

nonisolated enum HubNavigationPage: String, Sendable {
    case inbox, todos
}

/// The hub's sidebar arrangement. The phone only reads the visibility of its Inbox and To-dos pages.
@MainActor @Observable final class HubPageVisibility {
    nonisolated private struct Arrangement: Decodable {
        struct Pages: Decodable { var hidden: Set<String>? }
        var pages: Pages?
    }

    private var hidden: Set<HubNavigationPage> = []
    private var group: String?
    @ObservationIgnored private var reading: Task<Void, Never>?
    @ObservationIgnored private(set) var selection = 0

    func hiddenPages(in group: String?) -> Set<HubNavigationPage> {
        group == self.group ? hidden : []
    }

    func follow(_ group: String?) {
        guard group != self.group else { return }
        selection &+= 1
        reading?.cancel()
        reading = nil
        self.group = group
        hidden = []
    }

    /// A foreground transition, a hello and a link open can all ask at once. Coalesce reads for the current hub.
    @discardableResult func refresh(_ api: APIClient) -> Task<Void, Never> {
        follow(api.group)
        if let reading { return reading }
        let reading = Task {
            let pages: Set<HubNavigationPage>
            do {
                let data = try await api.request("GET", "/api/v1/navigation", timeout: 5)
                let saved = try JSONDecoder().decode(Arrangement.self, from: data)
                pages = Set((saved.pages?.hidden ?? []).compactMap(HubNavigationPage.init(rawValue:)))
            } catch {
                pages = [] // An older hub or failed read leaves the existing navigation available.
            }
            guard !Task.isCancelled else { return }
            if hidden != pages { hidden = pages }
            self.reading = nil
        }
        self.reading = reading
        return reading
    }
}

extension AppModel {
    var hiddenNavigationPages: Set<HubNavigationPage> {
        pageVisibility.hiddenPages(in: hub?.group)
    }

    @discardableResult func refreshPageVisibility() -> Task<Void, Never>? {
        guard let hub, !hub.isDemo else {
            pageVisibility.follow(nil)
            return nil
        }
        return pageVisibility.refresh(hub.api.showing(nil))
    }

    /// A system shortcut, widget or URL can launch the app before its first hello. Resolve it after the current hub's
    /// read so a hidden Inbox or To-dos page never opens while that read is pending.
    @discardableResult func openNavigationLink(_ page: HubPage, group: String) -> Task<Void, Never>? {
        guard let hub, hub.group == group else { return nil }
        let reading = refreshPageVisibility()
        let selection = pageVisibility.selection
        return Task {
            await reading?.value
            guard self.hub === hub, pageVisibility.selection == selection else { return }
            if case .sheet(let page) = openHubPage(page, group: group) { linkSheet = page }
        }
    }

    @discardableResult func returnToStartIfHidden(_ page: HubNavigationPage?) -> Bool {
        guard let page, hiddenNavigationPages.contains(page) else { return false }
        inboxToOpen = nil
        linkSheet = nil
        showShellPage(.conversation)
        return true
    }
}

extension HubPage {
    var navigationPage: HubNavigationPage? {
        switch self {
        case .inbox, .inboxItem: .inbox
        case .todos, .todo: .todos
        default: nil
        }
    }
}

extension ShellPage {
    var navigationPage: HubNavigationPage? {
        switch self {
        case .inbox: .inbox
        case .todos: .todos
        default: nil
        }
    }
}
#endif
