import Foundation
import XCTest
@testable import FolderCore

/// A made-up dialog that acts out what a real one might: Go to Folder opening after a delay, or
/// never, a field that won't take a value, the dialog closing part way. It records every key and
/// value it's sent, and nothing is ever sent anywhere real.
@MainActor
final class FakeDialog: DialogDriver {
    struct Field: Equatable {
        var name: String
        var role: String
        var subrole: String?
        /// False for a field in another window of the same app.
        var inDialog = true
    }

    enum Event: Equatable {
        case goToFolder
        case set(String, in: String)
        case typed(String)
        case returnKey
    }

    var events: [Event] = []
    var front = true
    var focused: Field? = Field(name: "name", role: "AXTextField")
    /// How many looks before Go to Folder's field takes the keyboard, or nil for never.
    var fieldAfter: Int? = 2
    var goToField = Field(name: "go", role: "AXTextField")
    var acceptsValue = true
    /// What the field reads back after it's set, if it tidies it.
    var readBack: ((String) -> String)?
    var allowed = true
    /// Called on each wait, to change the dialog part way through.
    var onWait: ((FakeDialog, Int) -> Void)?
    /// Called whenever a value is set.
    var onSet: ((FakeDialog) -> Void)?
    /// What the field reads back after typing, or nil for a field that won't say.
    var typedReadBack: ((String) -> String?)? = { $0 }
    private var waits = 0
    private var clock: TimeInterval = 0
    private var looksAfterShortcut: Int?
    private var values: [String: String] = [:]

    func dialogIsFront() -> Bool { front }

    func focusedField() -> (field: Field, role: String?, subrole: String?)? {
        if let looks = looksAfterShortcut, let after = fieldAfter, looks >= after { focused = goToField }
        if looksAfterShortcut != nil { looksAfterShortcut! += 1 }
        return focused.map { ($0, $0.role, $0.subrole) }
    }

    func same(_ a: Field, _ b: Field) -> Bool { a == b }

    func isInDialog(_ field: Field) -> Bool { field.inDialog }

    func now() -> TimeInterval { clock }

    func pressGoToFolder() -> Bool {
        guard allowed else { return false }
        events.append(.goToFolder)
        looksAfterShortcut = 0
        return true
    }

    func setValue(_ text: String, in field: Field) -> Bool {
        onSet?(self)
        guard acceptsValue else { return false }
        events.append(.set(text, in: field.name))
        values[field.name] = readBack?(text) ?? text
        return true
    }

    func value(of field: Field) -> String? { values[field.name] }

    func type(_ text: String) -> Bool {
        guard allowed else { return false }
        events.append(.typed(text))
        values[focused?.name ?? ""] = typedReadBack?(text)
        return true
    }

    func pressReturn() -> Bool {
        guard allowed else { return false }
        events.append(.returnKey)
        return true
    }

    func wait(_ seconds: TimeInterval) async {
        waits += 1
        clock += seconds
        onWait?(self, waits)
    }
}

@MainActor
final class JumperTests: XCTestCase {
    let home = "/Users/robin"
    let path = "/Users/robin/Documents/Thesis"

    func testTheUsualWay() async {
        let dialog = FakeDialog()
        let __result0 = await Jumper.jump(to: path, home: home, with: dialog)
        XCTAssert(__result0 == .done)
        XCTAssert(dialog.events == [.goToFolder, .set(path + "/", in: "go"), .returnKey])
    }

    func testAFieldThatTidiesThePathStillCounts() async {
        let dialog = FakeDialog()
        dialog.readBack = { "~" + $0.dropFirst(self.home.count) }
        let __result1 = await Jumper.jump(to: path, home: home, with: dialog)
        XCTAssert(__result1 == .done)
        XCTAssert(!dialog.events.contains { if case .typed = $0 { true } else { false } })
    }

    func testTypesWhenTheFieldWontTakeAValue() async {
        let dialog = FakeDialog()
        dialog.acceptsValue = false
        let __result2 = await Jumper.jump(to: path, home: home, with: dialog)
        XCTAssert(__result2 == .done)
        XCTAssert(dialog.events == [.goToFolder, .typed(path + "/"), .returnKey])
    }

