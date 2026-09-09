// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WayTrackCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "WayTrackCore", targets: ["WayTrackCore"])],
    targets: [
        .target(name: "WayTrackCore"),
        .testTarget(name: "WayTrackCoreTests", dependencies: ["WayTrackCore"]),
    ]
)
