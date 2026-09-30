// swift-tools-version:5.9
// UltraNotch — app que vive en el notch ("isla dinámica") de tu Mac.
import PackageDescription

let package = Package(
    name: "UltraNotch",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "UltraNotch", targets: ["UltraNotch"])
    ],
    targets: [
        // Ayudante en Objective-C para atrapar excepciones de Apple (ver UltraNotchObjC.h).
        .target(
            name: "UltraNotchObjC",
            path: "Sources/UltraNotchObjC"
        ),
        .executableTarget(
            name: "UltraNotch",
            dependencies: ["UltraNotchObjC"],
            path: "Sources/UltraNotch"
        )
    ]
)
