// swift-tools-version: 6.0
import Foundation
import PackageDescription

let cltTestingMacros = "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
let testSwiftSettings: [SwiftSetting] = FileManager.default.fileExists(atPath: cltTestingMacros)
    ? [.unsafeFlags(["-load-plugin-library", cltTestingMacros])]
    : []

let package = Package(
    name: "BusLensMac",
    platforms: [
        .macOS("14.0")
    ],
    products: [
        .library(name: "BusLensMacCore", targets: ["BusLensMacCore"]),
        .executable(name: "BusLensMac", targets: ["BusLensMac"])
    ],
    targets: [
        .target(
            name: "BusLensMacCore"
        ),
        .executableTarget(
            name: "BusLensMac",
            dependencies: ["BusLensMacCore"]
        ),
        .testTarget(
            name: "BusLensMacCoreTests",
            dependencies: ["BusLensMacCore"],
            swiftSettings: testSwiftSettings
        )
    ],
    swiftLanguageModes: [.v5]
)
