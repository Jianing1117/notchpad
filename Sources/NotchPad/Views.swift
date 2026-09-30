import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

// MARK: - 外形：从刘海里长出来的黑色面板 / the black panel growing out of the notch

struct NotchShape: Shape {
    var top: CGFloat
    var bottom: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(top, bottom) }
        set { top = newValue.first; bottom = newValue.second }
    }

    /// 顶边贴着屏幕，两个上角向外弯（像刘海和菜单栏接缝），下面两个角圆角
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX + top, y: r.minY + top), control: CGPoint(x: r.minX + top, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + top, y: r.maxY - bottom))
        p.addQuadCurve(to: CGPoint(x: r.minX + top + bottom, y: r.maxY), control: CGPoint(x: r.minX + top, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - top - bottom, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX - top, y: r.maxY - bottom), control: CGPoint(x: r.maxX - top, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - top, y: r.minY + top))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.maxX - top, y: r.minY))
        p.closeSubpath()
        return p
    }
}

struct NotchRootView: View {
    @ObservedObject var model: AppModel
    let notch: CGSize
    let size: CGSize
    let margin: CGFloat

    private let ear: CGFloat = 12

    var body: some View {
        let open = model.expanded
        let shape = NotchShape(top: open ? ear : 6, bottom: open ? 24 : 10)

        ZStack(alignment: .top) {
            Color.black
            if open {
                PanelContent(model: model, notch: notch, inset: ear)
                    .frame(width: size.width, height: size.height)
                    .transition(.asymmetric(
                        insertion: .opacity.animation(.easeOut(duration: 0.18).delay(0.08)),
                        removal: .opacity.animation(.easeIn(duration: 0.08))))
            }
        }
        .frame(width: open ? size.width : notch.width, height: open ? size.height : notch.height, alignment: .top)
        .clipShape(shape)
        .overlay(shape.stroke(Theme.hairline, lineWidth: 1).opacity(open ? 1 : 0))
        .shadow(color: .black.opacity(open ? 0.5 : 0), radius: 18, y: 8)
        .frame(width: size.width + margin * 2, height: size.height + margin, alignment: .top)
    }
}

// MARK: - 面板 / panel

struct PanelContent: View {
    @ObservedObject var model: AppModel
    let notch: CGSize
    let inset: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            // 第一行和刘海一样高：左边 tab，中间让出刘海，右边日期
            HStack(spacing: 0) {
                TabBar(model: model).frame(maxWidth: .infinity, alignment: .leading)
                Color.clear.frame(width: notch.width + 16)
                HeaderRight(model: model).frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, inset + 14)
            .frame(height: notch.height)

            if let notice = model.configNotice {
                Text(notice)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.amber)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, inset + 12)
                    .padding(.top, 6)
            }

            Group {
                let tab = model.tab
                let i = min(model.tabIndex, model.config.tabs.count - 1)
                switch tab.type {
                case .pipeline: PipelineView(model: model, spec: tab, index: i)
                case .sections: SectionsView(model: model, spec: tab, index: i)
                case .jots: JotsView(model: model, spec: tab, index: i)
                }
            }
            .id(model.tabIndex)
            .padding(.horizontal, inset + 10)
            .padding(.top, 10)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .environment(\.colorScheme, .dark)
    }
}

