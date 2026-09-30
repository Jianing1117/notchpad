import Foundation

/// 界面语言：先看配置文件里的 "language"，没写就跟系统（系统首选语言是中文就用中文，否则英文）。
/// UI language: the config's "language" if set, otherwise the system's (Chinese if the first
/// preferred language is Chinese, else English). `--lang zh|en` overrides both (for screenshots).
enum L {
    static let zh: Bool = {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--lang"), i + 1 < args.count { return args[i + 1].hasPrefix("zh") }
        if let saved = ConfigStore.savedLanguage { return saved.hasPrefix("zh") }
        return Locale.preferredLanguages.first?.hasPrefix("zh") ?? false
    }()

    static func s(_ zh: String, _ en: String) -> String { Self.zh ? zh : en }
}

enum Fmt {
    private static let locale = Locale(identifier: L.zh ? "zh_CN" : "en_US")

    static let today = formatter(L.zh ? "M月d日 EEE" : "EEE, MMM d")
    static let time = formatter("HH:mm")
    private static let day = formatter(L.zh ? "M月d日 EEE" : "EEE, MMM d")

    static func dayLabel(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return L.s("今天", "Today") }
        if cal.isDateInYesterday(d) { return L.s("昨天", "Yesterday") }
        return day.string(from: d)
    }

    /// 9 → 「9月」/ "Sep"
    static func month(_ m: Int) -> String {
        guard (1...12).contains(m) else { return "" }
        return L.zh ? "\(m)月" : formatter("MMM").shortMonthSymbols[m - 1]
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = locale
        f.dateFormat = format
        return f
    }
}
