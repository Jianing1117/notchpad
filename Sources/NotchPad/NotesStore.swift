import Foundation

/// 速记存在「备忘录 › iCloud › 配置里写的文件夹」里，一个想法一条笔记。
/// 备忘录没有开放给第三方的接口，只能通过系统自带的 osascript（JavaScript 版）去控制备忘录 app。
/// 只做新建、读取、打开、删除（删除 = 移到「最近删除」），从不改写已有笔记，
/// 所以手机上那条笔记里加了图片、清单也不会被冲掉。
///
/// Jots are stored as one note per thought in a Notes folder (iCloud account). Notes has no
/// public API, so this drives the Notes app through the built-in osascript (JavaScript).
/// It only creates, reads, opens and deletes (= moves to Recently Deleted) — it never rewrites
/// an existing note, so images or checklists you add on iPhone are safe.
@MainActor
final class NotesStore: JotBackend {
    func list(folder: String) async -> Result<[Jot], BackendError> {
        let script = """
        function run(argv) {
          const Notes = Application('Notes');
          const notes = folder(Notes, argv[0]).notes;
          const ids = notes.id(), texts = notes.plaintext(), dates = notes.creationDate();
          const out = [];
          for (let i = 0; i < ids.length; i++) out.push({ id: ids[i], text: texts[i], t: dates[i].getTime() });
          return JSON.stringify(out);
        }
        """
        let result = await Self.run(script, [folder])
        return result.flatMap { json in
            struct Row: Decodable { let id: String; let text: String; let t: Double }
            guard let data = json.data(using: .utf8),
                  let rows = try? JSONDecoder().decode([Row].self, from: data)
            else { return .failure(BackendError(message: L.s("读不懂备忘录返回的内容", "Unexpected reply from Notes"))) }
            return .success(rows.map {
                Jot(id: $0.id, text: Self.clean($0.text), date: Date(timeIntervalSince1970: $0.t / 1000))
            })
        }
    }

    func add(_ text: String, folder: String) async -> Result<Void, BackendError> {
        let script = """
        function run(argv) {
          const Notes = Application('Notes');
          folder(Notes, argv[0]).notes.push(Notes.Note({ body: argv[1] }));
          return 'ok';
        }
        """
        return await Self.run(script, [folder, Self.html(text)]).map { _ in () }
    }

    func open(id: String) async {
        let script = """
        function run(argv) {
          const Notes = Application('Notes');
          Notes.show(Notes.notes.byId(argv[0]));
          Notes.activate();
          return 'ok';
        }
        """
        _ = await Self.run(script, [id])
    }

    func delete(id: String) async {
        let script = """
        function run(argv) {
          const Notes = Application('Notes');
          Notes.delete(Notes.notes.byId(argv[0]));
          return 'ok';
        }
        """
        _ = await Self.run(script, [id])
    }

    // MARK: -

    /// 找 iCloud 账户下的那个文件夹，没有就建一个 / find (or create) the folder in the iCloud account
    nonisolated private static let helpers = """
    function account(Notes) {
      try { const a = Notes.accounts.byName('iCloud'); a.id(); return a; }
      catch (e) { return Notes.defaultAccount(); }
    }
    function folder(Notes, name) {
      const acc = account(Notes);
      const i = acc.folders.name().indexOf(name);
      if (i >= 0) return acc.folders[i];
      acc.folders.push(Notes.Folder({ name: name }));
      return acc.folders.byName(name);
    }
    """

    /// 在后台线程跑 osascript，用户输入的文字走参数传进去，不拼进脚本
    /// Runs osascript off the main thread; user text is passed as arguments, never spliced into the script
    nonisolated private static func run(_ body: String, _ args: [String]) async -> Result<String, BackendError> {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                p.arguments = ["-l", "JavaScript", "-e", helpers + "\n" + body] + args
                let out = Pipe(), err = Pipe()
                p.standardOutput = out
                p.standardError = err
                do { try p.run() } catch {
                    cont.resume(returning: .failure(BackendError(message: error.localizedDescription)))
                    return
                }
                let o = out.fileHandleForReading.readDataToEndOfFile()
                let e = err.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()

                let stdout = String(decoding: o, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                let stderr = String(decoding: e, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                if p.terminationStatus == 0 {
                    cont.resume(returning: .success(stdout))
                } else {
                    let denied = stderr.contains("-1743") || stderr.contains("-10004")
                    cont.resume(returning: .failure(BackendError(message: stderr, denied: denied)))
                }
            }
        }
    }

    private static func html(_ text: String) -> String {
        text.components(separatedBy: .newlines).map { line in
            let escaped = line
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            return "<div>\(escaped.isEmpty ? "<br>" : escaped)</div>"
        }.joined()
    }

    /// 去掉首尾空白和多余空行
    private static func clean(_ text: String) -> String {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}
