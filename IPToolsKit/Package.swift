// swift-tools-version: 6.0
// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import PackageDescription

let package = Package(
    name: "IPToolsKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "AppShell", targets: ["AppShell"]),
    ],
    targets: [
        // Logic (no SwiftUI, no inter-dependencies)
        .target(name: "NetCore"),
        .target(name: "RIPEstat"),
        .target(name: "BGPGraph"),

        // UI
        .target(name: "SharedUI", dependencies: ["NetCore"]),
        .target(name: "PingFeature", dependencies: ["NetCore", "SharedUI"]),
        .target(name: "TraceFeature", dependencies: ["NetCore", "RIPEstat", "SharedUI"]),
        .target(name: "BGPFeature", dependencies: ["RIPEstat", "BGPGraph", "NetCore", "SharedUI"]),
        .target(
            name: "AppShell",
            dependencies: [
                "NetCore", "RIPEstat", "BGPGraph", "SharedUI",
                "PingFeature", "TraceFeature", "BGPFeature",
            ]
        ),

        // Tests
        .testTarget(name: "NetCoreTests", dependencies: ["NetCore"]),
        .testTarget(
            name: "RIPEstatTests",
            dependencies: ["RIPEstat"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "BGPGraphTests",
            dependencies: ["BGPGraph", "RIPEstat"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "FeatureTests",
            dependencies: [
                "NetCore", "RIPEstat", "BGPGraph", "SharedUI",
                "PingFeature", "TraceFeature", "BGPFeature", "AppShell",
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
