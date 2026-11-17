import AppKit
import XCTest
@testable import FolderCore
@testable import RightFolder

@MainActor
final class RecordedActions: StatusMenuActions {
    nonisolated init() {}
    var calls: [String] = []
    func allowAccessibility() { calls.append("allow") }
    func pinFolder() { calls.append("pin") }
    func pinFinderFolder(_ path: String) { calls.append("pin " + path) }
    func togglePaused() { calls.append("pause") }
    func toggleRemembersRecents() { calls.append("recents") }
    func clearRecents() { calls.append("clear") }
    func openWindow() { calls.append("window") }
    func toggleOpenAtLogin() { calls.append("login") }
    func showAbout() { calls.append("about") }
}

@MainActor
final class StatusMenuTests: XCTestCase {
    func build(_ model: FolderModel, actions: RecordedActions = RecordedActions()) -> (NSMenu, StatusMenu) {
        let menu = NSMenu()
        let status = StatusMenu(model: model, actions: actions)
        status.opensAtLogin = { true }
        status.build(into: menu)
        return (menu, status)
    }

    func titles(_ menu: NSMenu) -> [String] {
        menu.items.filter { !$0.isSeparatorItem }.map(\.title)
    }

    func testShowsTheDialog() {
        let (menu, _) = build(Gallery.model())
        let titles = titles(menu)
        XCTAssert(titles.first == "Save dialog in Inkpad")
        XCTAssert(titles.contains("Pin “Drafts” from Finder"))
        XCTAssert(titles.contains("Open Right Folder…"))
        XCTAssert(!titles.contains("Allow Accessibility…"))
        XCTAssert(menu.items.first { $0.title == "Show Folders Beside Dialogs" }?.state == .on)
        XCTAssert(menu.items.first { $0.title == "Open at Login" }?.state == .on)
        XCTAssert(menu.items.last?.title == "Quit Right Folder")
    }

    func testAsksForAccessibility() {
        let (menu, _) = build(Gallery.model(trusted: false))
        XCTAssert(titles(menu).prefix(3) == ["Accessibility is off", StatusMenu.wrap(Describe.detail(.needsAccessibility)), "Allow Accessibility…"])
        XCTAssert(!titles(menu).contains { $0.hasPrefix("Pin “") })
    }

    func testNoFinderPinWhenAlreadyAFavorite() {
        let model = Gallery.model(favorites: [Gallery.finder[0]])
        XCTAssert(!titles(build(model).0).contains { $0.hasPrefix("Pin “") })
    }

    func testClearIsOffWithNothingToClear() {
        let model = Gallery.model(finder: [], recents: [])
        XCTAssert(build(model).0.items.first { $0.title == "Clear Recent Folders" }?.isEnabled == false)
    }

    func testItemsCallTheirActions() {
        let actions = RecordedActions()
        let (menu, status) = build(Gallery.model(trusted: true), actions: actions)
        for item in menu.items where item.target === status {
            if let action = item.action { NSApp.sendAction(action, to: status, from: item) }
        }
        XCTAssert(actions.calls == ["pin", "pin " + Gallery.finder[0], "window", "pause", "recents", "clear", "login", "about"])
    }

    func testWrapsLongLines() {
        let wrapped = StatusMenu.wrap(String(repeating: "word ", count: 30), width: 20)
        XCTAssert(wrapped.split(separator: "\n").allSatisfy { $0.count <= 20 })
        XCTAssert(StatusMenu.wrap("short") == "short")
    }
}
