// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Yisi",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Yisi", targets: ["Yisi"])
    ],
    targets: [
        .executableTarget(
            name: "Yisi",
            path: "Yisi"
        ),
        .testTarget(name: "YisiTests", dependencies: ["Yisi"], path: "Tests/YisiTests")
    ]
)
