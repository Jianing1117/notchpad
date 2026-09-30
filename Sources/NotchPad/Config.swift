import AppKit
import Foundation

/// 配置文件：~/Library/Application Support/NotchPad/config.json
/// 刘海里有几个 tab、每个 tab 是哪种积木、对应提醒事项的哪个列表 / 备忘录的哪个文件夹，都写在这里。
/// 改完保存，下次展开刘海就生效。格式说明见 docs/config.md。
///
/// The config file decides which tabs you get, what kind each one is, and which
/// Reminders lists / Notes folder it uses. Save it and the next hover picks it up.
/// See docs/config.en.md.
struct AppConfig: Codable, Equatable {
    /// "zh" 或 "en"；不写就跟系统 / "zh" or "en"; follows the system when absent
    var language: String?
    var tabs: [TabSpec]
    var panel: PanelSpec?
}

struct PanelSpec: Codable, Equatable {
    var width: Double?
    var height: Double?
}

struct TabSpec: Codable, Equatable {
    enum Kind: String, Codable {
        /// 流水线：几段按顺序往下走，最后是「完成」/ stages you move items through, then "done"
        case pipeline
        /// 分段清单：几段并列，勾掉就完成 / parallel sections of a checklist
        case sections
        /// 速记：写进备忘录的一个文件夹 / quick notes saved to a Notes folder
        case jots
    }

    var type: Kind
    var title: String
    var color: String?
    var placeholder: String?
    /// pipeline
    var stages: [ListSpec]?
    var doneTitle: String?
    /// sections
    var sections: [ListSpec]?
    var pinned: PinnedSpec?
    /// jots
    var folder: String?

    var folderName: String { folder ?? title }
}

struct ListSpec: Codable, Equatable {
    var title: String
    /// 提醒事项里的列表名，不写就和 title 一样 / Reminders list name; defaults to title
    var list: String?
    var color: String?

    var listName: String { list ?? title }
}

/// 置顶卡片：读一个 Markdown 文件里某个标题下面的列表
/// Pinned card: shows the bullet list under one heading of a Markdown file
struct PinnedSpec: Codable, Equatable {
    var title: String?
    var file: String
    var heading: String

    /// 以 / 或 ~ 开头是完整路径；否则算在配置文件旁边（比如 "goals.md"）
    /// A path starting with / or ~ is absolute; anything else is next to config.json (e.g. "goals.md")
    var path: String {
        if file.hasPrefix("/") || file.hasPrefix("~") { return NSString(string: file).expandingTildeInPath }
        return ConfigStore.dir.appendingPathComponent(file).path
    }
}

enum ConfigStore {
    struct Loaded {
        var config: AppConfig
        /// 配置文件有问题时给用户看的一句话 / shown in the panel when the file has a problem
        var notice: String?
    }

    static let presets = ["creator", "student", "minimal"]

    static func presetTitle(_ name: String) -> String {
        switch name {
        case "creator": L.s("创作者：选题 / 随手记 / Todo", "Creator: Ideas / Jots / Todo")
        case "student": L.s("学生：作业 / 灵感 / Todo", "Student: Assignments / Ideas / Todo")
        case "minimal": L.s("极简：待办 / 随手记", "Minimal: To Do / Jots")
        default: name
        }
    }

    /// 环境变量 NOTCHPAD_CONFIG_DIR 可以换个地方放配置（测试用）
    /// NOTCHPAD_CONFIG_DIR overrides the folder (for testing)
    static var dir: URL {
        if let custom = ProcessInfo.processInfo.environment["NOTCHPAD_CONFIG_DIR"] {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/NotchPad", isDirectory: true)
    }
    static var file: URL { dir.appendingPathComponent("config.json") }
    static var backup: URL { dir.appendingPathComponent("config.backup.json") }

    /// 读配置；第一次运行时按系统语言写一份「创作者」预设
    static func load() -> Loaded {
        guard FileManager.default.fileExists(atPath: file.path) else {
            write(preset: "creator")
            return preset("creator")
        }
        do {
            let data = try Data(contentsOf: file)
            let config = try decode(data)
            return Loaded(config: config, notice: nil)
        } catch {
            let fallback = preset("creator").config
            return Loaded(config: fallback, notice: L.s(
                "配置文件有误，先用默认配置。\(describe(error))",
                "Couldn't read config.json, using the default for now. \(describe(error))"))
        }
    }

    /// 只在内存里用某个预设（截图、演示时用），不碰配置文件
    static func preset(_ name: String) -> Loaded {
        let lang = L.zh ? "zh" : "en"
        if let url = Bundle.main.url(forResource: "\(name).\(lang)", withExtension: "json", subdirectory: "presets"),
           let data = try? Data(contentsOf: url), let config = try? decode(data) {
            return Loaded(config: config)
        }
        return Loaded(config: builtIn)
    }

    /// 换成某个预设：原来的配置先备份到 config.backup.json
    static func write(preset name: String) {
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        if fm.fileExists(atPath: file.path) {
            try? fm.removeItem(at: backup)
            try? fm.copyItem(at: file, to: backup)
        }
        let lang = L.zh ? "zh" : "en"
        if let url = Bundle.main.url(forResource: "\(name).\(lang)", withExtension: "json", subdirectory: "presets") {
            try? Data(contentsOf: url).write(to: file)
        } else if let data = try? JSONEncoder.pretty.encode(builtIn) {
            try? data.write(to: file)
        }
        ensurePinnedTemplates(preset(name).config)
    }

    /// 配置文件里写的界面语言（在读完整配置之前就要知道）
    /// The UI language saved in the config (needed before the full config is read)
    static var savedLanguage: String? {
        guard let data = try? Data(contentsOf: file),
              let json = try? JSONSerialization.jsonObject(with: Data(straightenQuotes(data).utf8)) as? [String: Any]
        else { return nil }
        return json["language"] as? String
    }

    /// 只改 "language" 这一项，其他内容和排版原样保留
    /// Changes only "language", leaving the rest of the file exactly as it was
    static func setLanguage(_ code: String) {
        _ = load()   // 确保文件存在 / make sure the file exists
        guard var text = try? String(contentsOf: file, encoding: .utf8) else { return }
        text = straightenQuotes(Data(text.utf8))
        if let r = text.range(of: #""language"\s*:\s*"[^"]*""#, options: .regularExpression) {
            text.replaceSubrange(r, with: "\"language\": \"\(code)\"")
        } else if let brace = text.firstIndex(of: "{") {
            text.insert(contentsOf: "\n  \"language\": \"\(code)\",", at: text.index(after: brace))
        }
        try? text.write(to: file, atomically: true, encoding: .utf8)
    }

    static func modificationDate() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date
    }

