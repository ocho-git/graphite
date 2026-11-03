// swift-tools-version:5.9
import PackageDescription

/// The engine's name, in one place. It names the package, the library product and its module (`import Graphite`),
/// and the command-line tool (its lowercase form). The folders under Sources/ and Examples/ do not depend on it.
/// Renaming: change it here, then the single `@_exported import` line in Examples/Engine.swift (and in any project
/// that depends on the package).
let name = "Graphite"

let package = Package(
    name: name,
    platforms: [.macOS(.v13)],
    products: [
        .library(name: name, targets: [name]),
        .executable(name: name.lowercased(), targets: [name + "CLI"]),
    ],
    targets: [
        .target(name: name, path: "Sources/Engine"),
        .executableTarget(name: name + "CLI", dependencies: [.target(name: name)], path: "Examples", exclude: ["output"]),
    ]
)