    func testTypesWhenTheValueDoesntStick() async {
        let dialog = FakeDialog()
        dialog.readBack = { _ in "" }
        let __result3 = await Jumper.jump(to: path, home: home, with: dialog)
        XCTAssert(__result3 == .done)
        XCTAssert(dialog.events == [.goToFolder, .set(path + "/", in: "go"), .set("", in: "go"), .typed(path + "/"), .returnKey])
    }

    func testTypingCanBeChosen() async {
        let dialog = FakeDialog()
        let __result4 = await Jumper.jump(to: path, home: home, typing: true, with: dialog)
        XCTAssert(__result4 == .done)
        XCTAssert(dialog.events == [.goToFolder, .set("", in: "go"), .typed(path + "/"), .returnKey])
    }

    func testGivesUpWhenGoToFolderNeverOpens() async {
        let dialog = FakeDialog()
        dialog.fieldAfter = nil
        let __result5 = await Jumper.jump(to: path, home: home, with: dialog)
        XCTAssert(__result5 == .failed(.noField))
        // Nothing but the shortcut was sent: no path, and no Return that could click Save.
        XCTAssert(dialog.events == [.goToFolder])
    }

    func testASearchFieldIsntGoToFolder() async {
        let dialog = FakeDialog()
        dialog.goToField = FakeDialog.Field(name: "search", role: "AXTextField", subrole: "AXSearchField")
        let __result6 = await Jumper.jump(to: path, home: home, with: dialog)
        XCTAssert(__result6 == .failed(.noField))
        XCTAssert(dialog.events == [.goToFolder])
    }

    func testTheNameFieldIsntGoToFolder() async {
        // In a Save dialog the name field already has the keyboard. If it still does after ⇧⌘G,
        // Go to Folder didn't open, and the path must not go into the file name.
        let dialog = FakeDialog()
        dialog.goToField = dialog.focused!
        let __result7 = await Jumper.jump(to: path, home: home, with: dialog)
        XCTAssert(__result7 == .failed(.noField))
        XCTAssert(dialog.events == [.goToFolder])
    }

    func testStopsWhenItCantTellWhatHadTheKeyboard() async {
        // Without knowing the field focused before ⇧⌘G, the Save dialog's name field could pass
        // for Go to Folder, and Return there would save. So it doesn't even start.
        let dialog = FakeDialog()
        dialog.focused = nil
        let __result8 = await Jumper.jump(to: path, home: home, with: dialog)
        XCTAssert(__result8 == .failed(.noField))
        XCTAssert(dialog.events.isEmpty)
    }

    func testAFieldOutsideTheDialogIsntGoToFolder() async {
        // Focus moved to a text field in the app's document window instead.
        let dialog = FakeDialog()
        dialog.goToField = FakeDialog.Field(name: "document", role: "AXTextField", inDialog: false)
        let __result9 = await Jumper.jump(to: path, home: home, with: dialog)
        XCTAssert(__result9 == .failed(.noField))
        XCTAssert(dialog.events == [.goToFolder])
    }

    func testAFieldThatTookTheWrongTextStops() async {
        let dialog = FakeDialog()
        dialog.acceptsValue = false
        dialog.typedReadBack = { String($0.prefix(10)) }
        let __result10 = await Jumper.jump(to: path, home: home, with: dialog)
        XCTAssert(__result10 == .failed(.pathRejected))
        XCTAssert(!dialog.events.contains(.returnKey))
    }

    func testAFieldThatWontSayWhatItHoldsIsTrusted() async {
        let dialog = FakeDialog()
        dialog.acceptsValue = false
        dialog.typedReadBack = nil
        let __result11 = await Jumper.jump(to: path, home: home, with: dialog)
        XCTAssert(__result11 == .done)
        XCTAssert(dialog.events.last == .returnKey)
    }

