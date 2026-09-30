import AppKit
import SwiftUI

struct TodoItem: Identifiable, Equatable {
    let id: String
    var title: String
    var done: Bool
    var created: Date
    var completed: Date?
    /// 在提醒事项的哪个列表里 / the Reminders list it lives in
    var list: String
}

struct Jot: Identifiable, Equatable {
    let id: String
    var text: String
    var date: Date

    /// 列表里只显示一句：第一行，遇到句号、问号、感叹号、分号就截断
    /// One line in the list: the first line, cut at the first sentence end
    var headline: String {
        let first = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        if let end = first.firstIndex(where: { "。！？；!?;".contains($0) }), end != first.startIndex {
            return String(first[..<end])
        }
        return first
    }
}

enum SourceState: Equatable {
    case idle, ready, denied
    case failed(String)
}

struct BackendError: Error {
    var message: String
    var denied = false
}

struct PinnedState: Equatable {
    var list: PinnedList?
    var error: String?
}

@MainActor
protocol TodoBackend: AnyObject {
    var authorized: Bool { get }
    func start(onChange: @escaping () -> Void) async -> SourceState
    /// 配置里用到的列表不存在就建好 / create any list the config needs
    func ensureLists(_ lists: [(name: String, color: Color)])
    func items(list: String, doneSince: Date) async -> [TodoItem]
    func add(_ title: String, list: String) async -> TodoItem?
    func setDone(id: String, _ done: Bool) async
    func rename(id: String, title: String) async
    func delete(id: String) async
    func move(id: String, toList: String) async
}

@MainActor
protocol JotBackend: AnyObject {
    func list(folder: String) async -> Result<[Jot], BackendError>
    func add(_ text: String, folder: String) async -> Result<Void, BackendError>
    func open(id: String) async
    func delete(id: String) async
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var config: AppConfig
    @Published private(set) var configNotice: String?
    @Published var tabIndex: Int {
        didSet {
            guard tabIndex != oldValue else { return }
            UserDefaults.standard.set(tabIndex, forKey: "tab")
            endEdit(save: true)
            editing = false
            if tab.type == .jots { refreshJots() }
        }
    }
    @Published var expanded = false
    /// 输入框有焦点时，鼠标移开也不收起（说话、打字时不会被打断）
    @Published var editing = false
    /// 提醒事项：列表名 → 条目（没做的在前，做完的在后）/ list name → items, open first
    @Published var lists: [String: [TodoItem]] = [:]
    /// 备忘录：文件夹名 → 随手记 / folder name → jots
    @Published var jots: [String: [Jot]] = [:]
    /// tab 序号 → 置顶卡片内容 / tab index → pinned card content
    @Published var pinned: [Int: PinnedState] = [:]
    @Published var remindersState: SourceState = .idle
    @Published var notesState: SourceState = .idle
    /// 分段清单的输入框要加进哪一段（按 tab 序号）/ which section the input adds to, per tab
    @Published var sectionTarget: [Int: Int] = [:]
    @Published var jotFocusTick = 0

    /// 正在改标题的那一条和改到一半的文字：点一下文字进入；回车、点别处或收起面板时保存，Esc 取消。
    /// 文字放在这里而不是输入框里：输入框被重建时不会丢，也不会自己结束修改。
    /// The item being edited and its draft. Return, clicking away or closing the panel saves; Esc cancels.
    /// The draft lives here, not in the field, so a rebuilt field neither loses it nor ends the edit.
    @Published var editingItemID: String?
    @Published var editDraft = ""

    /// 正在拖的那一条（拖动开始时记下，放下时用）
    var dragging: (id: String, at: Date)?

    var makeKey: () -> Void = {}
    var collapse: () -> Void = {}
    var panelChanged: () -> Void = {}

    let demo: Bool
    /// --preset：只在内存里用这个预设，不读写配置文件 / use a preset in memory only
    private let fixedPreset: String?
    private let todos: TodoBackend
    private let notes: JotBackend
    private var configDate: Date?
    private var lastTodoLoad = Date.distantPast
    private var lastJotLoad: [String: Date] = [:]
    private var reloadTask: Task<Void, Never>?

    var tab: TabSpec { config.tabs[min(tabIndex, config.tabs.count - 1)] }

    init(demo: Bool, preset: String?) {
        self.demo = demo
        fixedPreset = preset
        todos = demo ? DemoTodos() : RemindersStore()
        notes = demo ? DemoJots() : NotesStore()
        let loaded = preset.map(ConfigStore.preset) ?? ConfigStore.load()
        config = loaded.config
        configNotice = loaded.notice
        configDate = preset == nil ? ConfigStore.modificationDate() : nil
        tabIndex = min(UserDefaults.standard.integer(forKey: "tab"), loaded.config.tabs.count - 1)
    }

