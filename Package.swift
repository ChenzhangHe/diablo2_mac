// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "AshenSigil",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AshenSigil", targets: ["AshenApp"]),
        .library(name: "AshenCore", targets: ["AshenCore"]),
    ],
    targets: [
        .target(name: "AshenCore"),
        .executableTarget(name: "AshenApp", dependencies: ["AshenCore"]),
        .testTarget(name: "AshenCoreTests", dependencies: ["AshenCore"]),
    ]
)
