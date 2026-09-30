import AppKit
import SwiftUI

/// `--snapshot <文件夹>`：把每个 tab 展开后的样子各存一张 PNG（配一块假桌面和假刘海），然后退出。
/// 一般和 `--demo --preset creator --lang zh` 一起用。
///
/// Saves each tab, expanded, as a PNG (on a fake desktop with a fake notch), then quits.
/// Usually combined with `--demo --preset creator --lang en`.
@MainActor
enum Snapshot {
    static func run(model: AppModel, to dir: URL) {
        let g = NotchGeometry.current(panel: model.config.panel)
        let canvas = CGSize(width: g.size.width + 240, height: g.size.height + 70)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        model.expanded = true
        Task {
            try? await Task.sleep(for: .milliseconds(400))   // 等示例数据加载完 / let the data load
            for (i, tab) in model.config.tabs.enumerated() {
                model.tabIndex = i
                try? await Task.sleep(for: .milliseconds(300))
                let view = Backdrop(model: model, geometry: g).frame(width: canvas.width, height: canvas.height)
                let host = NSHostingView(rootView: view)
                host.frame = CGRect(origin: .zero, size: canvas)
                let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
                window.contentView = host
                window.appearance = NSAppearance(named: .darkAqua)
                host.layoutSubtreeIfNeeded()
                try? await Task.sleep(for: .milliseconds(300))
                if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                    host.cacheDisplay(in: host.bounds, to: rep)
                    let url = dir.appendingPathComponent("\(L.zh ? "zh" : "en")-\(i + 1)-\(tab.type.rawValue).png")
                    try? rep.representation(using: .png, properties: [:])?.write(to: url)
                    print(url.path)
                }
            }
            NSApp.terminate(nil)
        }
    }

    private struct Backdrop: View {
        @ObservedObject var model: AppModel
        let geometry: NotchGeometry

        var body: some View {
            ZStack(alignment: .top) {
                LinearGradient(colors: [Color(red: 0.93, green: 0.90, blue: 0.95), Color(red: 0.76, green: 0.84, blue: 0.95)],
                               startPoint: .top, endPoint: .bottom)
                Rectangle().fill(Color.white.opacity(0.45)).frame(height: geometry.notch.height)
                NotchShape(top: 6, bottom: 10).fill(Color.black)
                    .frame(width: geometry.notch.width, height: geometry.notch.height)
                NotchRootView(model: model, notch: geometry.notch, size: geometry.size, margin: NotchGeometry.margin)
            }
        }
    }
}
