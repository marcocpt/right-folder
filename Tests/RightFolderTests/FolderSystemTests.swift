import Foundation
import XCTest
@testable import FolderCore
@testable import RightFolder

/// The real folder checks, on a throwaway folder of made-up folders and links.
@MainActor
final class FolderSystemTests: XCTestCase {
    var root: String!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("RightFolderTests-\(UUID().uuidString)").path
        let files = FileManager.default
        try files.createDirectory(atPath: root + "/Thesis/Figures", withIntermediateDirectories: true)
        try Data().write(to: URL(fileURLWithPath: root + "/notes.md"))
        try files.createSymbolicLink(atPath: root + "/thesis-link", withDestinationPath: "Thesis")
        try files.createSymbolicLink(atPath: root + "/absolute-link", withDestinationPath: root + "/Thesis/Figures")
        try files.createSymbolicLink(atPath: root + "/file-link", withDestinationPath: "notes.md")
        try files.createSymbolicLink(atPath: root + "/dangling", withDestinationPath: "Nowhere")
        try files.createSymbolicLink(atPath: root + "/loop-a", withDestinationPath: "loop-b")
        try files.createSymbolicLink(atPath: root + "/loop-b", withDestinationPath: "loop-a")
        // Links onto a server: one into an automount folder, one onto a share that isn't mounted.
        try files.createSymbolicLink(atPath: root + "/lab-server", withDestinationPath: "/net/lab-server-that-does-not-exist/data")
        try files.createSymbolicLink(atPath: root + "/old-share", withDestinationPath: "/Volumes/RightFolderTests Share/data")
    }

    var checker: LiveChecker { LiveChecker(mounts: LiveFolderSystem.mounts()) }

    func testFoldersAndFiles() {
        XCTAssert(checker.isFolder(root))
        XCTAssert(checker.isFolder(root + "/Thesis/Figures"))
        XCTAssert(!checker.isFolder(root + "/notes.md"))
        XCTAssert(!checker.isFolder(root + "/Missing"))
        XCTAssert(checker.isFolder("/"))
    }

    func testFollowsLocalLinks() {
        XCTAssert(checker.isFolder(root + "/thesis-link"))
        XCTAssert(checker.isFolder(root + "/thesis-link/Figures"))
        XCTAssert(checker.isFolder(root + "/absolute-link"))
        XCTAssert(!checker.isFolder(root + "/file-link"))
        XCTAssert(!checker.isFolder(root + "/dangling"))
        XCTAssert(!checker.isFolder(root + "/loop-a"))
    }

    func testNeverLooksThroughLinksOntoServers() {
        // Taken as there without asking, since asking a dead server would hang.
        XCTAssert(checker.isFolder(root + "/lab-server"))
        XCTAssert(checker.isFolder(root + "/lab-server/deeper"))
        XCTAssert(checker.isFolder(root + "/old-share"))
    }

    func testMountsAndBookmarks() {
        let system = LiveFolderSystem()
        let mounts = LiveFolderSystem.mounts()
        XCTAssert(mounts.contains { $0.path == "/" && $0.isLocal })
        XCTAssert(system.bookmark(for: root + "/Thesis") != nil)
        // No bookmark is made for a folder on a server, or under /Volumes with nothing mounted.
        XCTAssert(system.bookmark(for: "/net/lab-server-that-does-not-exist") == nil)
        XCTAssert(system.bookmark(for: "/Volumes/RightFolderTests Share/data") == nil)
        // A bookmark follows its folder when it's renamed.
        let bookmark = system.bookmark(for: root + "/Thesis/Figures")
        try? FileManager.default.moveItem(atPath: root + "/Thesis/Figures", toPath: root + "/Thesis/Plots")
        let resolved = system.resolve(Favorite(path: root + "/Thesis/Figures", bookmark: bookmark))
        XCTAssert(resolved.map { Paths.normalize($0.path) ?? "" }?.hasSuffix("/Thesis/Plots") == true)
    }
}
