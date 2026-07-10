// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PerchHA",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "PearchHA", targets: ["PerchHAApp"]),
        .executable(name: "PerchHA", targets: ["PerchHAApp"]),
        .executable(name: "hamirror", targets: ["hamirror"]),
        .executable(name: "perchha-smoke", targets: ["perchha-smoke"]),
        .executable(name: "perchha-coverage-check", targets: ["perchha-coverage-check"]),
        .executable(name: "perchha-repo-audit", targets: ["perchha-repo-audit"]),
        .executable(name: "perchha-xcode-doctor", targets: ["perchha-xcode-doctor"]),
        .library(name: "PerchHACore", targets: ["PerchHACore"]),
        .library(name: "PerchHAClient", targets: ["PerchHAClient"]),
        .library(name: "PerchHAPersistence", targets: ["PerchHAPersistence"]),
        .library(name: "PerchHAAppShell", targets: ["PerchHAAppShell"]),
        .library(name: "PerchHAPackaging", targets: ["PerchHAPackaging"]),
        .library(name: "PerchHASupport", targets: ["PerchHASupport"]),
        .library(name: "PerchHAUI", targets: ["PerchHAUI"]),
        .library(name: "PerchHACoverageCheck", targets: ["PerchHACoverageCheck"]),
        .library(name: "PerchHARepoAudit", targets: ["PerchHARepoAudit"]),
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
            ],
            resources: [
                .copy("Resources/PearchHA.icns")
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
            name: "PerchHAPackaging",
            dependencies: ["PerchHASupport"]
        ),
        .target(
            name: "PerchHASupport"
        ),
        .target(
            name: "PerchHAUI",
            dependencies: ["PerchHACore"]
        ),
        .target(
            name: "PerchHACoverageCheck",
            dependencies: ["PerchHASupport"]
        ),
        .target(
            name: "PerchHATestSupport"
        ),
        .target(
            name: "PerchHARepoAudit",
            dependencies: ["PerchHASupport"]
        ),
        .executableTarget(
            name: "hamirror",
            dependencies: [
                "FakeHA",
                "PerchHAClient",
                "PerchHASupport"
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
                "PerchHAUI",
                "PerchHACoverageCheck",
                "PerchHARepoAudit"
            ],
            path: "Tools/perchha-smoke"
        ),
        .executableTarget(
            name: "perchha-coverage-check",
            dependencies: ["PerchHACoverageCheck"],
            path: "Tools/perchha-coverage-check"
        ),
        .executableTarget(
            name: "perchha-repo-audit",
            dependencies: ["PerchHARepoAudit"],
            path: "Tools/perchha-repo-audit"
        ),
        .executableTarget(
            name: "perchha-xcode-doctor",
            dependencies: ["PerchHAPackaging"],
            path: "Tools/perchha-xcode-doctor"
        ),
        .executableTarget(
            name: "perchha-package-app",
            dependencies: [
                "PerchHAClient",
                "PerchHAPackaging",
                "PerchHASupport"
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
                "PerchHAClient",
                "PerchHATestSupport"
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
            dependencies: [
                "PerchHASupport",
                "PerchHATestSupport"
            ]
        ),
        .testTarget(
            name: "PerchHAUITests",
            dependencies: [
                "FakeHA",
                "PerchHAClient",
                "PerchHAAppShell",
                "PerchHAPersistence",
                "PerchHAUI",
                "PerchHATestSupport"
            ]
        ),
        .testTarget(
            name: "PerchHACoverageCheckTests",
            dependencies: ["PerchHACoverageCheck"]
        ),
        .testTarget(
            name: "PerchHARepoAuditTests",
            dependencies: ["PerchHARepoAudit"]
        ),
        .testTarget(
            name: "FakeHATests",
            dependencies: ["FakeHA"]
        )
    ]
)
