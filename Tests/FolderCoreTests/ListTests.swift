import XCTest
@testable import FolderCore

final class ListTests: XCTestCase {
    let home = Mac.home

    func build(finder: [String] = [], favorites: [String] = [], recents: [String] = [], checker: FakeChecker = Mac.checker) -> FolderList {
        FolderList.build(finder: finder, favorites: favorites, recents: recents, context: Mac.context, checker: checker)
    }

    func testSectionsInOrder() {
        let list = build(
            finder: [home + "/Documents/Thesis", home + "/Downloads"],
            favorites: [home + "/Documents/Lab Notes"],
            recents: [home + "/Desktop"]
        )
        XCTAssert(list.finder.map(\.path) == [home + "/Documents/Thesis", home + "/Downloads"])
        XCTAssert(list.favorites.map(\.path) == [home + "/Documents/Lab Notes"])
        XCTAssert(list.recents.map(\.path) == [home + "/Desktop"])
        XCTAssert(list.cycle == [home + "/Documents/Thesis", home + "/Downloads", home + "/Documents/Lab Notes", home + "/Desktop"])
        XCTAssert(list.finder.allSatisfy { $0.source == .finder })
        XCTAssert(!list.isEmpty)
        XCTAssert(build().isEmpty)
    }

    func testEachFolderOnce() {
        let thesis = home + "/Documents/Thesis"
        let list = build(finder: [thesis, thesis + "/", home + "/Downloads"], favorites: [thesis], recents: [thesis, home + "/Downloads", home + "/Desktop"])
        // The favorite stays with the favorites, marked as open in Finder.
        XCTAssert(list.finder.map(\.path) == [home + "/Downloads"])
        XCTAssert(list.favorites.map(\.path) == [thesis])
        XCTAssert(list.favorites[0].isOpenInFinder)
        XCTAssert(list.recents.map(\.path) == [home + "/Desktop"])
        XCTAssert(Set(list.cycle).count == list.cycle.count)
    }

    func testGoneFoldersAreLeftOutExceptFavorites() {
        let gone = home + "/Documents/Deleted"
        let list = build(finder: [gone], favorites: [gone, home + "/Documents"], recents: [gone])
        XCTAssert(list.finder.isEmpty)
        XCTAssert(list.recents.isEmpty)
        XCTAssert(list.favorites.map(\.availability) == [.missing, .ready])
        XCTAssert(list.cycle == [home + "/Documents"])
    }

    func testNetworkFoldersAreNeverChecked() {
        // Nothing on the share is in the checker, and it's still offered: looking could hang.
        let list = build(finder: ["/Volumes/lab-share/data"], favorites: ["/Volumes/lab-share"])
        XCTAssert(list.finder.map(\.availability) == [.network])
        XCTAssert(list.favorites.map(\.availability) == [.network])
        XCTAssert(list.cycle.count == 2)
    }

    func testUnpluggedDrivesAreDisconnected() {
        let list = build(finder: ["/Volumes/Old Drive/Photos"], favorites: ["/Volumes/Old Drive/Photos", "/Volumes/Field Drive/2026 Survey"])
        XCTAssert(list.finder.isEmpty)
        XCTAssert(list.favorites.map(\.availability) == [.disconnected, .ready])
        XCTAssert(Describe.availability(.disconnected) == "Not connected")
    }

    func testAvailabilityRules() {
        let context = Mac.context
        let checker = Mac.checker
        XCTAssert(FolderList.availability(of: home + "/Documents", context: context, checker: checker) == .ready)
        XCTAssert(FolderList.availability(of: home + "/Nowhere", context: context, checker: checker) == .missing)
        XCTAssert(FolderList.availability(of: home + "/.Trash", context: context, checker: checker) == .offLimits)
        XCTAssert(FolderList.availability(of: "/Applications/Inkpad.app/Contents", context: context, checker: checker) == .offLimits)
        XCTAssert(FolderList.availability(of: "/Volumes/lab-share/x", context: context, checker: checker) == .network)
        XCTAssert(FolderList.availability(of: "/Volumes/Gone", context: context, checker: checker) == .disconnected)
        XCTAssert(FolderList.availability(of: "/Volumes", context: context, checker: FakeChecker(folders: ["/Volumes"])) == .ready)
        // With no mount table at all, a local folder is still checked.
        let bare = PathContext(home: home, mounts: [])
        XCTAssert(FolderList.availability(of: home + "/Documents", context: bare, checker: checker) == .ready)
        XCTAssert(FolderList.availability(of: "/Volumes/Field Drive", context: bare, checker: checker) == .disconnected)
        XCTAssert(Availability.network.canJump && Availability.ready.canJump)
        XCTAssert(![Availability.missing, .disconnected, .offLimits].contains { $0.canJump })
    }

    func testLimitsPerSection() {
        let many = (0..<20).map { home + "/Documents/F\($0)" }
        let checker = FakeChecker(folders: Set(many))
        let list = build(finder: many, recents: many.reversed(), checker: checker)
        XCTAssert(list.finder.count == FolderList.finderLimit)
        XCTAssert(list.recents.count == FolderList.recentLimit)
        XCTAssert(Set(list.finder.map(\.path)).isDisjoint(with: list.recents.map(\.path)))
    }

    func testBadPathsAreDropped() {
        let list = build(finder: ["relative", "/bad\npath", home + "/Documents"], favorites: [""], recents: ["~/Desktop"])
        XCTAssert(list.all.map(\.path) == [home + "/Documents"])
    }

    func testFindsEntries() {
        let list = build(finder: [home + "/Downloads"])
        XCTAssert(list.entry(home + "/Downloads")?.info.place == .downloads)
        XCTAssert(list.entry("/nope") == nil)
    }
}

final class CyclerTests: XCTestCase {
    let folders = ["/a", "/b", "/c"]

    func testStepsAndWraps() {
        var cycler = Cycler()
        XCTAssert(cycler.next(in: folders) == "/a")
        XCTAssert(cycler.next(in: folders) == "/b")
        XCTAssert(cycler.next(in: folders) == "/c")
        XCTAssert(cycler.next(in: folders) == "/a")
    }

    func testGoesBack() {
        var cycler = Cycler()
        XCTAssert(cycler.next(in: folders, backwards: true) == "/c")
        XCTAssert(cycler.next(in: folders, backwards: true) == "/b")
        XCTAssert(cycler.next(in: folders) == "/c")
    }

    func testCarriesOnFromAClick() {
        var cycler = Cycler()
        cycler.picked("/b")
        XCTAssert(cycler.next(in: folders) == "/c")
    }

    func testStartsOverWhenTheListChanges() {
        var cycler = Cycler(current: "/gone")
        XCTAssert(cycler.next(in: folders) == "/a")
        cycler.reset()
        XCTAssert(cycler.current == nil)
        XCTAssert(cycler.next(in: []) == nil)
        XCTAssert(cycler.next(in: ["/only"]) == "/only")
        XCTAssert(cycler.next(in: ["/only"]) == "/only")
    }
}