struct TabBar: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 16) {
            ForEach(Array(model.config.tabs.enumerated()), id: \.offset) { i, tab in
                let on = model.tabIndex == i
                Button { model.tabIndex = i } label: {
                    Text(tab.title)
                        .font(.system(size: 12.5, weight: on ? .semibold : .regular))
                        .foregroundStyle(on ? model.accent(i) : Theme.dim)
                        .lineLimit(1)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct HeaderRight: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            Text(Fmt.today.string(from: Date()))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Theme.dim)
                .lineLimit(1)
            Menu {
                Button(L.s("刷新", "Refresh")) { model.refreshAll() }
                Button(L.s("编辑配置文件…", "Edit Config…")) { model.editConfig() }
                Menu(L.s("换一套预设（当前配置会先备份）", "Switch Preset (current config is backed up)")) {
                    ForEach(ConfigStore.presets, id: \.self) { name in
                        Button(ConfigStore.presetTitle(name)) { model.applyPreset(name) }
                    }
                }
                Menu(L.s("界面语言", "Language")) {
                    Toggle("中文", isOn: Binding(get: { L.zh }, set: { if $0 { model.setLanguage("zh") } }))
                    Toggle("English", isOn: Binding(get: { !L.zh }, set: { if $0 { model.setLanguage("en") } }))
                }
                Divider()
                Toggle(L.s("开机时启动", "Launch at Login"), isOn: Binding(get: { LoginItem.enabled }, set: { LoginItem.set($0) }))
                Divider()
                Button(L.s("退出刘海记", "Quit NotchPad")) { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.dim)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }
}

enum LoginItem {
    static var enabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("NotchPad: login item failed \(error)")
        }
    }
}

// MARK: - 通用小部件 / shared pieces

struct InputShell<Content: View>: View {
    var alignment: VerticalAlignment = .center
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: alignment, spacing: 10) { content() }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: 34)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.field))
    }
}

struct CaptureField: View {
    @ObservedObject var model: AppModel
    let placeholder: String
    @Binding var text: String
    var multiline = false
    var focusTick = 0
    var onFocusChange: (Bool) -> Void = { _ in }
    let onSubmit: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text, prompt: Text(placeholder).foregroundColor(Theme.faint),
                  axis: multiline ? .vertical : .horizontal)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(Theme.text)
            .lineLimit(multiline ? 4 : 1)
            .focused($focused)
            .onSubmit(onSubmit)
            .onChange(of: focused) { _, f in
                model.editing = f
                onFocusChange(f)
            }
            .onChange(of: focusTick) { _, _ in focused = true }
            .onDisappear { model.editing = false }
    }
}

struct SourceGate<Content: View>: View {
    enum Pane {
        case reminders, automation
        var url: URL {
            URL(string: self == .reminders
                ? "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders"
                : "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
        }
    }

    let state: SourceState
    let what: String
    let pane: Pane
    @ViewBuilder let content: () -> Content

    var body: some View {
        switch state {
        case .denied:
            VStack(alignment: .leading, spacing: 8) {
                Text(L.s("还没有权限读写「\(what)」。", "NotchPad doesn't have access to \(what) yet."))
                    .foregroundStyle(Theme.text)
                Text(L.s("到 系统设置 › 隐私与安全性 里，把「刘海记」的开关打开，再回来就好。",
                         "Turn NotchPad on in System Settings › Privacy & Security, then come back."))
                    .foregroundStyle(Theme.dim)
                Button(L.s("打开系统设置", "Open System Settings")) { NSWorkspace.shared.open(pane.url) }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.cyan)
            }
            .font(.system(size: 12.5))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        case .failed(let message):
            Text(L.s("读取「\(what)」出错：\(message)", "Couldn't read \(what): \(message)"))
                .font(.system(size: 12))
                .foregroundStyle(Theme.dim)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        default:
            content()
        }
    }
}

struct Hint: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Theme.faint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, 10)
    }
}

/// 某一段是空的时候的一行灰字 / grey line shown in an empty section
struct EmptyLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(Theme.faint)
            .padding(.leading, 34)
            .padding(.vertical, 3)
    }
}

struct SectionHeader: View {
    let title: String
    var count: String?
    let color: Color
    var first = false
    var action: (() -> Void)?

    var body: some View {
        let label = HStack(spacing: 7) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
            if let count {
                Text(count)
                    .font(.system(size: 10.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Theme.faint)
            }
            Spacer()
        }
        .padding(.leading, 10)
        .padding(.top, first ? 4 : 12)
        .padding(.bottom, 3)
        .contentShape(Rectangle())

        if let action {
            Button(action: action) { label }
                .buttonStyle(.plain)
                .help(L.s("点一下，上面的输入框就加到这一段", "Click to make the input add to this section"))
        } else {
            label
        }
    }
}

