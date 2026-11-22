// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Seek",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Seek", targets: ["Seek"])
    ],
    targets: [
        .executableTarget(
            name: "Seek",
            path: "Sources/Seek",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)
