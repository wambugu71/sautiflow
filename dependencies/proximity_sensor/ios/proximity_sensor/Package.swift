// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "proximity_sensor",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(name: "proximity-sensor", targets: ["proximity_sensor"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "proximity_sensor",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ]
        )
    ]
)