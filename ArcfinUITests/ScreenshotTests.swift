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
    /// Set when the test turns the device, whose screen captures then need turning back.
    private var turned = false

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
        try openMovie()
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
        try openFeatureFilm()
        let play = app.buttons["detail.play"]
        try waitFor(play)
        press(play)
        #if os(iOS)
        // Turned only once the player is up: a tap just after a turn lands where the button
        // used to be. iPad stays upright.
        if UIDevice.current.userInterfaceIdiom == .phone {
            XCUIDevice.shared.orientation = .landscapeLeft
            turned = true
        }
        #endif
        // The demo server transcodes, so the picture can take a while to start.
        sleep(20)
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
        #elseif os(macOS)
        try selectTab("Browse")
        try waitFor(app.searchFields.firstMatch)
        // Clicking the toolbar field doesn't give it keyboard focus; Edit › Find… does.
        app.typeKey("f", modifierFlags: .command)
        sleep(1)
        app.typeText("night\n")
        #else
        try selectTab("Browse")
        let field = app.searchFields.firstMatch
        if !field.waitForExistence(timeout: 3) {
            app.swipeDown()
        }
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
        try openSettings()
        capture("10-settings")
    }

    @MainActor
    func test11Profiles() throws {
        try openSettings()
        let profile = app.buttons["settings.profile"].firstMatch
        try waitFor(profile)
        press(profile)
        settle()
        capture("11-profiles")
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

    private func openMovie() throws {
        #if os(macOS)
        // Home's shelves come in a different order each launch, and a test can't scroll the
        // Mac's Home page down to one, so the Mac opens the first movie in the library.
        try openLibrary("Movies")
        let movie = app.descendants(matching: .any)["library.grid"].buttons.firstMatch
        try waitFor(movie)
        press(movie)
        settle()
        #else
        try openShelfItem("recentlyAddedMovies")
        #endif
    }

    /// The demo's short films are over before the player is captured, so the player opens
    /// one of its feature films when there is one.
    private func openFeatureFilm() throws {
        try openLibrary("Movies")
        let grid = app.descendants(matching: .any)["library.grid"]
        try waitFor(grid.buttons.firstMatch)
        let film = ["Night of the Living Dead", "Dracula", "King Lear", "Sahara"]
            .lazy
            .map { grid.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", $0)).firstMatch }
            .first { $0.exists } ?? grid.buttons.firstMatch
        press(film)
        settle()
    }

    private func openSettings() throws {
        #if os(tvOS)
        try selectTab("Settings")
        #else
        let settings = app.buttons["Settings"].firstMatch
        try waitFor(settings)
        press(settings)
        #endif
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
        // Home's hidden hero takes a press, and a moment, to come back, so the presses are
        // spaced out.
        let tab = app.tabBars.buttons[title].firstMatch
        let focusedTab = app.tabBars.buttons.matching(NSPredicate(format: "hasFocus == true")).firstMatch
        for _ in 0..<20 where !focusedTab.exists {
            XCUIRemote.shared.press(.up)
            Thread.sleep(forTimeInterval: 0.4)
        }
        try waitFor(focusedTab, timeout: 5)
        for direction in [XCUIRemote.Button.right, .left] {
            for _ in 0..<8 where !tab.hasFocus {
                XCUIRemote.shared.press(direction)
                Thread.sleep(forTimeInterval: 0.3)
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
        // Poster buttons don't report a hit point on the Mac, so click their centre.
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        #else
        element.tap()
        #endif
    }

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
        let tracks = app.buttons["Subtitles and audio"].firstMatch
        if !tracks.exists {
            showPlayerControls()
        }
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
        #if os(macOS)
        // Only the window: the rest of the screen is the menu bar and desktop of whoever's Mac
        // this runs on.
        let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        #elseif os(iOS)
        let shot = XCTAttachment(image: upright(XCUIScreen.main.screenshot().image))
        #else
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        #endif
        shot.name = "\(Self.device)-\(name)"
        shot.lifetime = .keepAlways
        add(shot)
    }

    #if os(iOS)
    /// After the device turns, the screen capture is still the portrait image, marked as
    /// rotated. PNG export drops that mark, so the turn is drawn into the pixels here.
    private func upright(_ image: UIImage) -> UIImage {
        guard turned else { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        if image.size.width > image.size.height {
            return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in image.draw(at: .zero) }
        }
        let size = CGSize(width: image.size.height, height: image.size.width)
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            // A quarter turn anticlockwise, which undoes .landscapeLeft.
            context.cgContext.translateBy(x: 0, y: size.height)
            context.cgContext.rotate(by: -.pi / 2)
            image.draw(at: .zero)
        }
    }
    #endif

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
