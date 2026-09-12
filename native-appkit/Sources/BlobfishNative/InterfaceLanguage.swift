import Foundation

/// Keep interpolation values out of character conversion: names, messages,
/// paths and labels belong to the user, not to the interface dictionary.
struct InterfaceText: ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
    var parts: [(text: String, literal: Bool)]
    init(stringLiteral value: String) { parts = [(value, true)] }
    init(stringInterpolation: StringInterpolation) { parts = stringInterpolation.parts }
    struct StringInterpolation: StringInterpolationProtocol {
        var parts: [(text: String, literal: Bool)] = []
        init(literalCapacity: Int, interpolationCount: Int) {}
        mutating func appendLiteral(_ literal: String) { parts.append((literal, true)) }
        mutating func appendInterpolation<T>(_ value: T) { parts.append((String(describing: value), false)) }
    }
    func rendered(locale: String) -> String {
        parts.map { $0.literal ? InterfaceLanguage.authored($0.text, locale: locale) : $0.text }.joined()
    }
}

enum InterfaceLanguage {
    static let supported = ["zh-CN", "zh-HK", "en"]
    static func normalize(_ locale: String) -> String { supported.contains(locale) ? locale : "zh-CN" }
    private static let cache: NSCache<NSString, NSString> = {
        let cache = NSCache<NSString, NSString>()
        cache.countLimit = 1024
        return cache
    }()
    static func text(_ zh: InterfaceText, _ en: InterfaceText, locale: String) -> String {
        (locale == "en" ? en : zh).rendered(locale: locale)
    }
    static func integrationDetail(_ source: String, locale: String) -> String {
        let translations = [
            "连接管理器不可用": "Connection manager unavailable",
            "不支持的连接": "Unsupported connection",
            "已连接，并收到过真实任务状态": "Connected; live task events received",
            "已安装；请在 Codex 的 /hooks 允许水滴鱼，然后继续一次任务": "Installed; allow Blobfish in Codex /hooks, then continue a task",
            "已安装；重新打开 Claude Code 会话后继续一次任务": "Installed; reopen Claude Code, then continue a task",
            "尚未安装状态插件": "Status plugin not installed"
        ]
        if let english = translations[source] {
            return locale == "en" ? english : authored(source, locale: locale)
        }
        if source.hasPrefix("检查失败：") {
            let detail = String(source.dropFirst("检查失败：".count))
            return text("检查失败：\(detail)", "Check failed: \(detail)", locale: locale)
        }
        if source.hasPrefix("未找到 "), source.hasSuffix(" 命令行工具") {
            let cli = String(source.dropFirst("未找到 ".count).dropLast(" 命令行工具".count))
            return text("未找到 \(cli) 命令行工具", "\(cli) command-line tool not found", locale: locale)
        }
        return source
    }
    /// Only pass product-authored labels here, never user-entered content.
    static func authored(_ source: String, locale: String) -> String {
        guard locale != "en", source.range(of: #"[\u3400-\u9fff]"#, options: .regularExpression) != nil else { return source }
        let key = (locale + "|" + source) as NSString
        if let cached = cache.object(forKey: key) { return cached as String }
        let simplified = NativeLocalization.simplified(source)
        var result = simplified
        if locale == "zh-HK" {
            result = simplified.applyingTransform(StringTransform("Simplified-Traditional"), reverse: false) ?? simplified
            // Hong Kong interface terminology, not a Taiwan locale alias.
            for (from, to) in [
                ("設置", "設定"), ("界面", "介面"), ("鼠標", "滑鼠"), ("內存", "記憶體"),
                ("窗口", "視窗"), ("屏幕", "螢幕"), ("文件夾", "資料夾"), ("文件", "檔案"),
                ("用戶", "使用者"), ("登錄", "登入"), ("服務器", "伺服器"), ("粘貼", "貼上"),
                ("賬號", "帳戶"), ("帳號", "帳戶"), ("視頻", "影片")
            ] { result = result.replacingOccurrences(of: from, with: to) }
        }
        cache.setObject(result as NSString, forKey: key)
        return result
    }
}
