// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PearchHA",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "PearchHA", targets: ["PearchHAApp"]),
        .executable(name: "hamirror", targets: ["hamirror"]),
        .executable(name: "pearchha-smoke", targets: ["pearchha-smoke"]),
        .executable(name: "pearchha-coverage-check", targets: ["pearchha-coverage-check"]),
        .executable(name: "pearchha-repo-audit", targets: ["pearchha-repo-audit"]),
        .executable(name: "pearchha-xcode-doctor", targets: ["pearchha-xcode-doctor"]),
        .library(name: "PearchHACore", targets: ["PearchHACore"]),
        .library(name: "PearchHAClient", targets: ["PearchHAClient"]),
        .library(name: "PearchHAPersistence", targets: ["PearchHAPersistence"]),
        .library(name: "PearchHAAppShell", targets: ["PearchHAAppShell"]),
        .library(name: "PearchHAPackaging", targets: ["PearchHAPackaging"]),
        .library(name: "PearchHASupport", targets: ["PearchHASupport"]),
        .library(name: "PearchHAUI", targets: ["PearchHAUI"]),
        .library(name: "PearchHACoverageCheck", targets: ["PearchHACoverageCheck"]),
        .library(name: "PearchHARepoAudit", targets: ["PearchHARepoAudit"]),
        .library(name: "FakeHA", targets: ["FakeHA"]),
        .executable(name: "pearchha-package-app", targets: ["pearchha-package-app"])
    ],
    targets: [
        .executableTarget(
            name: "PearchHAApp",
            dependencies: [
                "PearchHAAppShell"
            ]
        ),
        .target(
            name: "PearchHAAppShell",
            dependencies: [
                "PearchHACore",
                "PearchHAClient",
                "PearchHAPersistence",
                "PearchHAUI"
            ],
            resources: [
                .copy("Resources/PearchHA.icns")
            ]
        ),
        .target(
            name: "PearchHACore",
            dependencies: ["PearchHASupport"]
        ),
        .target(
            name: "PearchHAClient",
            dependencies: [
                "PearchHACore",
                "PearchHASupport"
            ]
        ),
        .target(
            name: "PearchHAPersistence",
            dependencies: [
                "PearchHACore",
                "PearchHASupport"
            ]
        ),
        .target(
            name: "PearchHAPackaging",
            dependencies: ["PearchHASupport"]
        ),
        .target(
            name: "PearchHASupport"
        ),
        .target(
            name: "PearchHAUI",
            dependencies: ["PearchHACore"]
        ),
        .target(
            name: "PearchHACoverageCheck",
            dependencies: ["PearchHASupport"]
        ),
        .target(
            name: "PearchHATestSupport"
        ),
        .target(
            name: "PearchHARepoAudit",
            dependencies: ["PearchHASupport"]
        ),
        .executableTarget(
            name: "hamirror",
            dependencies: [
                "FakeHA",
                "PearchHAClient",
                "PearchHASupport"
            ],
            path: "Tools/hamirror"
        ),
        .executableTarget(
            name: "pearchha-smoke",
            dependencies: [
                "PearchHACore",
                "PearchHAClient",
                "PearchHAAppShell",
                "PearchHAPackaging",
                "FakeHA",
                "PearchHAPersistence",
                "PearchHASupport",
                "PearchHAUI",
                "PearchHACoverageCheck",
                "PearchHARepoAudit"
            ],
            path: "Tools/pearchha-smoke"
        ),
        .executableTarget(
            name: "pearchha-coverage-check",
            dependencies: ["PearchHACoverageCheck"],
            path: "Tools/pearchha-coverage-check"
        ),
        .executableTarget(
            name: "pearchha-repo-audit",
            dependencies: ["PearchHARepoAudit"],
            path: "Tools/pearchha-repo-audit"
        ),
        .executableTarget(
            name: "pearchha-xcode-doctor",
            dependencies: ["PearchHAPackaging"],
            path: "Tools/pearchha-xcode-doctor"
        ),
        .executableTarget(
            name: "pearchha-package-app",
            dependencies: [
                "PearchHAClient",
                "PearchHAPackaging",
                "PearchHASupport"
            ],
            path: "Tools/pearchha-package-app"
        ),
        .target(
            name: "FakeHA",
            dependencies: ["PearchHASupport"],
            path: "Tests/FakeHA",
            exclude: ["README.md"]
        ),
        .testTarget(
            name: "PearchHACoreTests",
            dependencies: ["PearchHACore"]
        ),
        .testTarget(
            name: "PearchHAClientTests",
            dependencies: [
                "FakeHA",
                "PearchHACore",
                "PearchHAClient",
                "PearchHATestSupport"
            ]
        ),
        .testTarget(
            name: "PearchHAPersistenceTests",
            dependencies: ["PearchHAPersistence"]
        ),
        .testTarget(
            name: "PearchHAPackagingTests",
            dependencies: ["PearchHAPackaging"]
        ),
        .testTarget(
            name: "PearchHASupportTests",
            dependencies: [
                "PearchHASupport",
                "PearchHATestSupport"
            ]
        ),
        .testTarget(
            name: "PearchHAUITests",
            dependencies: [
                "FakeHA",
                "PearchHAClient",
                "PearchHAAppShell",
                "PearchHAPersistence",
                "PearchHAUI",
                "PearchHATestSupport"
            ]
        ),
        .testTarget(
            name: "PearchHACoverageCheckTests",
            dependencies: ["PearchHACoverageCheck"]
        ),
        .testTarget(
            name: "PearchHARepoAuditTests",
            dependencies: ["PearchHARepoAudit"]
        ),
        .testTarget(
            name: "FakeHATests",
            dependencies: ["FakeHA"]
        )
    ]
)