    /// 置顶卡片指向 App 自己文件夹里的 goals.md、而它还不存在时，放一份带说明的样板
    static func ensurePinnedTemplates(_ config: AppConfig) {
        for spec in config.tabs.compactMap(\.pinned) {
            let path = spec.path
            guard path.hasPrefix(dir.path), !FileManager.default.fileExists(atPath: path) else { continue }
            let month = { let f = DateFormatter(); f.dateFormat = "yyyy-MM"; return f.string(from: Date()) }()
            let text = L.s("""
            # 目标

            刘海里 Todo 顶上的「置顶卡片」读的就是下面这一节。
            每行一条，前面可以用【】加一个标签。标题里写上年月，过了这个月会提醒你更新。

            ## \(spec.heading) (\(month))
            - 【示例】把这一行改成你这个月最重要的事
            - 【IP】每周发两条内容

            """, """
            # Goals

            The pinned card at the top of the Todo tab shows the section below.
            One item per line; add a tag in [brackets] if you like. Keep the year-month in
            the heading and NotchPad will remind you when the month is over.

            ## \(spec.heading) (\(month))
            - [Example] Replace this with the most important thing this month
            - [Content] Publish twice a week

            """)
            try? text.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    // MARK: -

    /// 用文本编辑器改 JSON 时，引号很容易被自动换成弯引号，这里先换回来
    private static func decode(_ data: Data) throws -> AppConfig {
        normalize(try JSONDecoder().decode(AppConfig.self, from: Data(straightenQuotes(data).utf8)))
    }

    private static func straightenQuotes(_ data: Data) -> String {
        var text = String(decoding: data, as: UTF8.self)
        for (curly, straight) in [("\u{201C}", "\""), ("\u{201D}", "\""), ("\u{2018}", "'"), ("\u{2019}", "'")] {
            text = text.replacingOccurrences(of: curly, with: straight)
        }
        return text
    }

    /// 补上空缺，去掉放不下的：最多 5 个 tab；流水线、分段至少有一段
    private static func normalize(_ config: AppConfig) -> AppConfig {
        var c = config
        c.tabs = Array(c.tabs.prefix(5)).map { tab in
            var t = tab
            if t.type == .pipeline, (t.stages ?? []).isEmpty { t.stages = [ListSpec(title: t.title)] }
            if t.type == .sections, (t.sections ?? []).isEmpty { t.sections = [ListSpec(title: t.title)] }
            return t
        }
        if c.tabs.isEmpty { c.tabs = builtIn.tabs }
        return c
    }

    private static func describe(_ error: Error) -> String {
        if case DecodingError.dataCorrupted(let ctx) = error {
            return (ctx.underlyingError as NSError?)?.userInfo[NSDebugDescriptionErrorKey] as? String ?? ctx.debugDescription
        }
        if case DecodingError.keyNotFound(let key, _) = error { return L.s("缺少「\(key.stringValue)」", "Missing “\(key.stringValue)”") }
        if case DecodingError.typeMismatch(_, let ctx) = error { return ctx.debugDescription }
        if case DecodingError.valueNotFound(_, let ctx) = error { return ctx.debugDescription }
        return error.localizedDescription
    }

    /// 找不到预设文件时（比如直接 swift run）用的最小配置
    private static let builtIn = AppConfig(tabs: [
        TabSpec(type: .sections, title: L.s("待办", "To Do"), sections: [ListSpec(title: L.s("待办", "To Do"))]),
        TabSpec(type: .jots, title: L.s("随手记", "Jots"), folder: L.s("随手记", "Quick Jots")),
    ])
}

extension JSONEncoder {
    static var pretty: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }
}
