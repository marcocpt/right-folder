import Foundation
import XCTest
@testable import FolderCore

final class DialogTests: XCTestCase {
    func testRecognizesAppKitPanels() {
        XCTAssert(Dialogs.kind(of: Recorded.savePanel) == .save)
        XCTAssert(Dialogs.kind(of: Recorded.openPanel) == .open)
        XCTAssert(Dialogs.kind(of: Recorded.saveSheet) == .save)
        XCTAssert(Dialogs.kind(of: Recorded.openSheet) == .open)
    }

    func testIgnoresOtherWindows() {
        for element in [Recorded.alert, Recorded.colorPanel, Recorded.fontPanel, Recorded.document(), Recorded.webPage] {
            XCTAssert(Dialogs.kind(of: element) == nil)
            XCTAssert(Dialogs.find(in: element) == nil)
        }
    }

    func testOnlyWindowsAndSheetsCount() {
        // The identifier on a button or a group in a web page isn't a dialog.
        for role in ["AXGroup", "AXButton", "AXWebArea", "AXTextField", nil] as [String?] {
            XCTAssert(Dialogs.kind(of: Element(role: role, identifier: "save-panel")) == nil)
            XCTAssert(Dialogs.kind(of: Element(role: role, subrole: "AXOpenPanel")) == nil)
        }
        XCTAssert(Dialogs.find(in: Recorded.webPage) == nil)
    }

    func testSubrolesCountToo() {
        XCTAssert(Dialogs.kind(of: Element(role: "AXWindow", subrole: "AXOpenPanel")) == .open)
        XCTAssert(Dialogs.kind(of: Element(role: "AXSheet", subrole: "AXSavePanel")) == .save)
        XCTAssert(Dialogs.kind(of: Element(role: "AXWindow", subrole: "AXDialog")) == nil)
    }

    func testIdentifiersMustMatchExactly() {
        for identifier in ["Save-Panel", "save-panel ", "savepanel", "save", "open-panel-2", ""] {
            XCTAssert(Dialogs.kind(of: Element(role: "AXWindow", identifier: identifier)) == nil)
        }
    }

    func testFindsTheWindowItself() {
        XCTAssert(Dialogs.find(in: Recorded.savePanel) == DialogMatch(kind: .save, path: []))
        XCTAssert(Dialogs.find(in: Recorded.openPanel) == DialogMatch(kind: .open, path: []))
    }

    func testFindsASheetOnADocument() {
        let window = Recorded.document(sheets: [Recorded.saveSheet])
        XCTAssert(Dialogs.find(in: window) == DialogMatch(kind: .save, path: [3]))
    }

    func testSkipsSheetsThatArentDialogs() {
        let alert = Element(role: "AXSheet", subrole: nil, identifier: nil)
        let window = Recorded.document(sheets: [alert, Recorded.openSheet])
        XCTAssert(Dialogs.find(in: window) == DialogMatch(kind: .open, path: [4]))
        XCTAssert(Dialogs.find(in: Recorded.document(sheets: [alert])) == nil)
    }

    func testTheDeepestDialogWins() {
        // An Open dialog opened from a sheet on a Save dialog, like "Choose…" in an export sheet.
        var save = Recorded.saveSheet
        save.children = [Element(role: "AXButton"), Recorded.openSheet]
        let window = Recorded.document(sheets: [save])
        XCTAssert(Dialogs.find(in: window) == DialogMatch(kind: .open, path: [3, 1]))
        // A plain alert on a Save dialog, like "Replace existing file?", still finds the Save dialog.
        var withAlert = Recorded.saveSheet
        withAlert.children = [Element(role: "AXSheet")]
        XCTAssert(Dialogs.find(in: Recorded.document(sheets: [withAlert])) == DialogMatch(kind: .save, path: [3]))
    }

    func testOnlySheetsAreSearched() {
        // A panel's identifier deep inside a window's content isn't a dialog on it.
        let window = Element(role: "AXWindow", children: [Element(role: "AXGroup", children: [Recorded.saveSheet])])
        XCTAssert(Dialogs.find(in: window) == nil)
    }

    func testSearchDepthIsLimited() {
        var element = Recorded.saveSheet
        for _ in 0..<6 { element = Element(role: "AXSheet", children: [element]) }
        let window = Element(role: "AXWindow", children: [element])
        XCTAssert(Dialogs.find(in: window) == nil)
        let shallow = Element(role: "AXWindow", children: [Element(role: "AXSheet", children: [Recorded.saveSheet])])
        XCTAssert(Dialogs.find(in: shallow)?.path == [0, 0])
    }

    func testWhereToOffer() {
        XCTAssert(Dialogs.shouldOffer(appBundleID: "com.example.inkpad", ownBundleID: "com.stanczykwyatt.RightFolder", excluded: []))
        XCTAssert(!Dialogs.shouldOffer(appBundleID: "com.stanczykwyatt.RightFolder", ownBundleID: "com.stanczykwyatt.RightFolder", excluded: []))
        XCTAssert(!Dialogs.shouldOffer(appBundleID: "com.example.inkpad", ownBundleID: nil, excluded: ["com.example.inkpad"]))
        // An app without a bundle ID, like a command line tool's window, can't be turned off by ID.
        XCTAssert(Dialogs.shouldOffer(appBundleID: nil, ownBundleID: "com.stanczykwyatt.RightFolder", excluded: ["com.example.inkpad"]))
    }

    func testElementsRoundTrip() throws {
        let window = Recorded.document(sheets: [Recorded.saveSheet])
        let data = try JSONEncoder().encode(window)
        XCTAssert(try JSONDecoder().decode(Element.self, from: data) == window)
    }
}
