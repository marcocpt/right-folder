import Foundation
import XCTest
@testable import FolderCore

final class RecentTests: XCTestCase {
    func testNewestFirstAndOnce() {
        var recents = RecentFolders()
        recents.add("/a")
        recents.add("/b")
        recents.add("/a/")
        XCTAssert(recents.paths == ["/a", "/b"])
    }

    func testKeepsOnlyTheLatest() {
        var recents = RecentFolders()
        for index in 0..<30 { recents.add("/folder\(index)") }
        XCTAssert(recents.paths.count == RecentFolders.limit)
        XCTAssert(recents.paths.first == "/folder29")
        XCTAssert(recents.paths.last == "/folder18")
    }

    func testIgnoresUnusablePaths() {
        var recents = RecentFolders()
        recents.add("relative")
        recents.add("/bad\npath")
        recents.add("")
        XCTAssert(recents.paths.isEmpty)
    }

    func testRemoveAndClear() {
        var recents = RecentFolders(paths: ["/a", "/b", "/c"])
        recents.remove("/b")
        XCTAssert(recents.paths == ["/a", "/c"])
        recents.clear()
        XCTAssert(recents.paths.isEmpty)
    }

    func testSavedListsAreCleanedOnLoad() throws {
        let json = #"{"paths": ["/a", "/a", "relative", "/b\n", "/c/", "/d"]}"#
        let recents = try JSONDecoder().decode(RecentFolders.self, from: Data(json.utf8))
        XCTAssert(recents.paths == ["/a", "/c", "/d"])
        let damaged = try JSONDecoder().decode(RecentFolders.self, from: Data(#"{"paths": 7}"#.utf8))
        XCTAssert(damaged.paths.isEmpty)
        let initialized = RecentFolders(paths: (0..<20).map { "/f\($0)" })
        XCTAssert(initialized.paths.first == "/f0" && initialized.paths.count == RecentFolders.limit)
    }

    func testRoundTrips() throws {
        let recents = RecentFolders(paths: ["/Users/robin/Documents", "/Volumes/Field Drive"])
        let data = try JSONEncoder().encode(recents)
        XCTAssert(try JSONDecoder().decode(RecentFolders.self, from: data) == recents)
    }
}

final class FavoriteTests: XCTestCase {
    func testAddsOnceInOrder() {
        var favorites = Favorites()
        let added = [
            favorites.add(Favorite(path: "/b")), favorites.add(Favorite(path: "/a/")),
            favorites.add(Favorite(path: "/a")), favorites.add(Favorite(path: "not/absolute")),
        ]
        XCTAssert(added == [true, true, false, false])
        XCTAssert(favorites.paths == ["/b", "/a"])
    }

    func testHasALimit() {
        var favorites = Favorites()
        for index in 0..<Favorites.limit { favorites.add(Favorite(path: "/f\(index)")) }
        let added = favorites.add(Favorite(path: "/one-more"))
        XCTAssert(!added)
        XCTAssert(favorites.items.count == Favorites.limit)
    }

    func testMovesAndRemoves() {
        var favorites = Favorites(items: ["/a", "/b", "/c"].map { Favorite(path: $0) })
        favorites.move("/c", by: -1)
        XCTAssert(favorites.paths == ["/a", "/c", "/b"])
        favorites.move("/a", by: -5)
        XCTAssert(favorites.paths == ["/a", "/c", "/b"])
        favorites.move("/a", by: 10)
        XCTAssert(favorites.paths == ["/c", "/b", "/a"])
        favorites.move("/missing", by: 1)
        favorites.remove("/b")
        XCTAssert(favorites.paths == ["/c", "/a"])
    }

    func testFollowsRenamedFolders() {
        var favorites = Favorites(items: [Favorite(path: "/Users/robin/Thesis", bookmark: Data([1])), Favorite(path: "/Users/robin/Notes", bookmark: Data([2]))])
        let changed = favorites.follow { item in
            item.bookmark == Data([1]) ? ("/Users/robin/Documents/Thesis (final)", Data([9])) : (item.path, nil)
        }
        XCTAssert(changed)
        XCTAssert(favorites.paths == ["/Users/robin/Documents/Thesis (final)", "/Users/robin/Notes"])
        XCTAssert(favorites.items[0].bookmark == Data([9]))
        XCTAssert(favorites.items[1].bookmark == Data([2]))
        // Nothing moved: nothing changes.
        let again = favorites.follow { ($0.path, nil) }
        XCTAssert(!again)
    }

    func testAMoveOntoAnotherFavoriteDropsTheDuplicate() {
        var favorites = Favorites(items: [Favorite(path: "/a", bookmark: Data([1])), Favorite(path: "/b", bookmark: Data([2]))])
        let changed = favorites.follow { $0.path == "/b" ? ("/a", nil) : nil }
        XCTAssert(changed)
        XCTAssert(favorites.paths == ["/a"])
    }

    func testUnresolvedBookmarksKeepTheirPath() {
        var favorites = Favorites(items: [Favorite(path: "/Volumes/Old Drive/Photos", bookmark: Data([3]))])
        let unresolved = favorites.follow { _ in nil }
        XCTAssert(!unresolved)
        XCTAssert(favorites.paths == ["/Volumes/Old Drive/Photos"])
        // A bookmark that resolves somewhere unusable is ignored too.
        let unusable = favorites.follow { _ in ("relative/path", nil) }
        XCTAssert(!unusable)
    }

    func testSavedListsSurviveDamage() throws {
        let json = #"{"items": [{"path": "/a"}, {"nope": 1}, {"path": "/a"}, {"path": "relative"}, {"path": "/b", "bookmark": "AQI="}]}"#
        let favorites = try JSONDecoder().decode(Favorites.self, from: Data(json.utf8))
        XCTAssert(favorites.paths == ["/a", "/b"])
        XCTAssert(favorites.items[1].bookmark == Data([1, 2]))
        XCTAssert(try JSONDecoder().decode(Favorites.self, from: Data("{}".utf8)).items.isEmpty)
    }

    func testRoundTrips() throws {
        let favorites = Favorites(items: [Favorite(path: "/a", bookmark: Data([1, 2, 3])), Favorite(path: "/b")])
        let data = try JSONEncoder().encode(favorites)
        XCTAssert(try JSONDecoder().decode(Favorites.self, from: data) == favorites)
    }
}
