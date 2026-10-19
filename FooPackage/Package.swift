// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "FooPackage",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "Foo", targets: ["Foo"]),
        .library(name: "A", type: .dynamic, targets: ["A"]),
        .library(name: "B", type: .dynamic, targets: ["B"]),
    ],
    targets: [
        .target(name: "Foo"),
        .target(name: "A", dependencies: ["Foo"]),
        .target(name: "B", dependencies: ["Foo"]),
    ],
    swiftLanguageModes: [.v6]
)