/// 一段可以把条目拖进来的区域；拖到上面时亮一下
/// A section you can drop items onto; it lights up while hovered
struct DropSection<Content: View>: View {
    let accent: Color
    let drop: () -> Bool
    @ViewBuilder let content: () -> Content

    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(accent.opacity(targeted ? 0.08 : 0))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(accent.opacity(targeted ? 0.45 : 0), lineWidth: 1))
            )
            .contentShape(Rectangle())
            .onDrop(of: [UTType.plainText, UTType.utf8PlainText, UTType.text], isTargeted: $targeted) { _ in drop() }
            .animation(.easeOut(duration: 0.12), value: targeted)
    }
}

// MARK: - 待办行 / a checklist row

struct TodoRow<M: View>: View {
    @ObservedObject var model: AppModel
    let item: TodoItem
    let accent: Color
    let toggle: () -> Void
    var hint: String?
    @ViewBuilder let menu: () -> M

    @State private var hover = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: toggle) {
                ZStack {
                    // 做完的整行变灰：灰圈、灰勾、灰字加删除线
                    Circle().strokeBorder(item.done ? Theme.faint : accent, lineWidth: 1.3)
                    if item.done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 7, weight: .black))
                            .foregroundStyle(Theme.dim)
                    }
                }
                .frame(width: 14, height: 14)
                .frame(width: 20, height: 18)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(hint ?? "")

            if model.editingItemID == item.id {
                EditField(model: model, item: item)
                    .padding(.top, 1)
            } else {
                Text(item.title)
                    .font(.system(size: 13))
                    .foregroundStyle(item.done ? Theme.dim : Theme.text)
                    .strikethrough(item.done, color: Theme.dim)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 1)
                    .contentShape(Rectangle())
                    // 点一下文字就地修改 / click the text to edit it in place
                    .onTapGesture {
                        model.makeKey()
                        model.editingItemID = item.id
                    }
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(model.editingItemID == item.id ? Theme.field : (hover ? Theme.hover : .clear)))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .contextMenu { menu() }
        .modifier(RowDrag(model: model, item: item))
    }
}

/// 按住一条可以拖到别的段（拖到别的 app 里会粘贴标题）；正在改它的标题时不拖，好在输入框里选字
/// Drag a row to another section (or into another app to paste its title) — but not while its title is being edited
struct RowDrag: ViewModifier {
    @ObservedObject var model: AppModel
    let item: TodoItem

    func body(content: Content) -> some View {
        if model.editingItemID == item.id {
            content
        } else {
            content.onDrag {
                model.beginDrag(item)
                return NSItemProvider(object: item.title as NSString)
            }
        }
    }
}

/// 就地修改一条的标题：回车或点别处保存，Esc 取消；清空不保存
/// Edit a title in place: Return or clicking away saves, Esc cancels; an empty title is ignored
struct EditField: View {
    @ObservedObject var model: AppModel
    let item: TodoItem

    @State private var text: String
    @FocusState private var focused: Bool

    init(model: AppModel, item: TodoItem) {
        self.model = model
        self.item = item
        _text = State(initialValue: item.title)
    }

