// swift-tools-version:5.10
import PackageDescription

// Tagwerk – Arbeitsname der Todo-App.
// TagwerkCore enthält Datenmodell, Zeitlogik und Speicherung und läuft auch unter Linux (für Tests).
// TagwerkApp ist die SwiftUI-Oberfläche und wird nur auf macOS gebaut.
// tagwerk-mcp ist der MCP-Server für Claude und liegt später neben der App im Bundle.

var products: [Product] = [
    .library(name: "TagwerkCore", targets: ["TagwerkCore"]),
    .executable(name: "tagwerk-mcp", targets: ["tagwerk-mcp"]),
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
    // MCP-Server, damit Claude (Desktop oder Code) auf Aufgaben und Zeiten zugreifen kann.
    .target(
        name: "TagwerkMCP",
        dependencies: ["TagwerkCore"]
    ),
    .executableTarget(
        name: "tagwerk-mcp",
        dependencies: ["TagwerkCore", "TagwerkMCP"],
        path: "Sources/tagwerk-mcp"
    ),
    .testTarget(
        name: "TagwerkMCPTests",
        dependencies: ["TagwerkMCP", "TagwerkCore"]
    ),
]

#if os(macOS)
products.append(.executable(name: "Tagwerk", targets: ["TagwerkApp"]))
targets.append(
    .executableTarget(
        name: "TagwerkApp",
        dependencies: ["TagwerkCore"],
        linkerSettings: [
            // Info.plist mit Berechtigungstexten in die Programmdatei einbetten,
            // damit auch `swift run` nach dem Kalender fragen darf.
            .unsafeFlags([
                "-Xlinker", "-sectcreate",
                "-Xlinker", "__TEXT",
                "-Xlinker", "__info_plist",
                "-Xlinker", Context.packageDirectory + "/Support/Info.plist",
            ]),
        ]
    )
)
#endif

let package = Package(
    name: "Tagwerk",
    // iOS: der Kern (TagwerkCore) baut schon fürs iPhone; die iPhone-App kommt später dazu.
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: products,
    targets: targets
)
