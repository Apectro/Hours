// swift-tools-version: 5.9

import PackageDescription

// A second way to build the calculation engine, alongside the Xcode project.
//
// The app target compiles `HoursCore/` directly, so nothing here is a
// dependency of the app and nothing in the app depends on this file. What it
// buys is a build of the engine on a platform that has no UIKit, no SwiftUI
// and no SwiftData: if any of those ever leaks into `HoursCore/`, this stops
// compiling. That guarantee is the whole point of keeping the engine
// Foundation-only, and until now it was upheld by review alone.
//
// The module is deliberately named `Hours`, the same as the app module, so the
// test files can say `@testable import Hours` and be compiled unchanged by
// either build.
let package = Package(
    name: "Hours",
    products: [
        .library(name: "Hours", targets: ["Hours"])
    ],
    targets: [
        .target(name: "Hours", path: "HoursCore"),
        .testTarget(
            name: "HoursTests",
            dependencies: ["Hours"],
            path: "HoursTests",
            // The rest of the suite covers the SwiftData layer and the
            // services above it, which only exist inside the app.
            exclude: [
                // Not a source file; the scheme and the StoreKit tests read it.
                "Hours.storekit",
                "AdjustmentTests.swift",
                "DuplicateReconciliationTests.swift",
                "ExportTests.swift",
                // Inflection is a Foundation-on-Apple feature, and the point of
                // these is what the app bundle renders.
                "InflectionTests.swift",
                "MigrationTests.swift",
                "PersistenceCodingTests.swift",
                "ShiftTests.swift",
                "SubscriptionStoreTests.swift",
                "TimeClockTests.swift",
            ]
        )
    ]
)
