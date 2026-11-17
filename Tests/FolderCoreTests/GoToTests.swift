import CoreGraphics
import Foundation
import XCTest
@testable import FolderCore

final class GoToTests: XCTestCase {
    func testTextEndsInASlash() {
        XCTAssert(GoTo.text(for: "/Users/robin/Documents") == "/Users/robin/Documents/")
        XCTAssert(GoTo.text(for: "/") == "/")
        XCTAssert(GoTo.text(for: "/Volumes/Field Drive") == "/Volumes/Field Drive/")
    }

    func testRecognizesTheField() {
        XCTAssert(GoTo.isGoToField(role: "AXTextField", subrole: nil, wasFocusedBefore: false))
        XCTAssert(GoTo.isGoToField(role: "AXComboBox", subrole: nil, wasFocusedBefore: false))
        // The Save dialog's name field was already focused, and a search field is never it.
        XCTAssert(!GoTo.isGoToField(role: "AXTextField", subrole: nil, wasFocusedBefore: true))
        XCTAssert(!GoTo.isGoToField(role: "AXTextField", subrole: "AXSearchField", wasFocusedBefore: false))
        XCTAssert(!GoTo.isGoToField(role: "AXTextField", subrole: "AXSecureTextField", wasFocusedBefore: false))
        for role in ["AXOutline", "AXList", "AXBrowser", "AXButton", "AXTextArea", nil] as [String?] {
            XCTAssert(!GoTo.isGoToField(role: role, subrole: nil, wasFocusedBefore: false))
        }
    }

    func testChecksTheFieldTookThePath() {
        let home = "/Users/robin"
        XCTAssert(GoTo.fieldHolds("/Users/robin/Documents/", path: "/Users/robin/Documents", home: home))
        XCTAssert(GoTo.fieldHolds("/Users/robin/Documents", path: "/Users/robin/Documents", home: home))
        XCTAssert(GoTo.fieldHolds("~/Documents/", path: "/Users/robin/Documents", home: home))
        XCTAssert(!GoTo.fieldHolds("/Users/robin/Desktop/", path: "/Users/robin/Documents", home: home))
        XCTAssert(!GoTo.fieldHolds("", path: "/Users/robin/Documents", home: home))
        XCTAssert(!GoTo.fieldHolds(nil, path: "/Users/robin/Documents", home: home))
        XCTAssert(!GoTo.fieldHolds("/Users/robin/Docu", path: "/Users/robin/Documents", home: home))
    }

    func testFailuresSayWhatToDo() {
        for failure in [GoTo.Failure.dialogGone, .noField, .notAllowed, .unavailable] {
            XCTAssert(failure.message.hasSuffix("."))
        }
        XCTAssert(GoTo.Failure.noField.message.contains("⇧⌘G"))
    }
}

final class KeyLayoutTests: XCTestCase {
    /// What the letter keys type on three layouts, by key code.
    static let qwerty: [UInt16: String] = [0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 34: "i", 36: "\r"]
    static let dvorak: [UInt16: String] = [0: "a", 1: "o", 2: "e", 3: "u", 4: "d", 5: "i", 34: "g", 36: "\r"]
    static let azerty: [UInt16: String] = [0: "q", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 12: "a"]

    func testFindsGOnEachLayout() {
        XCTAssert(KeyLayout.keyCode(for: "g", in: Self.qwerty) == 5)
        XCTAssert(KeyLayout.keyCode(for: "g", in: Self.dvorak) == 34)
        XCTAssert(KeyLayout.keyCode(for: "g", in: Self.azerty) == 5)
        XCTAssert(KeyLayout.keyCode(for: "G", in: Self.dvorak) == 34)
    }

    func testFallsBackToUSKeys() {
        let greek: [UInt16: String] = [5: "γ", 0: "α"]
        XCTAssert(KeyLayout.keyCode(for: "g", in: greek) == 5)
        XCTAssert(KeyLayout.keyCode(for: "g", in: [:]) == 5)
        XCTAssert(KeyLayout.keyCode(for: "q", in: [:]) == nil)
    }

    func testPrefersTheMainKeyboard() {
        XCTAssert(KeyLayout.keyCode(for: "g", in: [90: "g", 5: "g"]) == 5)
    }
}

final class PlacementTests: XCTestCase {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let size = CGSize(width: 260, height: 400)

