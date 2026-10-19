// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "ConsumerPackage",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Consumer", targets: ["Consumer"]),
    ],
    dependencies: [
        .package(name: "FooPackage", path: "FooPackage"),
    ],
    targets: [
        .executableTarget(
            name: "Consumer",
            dependencies: [
                .product(name: "Foo", package: "FooPackage"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