    func testTheTimeLimitIsWallClock() async {
        // Each look at the dialog is slow, so fewer looks fit in the time limit.
        let dialog = FakeDialog()
        dialog.fieldAfter = nil
        var waits = 0
        dialog.onWait = { _, _ in waits += 1 }
        let __result12 = await Jumper.jump(to: path, home: home, with: dialog)
        XCTAssert(__result12 == .failed(.noField))
        XCTAssert(waits == Int((GoTo.fieldTimeout / GoTo.pollInterval).rounded()))
    }

    func testStopsIfTheDialogClosesWhileWaiting() async {
        let dialog = FakeDialog()
        dialog.fieldAfter = 5
        dialog.onWait = { dialog, count in if count == 2 { dialog.front = false } }
        let __result13 = await Jumper.jump(to: path, home: home, with: dialog)
        XCTAssert(__result13 == .failed(.dialogGone))
        XCTAssert(dialog.events == [.goToFolder])
    }

    func testStopsIfTheDialogClosesBeforeReturn() async {
        let dialog = FakeDialog()
        // Three looks to find the field, then the pause before Return.
        dialog.onWait = { dialog, count in if count == 4 { dialog.front = false } }
        let __result14 = await Jumper.jump(to: path, home: home, with: dialog)
        XCTAssert(__result14 == .failed(.dialogGone))
        XCTAssert(dialog.events.count == 2)
        XCTAssert(!dialog.events.contains(.returnKey))
    }

    func testNeverPressesReturnOutsideTheField() async {
        // Something else takes the keyboard after the path is set: Return would click Save.
        let dialog = FakeDialog()
        dialog.onWait = { dialog, count in if count == 4 { dialog.goToField = FakeDialog.Field(name: "save button", role: "AXButton") } }
        let __result15 = await Jumper.jump(to: path, home: home, with: dialog)
        XCTAssert(__result15 == .failed(.dialogGone))
        XCTAssert(dialog.events.count == 2)
        XCTAssert(!dialog.events.contains(.returnKey))
    }

    func testNeverTypesOutsideTheField() async {
        // The field won't take the path, and by then something else has the keyboard.
        let dialog = FakeDialog()
        dialog.acceptsValue = false
        dialog.onSet = { $0.goToField = FakeDialog.Field(name: "list", role: "AXOutline") }
        let __result16 = await Jumper.jump(to: path, home: home, with: dialog)
        XCTAssert(__result16 == .failed(.dialogGone))
        XCTAssert(dialog.events == [.goToFolder])
    }

    func testNotAllowedWithoutAccessibility() async {
        let dialog = FakeDialog()
        dialog.allowed = false
        let __result17 = await Jumper.jump(to: path, home: home, with: dialog)
        XCTAssert(__result17 == .failed(.notAllowed))
        XCTAssert(dialog.events.isEmpty)
    }

    func testTypesWholeCharacters() {
        let path = "/Users/robin/📁 Résumés/日本語のフォルダ/👩🏽‍🔬 lab/"
        let pieces = GoTo.chunks(path, size: 16)
        XCTAssert(pieces.joined() == path)
        XCTAssert(pieces.allSatisfy { $0.utf16.count <= 16 || $0.count == 1 })
        XCTAssert(GoTo.chunks("", size: 16).isEmpty)
        // A character longer than a whole piece still goes in one piece of its own.
        XCTAssert(GoTo.chunks("👩🏽‍🔬", size: 2) == ["👩🏽‍🔬"])
    }

    func testNotStartedWithoutADialog() async {
        let dialog = FakeDialog()
        dialog.front = false
        let __result18 = await Jumper.jump(to: path, home: home, with: dialog)
        XCTAssert(__result18 == .failed(.dialogGone))
        XCTAssert(dialog.events.isEmpty)
    }

    func testTheRootFolder() async {
        let dialog = FakeDialog()
        let __result19 = await Jumper.jump(to: "/", home: home, with: dialog)
        XCTAssert(__result19 == .done)
        XCTAssert(dialog.events[1] == .set("/", in: "go"))
    }
}