    func testBesideOnTheRight() {
        let dialog = CGRect(x: 400, y: 120, width: 640, height: 480)
        let frame = Placement.frame(beside: dialog, size: size, screens: [screen])
        XCTAssert(frame == CGRect(x: 1048, y: 120, width: 260, height: 400))
    }

    func testLeftWhenTheRightIsFull() {
        let dialog = CGRect(x: 700, y: 100, width: 640, height: 480)
        let frame = Placement.frame(beside: dialog, size: size, screens: [screen])
        XCTAssert(frame.maxX == 692)
        XCTAssert(frame.minY == 100)
    }

    func testInsideWhenNeitherSideFits() {
        let dialog = CGRect(x: 40, y: 60, width: 1360, height: 700)
        let frame = Placement.frame(beside: dialog, size: size, screens: [screen])
        XCTAssert(frame.maxX == dialog.maxX - Placement.gap)
        XCTAssert(screen.contains(frame))
    }

    func testStaysOnScreen() {
        let low = CGRect(x: 300, y: 700, width: 500, height: 180)
        let frame = Placement.frame(beside: low, size: size, screens: [screen])
        XCTAssert(frame.maxY <= screen.maxY && frame.minY >= screen.minY)
        let huge = Placement.frame(beside: low, size: CGSize(width: 260, height: 2000), screens: [screen])
        XCTAssert(huge.height == 900 && huge.minY == 0)
    }

    func testPicksTheDialogsScreen() {
        let right = CGRect(x: 1440, y: -200, width: 1920, height: 1080)
        let dialog = CGRect(x: 1800, y: 0, width: 600, height: 400)
        let frame = Placement.frame(beside: dialog, size: size, screens: [screen, right])
        XCTAssert(right.contains(frame))
        XCTAssert(frame.minX == dialog.maxX + Placement.gap)
        // Mostly on the left screen, so it stays there, on its left side.
        let straddling = CGRect(x: 1000, y: 100, width: 600, height: 400)
        XCTAssert(Placement.screen(for: straddling, in: [screen, right]) == screen)
        // Off every screen: the main one.
        XCTAssert(Placement.screen(for: CGRect(x: -5000, y: 0, width: 10, height: 10), in: [screen, right]) == screen)
        XCTAssert(Placement.screen(for: dialog, in: []).width > 0)
    }

    func testFlipsCoordinates() {
        let ax = CGRect(x: 100, y: 50, width: 200, height: 100)
        let appKit = Placement.flip(ax, mainHeight: 900)
        XCTAssert(appKit == CGRect(x: 100, y: 750, width: 200, height: 100))
        XCTAssert(Placement.flip(appKit, mainHeight: 900) == ax)
    }
}

final class DescribeTests: XCTestCase {
    func testStatusLines() {
        XCTAssert(Describe.headline(.waiting) == "Waiting for an Open or Save dialog")
        XCTAssert(Describe.headline(.showing(.save, app: "Inkpad")) == "Save dialog in Inkpad")
        XCTAssert(Describe.headline(.showing(.open, app: "Inkpad")) == "Open dialog in Inkpad")
        XCTAssert(Describe.headline(.offInApp("Inkpad")) == "Off in Inkpad")
        for status in [Describe.Status.needsAccessibility, .paused, .waiting, .showing(.open, app: "A"), .offInApp("A")] {
            XCTAssert(!Describe.headline(status).isEmpty)
            XCTAssert(Describe.detail(status).hasSuffix("."))
        }
        XCTAssert(Describe.detail(.waiting).contains(Describe.shortcut))
    }

    func testSectionsAndAvailability() {
        XCTAssert(Describe.section(.finder) == "Open in Finder")
        XCTAssert(Describe.section(.favorite) == "Favorites")
        XCTAssert(Describe.section(.recent) == "Recent")
        XCTAssert(Describe.availability(.ready) == nil)
        XCTAssert(Describe.availability(.missing) == "Not found")
    }

    func testSafeText() {
        XCTAssert(Describe.safe("Inkpad") == "Inkpad")
        XCTAssert(Describe.safe("Evil\u{202E}gpj.app") == "Evilgpj.app")
        XCTAssert(Describe.safe("Two\nlines") == "Two lines")
        XCTAssert(Describe.safe("  padded  ") == "padded")
        XCTAssert(Describe.safe(String(repeating: "x", count: 100), limit: 10) == String(repeating: "x", count: 9) + "…")
        XCTAssert(Describe.headline(.showing(.open, app: String(repeating: "y", count: 100))).count < 70)
    }
}
