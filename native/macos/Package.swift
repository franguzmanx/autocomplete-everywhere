// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AutocompleteHelper",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AutocompleteContextService", targets: ["AutocompleteContextService"]),
        .executable(name: "AutocompleteHelper", targets: ["AutocompleteHelper"]),
        .executable(name: "AutocompleteSettings", targets: ["AutocompleteSettings"]),
    ],
    dependencies: [.package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", exact: "3.0.1")],
    targets: [
        .systemLibrary(name: "CSQLCipher", pkgConfig: "sqlcipher", providers: [.brew(["sqlcipher"])]),
        .target(name: "ContextServiceCore", dependencies: ["CSQLCipher"], exclude: ["README.md"], swiftSettings: [.unsafeFlags(["-Xcc", "-DACCELERATE_NEW_LAPACK"])]),
        .executableTarget(name: "AutocompleteContextService", dependencies: ["ContextServiceCore"]),
        .testTarget(name: "ContextServiceTests", dependencies: ["ContextServiceCore"]),
        .target(name: "ShortcutRules"),
        .executableTarget(name: "AutocompleteHelper", dependencies: ["ShortcutRules"]),
        .testTarget(
            name: "AutocompleteHelperTests",
            dependencies: ["AutocompleteHelper"]
        ),
        .executableTarget(name: "AutocompleteSettings", dependencies: ["KeyboardShortcuts", "ShortcutRules"]),
        .testTarget(
            name: "AutocompleteSettingsTests",
            dependencies: ["AutocompleteSettings"]
        ),
    ]
)
