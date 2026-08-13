// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ArgusMenuBar",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ArgusMenuBar", targets: ["ArgusMenuBar"])],
    targets: [.executableTarget(name: "ArgusMenuBar")]
)
