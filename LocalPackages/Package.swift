// swift-tools-version: 6.2
// SPDX-License-Identifier: AGPL-3.0-or-later

import PackageDescription

let package = Package(
    name: "ArcfinPackages",
    platforms: [
        .iOS(.v26),
        .tvOS(.v26),
        .macOS(.v15),
    ],
    products: [
        // MARK: Core Services
        .library(name: "Telemetry",       targets: ["Telemetry"]),
        // Shared ActivityAttributes for the download Live Activity — deliberately tiny
        // (Foundation + ActivityKit only) since it's linked into the widget extension too.
        .library(name: "LiveActivityKit", targets: ["LiveActivityKit"]),
        .library(name: "AuthCore",        targets: ["AuthCore"]),
        .library(name: "Persistence",     targets: ["Persistence"]),
        .library(name: "ImageCache",      targets: ["ImageCache"]),
        .library(name: "BackgroundKit",   targets: ["BackgroundKit"]),
        .library(name: "JellyfinAPI",     targets: ["JellyfinAPI"]),
        .library(name: "SeerrAPI",   targets: ["SeerrAPI"]),
        // MARK: Feature Packages
        .library(name: "AppState",        targets: ["AppState"]),
        .library(name: "MediaEngine",     targets: ["MediaEngine"]),
        .library(name: "SyncEngine",      targets: ["SyncEngine"]),
        .library(name: "SearchKit",       targets: ["SearchKit"]),
        .library(name: "CastKit",         targets: ["CastKit"]),
    ],
    dependencies: [
        // State management
        .package(
            url: "https://github.com/pointfreeco/swift-composable-architecture",
            from: "1.15.0"
        ),
        // Image caching
        .package(
            url: "https://github.com/kean/Nuke",
            from: "12.0.0"
        ),
        // OpenAPI — runtime + transport (generator plugin applied per-target when specs are ready)
        .package(
            url: "https://github.com/apple/swift-openapi-runtime",
            from: "1.3.0"
        ),
        .package(
            url: "https://github.com/apple/swift-openapi-urlsession",
            from: "1.0.0"
        ),
        // OpenAPI generator build-tool plugin (wire up per-target alongside openapi.yaml)
        .package(
            url: "https://github.com/apple/swift-openapi-generator",
            from: "1.3.0"
        ),
        // Primary player engine — FFmpeg demux + VideoToolbox hardware decode + a real
        // AVPlayer leg for Dolby Vision display-criteria switching and Atmos passthrough.
        // Auto mode prefers this; AVFoundation/VLC are the runtime fallback when it fails to
        // open a source. LGPL-3.0 with an App Store/DRM exception (same shape as SwiftVLC's
        // own LGPLv2.1 terms below).
        .package(
            url: "https://github.com/superuser404notfound/AetherEngine",
            from: "7.51.0"
        ),
        // Fallback player engine — libVLC (LGPLv2.1) via a Swift 6/@Observable wrapper, used
        // when AetherEngine itself fails to open a source. Still directly selectable in
        // Settings too.
        .package(
            url: "https://github.com/harflabs/SwiftVLC.git",
            from: "1.0.0"
        ),
        // Chromecast sender SDK — Google doesn't publish an SPM package itself, this is the
        // most actively maintained community SPM wrapper around Google's own XCFramework
        // release (not a reimplementation). iOS only; CastKit's dependency on it is
        // platform-conditioned so tvOS/macOS builds don't try to link it at all.
        .package(
            url: "https://github.com/SRGSSR/google-cast-sdk",
            from: "4.8.0"
        ),
        // In-app YouTube trailer playback fallback (when a title has no local trailer) —
        // a proper YouTube Terms of Service-compliant iframe player wrapper, replacing an
        // earlier hand-rolled WKWebView+HTML approach that kept hitting real embed errors
        // (origin/config validation YouTube's player does isn't something worth
        // reimplementing by hand when a maintained, MIT-licensed package already does it).
        .package(
            url: "https://github.com/SvenTiigi/YouTubePlayerKit.git",
            from: "2.0.0"
        ),
    ],
    targets: [

        // ── Core Services ──────────────────────────────────────────────────

        .target(
            name: "Telemetry",
            dependencies: []
        ),

        .target(
            name: "AuthCore",
            dependencies: ["Telemetry"]
        ),

        .target(
            name: "LiveActivityKit",
            dependencies: []
        ),

        .target(
            name: "Persistence",
            dependencies: ["Telemetry"]
        ),

        .target(
            name: "ImageCache",
            dependencies: [
                "AuthCore",
                "JellyfinAPI",
                "Telemetry",
                .product(name: "Nuke",   package: "Nuke"),
                .product(name: "NukeUI", package: "Nuke"),
            ]
        ),

        .target(
            name: "BackgroundKit",
            dependencies: ["Telemetry"]
        ),

        // API clients — manual stubs now; swap to OpenAPI-generated when specs land.
        // To enable generation: add the plugin + openapi.yaml + openapi-generator-config.yaml
        // to the target directory, then uncomment the plugins line below.
        .target(
            name: "JellyfinAPI",
            dependencies: [
                "AuthCore",
                "Telemetry",
                .product(name: "OpenAPIRuntime",    package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
            ]
            // plugins: [.plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")]
        ),

        .target(
            name: "SeerrAPI",
            dependencies: [
                "AuthCore",
                "Telemetry",
                .product(name: "OpenAPIRuntime",    package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
            ]
            // plugins: [.plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")]
        ),

        // ── Feature Packages ───────────────────────────────────────────────

        .target(
            name: "AppState",
            dependencies: [
                "JellyfinAPI",
                "SeerrAPI",
                "Persistence",
                "AuthCore",
                "Telemetry",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            ]
        ),

        .target(
            name: "MediaEngine",
            dependencies: [
                "AppState",
                "AuthCore",
                "JellyfinAPI",
                "Telemetry",
                .product(name: "AetherEngine", package: "AetherEngine"),
                .product(name: "SwiftVLC", package: "SwiftVLC"),
                // Not actually imported anywhere in this target — YouTubeTrailerPlayerView.swift
                // (the only real consumer) lives in the app target and already excludes tvOS
                // itself. Without this condition, SPM still builds YouTubePlayerKit for tvOS as
                // part of this target's own platform list, which fails: it depends on WebKit,
                // a framework that doesn't exist on tvOS at all.
                .product(name: "YouTubePlayerKit", package: "YouTubePlayerKit", condition: .when(platforms: [.iOS, .macOS])),
            ]
        ),

        .target(
            name: "SyncEngine",
            dependencies: [
                "AppState",
                "AuthCore",
                "JellyfinAPI",
                "Persistence",
                "Telemetry",
            ]
        ),

        .target(
            name: "SearchKit",
            dependencies: [
                "AppState",
                "JellyfinAPI",
                "Persistence",
                "Telemetry",
            ]
        ),

        .target(
            name: "CastKit",
            dependencies: [
                "JellyfinAPI",
                "Telemetry",
                .product(name: "GoogleCast", package: "google-cast-sdk", condition: .when(platforms: [.iOS])),
            ]
        ),

        // ── Tests ─────────────────────────────────────────────────────────

        .testTarget(name: "AppStateTests",    dependencies: ["AppState"]),
        .testTarget(name: "JellyfinAPITests", dependencies: ["JellyfinAPI"]),
        .testTarget(name: "AuthCoreTests",    dependencies: ["AuthCore"]),
        .testTarget(name: "PersistenceTests", dependencies: ["Persistence"]),
        .testTarget(name: "MediaEngineTests", dependencies: ["MediaEngine"]),
        .testTarget(name: "SearchKitTests",   dependencies: ["SearchKit"]),
        .testTarget(name: "SyncEngineTests",  dependencies: ["SyncEngine"]),
    ]
)