    var body: some View {
        TextField("", text: $text, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(Theme.text)
            .lineLimit(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .focused($focused)
            .onSubmit(commit)
            .onAppear {
                model.editing = true
                DispatchQueue.main.async { focused = true }
            }
            .onChange(of: focused) { was, now in
                if was, !now { commit() }
            }
            .onDisappear {
                commit()
                model.editing = false
            }
    }

    private func commit() {
        // Esc 取消时 editingItemID 已经被清掉，这里就不会保存
        // After Esc, editingItemID is already nil, so nothing is saved
        guard model.editingItemID == item.id else { return }
        model.editingItemID = nil
        model.rename(item, to: text)
    }
}

// MARK: - 流水线 / pipeline

struct PipelineView: View {
    @ObservedObject var model: AppModel
    let spec: TabSpec
    let index: Int

    @State private var draft = ""

    private var stages: [ListSpec] { spec.stages ?? [] }
    private var doneTitle: String { spec.doneTitle ?? L.s("完成", "Done") }

    var body: some View {
        let accent = model.accent(index)
        VStack(spacing: 8) {
            InputShell {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(accent)
                    .frame(width: 14)
                CaptureField(model: model, placeholder: spec.placeholder ?? L.s("写一条，回车保存", "Type and press Return"),
                             text: $draft) {
                    if let first = stages.first { model.add(draft, list: first.listName) }
                    draft = ""
                }
            }
            SourceGate(state: model.remindersState, what: L.s("提醒事项", "Reminders"), pane: .reminders) {
                if model.remindersState != .ready {
                    Hint(text: L.s("正在读取提醒事项…", "Loading Reminders…"))
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            // 按流程从上往下，完成的沉底 / top to bottom in order; done sinks to the end
                            ForEach(Array(stages.enumerated()), id: \.offset) { i, stage in
                                DropSection(accent: accent, drop: { model.drop(onList: stage.listName, undone: true) }) {
                                    stageRows(i, stage, accent)
                                }
                            }
                            DropSection(accent: accent, drop: { model.dropDone() }) {
                                doneRows(accent)
                            }
                        }
                    }
                    .scrollIndicators(.never)
                }
            }
        }
    }

    @ViewBuilder
    private func stageRows(_ i: Int, _ stage: ListSpec, _ accent: Color) -> some View {
        let items = model.openItems(stage.listName)
        let last = i + 1 == stages.count
        let next = last ? doneTitle : stages[i + 1].title
        SectionHeader(title: stage.title, count: items.isEmpty ? nil : "\(items.count)",
                      color: i == 0 ? Theme.text.opacity(0.75) : accent, first: i == 0)
        if items.isEmpty {
            EmptyLine(text: i == 0
                      ? L.s("想到什么，先在上面敲下来", "Type above to add one")
                      : L.s("拖到这里，或点上一段条目前面的圆圈", "Drag items here, or click a circle in the section above"))
        }
        ForEach(items) { item in
            TodoRow(model: model, item: item, accent: accent, toggle: { model.advance(item, in: spec) },
                    hint: last ? L.s("点一下标记「\(next)」", "Click to mark as “\(next)”")
                               : L.s("点一下移到「\(next)」", "Click to move to “\(next)”")) {
                ForEach(Array(stages.enumerated()), id: \.offset) { j, s in
                    if j != i {
                        Button(L.s("移到「\(s.title)」", "Move to “\(s.title)”")) { model.place(item, list: s.listName, done: false) }
                    }
                }
                Button(L.s("标记「\(doneTitle)」", "Mark as “\(doneTitle)”")) { model.place(item, list: item.list, done: true) }
                Divider()
                Button(L.s("删除", "Delete"), role: .destructive) { model.delete(item) }
            }
        }
    }

    @ViewBuilder
    private func doneRows(_ accent: Color) -> some View {
        let done = model.doneItems(spec)
        SectionHeader(title: doneTitle, count: L.s("本月 \(done.thisMonth)", "\(done.thisMonth) this month"), color: Theme.faint)
        ForEach(done.items) { item in
            let back = stages.first { $0.listName == item.list }?.title ?? stages.last?.title ?? ""
            TodoRow(model: model, item: item, accent: accent, toggle: { model.advance(item, in: spec) },
                    hint: L.s("点一下退回「\(back)」", "Click to move back to “\(back)”")) {
                ForEach(Array(stages.enumerated()), id: \.offset) { _, s in
                    Button(L.s("退回「\(s.title)」", "Move back to “\(s.title)”")) { model.place(item, list: s.listName, done: false) }
                }
                Divider()
                Button(L.s("删除", "Delete"), role: .destructive) { model.delete(item) }
            }
        }
    }
}

// MARK: - 分段清单 / sections

struct SectionsView: View {
    @ObservedObject var model: AppModel
    let spec: TabSpec
    let index: Int

    @State private var draft = ""

    private var sections: [ListSpec] { spec.sections ?? [] }

