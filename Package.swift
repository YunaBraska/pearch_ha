// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PerchHA",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "PerchHA", targets: ["PerchHAApp"]),
        .executable(name: "hamirror", targets: ["hamirror"]),
        .executable(name: "perchha-smoke", targets: ["perchha-smoke"]),
        .library(name: "PerchHACore", targets: ["PerchHACore"]),
        .library(name: "PerchHAClient", targets: ["PerchHAClient"]),
        .library(name: "PerchHAPersistence", targets: ["PerchHAPersistence"]),
        .library(name: "PerchHAAppShell", targets: ["PerchHAAppShell"]),
        .library(name: "PerchHAPackaging", targets: ["PerchHAPackaging"]),
        .library(name: "PerchHASupport", targets: ["PerchHASupport"]),
        .library(name: "PerchHAUI", targets: ["PerchHAUI"]),
        .library(name: "FakeHA", targets: ["FakeHA"]),
        .executable(name: "perchha-package-app", targets: ["perchha-package-app"])
    ],
    targets: [
        .executableTarget(
            name: "PerchHAApp",
            dependencies: [
                "PerchHAAppShell"
            ]
        ),
        .target(
            name: "PerchHAAppShell",
            dependencies: [
                "PerchHACore",
                "PerchHAClient",
                "PerchHAPersistence",
                "PerchHAUI"
            ]
        ),
        .target(
            name: "PerchHACore",
            dependencies: ["PerchHASupport"]
        ),
        .target(
            name: "PerchHAClient",
            dependencies: [
                "PerchHACore",
                "PerchHASupport"
            ]
        ),
        .target(
            name: "PerchHAPersistence",
            dependencies: [
                "PerchHACore",
                "PerchHASupport"
            ]
        ),
        .target(
            name: "PerchHAPackaging"
        ),
        .target(
            name: "PerchHASupport"
        ),
        .target(
            name: "PerchHAUI",
            dependencies: ["PerchHACore"]
        ),
        .executableTarget(
            name: "hamirror",
            dependencies: [
                "FakeHA",
                "PerchHAClient"
            ],
            path: "Tools/hamirror"
        ),
        .executableTarget(
            name: "perchha-smoke",
            dependencies: [
                "PerchHACore",
                "PerchHAClient",
                "PerchHAAppShell",
                "PerchHAPackaging",
                "FakeHA",
                "PerchHAPersistence",
                "PerchHASupport",
                "PerchHAUI"
            ],
            path: "Tools/perchha-smoke"
        ),
        .executableTarget(
            name: "perchha-package-app",
            dependencies: [
                "PerchHAPackaging"
            ],
            path: "Tools/perchha-package-app"
        ),
        .target(
            name: "FakeHA",
            dependencies: ["PerchHASupport"],
            path: "Tests/FakeHA",
            exclude: ["README.md"]
        ),
        .testTarget(
            name: "PerchHACoreTests",
            dependencies: ["PerchHACore"]
        ),
        .testTarget(
            name: "PerchHAClientTests",
            dependencies: [
                "FakeHA",
                "PerchHACore",
                "PerchHAClient"
            ]
        ),
        .testTarget(
            name: "PerchHAPersistenceTests",
            dependencies: ["PerchHAPersistence"]
        ),
        .testTarget(
            name: "PerchHAPackagingTests",
            dependencies: ["PerchHAPackaging"]
        ),
        .testTarget(
            name: "PerchHASupportTests",
            dependencies: ["PerchHASupport"]
        ),
        .testTarget(
            name: "PerchHAUITests",
            dependencies: [
                "FakeHA",
                "PerchHAClient",
                "PerchHAAppShell",
                "PerchHAPersistence",
                "PerchHAUI"
            ]
        ),
        .testTarget(
            name: "FakeHATests",
            dependencies: ["FakeHA"]
        )
    ]
)
