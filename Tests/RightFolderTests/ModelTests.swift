import Foundation
import XCTest
@testable import FolderCore
@testable import RightFolder

@MainActor
final class ModelTests: XCTestCase {
    let home = Gallery.home

    func testListsTheGallery() {
        let model = Gallery.model()
        XCTAssert(model.list.finder.map(\.path) == Gallery.finder)
        XCTAssert(model.list.favorites.map(\.path) == Gallery.favorites)
        XCTAssert(model.list.favorites.last?.availability == .network)
        // The front Finder folder became a recent folder when the dialog opened, but it's listed under Finder.
        XCTAssert(model.recents.paths.first == Gallery.finder[0])
        XCTAssert(model.list.recents.map(\.path) == Gallery.recents)
        XCTAssert(model.status == .showing(.save, app: "Inkpad"))
        XCTAssert(model.showsPanel)
    }

    func testJumpsWhenClicked() async {
        let jumps = RecordedJumps()
        let model = Gallery.model(jumps: jumps)
        await model.jump(to: home + "/Documents/Lab Notes")
        XCTAssert(jumps.paths == [home + "/Documents/Lab Notes"])
        XCTAssert(model.recents.paths.first == home + "/Documents/Lab Notes")
        XCTAssert(model.message == nil)
        XCTAssert(model.jumping == nil)
    }

    func testRemembersJumpsAcrossLaunches() async {
        let preferences = testPreferences()
        let model = Gallery.model(preferences: preferences)
        await model.jump(to: home + "/Desktop")
        XCTAssert(preferences.recents.paths.first == home + "/Desktop")
    }

    func testSaysWhatWentWrong() async {
        let jumps = RecordedJumps()
        jumps.result = .failed(.noField)
        let model = Gallery.model(jumps: jumps)
        await model.jump(to: home + "/Downloads")
        XCTAssert(model.message == GoTo.Failure.noField.message)
        XCTAssert(!model.recents.paths.contains(home + "/Downloads"))
        // The message goes when the dialog does.
        model.dialogClosed()
        XCTAssert(model.message == nil)
    }

    func testNeverJumpsSomewhereUnavailable() async {
        let jumps = RecordedJumps()
        let system = FakeSystem()
        system.folders.remove(home + "/Documents/Lab Notes")
        let model = Gallery.model(system: system, jumps: jumps)
        XCTAssert(model.list.favorites.first?.availability == .missing)
        await model.jump(to: home + "/Documents/Lab Notes")
        await model.jump(to: "/Not/Listed")
        XCTAssert(jumps.paths.isEmpty)
        XCTAssert(model.message == GoTo.Failure.unavailable.message)
    }

    func testNeverJumpsWithoutADialog() async {
        let jumps = RecordedJumps()
        let model = Gallery.model(dialog: nil, jumps: jumps)
        await model.jump(to: home + "/Downloads")
        await model.step(backwards: false)
        XCTAssert(jumps.paths.isEmpty)
        XCTAssert(model.status == .waiting)
        XCTAssert(!model.showsPanel)
    }

    func testTheShortcutStepsThroughInOrder() async {
        let jumps = RecordedJumps()
        let model = Gallery.model(jumps: jumps)
        for _ in 0..<3 { await model.step(backwards: false) }
        XCTAssert(jumps.paths == Array(model.list.cycle.prefix(3)))
        await model.step(backwards: true)
        XCTAssert(jumps.paths.last == model.list.cycle[1])
    }

    func testTheShortcutSkipsWhatsUnavailable() async {
        let jumps = RecordedJumps()
        let model = Gallery.model(finder: [], favorites: ["/Volumes/Old Drive/Photos"], recents: [home + "/Desktop"], jumps: jumps)
        await model.step(backwards: false)
        await model.step(backwards: false)
        XCTAssert(jumps.paths == [home + "/Desktop", home + "/Desktop"])
    }

    func testANewDialogStartsTheShortcutOver() async {
        let jumps = RecordedJumps()
        let model = Gallery.model(jumps: jumps)
        await model.step(backwards: false)
        await model.step(backwards: false)
        model.dialogClosed()
        model.dialogOpened(FolderModel.Dialog(kind: .open, appName: "Inkpad", bundleID: "com.example.inkpad"))
        await model.step(backwards: false)
        XCTAssert(jumps.paths.last == model.list.cycle[0])
    }