    var body: some View {
        let target = min(model.sectionTarget[index] ?? 0, max(0, sections.count - 1))
        let colors = sections.indices.map { model.sectionColor(spec, $0) }
        let multiple = sections.count > 1
        VStack(spacing: 8) {
            if let pinned = spec.pinned {
                PinnedCard(model: model, spec: pinned, state: model.pinned[index])
            }
            if !sections.isEmpty {
                InputShell {
                    if multiple {
                        Circle().fill(colors[target]).frame(width: 7, height: 7).frame(width: 14)
                    } else {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(model.accent(index))
                            .frame(width: 14)
                    }
                    CaptureField(model: model,
                                 placeholder: spec.placeholder ?? (multiple
                                    ? L.s("加到「\(sections[target].title)」，回车保存", "Add to “\(sections[target].title)” — press Return")
                                    : L.s("写一条，回车保存", "Type and press Return")),
                                 text: $draft) {
                        model.add(draft, list: sections[target].listName)
                        draft = ""
                    }
                    if multiple { picker(target, colors) }
                }
            }
            SourceGate(state: model.remindersState, what: L.s("提醒事项", "Reminders"), pane: .reminders) {
                if model.remindersState != .ready {
                    Hint(text: L.s("正在读取提醒事项…", "Loading Reminders…"))
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(sections.enumerated()), id: \.offset) { i, section in
                                DropSection(accent: colors[i], drop: { model.drop(onList: section.listName, undone: false) }) {
                                    sectionRows(i, section, colors[i], multiple)
                                }
                            }
                        }
                    }
                    .scrollIndicators(.never)
                }
            }
        }
    }

    /// 输入框右边的小圆点：选这一条加到哪一段 / dots that pick the target section
    private func picker(_ target: Int, _ colors: [Color]) -> some View {
        HStack(spacing: 2) {
            ForEach(Array(sections.enumerated()), id: \.offset) { i, section in
                Button { model.sectionTarget[index] = i } label: {
                    Circle()
                        .fill(colors[i].opacity(target == i ? 1 : 0.3))
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(colors[i], lineWidth: 1).padding(-3).opacity(target == i ? 1 : 0))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(section.title)
            }
        }
    }

    @ViewBuilder
    private func sectionRows(_ i: Int, _ section: ListSpec, _ color: Color, _ multiple: Bool) -> some View {
        let items = model.items(section.listName)
        let open = items.filter { !$0.done }.count
        if multiple {
            SectionHeader(title: section.title, count: open > 0 ? "\(open)" : nil, color: color, first: i == 0) {
                model.sectionTarget[index] = i
            }
        } else if items.isEmpty {
            EmptyLine(text: L.s("还没有待办。在上面写一条试试。", "Nothing here yet. Add one above."))
        }
        ForEach(items) { item in
            TodoRow(model: model, item: item, accent: color, toggle: { model.toggle(item) }) {
                ForEach(Array(sections.enumerated()), id: \.offset) { j, s in
                    if j != i {
                        Button(L.s("移到「\(s.title)」", "Move to “\(s.title)”")) { model.place(item, list: s.listName, done: item.done) }
                    }
                }
                if multiple { Divider() }
                Button(L.s("删除", "Delete"), role: .destructive) { model.delete(item) }
            }
        }
    }
}

// MARK: - 置顶卡片 / pinned card

struct PinnedCard: View {
    @ObservedObject var model: AppModel
    let spec: PinnedSpec
    let state: PinnedState?

    private let columns = [
        GridItem(.flexible(), spacing: 16, alignment: .leading),
        GridItem(.flexible(), spacing: 16, alignment: .leading),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text(spec.title ?? spec.heading)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.text)
                if let list = state?.list, let label = list.monthLabel {
                    Text(list.isStale ? L.s("\(label) · 该更新了", "\(label) · time to update") : label)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(list.isStale ? Theme.amber : Theme.faint)
                }
                Spacer()
                Button { model.openPinned(spec) } label: {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.faint)
                        .frame(width: 18, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L.s("打开这个文件", "Open this file"))
            }

            if let items = state?.list?.items, !items.isEmpty {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 5) {
                    ForEach(items) { PinnedCell(item: $0) }
                }
            } else {
                let name = (spec.path as NSString).lastPathComponent
                Text(state?.error ?? L.s("在 \(name) 里写一节「## \(spec.heading)」，就会显示在这里。",
                                         "Add a “## \(spec.heading)” section to \(name) to show it here."))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.faint)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
    }
}

