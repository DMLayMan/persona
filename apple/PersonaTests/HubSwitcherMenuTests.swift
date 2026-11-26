import Foundation
import Testing
@testable import Persona

/// The flat hub-group menu behind `HubSwitcher` and the Assistant hub entries (#16487): macOS used to turn the
/// `Picker("hub")` inside a `Menu` into an intermediate "hub" submenu. These pin the flat option list, its single
/// current mark and the stable accessibility identifiers the UI tests and AX checks rely on.
struct HubSwitcherMenuTests {
    @Test func listsEveryGroupInOrderWithExactlyOneCurrent() {
        let options = HubGroupMenu.options(["", "gabc12345", "gdef67890"], current: "gabc12345")

        #expect(options.map(\.group) == ["", "gabc12345", "gdef67890"])
        #expect(options.map(\.isCurrent) == [false, true, false])
        #expect(options.filter(\.isCurrent).count == 1)
    }

    @Test func theCurrentGroupCanBeTheDefaultEmptyOne() {
        let options = HubGroupMenu.options(["", "gabc12345"], current: "")

        #expect(options.first?.isCurrent == true)
        #expect(options.last?.isCurrent == false)
    }

    @Test func identifiersAreStableAndUniqueIncludingTheDefaultGroup() {
        // Group ids are safe identifier fragments ("g" + hex, or "" for the default group, docs/protocol/multi-hub.md);
        // the default group's identifier therefore ends in the prefix's trailing dot.
        let options = HubGroupMenu.options(["", "gabc12345"], current: "")

        #expect(options.map(\.accessibilityIdentifier) == ["hub.switcher.", "hub.switcher.gabc12345"])
        #expect(Set(options.map(\.accessibilityIdentifier)).count == options.count)
        #expect(HubGroupMenu.identifier(for: "gabc12345") == "hub.switcher.gabc12345")
        #expect(HubGroupMenu.identifier(for: "") == "hub.switcher.")
    }

    @Test func aCurrentGroupMissingFromTheListMarksNothing() {
        // `HubSwitcher` only shows while `model.hub?.group` is one of the links, but the pure model stays total.
        let options = HubGroupMenu.options(["", "g1"], current: "gone")

        #expect(options.allSatisfy { !$0.isCurrent })
    }

    /// Regression guard for #16487: a `Picker("hub")` inside these `Menu`/`Section` containers is exactly what macOS
    /// renders as the extra titled "hub" submenu. The Agents-list filter Picker is deliberately not in this list.
    @Test func hubLevelMenusEnumerateFlatButtonsInsteadOfANestedHubPicker() throws {
        let testsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent() // apple/PersonaTests
        let appleDir = testsDir.deletingLastPathComponent()
        let files = [
            "Persona/DesignSystem/HubComponents.swift",
            "Persona/Views/Assistant/AssistantTopBar.swift",
            "Persona/Views/Assistant/AssistantSidebar.swift",
        ]
        for file in files {
            let text = try String(contentsOf: appleDir.appending(path: file), encoding: .utf8)
            #expect(!text.contains("Picker(\"hub\""),
                     Comment(rawValue: "\(file) must use flat HubGroupMenuItems, not a nested Picker(\"hub\") (#16487)"))
        }
        let components = try String(contentsOf: appleDir.appending(path: files[0]), encoding: .utf8)
        #expect(components.contains("struct HubGroupMenuItems"))
        #expect(components.contains(".labelOnlyMenu()")) // hides the duplicate macOS system chevron
    }
}