    func start() {
        loadPinned()
        Task { await connectReminders() }
    }

    func didExpand() {
        reloadConfigIfChanged()
        loadPinned()
        if remindersState == .denied, todos.authorized {
            Task { await connectReminders() }
        } else if Date().timeIntervalSince(lastTodoLoad) > 5 {
            Task { await reloadTodos() }
        }
        if tab.type == .jots { refreshJots() }
    }

    func refreshAll() {
        reloadConfigIfChanged(force: true)
        loadPinned()
        Task { await reloadTodos() }
        refreshJots(force: true)
    }

    // MARK: 颜色 / colors

    func accent(_ index: Int) -> Color {
        Color(hex: config.tabs[index].color) ?? Theme.tabAccents[index % Theme.tabAccents.count]
    }

    func sectionColor(_ tab: TabSpec, _ i: Int) -> Color {
        Color(hex: tab.sections?[i].color) ?? Theme.sectionColors[i % Theme.sectionColors.count]
    }

    // MARK: 配置 / config

    func reloadConfigIfChanged(force: Bool = false) {
        guard fixedPreset == nil else { return }
        let date = ConfigStore.modificationDate()
        guard force || date != configDate else { return }
        configDate = date
        apply(ConfigStore.load())
    }

    func applyPreset(_ name: String) {
        guard fixedPreset == nil else { return }
        ConfigStore.write(preset: name)
        reloadConfigIfChanged(force: true)
    }

    func editConfig() {
        guard fixedPreset == nil else { return }
        collapse()
        _ = ConfigStore.load()   // 确保文件存在 / make sure the file exists
        let file = ConfigStore.file
        if NSWorkspace.shared.urlForApplication(toOpen: file) != nil {
            NSWorkspace.shared.open(file)
        } else {
            NSWorkspace.shared.open([file], withApplicationAt: URL(fileURLWithPath: "/System/Applications/TextEdit.app"),
                                    configuration: NSWorkspace.OpenConfiguration())
        }
    }

    /// 换界面语言：写进配置，然后重启自己
    /// Switch UI language: save it to the config, then relaunch
    func setLanguage(_ code: String) {
        guard fixedPreset == nil, code.hasPrefix("zh") != L.zh else { return }
        ConfigStore.setLanguage(code)
        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
        relaunch.arguments = ["-c", "sleep 0.6; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? relaunch.run()
        NSApp.terminate(nil)
    }

    private func apply(_ loaded: ConfigStore.Loaded) {
        let oldPanel = config.panel
        config = loaded.config
        configNotice = loaded.notice
        if tabIndex >= config.tabs.count { tabIndex = 0 }
        if remindersState == .ready {
            todos.ensureLists(listPlan.map { ($0.name, $0.color) })
            Task { await reloadTodos() }
        }
        loadPinned()
        if tab.type == .jots { refreshJots(force: true) }
        if config.panel != oldPanel { panelChanged() }
    }

    /// 配置里用到的每个提醒事项列表：名字、颜色、已完成的要往回读到哪天
    /// Every Reminders list the config uses: name, color, and how far back to read finished items
    private var listPlan: [(name: String, color: Color, doneSince: Date)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let monthStart = cal.dateInterval(of: .month, for: Date())?.start ?? today
        let pipelineSince = min(monthStart, cal.date(byAdding: .day, value: -30, to: today) ?? today)

        var plan: [(name: String, color: Color, doneSince: Date)] = []
        func add(_ name: String, _ color: Color, _ since: Date) {
            if let i = plan.firstIndex(where: { $0.name == name }) {
                plan[i].doneSince = min(plan[i].doneSince, since)
            } else {
                plan.append((name, color, since))
            }
        }
        for (i, tab) in config.tabs.enumerated() {
            for stage in tab.stages ?? [] where tab.type == .pipeline { add(stage.listName, accent(i), pipelineSince) }
            for (j, s) in (tab.sections ?? []).enumerated() where tab.type == .sections { add(s.listName, sectionColor(tab, j), today) }
        }
        return plan
    }

    // MARK: 提醒事项 / Reminders

    private func connectReminders() async {
        remindersState = await todos.start { [weak self] in self?.scheduleReload() }
        if remindersState == .ready {
            todos.ensureLists(listPlan.map { ($0.name, $0.color) })
            await reloadTodos()
        }
    }

    /// 手机上改了，iCloud 同步过来会触发这里；稍等一下再读，避免连着刷好几次
    private func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task {
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            await reloadTodos()
        }
    }

