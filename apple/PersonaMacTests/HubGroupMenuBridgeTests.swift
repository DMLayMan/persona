import AppKit
import SwiftUI
import Testing
@testable import Persona

/// Verifies what `HubGroupMenuItems` bridges to as a real AppKit menu (#16487): the groups must be top-level items
/// with the current one marked, never an intermediate titled "hub" submenu. `NSHostingMenu` builds the same
/// SwiftUI → NSMenu bridge an open `Menu` uses, without needing a visible window (the CI/locally-locked Mac case).
@MainActor
struct HubGroupMenuBridgeTests {
    @Test func groupsAreTopLevelItemsWithOneMarkAndNoHubSubmenu() throws {
        let model = AppModel()
        model.registry = HubRegistry(hubs: [
            PairedHub(id: "h1", config: ServerConfig(url: URL(string: "http://127.0.0.1:18771")!, token: "t1"), group: ""),
            PairedHub(id: "h2", config: ServerConfig(url: URL(string: "http://127.0.0.1:18772")!, token: "t2"), group: "gstudio"),
        ], groupNames: ["": "Persona Local", "gstudio": "macStudio"])
        model.buildLinks()

        let menu = NSHostingMenu(rootView: HubGroupMenuItems(current: "gstudio").environment(model))
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        let items = menu.items
        #expect(items.count == 2, Comment(rawValue: "expected two flat items, got \(items.map(\.title))"))
        #expect(items.map(\.title).contains("Persona Local"))
        #expect(items.map(\.title).contains("macStudio"))
        // No item carries a nested menu (that was the "hub" Picker submenu).
        #expect(items.allSatisfy { $0.submenu == nil })
        #expect(!items.contains { $0.title == "hub" })
        // The current row is marked by the checkmark LABEL ICON this repo's selection menus use; AppKit state stays
        // off because SwiftUI draws the `Label(systemImage: checkmark)` itself.
        let studio = try #require(items.first { $0.title == "macStudio" })
        let local = try #require(items.first { $0.title == "Persona Local" })
        let studioMarked = studio.state == .on || studio.image != nil
        let localMarked = local.state == .on || local.image != nil
        #expect(studioMarked, "the current group macStudio must carry a state or checkmark image")
        #expect(!localMarked, "the non-current group Persona Local must not be marked")
    }

    @Test func pressingAnItemCallsSelectHubOnce() throws {
        // The unsigned test host shares local.persona.maclocal's defaults domain with a possibly running installed
        // app: save and restore the real hub.group around the write `selectHub` performs.
        let defaults = UserDefaults.standard
        let previous = defaults.string(forKey: AppModel.hubGroupKey)
        defer {
            if let previous { defaults.set(previous, forKey: AppModel.hubGroupKey) }
            else { defaults.removeObject(forKey: AppModel.hubGroupKey) }
        }

        let model = AppModel()
        model.registry = HubRegistry(hubs: [
            PairedHub(id: "h1", config: ServerConfig(url: URL(string: "http://127.0.0.1:18771")!, token: "t1"), group: ""),
            PairedHub(id: "h2", config: ServerConfig(url: URL(string: "http://127.0.0.1:18772")!, token: "t2"), group: "gstudio"),
        ], groupNames: ["": "Persona Local", "gstudio": "macStudio"])
        model.buildLinks()
        model.hubGroup = "gstudio"
        #expect(model.hub?.group == "gstudio")

        let menu = NSHostingMenu(rootView: HubGroupMenuItems(current: "gstudio").environment(model))
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        let local = try #require(menu.items.first { $0.title == "Persona Local" })
        let action = try #require(local.action)
        // The same path a real menu click takes; SwiftUI's target performs the button action closure.
        NSApp.sendAction(action, to: local.target, from: local)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        #expect(model.hub?.group == "")
        #expect(UserDefaults.standard.string(forKey: AppModel.hubGroupKey) == "")
    }
}
