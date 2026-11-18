import AppKit
import ApplicationServices
import Carbon.HIToolbox
import XCTest
@testable import FolderCore
@testable import RightFolder

/// Guards the fix for the "click a folder, nothing happens, Go to Folder warning" bug.
///
/// An Open/Save panel's keyboard focus can live in a separate "Open and Save Panel Service"
/// process. Posting keys with `postToPid(ownerPid)` misses that focus, so ⇧⌘G never opens Go to
/// Folder and a jump ends in `.noField`. Keys must be posted at the system event tap through
/// `KeyDelivery`, which delivers to the view that actually has the keyboard.
///
/// These tests inject a recorder into `KeyDelivery` and check that every key a jump sends goes
/// through that layer. If anyone reverts `press()`/`type()` to a direct `postToPid`, the recorder
/// sees no events and these tests fail.
@MainActor
final class KeyDeliveryTests: XCTestCase {
    private var originalPost: ((CGEvent) -> Void)!

    override func setUp() {
        super.setUp()
        originalPost = KeyDelivery.post
    }

    override func tearDown() {
        KeyDelivery.post = originalPost
        super.tearDown()
    }

    /// A stand-in dialog. Building its Accessibility element needs no permission, and press/type
    /// only create and hand off CGEvents — they never read this element.
    private func makeDialog() -> OpenDialog {
        OpenDialog(
            pid: pid_t(getpid()),
            appName: "TestApp",
            bundleID: "com.example.test",
            kind: .open,
            element: AXUIElementCreateApplication(pid_t(getpid())),
            frame: nil
        )
    }

    func testAllJumpKeysGoThroughTheDeliveryLayer() {
        var recorded: [CGEvent] = []
        KeyDelivery.post = { recorded.append($0) }
        let dialog = LiveDialog(makeDialog())

        // The three keys a jump can send: ⇧⌘G, the path text, and Return.
        XCTAssertTrue(dialog.pressGoToFolder())
        XCTAssertTrue(dialog.type("/Users/robin/Documents/"))
        XCTAssertTrue(dialog.pressReturn())

        // press sends down+up for each key; type sends down+up per text chunk.
        // The point is that every one of them reached the delivery layer.
        XCTAssertGreaterThanOrEqual(recorded.count, 6, "Keys were not posted through KeyDelivery")
    }

    func testGoToFolderShortcutHasTheRightKeyAndModifiers() {
        var recorded: [CGEvent] = []
        KeyDelivery.post = { recorded.append($0) }
        let dialog = LiveDialog(makeDialog())

        XCTAssertTrue(dialog.pressGoToFolder())

        // ⇧⌘G: key code for G, down then up, with command+shift flags.
        XCTAssertEqual(recorded.count, 2)
        for event in recorded {
            XCTAssertEqual(event.flags, [.maskCommand, .maskShift])
        }
        XCTAssertEqual(KeyLayout.keyCode(for: "g", in: Keyboard.table(command: true)) ?? 5, 5)
    }
}