    private func reloadTodos() async {
        guard remindersState == .ready else { return }
        lastTodoLoad = Date()
        var result: [String: [TodoItem]] = [:]
        for plan in listPlan {
            result[plan.name] = sorted(await todos.items(list: plan.name, doneSince: plan.doneSince))
        }
        withAnimation(.easeOut(duration: 0.2)) { lists = result }
    }

    /// 没做的在上面（新的在前），做完的沉到下面
    private func sorted(_ items: [TodoItem]) -> [TodoItem] {
        let open = items.filter { !$0.done }.sorted { $0.created > $1.created }
        let done = items.filter { $0.done }
            .sorted { ($0.completed ?? .distantPast) > ($1.completed ?? .distantPast) }
        return open + done
    }

    func items(_ list: String) -> [TodoItem] { lists[list] ?? [] }

    func openItems(_ list: String) -> [TodoItem] { items(list).filter { !$0.done } }

    /// 流水线的「完成」段：各段里做完的，最近 10 条；以及本月一共完成几条
    func doneItems(_ tab: TabSpec) -> (items: [TodoItem], thisMonth: Int) {
        let monthStart = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
        let done = (tab.stages ?? []).flatMap { items($0.listName) }.filter(\.done)
            .sorted { ($0.completed ?? .distantPast) > ($1.completed ?? .distantPast) }
        return (Array(done.prefix(10)), done.filter { ($0.completed ?? .distantPast) >= monthStart }.count)
    }

    func add(_ title: String, list: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        Task {
            guard let item = await todos.add(t, list: list) else { return }
            withAnimation(.snappy) { lists[list, default: []].insert(item, at: 0) }
        }
    }

