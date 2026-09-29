// swift-tools-version:5.9
// Isla — app que vive en el notch ("isla dinámica") de tu Mac.
import PackageDescription

let package = Package(
    name: "IslaMM",
    platforms: [.macOS(.v13)],
    targets: [
        // Ayudante en Objective-C para atrapar excepciones de Apple (ver IslaObjC.h).
        .target(
            name: "IslaObjC",
            path: "Sources/IslaObjC"
        ),
        .executableTarget(
            name: "IslaMM",
            dependencies: ["IslaObjC"],
            path: "Sources/IslaMM"
        )
    ]
)
