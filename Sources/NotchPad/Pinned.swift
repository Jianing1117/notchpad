import Foundation

/// 置顶卡片：只读 Markdown 文件里某个「## 标题」下面的列表，不写回。
/// Pinned card: reads (never writes) the bullet list under one "## heading" of a Markdown file.
///
///     ## 本月重点 (2026-10)
///     - 【IP】每周发两条内容
///     - [x] 已经做完的会变灰
struct PinnedItem: Identifiable, Equatable {
    let id: Int
    let tag: String?
    let text: String
    let done: Bool
}

struct PinnedList: Equatable {
    /// 标题里的年月，比如 "2026-10" / year-month found in the heading
    var month: String?
    var items: [PinnedItem]

    /// 「10月」/ "Oct"
    var monthLabel: String? {
        guard let month, let m = Int(month.split(separator: "-").last ?? "") else { return nil }
        return Fmt.month(m)
    }

    /// 标题里的月份不是这个月了，提醒一下该更新 / the heading's month has passed
    var isStale: Bool {
        guard let month else { return false }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        return month != f.string(from: Date())
    }
}

enum PinnedFile {
    static func load(_ path: String, heading: String) -> Result<PinnedList, BackendError> {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            let name = (path as NSString).lastPathComponent
            return .failure(BackendError(message: L.s("读不到 \(name)", "Can't read \(name)")))
        }
        return .success(parse(text, heading: heading))
    }

    static func parse(_ text: String, heading: String) -> PinnedList {
        var inSection = false
        var result = PinnedList(month: nil, items: [])

        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") {
                if inSection { break }   // 下一个标题，这一节结束 / next heading ends the section
                if line.contains(heading) {
                    inSection = true
                    if let r = line.range(of: #"\d{4}-\d{1,2}"#, options: .regularExpression) {
                        result.month = String(line[r])
                    }
                }
                continue
            }
            guard inSection, line.hasPrefix("- ") || line.hasPrefix("* ") else { continue }

            var body = String(line.dropFirst(2))
            var done = false
            if body.hasPrefix("[ ]") {
                body = String(body.dropFirst(3))
            } else if body.lowercased().hasPrefix("[x]") {
                body = String(body.dropFirst(3))
                done = true
            }
            body = body.trimmingCharacters(in: .whitespaces)

            // 【IP】或 [Work] 当标签
            var tag: String?
            for (open, close) in [("【", "】"), ("[", "]")] where body.hasPrefix(open) {
                if let end = body.firstIndex(of: Character(close)), end > body.index(after: body.startIndex) {
                    tag = String(body[body.index(after: body.startIndex)..<end])
                    body = String(body[body.index(after: end)...]).trimmingCharacters(in: .whitespaces)
                }
                break
            }
            if !body.isEmpty {
                result.items.append(PinnedItem(id: result.items.count, tag: tag, text: body, done: done))
            }
        }
        return result
    }
}
