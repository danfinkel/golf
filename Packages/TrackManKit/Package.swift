// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TrackManKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "TrackManKit", targets: ["TrackManKit"]),
    ],
    targets: [
        .target(name: "TrackManKit"),
        .testTarget(name: "TrackManKitTests", dependencies: ["TrackManKit"]),
    ]
)
