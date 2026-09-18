// swift-tools-version: 6.2
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
        .library(name: "AuthCore",        targets: ["AuthCore"]),
        .library(name: "Persistence",     targets: ["Persistence"]),
        .library(name: "ImageCache",      targets: ["ImageCache"]),
        .library(name: "BackgroundKit",   targets: ["BackgroundKit"]),
        .library(name: "JellyfinAPI",     targets: ["JellyfinAPI"]),
        .library(name: "StreamystatsAPI", targets: ["StreamystatsAPI"]),
        .library(name: "SeerrAPI",   targets: ["SeerrAPI"]),
        // MARK: Feature Packages
        .library(name: "AppState",        targets: ["AppState"]),
        .library(name: "MediaEngine",     targets: ["MediaEngine"]),
        .library(name: "SyncEngine",      targets: ["SyncEngine"]),
        .library(name: "SearchKit",       targets: ["SearchKit"]),
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
            name: "Persistence",
            dependencies: ["Telemetry"]
        ),

        .target(
            name: "ImageCache",
            dependencies: [
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
            name: "StreamystatsAPI",
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
                "StreamystatsAPI",
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
                "JellyfinAPI",
                "Telemetry",
            ]
        ),

        .target(
            name: "SyncEngine",
            dependencies: [
                "AppState",
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

        // ── Tests ─────────────────────────────────────────────────────────

        .testTarget(name: "AppStateTests",    dependencies: ["AppState"]),
        .testTarget(name: "JellyfinAPITests", dependencies: ["JellyfinAPI"]),
        .testTarget(name: "AuthCoreTests",    dependencies: ["AuthCore"]),
        .testTarget(name: "PersistenceTests", dependencies: ["Persistence"]),
        .testTarget(name: "MediaEngineTests", dependencies: ["MediaEngine"]),
        .testTarget(name: "SearchKitTests",   dependencies: ["SearchKit"]),
    ]
)