struct PinnedCell: View {
    let item: PinnedItem

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let tag = item.tag {
                Text(tag)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
                    .frame(width: L.zh ? 24 : 50, alignment: .leading)
            }
            Text(item.text)
                .font(.system(size: 12))
                .foregroundStyle(item.done ? Theme.faint : Theme.text.opacity(0.88))
                .strikethrough(item.done, color: Theme.faint)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(item.text)
    }
}

// MARK: - 速记 / jots

struct JotsView: View {
    @ObservedObject var model: AppModel
    let spec: TabSpec
    let index: Int

    @State private var draft = ""
    @State private var stamp: Date?

    var body: some View {
        let accent = model.accent(index)
        let folder = spec.folderName
        let jots = model.jots[folder] ?? []
        VStack(spacing: 8) {
            InputShell(alignment: .firstTextBaseline) {
                // 一点进输入框，就把这一刻的时间记下来 / the moment you click in, the time is stamped
                Group {
                    if let stamp {
                        Text(Fmt.time.string(from: stamp))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    } else {
                        Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                    }
                }
                .foregroundStyle(accent)
                .frame(width: 40, alignment: .leading)
                CaptureField(model: model,
                             placeholder: spec.placeholder ?? L.s("想到什么，写下来，或点右边的话筒说出来",
                                                                  "Jot it down, or click the mic to dictate"),
                             text: $draft, multiline: true, focusTick: model.jotFocusTick,
                             onFocusChange: { focused in
                                 if focused, draft.isEmpty { stamp = Date() }
                                 if !focused, draft.isEmpty { stamp = nil }
                             }) {
                    model.addJot(draft, folder: folder)
                    draft = ""
                    stamp = Date()
                }
                Button { model.dictate() } label: {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(accent)
                        .frame(width: 22, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L.s("语音输入（也可以直接按键盘上的 🎤 键）", "Dictate (or press the 🎤 key)"))
            }
            SourceGate(state: model.notesState, what: L.s("备忘录", "Notes"), pane: .automation) {
                if jots.isEmpty {
                    Hint(text: model.notesState == .ready
                         ? L.s("还没有记录。点上面，写一句或说一句。", "Nothing yet. Click above to write or dictate.")
                         : L.s("正在打开备忘录…", "Opening Notes…"))
                } else {
                    list(jots, folder: folder, accent: accent)
                }
            }
        }
    }

    private func list(_ jots: [Jot], folder: String, accent: Color) -> some View {
        let cal = Calendar.current
        let groups = Dictionary(grouping: jots) { cal.startOfDay(for: $0.date) }
            .sorted { $0.key > $1.key }
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(groups, id: \.key) { day, items in
                    Text(Fmt.dayLabel(day))
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Theme.faint)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                        .padding(.bottom, 2)
                    ForEach(items) { jot in
                        JotRow(jot: jot, accent: accent, open: { model.openJot(jot) },
                               delete: { model.deleteJot(jot, folder: folder) })
                    }
                }
            }
        }
        .scrollIndicators(.never)
    }
}

struct JotRow: View {
    let jot: Jot
    let accent: Color
    let open: () -> Void
    let delete: () -> Void

    @State private var hover = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(Fmt.time.string(from: jot.date))
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .foregroundStyle(accent.opacity(0.75))
                .frame(width: 40, alignment: .leading)
            Text(jot.headline)
                .font(.system(size: 13))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(hover ? Theme.hover : .clear))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .help(jot.text)
        .onTapGesture(perform: open)
        .contextMenu {
            Button(L.s("在备忘录中打开", "Open in Notes"), action: open)
            Button(L.s("删除（移到最近删除）", "Delete (moves to Recently Deleted)"), role: .destructive, action: delete)
        }
    }
}
