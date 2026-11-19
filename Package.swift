// swift-tools-version:5.10
import PackageDescription

// Tagwerk – Arbeitsname der Todo-App.
// TagwerkCore enthält Datenmodell, Zeitlogik und Speicherung und läuft auch unter Linux (für Tests).
// TagwerkApp ist die SwiftUI-Oberfläche und wird nur auf macOS gebaut.

var products: [Product] = [
    .library(name: "TagwerkCore", targets: ["TagwerkCore"]),
]

var targets: [Target] = [
    .systemLibrary(name: "CSQLite", path: "Sources/CSQLite"),
    .target(
        name: "TagwerkCore",
        dependencies: [
            .target(name: "CSQLite", condition: .when(platforms: [.linux])),
        ]
    ),
    .testTarget(
        name: "TagwerkCoreTests",
        dependencies: ["TagwerkCore"]
    ),
]

#if os(macOS)
products.append(.executable(name: "Tagwerk", targets: ["TagwerkApp"]))
targets.append(
    .executableTarget(
        name: "TagwerkApp",
        dependencies: ["TagwerkCore"]
    )
)
#endif

let package = Package(
    name: "Tagwerk",
    platforms: [.macOS(.v14)],
    products: products,
    targets: targets
)
