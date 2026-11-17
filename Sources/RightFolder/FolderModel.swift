import Foundation
import FolderCore
import Combine

/// What the panel, the menu and the window show, and what clicking a folder does. A dialog only
/// ever moves when you click a folder or press the shortcut.
@MainActor
final class FolderModel: ObservableObject {
    /// The dialog that's open, as the panel describes it. `id` changes whenever a different
    /// dialog opens, even one that looks the same, like the next Save sheet in the same app.
    struct Dialog: Equatable {
        var kind: DialogKind
        var appName: String
        var bundleID: String?
        var id = 0
    }

    let preferences: Preferences
    let finder: any FinderSource
    let system: any FolderSystem
    var isTrusted: () -> Bool
    /// Carries out a jump on the dialog that's open. Tests record jumps instead.
    var jumper: (String) async -> JumpResult = { _ in .failed(.dialogGone) }
    private var cycler = Cycler()
    /// Counts dialogs, so a jump that finishes after its dialog closed can't touch the next one.
    private var generation = 0
    /// The folders open in Finder when it last looked.
    private var finderFolders: [String] = []

    @Published private(set) var trusted = false
    @Published private(set) var dialog: Dialog?
    @Published private(set) var list = FolderList()
    @Published private(set) var favorites: Favorites
    @Published private(set) var recents: RecentFolders
    /// The folder a jump is on its way to.
    @Published private(set) var jumping: String?
    /// What went wrong with the last jump, shown in the panel until the next one.
    @Published private(set) var message: String?
    @Published private(set) var paused: Bool
    @Published private(set) var remembersRecents: Bool
    @Published private(set) var excludedApps: Set<String>

    init(preferences: Preferences = Preferences(), finder: any FinderSource = FinderWindows(), system: any FolderSystem = LiveFolderSystem(), isTrusted: @escaping () -> Bool) {
        self.preferences = preferences
        self.finder = finder
        self.system = system
        self.isTrusted = isTrusted
        favorites = preferences.favorites
        recents = preferences.recents
        paused = preferences.paused
        remembersRecents = preferences.remembersRecents
        excludedApps = preferences.excludedApps
        refresh()
    }

    var status: Describe.Status {
        if !trusted { return .needsAccessibility }
        if paused { return .paused }
        guard let dialog else { return .waiting }
        if let id = dialog.bundleID, excludedApps.contains(id) { return .offInApp(dialog.appName) }
        return .showing(dialog.kind, app: dialog.appName)
    }

    /// Whether the panel should be beside the dialog that's open.
    var showsPanel: Bool {
        guard trusted, !paused, let dialog else { return false }
        return Dialogs.shouldOffer(appBundleID: dialog.bundleID, ownBundleID: Bundle.main.bundleIdentifier, excluded: excludedApps)
    }

    /// The folder in the front Finder window, for pinning from the menu.
    var frontFinderFolder: String? {
        guard trusted else { return nil }
        return finderFolders.first.flatMap(Paths.normalize)
    }

    /// Looks again at Finder's windows, the folders' availability and where favorites have moved.
    func refresh() {
        trusted = isTrusted()
        var favorites = self.favorites
        if favorites.follow({ system.resolve($0) }) {
            self.favorites = favorites
            preferences.favorites = favorites
        }
        finderFolders = trusted ? finder.folders() : []
        list = FolderList.build(
            finder: finderFolders, favorites: favorites.paths, recents: recents.paths,
            context: system.context(), checker: system.checker
        )
    }

    // MARK: Dialogs

    func dialogOpened(_ dialog: Dialog) {
        guard dialog != self.dialog else { return }
        self.dialog = dialog
        generation += 1
        cycler.reset()
        message = nil
        refresh()
        // The front Finder window's folder is remembered, so it's still offered after the window closes.
        if showsPanel, remembersRecents, let front = list.finder.first?.path {
            recents.add(front)
            preferences.recents = recents
        }
    }

    func dialogClosed() {
        dialog = nil
        generation += 1
        message = nil
        cycler.reset()
    }

    // MARK: Jumping

    func jump(to path: String) async {
        guard showsPanel, jumping == nil else { return }
        guard let entry = list.entry(path), entry.availability.canJump else {
            message = GoTo.Failure.unavailable.message
            return
        }
        jumping = path
        message = nil
        cycler.picked(path)
        let started = generation
        let result = await jumper(path)
        // `jumping` stays set until the jump is over, even if its dialog closed meanwhile, so two
        // jumps never send keys at the same time.
        jumping = nil
        guard generation == started else { return }
        switch result {
        case .done:
            if remembersRecents {
                recents.add(path)
                preferences.recents = recents
            }
        case let .failed(failure):
            message = failure.message
        }
        refresh()
    }

    /// The shortcut: on to the next folder, or back with Shift.
    func step(backwards: Bool) async {
        guard showsPanel, jumping == nil, let path = cycler.next(in: list.cycle, backwards: backwards) else { return }
        await jump(to: path)
    }

    // MARK: Favorites and recents

    func pin(_ path: String) {
        guard favorites.add(Favorite(path: path, bookmark: system.bookmark(for: path))) else { return }
        preferences.favorites = favorites
        refresh()
    }

    func unpin(_ path: String) {
        favorites.remove(path)
        preferences.favorites = favorites
        refresh()
    }

    func move(_ path: String, by offset: Int) {
        favorites.move(path, by: offset)
        preferences.favorites = favorites
        refresh()
    }

    func forget(_ path: String) {
        recents.remove(path)
        preferences.recents = recents
        refresh()
    }

    func clearRecents() {
        recents.clear()
        preferences.recents = recents
        refresh()
    }

    /// Turning it off clears the list too, so nothing is kept.
    func setRemembersRecents(_ on: Bool) {
        remembersRecents = on
        preferences.remembersRecents = on
        if !on { clearRecents() }
    }

    func setPaused(_ paused: Bool) {
        self.paused = paused
        preferences.paused = paused
    }

    // MARK: Apps

    func setExcluded(_ bundleID: String, _ excluded: Bool) {
        if excluded { excludedApps.insert(bundleID) } else { excludedApps.remove(bundleID) }
        preferences.excludedApps = excludedApps
    }
}
