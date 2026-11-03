// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Hailbell",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "Hailbell", targets: ["Hailbell"]),
        // For a Notification Service Extension: images, buttons, badges and delivery receipts.
        .library(name: "HailbellNotificationService", targets: ["HailbellNotificationService"]),
    ],
    targets: [
        .target(name: "Hailbell", path: "Sources/Hailbell", resources: [.copy("PrivacyInfo.xcprivacy")]),
        .target(name: "HailbellNotificationService", path: "Sources/HailbellNotificationService", resources: [.copy("PrivacyInfo.xcprivacy")]),
        .testTarget(name: "HailbellTests", dependencies: ["Hailbell", "HailbellNotificationService"], path: "Tests/HailbellTests"),
    ]
)
