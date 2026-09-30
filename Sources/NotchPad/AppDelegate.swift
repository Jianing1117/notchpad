import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotchController?

    /// 启动参数（调试、截图用）/ launch arguments (for debugging and screenshots):
    ///   --demo           用内置示例数据，不碰提醒事项和备忘录 / sample data, never touches Reminders or Notes
    ///   --preset NAME    只在内存里用某个预设，不读写配置文件 / use a preset in memory, don't read or write config.json
    ///   --lang zh|en     指定界面语言 / force the UI language
    ///   --expanded       启动后直接展开并固定（Esc 收起）/ start expanded and pinned (Esc to close)
    ///   --tab N          从第 N 个 tab 开始（从 1 数）/ start on tab N (1-based)
    ///   --snapshot DIR   把每个 tab 存成 PNG 然后退出 / save each tab as a PNG, then quit
    ///   --debug          打印展开、收起 / log expand and collapse
    ///   --set-language zh|en  改配置里的界面语言然后退出 / set the UI language in the config, then quit
    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        func value(_ flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        if let code = value("--set-language") {
            ConfigStore.setLanguage(code)
            exit(0)
        }
        NSApp.mainMenu = makeMainMenu()

        let model = AppModel(demo: args.contains("--demo"), preset: value("--preset"))
        if let n = value("--tab").flatMap(Int.init), (1...model.config.tabs.count).contains(n) {
            model.tabIndex = n - 1
        }
        if let dir = value("--snapshot") {
            model.start()
            Snapshot.run(model: model, to: URL(fileURLWithPath: dir))
            return
        }
        let controller = NotchController(model: model)
        self.controller = controller
        model.start()
        if args.contains("--expanded") { controller.expand(pin: true) }
    }

    /// 没有菜单栏也要挂一个 Edit 菜单，否则输入框里 ⌘C / ⌘V / ⌘A / ⌘Z 不生效
    /// An Edit menu is needed even without a menu bar, or ⌘C / ⌘V / ⌘A / ⌘Z won't work in text fields
    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: L.s("退出刘海记", "Quit NotchPad"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: L.s("撤销", "Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: L.s("重做", "Redo"), action: Selector(("redo:")), keyEquivalent: "z")
            .keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: L.s("剪切", "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: L.s("拷贝", "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: L.s("粘贴", "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: L.s("全选", "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        return main
    }
}
