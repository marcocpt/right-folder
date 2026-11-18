import AppKit
import Foundation
import XCTest
@testable import FolderCore
@testable import RightFolder

/// Real Open and Save panels, made in this test process and never shown, read through AppKit's
/// own accessibility methods: the same role, subrole and identifier another app sees.
@MainActor
final class RealPanelTests: XCTestCase {
    private func element(_ window: NSWindow) -> Element {
        Element(role: window.accessibilityRole()?.rawValue, subrole: window.accessibilitySubrole()?.rawValue, identifier: window.accessibilityIdentifier())
    }

    func testSavePanel() {
        let panel = NSSavePanel()
        XCTAssert(!panel.isVisible)
        XCTAssert(Dialogs.kind(of: element(panel)) == .save)
    }

    func testOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        XCTAssert(!panel.isVisible)
        XCTAssert(Dialogs.kind(of: element(panel)) == .open)
    }

    func testOtherPanelsArentDialogs() {
        for window in [NSAlert().window, NSPanel(), NSWindow()] {
            XCTAssert(Dialogs.kind(of: element(window)) == nil)
        }
    }

    func testAWindowShowingAFolderNamesIt() {
        // Finder's windows say which folder they show the same way: the window's represented URL.
        let window = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        window.representedURL = URL(fileURLWithPath: "/Users/robin/Documents", isDirectory: true)
        let document = window.accessibilityDocument()
        XCTAssert(document.flatMap(Paths.fromFileURL) == "/Users/robin/Documents")
        XCTAssert(!window.isVisible)
    }

    func testKeyboardLayoutHasAG() {
        // Whatever layout this Mac uses, some key types g, or the US one is used.
        XCTAssert(KeyLayout.keyCode(for: "g", in: Keyboard.table()) != nil)
        XCTAssert(KeyLayout.keyCode(for: "j", in: Keyboard.table()) != nil || KeyLayout.ansi["j"] != nil)
    }
}

/// The app's bundle settings and signing, checked against what the docs promise.
final class BundleTests: XCTestCase {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    func testAMenuBarAppWithItsOwnID() throws {
        let info = try XCTUnwrap(NSDictionary(contentsOf: Self.root.appendingPathComponent("Resources/Info.plist")) as? [String: Any])
        XCTAssert(info["CFBundleIdentifier"] as? String == "com.stanczykwyatt.RightFolder")
        XCTAssert(info["LSUIElement"] as? Bool == true)
        XCTAssert(info["CFBundleShortVersionString"] as? String == Describe.version)
        // Matches Package.swift's .macOS(.v13) deployment target, so the app runs on macOS 13.
        XCTAssert(info["LSMinimumSystemVersion"] as? String == "13.0")
        // It never sends Apple Events, so it has no reason to ask to.
        XCTAssert(info["NSAppleEventsUsageDescription"] == nil)
    }

    func testNoEntitlementsAndTheDefaultSignature() throws {
        // Accessibility is the only permission, and it needs no entitlement. The build signs with
        // the hardened runtime and macOS's default requirement, never one that trusts the bundle ID alone.
        let resources = try FileManager.default.contentsOfDirectory(atPath: Self.root.appendingPathComponent("Resources").path)
        XCTAssert(!resources.contains { $0.hasSuffix(".entitlements") })
        let script = try String(contentsOf: Self.root.appendingPathComponent("scripts/build-app.sh"), encoding: .utf8)
        XCTAssert(script.contains("--options runtime"))
        XCTAssert(!script.contains("--entitlements"))
        XCTAssert(!script.contains("--requirements"))
        XCTAssert(!script.contains("designated =>"))
    }
}
