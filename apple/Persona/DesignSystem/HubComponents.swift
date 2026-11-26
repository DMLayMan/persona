import SwiftUI

// Several groups of hubs on one device (docs/protocol/multi-hub.md): what the merged lists and the hub-level pages show of them.
// With one group none of this draws anything: every screen stays what it was.

/// The flat list of hub groups the switcher menus offer (#16487). A hub-titled SwiftUI `Picker` nested in a `Menu`
/// becomes an intermediate "hub" submenu on macOS, so the menus instead enumerate these options as plain buttons.
nonisolated enum HubGroupMenu {
    struct Option: Equatable, Sendable, Identifiable {
        let group: String
        let isCurrent: Bool
        var id: String { group }
        var accessibilityIdentifier: String { HubGroupMenu.identifier(for: group) }
    }

    /// Every option id shares the switcher prefix; the default group's id is "", so its id ends in a dot.
    static let identifierPrefix = "hub.switcher"

    static func identifier(for group: String) -> String { "\(identifierPrefix).\(group)" }

    static func options(_ groups: [String], current: String?) -> [Option] {
        groups.map { Option(group: $0, isCurrent: $0 == current) }
    }
}

/// The hub groups as flat menu buttons: the current group carries the checkmark the other selection menus use
/// (`Label(…, systemImage: Theme.Icon.done)` versus a plain `Text`). Every button calls the same `selectHub(_:)`.
struct HubGroupMenuItems: View {
    @Environment(AppModel.self) private var model
    let current: String

    var body: some View {
        ForEach(HubGroupMenu.options(model.groupIDs, current: current)) { option in
            Button {
                Haptics.tap()
                model.selectHub(option.group)
            } label: {
                if option.isCurrent {
                    Label(model.groupName(option.group), systemImage: Theme.Icon.done)
                } else {
                    Text(model.groupName(option.group))
                }
            }
            .accessibilityIdentifier(option.accessibilityIdentifier)
        }
    }
}

/// The group filter of the merged lists (Agents, the ⋯ menu): "" every group, "=<group>" one of them (the default
/// group's id is "", hence the mark).
nonisolated enum HubFilter {
    static let key = "dev.hubFilter"
    static func value(_ group: String) -> String { "=" + group }
    static func matches(_ filter: String, _ group: String) -> Bool { filter.isEmpty || filter == "=" + group }
    static func group(_ filter: String) -> String? { filter.hasPrefix("=") ? String(filter.dropFirst()) : nil }
}

/// Which group of hubs a row or a page is about, as a small chip; nothing with one group.
struct HubTag: View {
    @Environment(AppModel.self) private var model
    var group: String

    var body: some View {
        if model.isMultiHub {
            Chip(text: model.groupName(group), symbol: Theme.Icon.hubGroup, shrinks: true)
                .accessibilityLabel("From \(model.groupName(group))")
        }
    }
}

/// The group a hub-level page (Persona, Inbox, the hub's settings) shows, and the menu to pick another; nothing with
/// one group. Each group has its own Persona, inbox and settings: they are not merged (docs/archive/operations/plan-hub-mesh.md 2.6).
struct HubSwitcher: View {
    @Environment(AppModel.self) private var model
    /// Only the group's icon and name, for a bar; the full label elsewhere.
    var compact = false

    var body: some View {
        if model.isMultiHub, let current = model.hub?.group {
            // Flat buttons, not a hub-titled Picker: inside a Menu macOS turns that Picker into a titled "hub"
            // submenu (#16487), one extra hover/click before the groups.
            Menu {
                HubGroupMenuItems(current: current)
            } label: {
                HStack(spacing: Theme.Space.xs) {
                    ThemedIcon(Theme.Icon.hubGroup)
                    Text(model.groupName(current)).lineLimit(1)
                    ThemedIcon(Theme.Icon.expand).font(Theme.Font.labelHeavy)
                }
                .font(compact ? Theme.Font.label : Theme.Font.secondaryStrong)
                .foregroundStyle(Color.secondary)
                .fixedSize()
            }
            // The label draws its own chevron; hide the Mac menu indicator so the two do not sit side by side.
            .labelOnlyMenu()
            .accessibilityIdentifier("hub.switcher")
            .accessibilityLabel("Current hub: \(model.groupName(current))")
        }
    }
}

/// A group's link to its hub as a dot: up, being opened, or down.
struct HubStatusDot: View {
    var live: LiveConnection

    var body: some View {
        Circle()
            .fill(color)
            .scaledFrame(width: Theme.Size.dotS, height: Theme.Size.dotS)
            .accessibilityHidden(true)
    }

    private var color: Color {
        if live.inGrace { return Theme.positive } // dropped a moment ago and coming back (a hub restart): nothing to say
        return switch live.state {
        case .connected: live.stalled ? Theme.caution : Theme.positive
        case .connecting: Theme.caution
        case .idle, .failed: Color.secondary
        }
    }
}
