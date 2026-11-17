import XCTest
@testable import FolderCore

final class PathTests: XCTestCase {
    func testNormalizes() {
        XCTAssert(Paths.normalize("/Users/robin/Documents/") == "/Users/robin/Documents")
        XCTAssert(Paths.normalize("/Users//robin///Documents") == "/Users/robin/Documents")
        XCTAssert(Paths.normalize("/Users/robin/./Documents/../Desktop") == "/Users/robin/Desktop")
        XCTAssert(Paths.normalize("/") == "/")
        XCTAssert(Paths.normalize("//") == "/")
        XCTAssert(Paths.normalize("/..") == "/")
        XCTAssert(Paths.normalize("/../../etc") == "/etc")
    }

    func testRefusesWhatADialogCantTake() {
        XCTAssert(Paths.normalize("") == nil)
        XCTAssert(Paths.normalize("Documents") == nil)
        XCTAssert(Paths.normalize("~/Documents") == nil)
        XCTAssert(Paths.normalize("/Users/robin/Line\nBreak") == nil)
        XCTAssert(Paths.normalize("/Users/robin/Tab\there") == nil)
        XCTAssert(Paths.normalize("/Users/robin/Null\u{0}") == nil)
        XCTAssert(Paths.normalize("/Users/robin/Bell\u{7}") == nil)
        XCTAssert(Paths.normalize("/" + String(repeating: "a", count: 1100)) == nil)
    }

    func testKeepsUnusualButValidNames() {
        for name in ["Résumé drafts", "日本語", "100% done", "a:b", "#hash", "emoji 📁", "quotes \"and\" 'apostrophes'", " leading space", "trailing dot."] {
            XCTAssert(Paths.normalize("/Users/robin/" + name) == "/Users/robin/" + name)
        }
    }

    func testMapsDataVolumeFirmlinks() {
        XCTAssert(Paths.normalize("/System/Volumes/Data/Users/robin/Documents") == "/Users/robin/Documents")
        XCTAssert(Paths.normalize("/System/Volumes/Data/Applications") == "/Applications")
        XCTAssert(Paths.normalize("/System/Volumes/Data/private/tmp") == "/private/tmp")
        // Something only on the Data volume stays as it is.
        XCTAssert(Paths.normalize("/System/Volumes/Data/.Spotlight-V100") == "/System/Volumes/Data/.Spotlight-V100")
        XCTAssert(Paths.normalize("/System/Volumes/Data") == "/System/Volumes/Data")
    }

    func testReadsFinderURLs() {
        XCTAssert(Paths.fromFileURL("file:///Users/robin/Documents/") == "/Users/robin/Documents")
        XCTAssert(Paths.fromFileURL("file:///Users/robin/Lab%20Notes/") == "/Users/robin/Lab Notes")
        XCTAssert(Paths.fromFileURL("file:///Users/robin/R%C3%A9sum%C3%A9/") == "/Users/robin/Résumé")
        XCTAssert(Paths.fromFileURL("file://localhost/Volumes/Field%20Drive/") == "/Volumes/Field Drive")
        XCTAssert(Paths.fromFileURL("file:///") == "/")
        XCTAssert(Paths.fromFileURL("FILE:///tmp/") == "/tmp")
        XCTAssert(Paths.fromFileURL("file:///Users/robin/100%25/") == "/Users/robin/100%")
    }

    func testRefusesOtherURLs() {
        for url in ["https://example.com/", "smb://lab-share/data/", "afp://server/", "file://server/share/", "x-finder:recents", "", "not a url", "/Users/robin", "file:///Users/robin/Bad%0ABreak/"] {
            XCTAssert(Paths.fromFileURL(url) == nil, "\(url)")
        }
    }

    func testAbbreviatesHome() {
        XCTAssert(Paths.abbreviate("/Users/robin", home: "/Users/robin") == "~")
        XCTAssert(Paths.abbreviate("/Users/robin/Documents", home: "/Users/robin") == "~/Documents")
        XCTAssert(Paths.abbreviate("/Users/robinson/Documents", home: "/Users/robin") == "/Users/robinson/Documents")
        XCTAssert(Paths.abbreviate("/Volumes/X", home: "/Users/robin") == "/Volumes/X")
        XCTAssert(Paths.abbreviate("/tmp", home: "/") == "/tmp")
    }

    func testInsideIsByWholeFolders() {
        XCTAssert(Paths.isInside("/Users/robin/Documents", "/Users/robin"))
        XCTAssert(Paths.isInside("/Users/robin", "/Users/robin"))
        XCTAssert(!Paths.isInside("/Users/robinson", "/Users/robin"))
        XCTAssert(Paths.isInside("/anything", "/"))
    }

    func testOffLimits() {
        let home = Mac.home
        XCTAssert(Paths.isOffLimits(home + "/.Trash", home: home))
        XCTAssert(Paths.isOffLimits(home + "/.Trash/old", home: home))
        XCTAssert(Paths.isOffLimits("/Volumes/Field Drive/.Trashes/501", home: home))
        XCTAssert(Paths.isOffLimits("/Applications/Inkpad.app/Contents", home: home))
        XCTAssert(Paths.isOffLimits(home + "/Pictures/Photos Library.photoslibrary/originals", home: home))
        // A package itself can be picked in a dialog; only going inside it is off limits.
        XCTAssert(!Paths.isOffLimits("/Applications/Inkpad.app", home: home))
        XCTAssert(!Paths.isOffLimits(home + "/Documents", home: home))
        XCTAssert(!Paths.isOffLimits(home + "/.Trashy", home: home))
        XCTAssert(!Paths.isOffLimits(home + "/Projects/my.app.notes", home: home))
    }

