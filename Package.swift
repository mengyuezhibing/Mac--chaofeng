// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SnowLeopardVision",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "SnowLeopardVision",
            path: "Sources/SnowLeopardVision",
            swiftSettings: [
                // 以 Swift 5 语言模式编译，避免 Swift 6 严格并发检查带来的大量改造成本
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
