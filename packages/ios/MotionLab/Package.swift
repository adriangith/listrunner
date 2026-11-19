// swift-tools-version: 5.9
// Motion Lab: self-contained SwiftUI motion components for ListRunner,
// tuned in Xcode Previews before they are wired into the app.
import PackageDescription

let package = Package(
    name: "ListRunnerMotion",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "ListRunnerMotion", targets: ["ListRunnerMotion"])
    ],
    targets: [
        .target(name: "ListRunnerMotion")
    ]
)