    func testFollowsLinks() {
        XCTAssert(Paths.linkTarget("/Volumes/lab-share/data", of: "/Users/robin/data") == "/Volumes/lab-share/data")
        XCTAssert(Paths.linkTarget("../Shared/data", of: "/Users/robin/Desktop/data") == "/Users/robin/Shared/data")
        XCTAssert(Paths.linkTarget("Projects", of: "/Users/robin/p") == "/Users/robin/Projects")
        // A link whose target holds a line break can't be offered.
        XCTAssert(Paths.linkTarget("bad\nlink", of: "/Users/robin/p") == nil)
        XCTAssert(Paths.linkTarget("/x\u{0}", of: "/y") == nil)
    }

    func testAutomountFolders() {
        XCTAssert(Paths.isAutomount("/net/fileserver/home"))
        XCTAssert(Paths.isAutomount("/Network/Servers"))
        XCTAssert(!Paths.isAutomount("/Users/robin/net"))
        XCTAssert(!Paths.isAutomount("/network-notes"))
        XCTAssert(FolderList.availability(of: "/net/fileserver/home", context: Mac.context, checker: FakeChecker(folders: [])) == .network)
    }

    func testFindsTheVolume() {
        XCTAssert(Mount.of("/Volumes/Field Drive/2026 Survey", in: Mac.mounts)?.name == "Field Drive")
        XCTAssert(Mount.of("/Volumes/Field Drive Backup", in: Mac.mounts)?.path == "/")
        XCTAssert(Mount.of("/Users/robin", in: Mac.mounts)?.path == "/")
        XCTAssert(Mount.of("/Users/robin", in: [])?.path == nil)
    }
}

final class NameTests: XCTestCase {
    let context = Mac.context

    func testHomeFolders() {
        XCTAssert(context.describe(Mac.home) == FolderInfo(name: "robin", location: "Home", place: .home))
        XCTAssert(context.describe(Mac.home + "/Desktop").place == .desktop)
        XCTAssert(context.describe(Mac.home + "/Documents") == FolderInfo(name: "Documents", location: "~", place: .documents))
        XCTAssert(context.describe(Mac.home + "/Downloads").place == .downloads)
        XCTAssert(context.describe(Mac.home + "/Documents/Thesis/Figures") == FolderInfo(name: "Figures", location: "~/Documents/Thesis", place: .folder))
    }

    func testOtherFolders() {
        XCTAssert(context.describe("/Applications") == FolderInfo(name: "Applications", location: "/", place: .folder))
        XCTAssert(context.describe("/") == FolderInfo(name: "Macintosh HD", location: "Startup disk", place: .volume))
        let renamed = PathContext(home: Mac.home, mounts: Mac.mounts, bootName: "Studio")
        XCTAssert(renamed.describe("/").name == "Studio")
    }

    func testICloudDrive() {
        let drive = Mac.home + "/Library/Mobile Documents/com~apple~CloudDocs"
        XCTAssert(context.describe(drive) == FolderInfo(name: "iCloud Drive", location: "iCloud", place: .iCloud))
        XCTAssert(context.describe(drive + "/Reading") == FolderInfo(name: "Reading", location: "iCloud Drive", place: .iCloud))
        XCTAssert(context.describe(drive + "/Reading/2026") == FolderInfo(name: "2026", location: "iCloud Drive › Reading", place: .iCloud))
    }

    func testAppFoldersInICloud() {
        let root = Mac.home + "/Library/Mobile Documents"
        XCTAssert(context.describe(root + "/com~apple~Pages/Documents") == FolderInfo(name: "Pages", location: "iCloud Drive", place: .iCloud))
        XCTAssert(context.describe(root + "/com~apple~Pages") == FolderInfo(name: "Pages", location: "iCloud Drive", place: .iCloud))
        XCTAssert(context.describe(root + "/iCloud~com~example~Notebook/Documents/Ideas") == FolderInfo(name: "Ideas", location: "iCloud Drive › Notebook", place: .iCloud))
        XCTAssert(context.describe(root + "/iCloud~com~example~Notebook/Documents/Ideas/Old") == FolderInfo(name: "Old", location: "iCloud Drive › Notebook › Ideas", place: .iCloud))
        XCTAssert(context.describe(root + "/iCloud~com~example~Notebook/Data") == FolderInfo(name: "Data", location: "iCloud Drive › Notebook", place: .iCloud))
        XCTAssert(PathContext.appName(container: "com~apple~Numbers") == "Numbers")
        XCTAssert(PathContext.appName(container: "plain") == "plain")
        XCTAssert(PathContext.appName(container: "trailing~") == "trailing")
    }

    func testVolumes() {
        XCTAssert(context.describe("/Volumes/Field Drive") == FolderInfo(name: "Field Drive", location: "Disk", place: .volume))
        XCTAssert(context.describe("/Volumes/Field Drive/2026 Survey") == FolderInfo(name: "2026 Survey", location: "Field Drive", place: .folder))
        XCTAssert(context.describe("/Volumes/Field Drive/2026 Survey/Plots") == FolderInfo(name: "Plots", location: "Field Drive › 2026 Survey", place: .folder))
        XCTAssert(context.describe("/Volumes/lab-share") == FolderInfo(name: "lab-share", location: "Network", place: .network))
        XCTAssert(context.describe("/Volumes/lab-share/data") == FolderInfo(name: "data", location: "lab-share", place: .network))
    }

    func testUnmountedVolumesStillGetNames() {
        XCTAssert(context.describe("/Volumes/Old Drive/Photos") == FolderInfo(name: "Photos", location: "/Volumes/Old Drive", place: .folder))
    }
}
