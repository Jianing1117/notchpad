import AppKit
import SwiftUI

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    // 允许窗口贴着屏幕最顶端，盖住菜单栏 / allow the window to sit over the menu bar
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

struct NotchGeometry: Equatable {
    var screen: NSRect
    var notch: CGSize
    var size: CGSize
    /// 窗口比黑色面板大一圈，留给阴影 / room around the panel for its shadow
    static let margin: CGFloat = 28

    /// 展开后黑色面板在屏幕上的位置
    var contentFrame: NSRect {
        NSRect(x: screen.midX - size.width / 2, y: screen.maxY - size.height,
               width: size.width, height: size.height)
    }

    var panelFrame: NSRect {
        NSRect(x: contentFrame.minX - Self.margin, y: contentFrame.minY - Self.margin,
               width: size.width + Self.margin * 2, height: size.height + Self.margin)
    }

    /// 鼠标碰到这块就展开：刘海本身，左右各放宽一点，往上多 1pt 盖住屏幕最顶边
    /// Hovering here expands the panel: the notch, a bit wider, plus the very top edge
    var hotZone: NSRect {
        NSRect(x: screen.midX - notch.width / 2 - 8, y: screen.maxY - notch.height,
               width: notch.width + 16, height: notch.height + 1)
    }

    static func current(panel: PanelSpec? = nil) -> NotchGeometry {
        let s = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
        // 没有刘海的屏幕（外接显示器）：在菜单栏正中假装有一个
        // No notch (external display): pretend there is one in the middle of the menu bar
        var notch = CGSize(width: 200, height: max(24, s.frame.maxY - s.visibleFrame.maxY))
        if s.safeAreaInsets.top > 0, let l = s.auxiliaryTopLeftArea, let r = s.auxiliaryTopRightArea {
            notch = CGSize(width: s.frame.width - l.width - r.width, height: s.safeAreaInsets.top)
        }
        let width = panel?.width.map { CGFloat($0) } ?? 560
        let height = panel?.height.map { CGFloat($0) } ?? 420
        let size = CGSize(width: max(width, notch.width + 300), height: min(max(height, 200), s.frame.height - 40))
        return NotchGeometry(screen: s.frame, notch: notch, size: size)
    }
}

/// 管窗口和鼠标：碰到刘海展开，移开收起 / owns the window: hover the notch to expand, leave to collapse
@MainActor
final class NotchController {
    private let model: AppModel
    private let panel: NotchPanel
    private var geometry: NotchGeometry
    private var monitors: [Any] = []
    private var expandTask: Task<Void, Never>?
    private var collapseTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    private var pinned = false
    private let debug = CommandLine.arguments.contains("--debug")

    init(model: AppModel) {
        self.model = model
        geometry = .current(panel: model.config.panel)
        panel = NotchPanel(contentRect: geometry.panelFrame,
                           styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true   // 点按钮不抢键盘，点输入框才接管
        panel.isReleasedWhenClosed = false
        panel.appearance = NSAppearance(named: .darkAqua)
        mountContent()

        model.makeKey = { [weak self] in self?.panel.makeKey() }
        model.collapse = { [weak self] in self?.collapse(force: true) }
        model.panelChanged = { [weak self] in self?.screensChanged() }
        installMonitors()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        }
    }

    func expand(pin: Bool = false) {
        expandTask?.cancel(); expandTask = nil
        hideTask?.cancel(); hideTask = nil
        if pin { pinned = true }
        guard !model.expanded else { return }
        panel.ignoresMouseEvents = false
        panel.orderFrontRegardless()
        log("expand")
        withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) { model.expanded = true }
        model.didExpand()
    }

    func collapse(force: Bool = false) {
        collapseTask?.cancel(); collapseTask = nil
        if force { pinned = false }
        guard model.expanded, !pinned else { return }
        model.endEdit(save: true)   // 收起前把正在改的标题存好 / save an in-progress edit before closing
        model.editing = false
        model.dragging = nil
        panel.makeFirstResponder(nil)
        panel.ignoresMouseEvents = true
        log("collapse")
        withAnimation(.spring(response: 0.3, dampingFraction: 0.92)) { model.expanded = false }
        // 收完再把窗口撤掉：不占渲染，键盘焦点也自然回到原来的 app
        // Order the window out once collapsed: nothing to render, and keyboard focus returns to the previous app
        hideTask = later(.milliseconds(380)) { $0.panel.orderOut(nil) }
    }

    // MARK: -

    private func mountContent() {
        panel.setFrame(geometry.panelFrame, display: false)
        let host = NSHostingView(rootView: NotchRootView(
            model: model, notch: geometry.notch, size: geometry.size, margin: NotchGeometry.margin))
        host.sizingOptions = []
        panel.contentView = host
    }

    private func installMonitors() {
        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        add(NSEvent.addGlobalMonitorForEvents(matching: moves) { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseMoved() }
        })
        add(NSEvent.addLocalMonitorForEvents(matching: moves) { [weak self] event in
            MainActor.assumeIsolated { self?.mouseMoved() }
            return event
        })
        // 点了别的 app → 收起 / a click in another app collapses
        add(NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.collapse(force: true) }
        })
        add(NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated { self?.handleKey(event) ?? event }
        })
    }

    private func add(_ monitor: Any?) {
        if let monitor { monitors.append(monitor) }
    }

    private func mouseMoved() {
        let p = NSEvent.mouseLocation
        if model.expanded {
            let inside = geometry.contentFrame.insetBy(dx: -6, dy: -6).contains(p) || geometry.hotZone.contains(p)
            if inside || model.titleDragActive || model.editing || model.editingItemID != nil || pinned {
                collapseTask?.cancel(); collapseTask = nil
            } else if collapseTask == nil {
                collapseTask = later(.milliseconds(300)) { $0.collapse() }
            }
        } else if geometry.hotZone.contains(p) {
            if expandTask == nil { expandTask = later(.milliseconds(90)) { $0.expand() } }
        } else {
            expandTask?.cancel(); expandTask = nil
        }
    }

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        guard model.expanded else { return event }
        if event.keyCode == 53 { // Esc
            // 输入法还在选字时，Esc 留给输入法 / let the input method use Esc while composing
            if let tv = panel.firstResponder as? NSTextView, tv.hasMarkedText() { return event }
            // 正在改某一条的标题：Esc 只取消这次修改 / while editing a title, Esc only cancels the edit
            if model.editingItemID != nil {
                model.endEdit(save: false)
                return nil
            }
            collapse(force: true)
            return nil
        }
        // ⌘1、⌘2… 切换 tab / ⌘1, ⌘2… switch tabs
        if event.modifierFlags.contains(.command),
           let c = event.charactersIgnoringModifiers, let n = Int(c), (1...model.config.tabs.count).contains(n) {
            model.tabIndex = n - 1
            return nil
        }
        return event
    }

    private func log(_ message: String) {
        guard debug else { return }
        print("\(Date().formatted(.dateTime.hour().minute().second())) \(message)  notch=\(geometry.notch) hot=\(geometry.hotZone)")
        fflush(stdout)
    }

    private func screensChanged() {
        let g = NotchGeometry.current(panel: model.config.panel)
        guard g != geometry else { return }
        geometry = g
        mountContent()
    }

    private func later(_ delay: Duration, _ action: @escaping (NotchController) -> Void) -> Task<Void, Never> {
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            action(self)
        }
    }
}
