// swift-tools-version:5.9
// 用 Xcode 打开这个文件夹，或者 `swift build`，都可以编译源码。
// 打包成 .app 请用 ./build.sh（它会把 Info.plist 和预设文件一起放进去）。
// Open this folder in Xcode or run `swift build` to compile the sources.
// Use ./build.sh to produce the .app bundle (it adds Info.plist and the presets).
import PackageDescription

let package = Package(
    name: "NotchPad",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "NotchPad", path: "Sources/NotchPad")
    ]
)
