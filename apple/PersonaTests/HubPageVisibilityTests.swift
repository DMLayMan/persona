#if os(iOS)
import Foundation
import Testing
@testable import Persona

@MainActor struct HubPageVisibilityTests {
    private static let path = "/api/v1/navigation"
    private static let hidden = #"{"pages":{"hidden":["todos","inbox","web-only"]}}"#

    @Test func refreshHidesPagesAndShowsThemAgain() async {
        let hub = FakeHub(), visibility = HubPageVisibility()
        hub.on("GET", Self.path, json: Self.hidden)
        let first = visibility.refresh(hub.client)
        let same = visibility.refresh(hub.client)
        await first.value
        await same.value
        #expect(hub.sent("GET", Self.path).count == 1)
        #expect(visibility.hiddenPages(in: "") == [.inbox, .todos])

        hub.on("GET", Self.path, json: #"{"pages":{"hidden":[]}}"#)
        await visibility.refresh(hub.client).value
        #expect(visibility.hiddenPages(in: "").isEmpty)
    }

    @Test(arguments: [404, 503]) func failedRefreshShowsEveryPage(status: Int) async {
        let hub = FakeHub(), visibility = HubPageVisibility()
        hub.on("GET", Self.path, json: Self.hidden)
        await visibility.refresh(hub.client).value
        #expect(visibility.hiddenPages(in: "") == [.inbox, .todos])

        hub.on("GET", Self.path) { _ in throw APIError(status: status, message: "Unavailable") }
        await visibility.refresh(hub.client).value
        #expect(visibility.hiddenPages(in: "").isEmpty)
    }

    @Test func aLateResponseCannotCrossHubSelections() async {
        let first = FakeHub(), second = FakeHub(), visibility = HubPageVisibility()
        let gate = ReadGate()
        first.onAsync("GET", Self.path) { _ in await gate.hold() }
        second.on("GET", Self.path, json: #"{"pages":{"hidden":["inbox"]}}"#)
        var secondClient = second.client
        secondClient.group = "other"
        let old = visibility.refresh(first.client)
        await gate.arrival()

        await visibility.refresh(secondClient).value
        #expect(visibility.hiddenPages(in: "").isEmpty)
        #expect(visibility.hiddenPages(in: "other") == [.inbox])
        gate.release(Data(Self.hidden.utf8))
        await old.value
        #expect(visibility.hiddenPages(in: "other") == [.inbox])
    }

    @Test func quickActionsKeepTheirOrderAndOmitHiddenInbox() {
        #expect(QuickAction.offered(recording: .on, hidden: [.inbox, .todos]) == [.meetingRecording, .newConversation])
        #expect(QuickAction.offered(recording: .off, hidden: [.todos]) == [.newConversation, .inbox])
    }

    @Test func launchRoutesWaitForVisibilityAndReturnToStart() async throws {
        let hub = FakeHub(), gate = ReadGate()
        hub.onAsync("GET", Self.path) { _ in await gate.hold() }
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let app = AppModel(stateFolder: folder)
        app.linkHooksForTests = (transport: try #require(hub.client.transport), socket: { SyncSocket() })
        app.connectOnly(ServerConfig(url: hub.url, token: "sample"))
        let router = PadRouter(unified: true)
        router.attach(to: app)
        app.selectedTab = .chats
        let inbox = try #require(app.openNavigationLink(.inboxItem(id: "example", manager: nil), group: ""))
        await gate.arrival()
        #expect(app.selectedTab == .chats)
        gate.release(Data(Self.hidden.utf8))
        await inbox.value
        #expect(app.inboxToOpen == nil)
        #expect(app.selectedTab == .assistant)
        #expect(router.request?.page == .conversation)

        for path in ["/inbox", "/todos", "/todos/example", "/todos?id=example"] {
            let url = try #require(URL(string: "persona://open\(path)"))
            #expect(app.openOwnLink(url) == .opened)
            #expect(router.request?.page == .conversation)
        }
        app.pageVisibility.follow(nil)
        #expect(app.openHubPage(.todo(id: "example"), group: "") == .sheet(.todo("example")))
        #expect(app.openHubPage(.inbox, group: "") == .opened)
        #expect(router.request?.page == .inbox)
    }

    private final class ReadGate {
        private var response: CheckedContinuation<Data, Never>?
        private var awaitingArrival: CheckedContinuation<Void, Never>?

        func hold() async -> Data {
            await withCheckedContinuation { continuation in
                response = continuation
                awaitingArrival?.resume()
                awaitingArrival = nil
            }
        }

        func arrival() async {
            if response == nil { await withCheckedContinuation { awaitingArrival = $0 } }
        }

        func release(_ data: Data) {
            response?.resume(returning: data)
            response = nil
        }
    }
}
#endif