    /// 分段清单：点圆圈勾掉 / 取消。先显示勾，再沉到本段下面
    /// Sections: toggle done — show the check first, then let it sink
    func toggle(_ item: TodoItem) {
        let done = !item.done
        if let i = lists[item.list]?.firstIndex(where: { $0.id == item.id }) {
            lists[item.list]?[i].done = done
            lists[item.list]?[i].completed = done ? Date() : nil
        }
        Task { await todos.setDone(id: item.id, done) }
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                lists[item.list] = sorted(lists[item.list] ?? [])
            }
        }
    }

    /// 流水线：点圆圈往下一段走；最后一段再往下就是完成；完成的点一下退回原来那段
    /// Pipeline: move to the next stage; after the last stage it's done; clicking a done item moves it back
    func advance(_ item: TodoItem, in tab: TabSpec) {
        let names = (tab.stages ?? []).map(\.listName)
        if item.done {
            place(item, list: item.list, done: false)
        } else if let i = names.firstIndex(of: item.list), i + 1 < names.count {
            place(item, list: names[i + 1], done: false)
        } else {
            place(item, list: item.list, done: true)
        }
    }

    /// 把一条放进某个列表、设成做完或没做完。拖动、右键菜单、点圆圈都走这里
    /// Put an item into a list, done or not. Used by drag, context menu and the circle.
    func place(_ item: TodoItem, list: String, done: Bool) {
        guard item.list != list || item.done != done else { return }
        var moved = item
        moved.list = list
        moved.done = done
        moved.completed = done ? (item.done ? item.completed : Date()) : nil
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            lists[item.list]?.removeAll { $0.id == item.id }
            lists[list] = sorted((lists[list] ?? []) + [moved])
        }
        Task {
            // 先改勾选，再换列表：换列表后条目的编号可能会变
            if done != item.done { await todos.setDone(id: item.id, done) }
            if list != item.list { await todos.move(id: item.id, toList: list) }
            scheduleReload()
        }
    }

    func beginEdit(_ item: TodoItem) {
        endEdit(save: true)   // 正在改别的那条，先保存 / save any other edit first
        makeKey()
        editDraft = item.title
        editingItemID = item.id
        editing = true
    }

    /// 结束修改：save 为 true 就保存（清空不保存）/ end editing; saves when `save` is true (empty is ignored)
    func endEdit(save: Bool) {
        guard let id = editingItemID else { return }
        editingItemID = nil
        editing = false
        guard save, let item = lists.values.lazy.flatMap({ $0 }).first(where: { $0.id == id }) else { return }
        rename(item, to: editDraft)
    }

    /// 改一条的标题；清空不保存 / rename an item; an empty title is ignored
    func rename(_ item: TodoItem, to title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t != item.title else { return }
        if let i = lists[item.list]?.firstIndex(where: { $0.id == item.id }) { lists[item.list]?[i].title = t }
        Task { await todos.rename(id: item.id, title: t) }
    }

    func delete(_ item: TodoItem) {
        withAnimation(.snappy) { lists[item.list]?.removeAll { $0.id == item.id } }
        Task { await todos.delete(id: item.id) }
    }

    // MARK: 拖动 / drag and drop

    func beginDrag(_ item: TodoItem) {
        dragging = (item.id, Date())
    }

    /// 取出刚才拖的那条；太久以前的（拖到一半取消了）不算
    private func takeDragged() -> TodoItem? {
        defer { dragging = nil }
        guard let d = dragging, Date().timeIntervalSince(d.at) < 60 else { return nil }
        return lists.values.lazy.flatMap { $0 }.first { $0.id == d.id }
    }

    /// 拖到某一段。流水线里拖进一段 = 没做完；分段清单里保持原来的勾选状态
    func drop(onList list: String, undone: Bool) -> Bool {
        guard let item = takeDragged() else { return false }
        place(item, list: list, done: undone ? false : item.done)
        return true
    }

    func dropDone() -> Bool {
        guard let item = takeDragged() else { return false }
        place(item, list: item.list, done: true)
        return true
    }

    // MARK: 置顶卡片 / pinned card

    func loadPinned() {
        for (i, tab) in config.tabs.enumerated() {
            guard let spec = tab.pinned else { continue }
            if demo {
                pinned[i] = PinnedState(list: DemoData.pinned, error: nil)
                continue
            }
            let path = spec.path, heading = spec.heading
            Task {
                // 在后台读：第一次读「文稿」等文件夹时系统会弹授权，不能卡住界面
                let result = await Task.detached { PinnedFile.load(path, heading: heading) }.value
                let state: PinnedState
                switch result {
                case .success(let list): state = PinnedState(list: list, error: nil)
                case .failure(let e): state = PinnedState(list: nil, error: e.message)
                }
                if pinned[i] != state { withAnimation(.easeOut(duration: 0.2)) { pinned[i] = state } }
            }
        }
    }

    /// 在 Obsidian 库里的文件用 Obsidian 打开，其他用默认程序
    /// Files inside an Obsidian vault open in Obsidian, everything else in the default app
    func openPinned(_ spec: PinnedSpec) {
        guard !demo else { return }
        collapse()
        let path = spec.path
        var dir = URL(fileURLWithPath: path).deletingLastPathComponent()
        while dir.path != "/" {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent(".obsidian").path) {
                var c = URLComponents()
                c.scheme = "obsidian"
                c.host = "open"
                c.queryItems = [URLQueryItem(name: "path", value: path)]
                if let url = c.url { NSWorkspace.shared.open(url); return }
            }
            dir = dir.deletingLastPathComponent()
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    // MARK: 随手记（备忘录）/ jots (Notes)

    func refreshJots(force: Bool = false) {
        guard tab.type == .jots else { return }
        let folder = tab.folderName
        guard force || Date().timeIntervalSince(lastJotLoad[folder] ?? .distantPast) > 15 else { return }
        lastJotLoad[folder] = Date()
        Task {
            switch await notes.list(folder: folder) {
            case .success(let list):
                withAnimation(.easeOut(duration: 0.2)) { jots[folder] = list.sorted { $0.date > $1.date } }
                notesState = .ready
            case .failure(let e):
                notesState = e.denied ? .denied : .failed(e.message)
            }
        }
    }

    func addJot(_ text: String, folder: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        let pending = Jot(id: "pending-\(UUID().uuidString)", text: t, date: Date())
        withAnimation(.snappy) { jots[folder, default: []].insert(pending, at: 0) }
        Task {
            if case .failure(let e) = await notes.add(t, folder: folder) {
                notesState = e.denied ? .denied : .failed(e.message)
                jots[folder]?.removeAll { $0.id == pending.id }
                return
            }
            refreshJots(force: true)
        }
    }

    func openJot(_ jot: Jot) {
        guard !jot.id.hasPrefix("pending-") else { return }
        collapse()
        Task { await notes.open(id: jot.id) }
    }

    func deleteJot(_ jot: Jot, folder: String) {
        withAnimation(.snappy) { jots[folder]?.removeAll { $0.id == jot.id } }
        Task { await notes.delete(id: jot.id) }
    }

    /// 聚焦随手记输入框，然后调起系统听写（和按键盘上的 🎤 键一样）
    /// Focus the jot field and start system dictation (same as the 🎤 key)
    func dictate() {
        makeKey()
        jotFocusTick += 1
        Task {
            try? await Task.sleep(for: .milliseconds(180))
            NSApp.sendAction(Selector(("startDictation:")), to: nil, from: nil)
        }
    }
}
