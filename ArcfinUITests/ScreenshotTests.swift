// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

/// Captures the main screens for a release's screenshots. testflight.yml runs it after each
/// upload and attaches the result to the release. It signs in to Jellyfin's public demo
/// server and opens the first item it finds, since the demo library changes; if the server
/// can't be reached, every test skips.
///
/// Each screen is its own test with a fresh launch, so one that can't be reached doesn't
/// stop the rest. UI tests need XCTest: Swift Testing can't drive an app.
final class ScreenshotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        #if os(iOS)
        // The player test turns the device; the next screen shouldn't inherit that.
        XCUIDevice.shared.orientation = .portrait
        #endif
        app = XCUIApplication()
        app.launchArguments += [
            "-ArcfinScreenshotDemo",
            "-arcfin.introduction.onboardingSeen", "99",
            "-arcfin.introduction.whatsNewSeen", "99",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
            "-bottomNavActive", "home,browse,stats",
            "-libraryScreensaverEnabled", "NO",
        ]
        #if os(macOS)
        // Only this app: the system appearance belongs to whoever's Mac this runs on.
        app.launchArguments += ["-AppleInterfaceStyle", "Dark"]
        #endif
        app.launch()
        guard shelfItem("recentlyAddedMovies").waitForExistence(timeout: 60) else {
            throw XCTSkip("The demo server didn't load")
        }
    }

    // MARK: - Screens

    @MainActor
    func test01Home() throws {
        #if os(tvOS)
        // Focus can start on a lower shelf; Home reads best from the top.
        let first = shelfItem("continueWatching")
        for _ in 0..<12 where first.exists && !first.hasFocus {
            XCUIRemote.shared.press(.up)
        }
        for _ in 0..<10 where first.exists && !first.hasFocus {
            XCUIRemote.shared.press(.left)
        }
        #endif
        settle(seconds: 8)
        capture("01-home")
    }

    @MainActor
    func test02Movie() throws {
        try openShelfItem("recentlyAddedMovies")
        try waitFor(app.buttons["detail.play"])
        settle()
        capture("02-movie")
    }

    @MainActor
    func test03Series() throws {
        try openLibrary("Shows")
        let show = app.descendants(matching: .any)["library.grid"].buttons.firstMatch
        try waitFor(show)
        press(show)
        try waitFor(app.buttons["detail.play"])
        settle(seconds: 4)
        capture("03-series")
    }

    @MainActor
    func test04Player() throws {
        try openShelfItem("recentlyAddedMovies")
        let play = app.buttons["detail.play"]
        try waitFor(play)
        #if os(iOS)
        // iPad stays upright: its screen captures don't follow a rotation.
        if UIDevice.current.userInterfaceIdiom == .phone {
            XCUIDevice.shared.orientation = .landscapeLeft
        }
        #endif
        press(play)
        sleep(12)
        showPlayerControls()
        capture("04-player")
        openPlayerMenu()
        capture("05-player-menu")
    }

    @MainActor
    func test06Library() throws {
        try openLibrary("Movies")
        try waitFor(app.descendants(matching: .any)["library.grid"].buttons.firstMatch)
        settle()
        capture("06-library")
    }

    @MainActor
    func test07Search() throws {
        #if os(tvOS)
        try selectTab("Search")
        let field = app.searchFields.firstMatch
        try waitFor(field)
        XCUIRemote.shared.press(.down)
        field.typeText("night")
        #else
        try selectTab("Browse")
        let field = app.searchFields.firstMatch
        #if os(iOS)
        if !field.waitForExistence(timeout: 3) {
            app.swipeDown()
        }
        #endif
        try waitFor(field)
        field.tap()
        // Return dismisses the keyboard, which would cover the results.
        field.typeText("night\n")
        #endif
        settle(seconds: 4)
        capture("07-search")
    }

    #if !os(tvOS)
    @MainActor
    func test08Downloads() throws {
        #if os(macOS)
        try chooseFromGoMenu("Downloads")
        #else
        try selectTab("Browse")
        let downloads = button(startingWith: "Downloads")
        try waitFor(downloads)
        press(downloads)
        #endif
        settle()
        capture("08-downloads")
    }
    #endif

    @MainActor
    func test09Stats() throws {
        try selectTab("Stats")
        settle(seconds: 6)
        capture("09-stats")
    }

    @MainActor
    func test10Settings() throws {
        #if os(tvOS)
        try selectTab("Settings")
        #else
        let settings = app.buttons["Settings"].firstMatch
        try waitFor(settings)
        press(settings)
        #endif
        settle()
        capture("10-settings")
    }

    // MARK: - Navigation

    private func shelfItem(_ shelf: String) -> XCUIElement {
        app.descendants(matching: .any)["shelf.\(shelf)"].scrollViews.firstMatch.buttons.firstMatch
    }

    private func openShelfItem(_ shelf: String) throws {
        let item = shelfItem(shelf)
        try waitFor(item)
        press(item)
        settle()
    }

    private func openLibrary(_ name: String) throws {
        #if os(tvOS)
        try selectTab("Library")
        #else
        try selectTab("Browse")
        #endif
        let library = app.buttons[name].firstMatch
        try waitFor(library)
        press(library)
        settle()
    }

    private func selectTab(_ title: String) throws {
        #if os(tvOS)
        // The tab bar only takes focus once focus moves up past the top of the page. Its
        // buttons exist in the tree even while it's hidden, so wait for focus, not existence.
        let tab = app.tabBars.buttons[title].firstMatch
        let focusedTab = app.tabBars.buttons.matching(NSPredicate(format: "hasFocus == true")).firstMatch
        for _ in 0..<15 where !focusedTab.exists {
            XCUIRemote.shared.press(.up)
        }
        try waitFor(focusedTab, timeout: 5)
        for direction in [XCUIRemote.Button.right, .left] {
            for _ in 0..<8 where !tab.hasFocus {
                XCUIRemote.shared.press(direction)
            }
        }
        XCUIRemote.shared.press(.select)
        #elseif os(macOS)
        // Clicking a sidebar row's text doesn't select it; the Go menu has every tab.
        try chooseFromGoMenu(title)
        #else
        let tab = app.buttons[title].firstMatch
        try waitFor(tab)
        tab.tap()
        #endif
        settle()
    }

    #if os(macOS)
    private func chooseFromGoMenu(_ title: String) throws {
        app.menuBars.menuBarItems["Go"].click()
        let item = app.menuBars.menuItems[title].firstMatch
        try waitFor(item, timeout: 5)
        item.click()
    }
    #endif

    private func button(startingWith prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    private func press(_ element: XCUIElement) {
        #if os(tvOS)
        focus(element)
        XCUIRemote.shared.press(.select)
        #elseif os(macOS)
        // Poster buttons inside a shelf don't report a hit point, so click their centre.
        scrollIntoView(element)
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        #else
        element.tap()
        #endif
    }

    #if os(macOS)
    /// A click doesn't scroll to its target the way a tap does on iPhone. If a scroll moves
    /// the target the wrong way, the direction flips.
    private func scrollIntoView(_ element: XCUIElement) {
        let window = app.windows.firstMatch
        var sign: CGFloat = -1
        for _ in 0..<20 {
            let frame = element.frame, visible = window.frame
            let below = frame.maxY > visible.maxY
            guard below || frame.minY < visible.minY + 60 else { return }
            window.scroll(byDeltaX: 0, deltaY: (below ? sign : -sign) * 400)
            let moved = element.frame.minY - frame.minY
            if below ? moved > 0 : moved < 0 { sign = -sign }
        }
    }
    #endif

    #if os(tvOS)
    /// Moves focus with the remote until it reaches `element`: down, then right, up and left.
    private func focus(_ element: XCUIElement) {
        for direction in [XCUIRemote.Button.down, .right, .up, .left] {
            for _ in 0..<12 where !element.hasFocus {
                XCUIRemote.shared.press(direction)
            }
            if element.hasFocus { return }
        }
    }
    #endif

    private func showPlayerControls() {
        #if os(tvOS)
        XCUIRemote.shared.press(.select)
        #elseif os(macOS)
        app.windows.firstMatch.hover()
        #else
        app.windows.firstMatch.tap()
        #endif
        sleep(1)
    }

    private func openPlayerMenu() {
        #if os(tvOS)
        // Down opens subtitles and audio once the controls have hidden again.
        sleep(8)
        XCUIRemote.shared.press(.down)
        #else
        let tracks = app.buttons["captions.bubble"].firstMatch
        if tracks.exists {
            tracks.tap()
        } else {
            app.buttons["More options"].firstMatch.tap()
            app.buttons["Subtitles & Audio"].firstMatch.tap()
        }
        #endif
        sleep(2)
    }

    // MARK: - Capture

    private func waitFor(_ element: XCUIElement, timeout: TimeInterval = 30) throws {
        guard !element.waitForExistence(timeout: timeout) else { return }
        attachTree("missing")
        XCTFail("Not found: \(element)")
    }

    /// Posters and backdrops load after the screen appears.
    private func settle(seconds: UInt32 = 3) {
        sleep(seconds)
    }

    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "\(Self.device)-\(name)"
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func attachTree(_ name: String) {
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "tree-\(name)"
        tree.lifetime = .keepAlways
        add(tree)
    }

    private static var device: String {
        #if os(macOS)
        "Mac"
        #elseif os(tvOS)
        "AppleTV"
        #else
        UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #endif
    }
}
