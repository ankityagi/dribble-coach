// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DribbleCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "DribbleCore", targets: ["DribbleCore"]),
    ],
    targets: [
        .target(name: "DribbleCore"),
        .testTarget(name: "DribbleCoreTests", dependencies: ["DribbleCore"]),
    ]
)