    func testALateJumpDoesntTouchTheNextDialog() async {
        let jumps = RecordedJumps()
        jumps.result = .failed(.dialogGone)
        jumps.delay = 0.05
        let model = Gallery.model(jumps: jumps)
        let jump = Task { await model.jump(to: home + "/Downloads") }
        try? await Task.sleep(for: .seconds(0.01))
        model.dialogClosed()
        model.dialogOpened(FolderModel.Dialog(kind: .save, appName: "Inkpad", bundleID: "com.example.inkpad", id: 2))
        // While the first jump is still going, nothing else can start.
        await model.step(backwards: false)
        XCTAssert(jumps.paths == [home + "/Downloads"])
        await jump.value
        XCTAssert(model.message == nil)
        XCTAssert(model.jumping == nil)
        await model.step(backwards: false)
        XCTAssert(jumps.paths.count == 2)
    }

    func testTheNextLookalikeDialogStartsOver() async {
        let jumps = RecordedJumps()
        let model = Gallery.model(jumps: jumps)
        await model.step(backwards: false)
        await model.step(backwards: false)
        // Another Save sheet in the same app looks the same, but it's a new dialog.
        model.dialogOpened(FolderModel.Dialog(kind: .save, appName: "Inkpad", bundleID: "com.example.inkpad", id: 7))
        await model.step(backwards: false)
        XCTAssert(jumps.paths.last == model.list.cycle[0])
    }

    func testPinsAndUnpins() {
        let preferences = testPreferences()
        let model = Gallery.model(preferences: preferences)
        model.pin(home + "/Downloads")
        XCTAssert(model.list.favorites.last?.path == home + "/Downloads")
        XCTAssert(!model.list.finder.map(\.path).contains(home + "/Downloads"))
        XCTAssert(model.list.favorites.last?.isOpenInFinder == true)
        XCTAssert(preferences.favorites.items.last?.bookmark == Data((home + "/Downloads").utf8))
        model.unpin(home + "/Downloads")
        XCTAssert(model.list.finder.map(\.path).contains(home + "/Downloads"))
        model.move(Gallery.favorites[1], by: -1)
        XCTAssert(preferences.favorites.paths.first == Gallery.favorites[1])
    }

    func testFavoritesFollowMovedFolders() {
        let system = FakeSystem()
        let renamed = home + "/Documents/Lab Notebook"
        system.folders.insert(renamed)
        system.moved[home + "/Documents/Lab Notes"] = renamed
        let preferences = testPreferences()
        let model = Gallery.model(system: system, preferences: preferences)
        XCTAssert(model.list.favorites.first?.path == renamed)
        XCTAssert(preferences.favorites.paths.first == renamed)
    }

    func testRecentsCanBeTurnedOff() async {
        let preferences = testPreferences()
        let jumps = RecordedJumps()
        let model = Gallery.model(preferences: preferences, jumps: jumps)
        model.setRemembersRecents(false)
        XCTAssert(model.recents.paths.isEmpty)
        XCTAssert(preferences.recents.paths.isEmpty)
        XCTAssert(!preferences.remembersRecents)
        await model.jump(to: home + "/Downloads")
        model.dialogClosed()
        model.dialogOpened(Gallery.inkpad)
        XCTAssert(model.recents.paths.isEmpty)
        model.setRemembersRecents(true)
        model.forget("/nothing")
        model.clearRecents()
        XCTAssert(model.list.recents.isEmpty)
    }

    func testPausedMeansNoPanel() async {
        let jumps = RecordedJumps()
        let model = Gallery.model(jumps: jumps)
        model.setPaused(true)
        XCTAssert(model.status == .paused)
        XCTAssert(!model.showsPanel)
        await model.step(backwards: false)
        XCTAssert(jumps.paths.isEmpty)
        model.setPaused(false)
        XCTAssert(model.showsPanel)
    }

    func testOffInAnApp() {
        let preferences = testPreferences()
        let model = Gallery.model(preferences: preferences)
        model.setExcluded("com.example.inkpad", true)
        XCTAssert(!model.showsPanel)
        XCTAssert(model.status == .offInApp("Inkpad"))
        XCTAssert(preferences.excludedApps == ["com.example.inkpad"])
        model.setExcluded("com.example.inkpad", false)
        XCTAssert(model.showsPanel)
    }

    func testWithoutAccessibility() {
        let model = Gallery.model(trusted: false)
        XCTAssert(model.status == .needsAccessibility)
        XCTAssert(!model.showsPanel)
        // Finder isn't asked about its windows without permission.
        XCTAssert(model.list.finder.isEmpty)
        XCTAssert(!model.list.favorites.isEmpty)
    }

    func testPreferencesDefaults() {
        let preferences = testPreferences()
        XCTAssert(preferences.remembersRecents)
        XCTAssert(!preferences.paused)
        XCTAssert(!preferences.typesPaths)
        XCTAssert(preferences.excludedApps.isEmpty)
        XCTAssert(preferences.favorites.items.isEmpty)
        // A damaged saved list is ignored rather than crashing.
        preferences.defaults.set(Data("not json".utf8), forKey: "favorites")
        XCTAssert(preferences.favorites.items.isEmpty)
    }
}
