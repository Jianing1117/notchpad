import Foundation
import SwiftUI

/// `--demo`：只在内存里的示例数据，不碰提醒事项和备忘录（截图、试用时用）
/// In-memory sample data for `--demo`; never touches Reminders or Notes.
enum DemoData {
    /// 列表名 → 示例条目（标题, 几分钟前建的, 是否做完）
    static let todos: [String: [(String, Double, Bool)]] = [
        // 创作者（中文）
        "选题": [("为什么我开始用纸质笔记本", 30, false), ("一个人做内容，怎么安排一周", 300, false),
                ("新手剪辑最容易踩的三个坑", 1500, false), ("我的桌面整理前后对比", 4000, true)],
        "待拍": [("读完《原子习惯》的五个改变", 800, false), ("周末城市散步 vlog", 2400, false)],
        "重要紧急": [("周五前交方案", 60, false), ("回复合作邮件", 90, true)],
        "重要不紧急": [("整理本月素材库", 200, false), ("学一下调色", 400, false)],
        "紧急不重要": [("取快递", 20, false)],
        // Creator (English)
        "Content Ideas": [("Why I switched to a paper notebook", 30, false), ("Planning a solo creator's week", 300, false),
                          ("3 editing mistakes beginners make", 1500, false), ("Desk makeover before/after", 4000, true)],
        "Ready to Film": [("5 changes after reading Atomic Habits", 800, false), ("Weekend city walk vlog", 2400, false)],
        "Urgent & Important": [("Send the proposal by Friday", 60, false), ("Reply to the sponsor email", 90, true)],
        "Important, Not Urgent": [("Sort this month's footage", 200, false), ("Learn color grading basics", 400, false)],
        "Urgent, Not Important": [("Pick up the parcel", 20, false)],
        // 学生 / Student
        "作业·待开始": [("统计学第 5 章习题", 100, false), ("小组展示分工", 600, false)],
        "作业·进行中": [("期中论文初稿", 900, false)],
        "今天": [("复习线性代数", 30, false), ("去图书馆还书", 80, true)],
        "本周": [("报名比赛", 300, false)],
        "Assignments · To Start": [("Stats chapter 5 problems", 100, false), ("Group presentation roles", 600, false)],
        "Assignments · In Progress": [("Midterm essay draft", 900, false)],
        "Today": [("Review linear algebra", 30, false), ("Return library books", 80, true)],
        "This Week": [("Sign up for the case competition", 300, false)],
        // 极简 / Minimal
        "待办": [("买咖啡豆", 30, false), ("给妈妈打电话", 120, false), ("交水电费", 300, true)],
        "To Do": [("Buy coffee beans", 30, false), ("Call mom", 120, false), ("Pay the utility bill", 300, true)],
    ]

    /// 示例随手记：（内容, 哪天, 几点几分）；0 = 今天，-1 = 昨天
    static let jots: [(String, Int, Int, Int)] = L.zh
        ? [("地铁上看到的广告文案，可以拆成一期", 0, 9, 12), ("选题不是想出来的，是记下来的。后面可以展开讲讲", 0, 8, 5),
           ("睡前别刷手机", -1, 22, 40), ("朋友说的「先完成再完美」，适合做开头", -1, 14, 5)]
        : [("That subway ad copy could be a whole episode", 0, 9, 12), ("Ideas aren't thought up, they're written down. Expand later", 0, 8, 5),
           ("No phone before bed", -1, 22, 40), ("A friend said “done beats perfect” — good opener", -1, 14, 5)]

    static var pinned: PinnedList {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        let text = L.s("""
        ## 本月重点 (\(f.string(from: Date())))
        - 【内容】每周发两条视频
        - 【内容】把素材库整理好
        - [x] 【学习】剪辑课学完
        - 【生活】每天散步 30 分钟
        """, """
        ## This Month (\(f.string(from: Date())))
        - [Content] Publish two videos a week
        - [Content] Organize the footage library
        - [x] [Learning] Finish the editing course
        - [Life] Walk 30 minutes a day
        """)
        return PinnedFile.parse(text, heading: L.s("本月重点", "This Month"))
    }
}

@MainActor
final class DemoTodos: TodoBackend {
    private var data: [String: [TodoItem]] = [:]

    init() {
        let now = Date()
        for (list, rows) in DemoData.todos {
            data[list] = rows.map { title, minutesAgo, done in
                TodoItem(id: UUID().uuidString, title: title, done: done,
                         created: now.addingTimeInterval(-minutesAgo * 60),
                         completed: done ? now.addingTimeInterval(-minutesAgo * 20) : nil, list: list)
            }
        }
    }

    var authorized: Bool { true }
    func start(onChange: @escaping () -> Void) async -> SourceState { .ready }
    func ensureLists(_ lists: [(name: String, color: Color)]) {}
    func items(list: String, doneSince: Date) async -> [TodoItem] { data[list] ?? [] }

    func add(_ title: String, list: String) async -> TodoItem? {
        let item = TodoItem(id: UUID().uuidString, title: title, done: false, created: Date(), completed: nil, list: list)
        data[list, default: []].insert(item, at: 0)
        return item
    }

    func setDone(id: String, _ done: Bool) async {
        for key in data.keys {
            guard let i = data[key]?.firstIndex(where: { $0.id == id }) else { continue }
            data[key]?[i].done = done
            data[key]?[i].completed = done ? Date() : nil
        }
    }

    func delete(id: String) async {
        for key in data.keys { data[key]?.removeAll { $0.id == id } }
    }

    func move(id: String, toList list: String) async {
        for key in data.keys {
            guard var item = data[key]?.first(where: { $0.id == id }) else { continue }
            data[key]?.removeAll { $0.id == id }
            item.list = list
            data[list, default: []].append(item)
            return
        }
    }
}

@MainActor
final class DemoJots: JotBackend {
    private var jots: [Jot] = DemoData.jots.enumerated().map { i, row in
        let cal = Calendar.current
        let day = cal.date(byAdding: .day, value: row.1, to: Date()) ?? Date()
        return Jot(id: "\(i)", text: row.0, date: cal.date(bySettingHour: row.2, minute: row.3, second: 0, of: day) ?? day)
    }

    func list(folder: String) async -> Result<[Jot], BackendError> { .success(jots) }

    func add(_ text: String, folder: String) async -> Result<Void, BackendError> {
        jots.insert(Jot(id: UUID().uuidString, text: text, date: Date()), at: 0)
        return .success(())
    }

    func open(id: String) async {}

    func delete(id: String) async { jots.removeAll { $0.id == id } }
}
