import Foundation

/// Display names belong to the interface locale, not the character's speech pack.
enum NativeLocalization {
    static func simplified(_ text: String) -> String {
        text.applyingTransform(StringTransform("Traditional-Simplified"), reverse: false) ?? text
    }

    static func characterName(id: String, fallback: String, locale: String) -> String {
        guard locale == "en" else { return InterfaceLanguage.authored(fallback, locale: locale) }
        return ["blobfish": "Blobfish", "blobfish-wotou": "Blobfish (Wotou)", "grass-buddy": "Grass Buddy"][id]
            ?? titleCaseID(id, fallback: fallback)
    }

    static func accessoryName(id: String, fallback: String, locale: String) -> String {
        guard locale == "en" else { return InterfaceLanguage.authored(fallback, locale: locale) }
        let names = [
            "alarm-clock": "Coral Hug Clock", "alarm-clock-honey": "Honey Sugar-Cube Clock",
            "alarm-clock-plum-night": "Moonlight Jellyfish Clock", "alarm-clock-seafoam": "Seafoam Shell Clock",
            "message-envelope": "Moon-Shell Envelope", "message-flying-letter": "Ray Flying Letter",
            "message-mailbox": "Anemone Flag Mailbox", "message-sea-mail": "Sea Bottle Letter",
            "face-grass-calm": "Calm", "face-grass-happy": "Happy", "face-grass-worried": "Worried",
            "face-blank": "Speechless", "face-coy": "Affectionate", "face-money": "Money Eyes",
            "face-nosebleed": "Smitten", "face-question": "Puzzled", "face-smug": "Unbothered",
            "face-star-eye": "Starry Eyes", "face-swirl-cheek": "Giddy",
            "half-moon": "Half-Moon Glasses", "eye-mask": "Cloth Eye Mask",
            "rilakkuma-cap": "Rilakkuma Baseball Cap", "rilakkuma-cap-2": "Rilakkuma Baseball Cap (Style 2)",
            "rilakkuma-glasses": "Rilakkuma Glasses", "rilakkuma-plush": "Rilakkuma Plush Toy",
        ]
        return names[id] ?? titleCaseID(id, fallback: fallback)
    }

    static func shapeName(label: String, locale: String) -> String {
        guard locale == "en" else { return InterfaceLanguage.authored(label, locale: locale) }
        // Keep these names aligned with the shared Electron UI dictionary.
        return [
            "圆润": "Rounded", "窝窝头": "Wotou", "水滴": "Droplet", "扁圆": "Wide oval",
            "圆团": "Round", "收腰": "Tapered", "椭圆": "Oval", "双凸": "Double curve",
            "单弧": "Single arc", "小鳍": "Small fins", "圆鳍": "Round fins", "长鳍": "Long fins",
            "尖鳍": "Pointed fins", "垂手": "Lowered hands", "短手": "Short hands",
            "圆手": "Round hands", "举手": "Raised hands",
        ][label] ?? label
    }

    static func languageName(id: String, fallback: String, locale: String) -> String {
        if locale == "en" {
            return [
                "blobfish-zh-TW": "Blobfish · Traditional Chinese", "blobfish-en": "Blobfish · English",
                "grass-buddy-zh-CN": "Grass Buddy · Simplified Chinese", "grass-buddy-en": "Grass Buddy · English",
            ][id] ?? fallback
        }
        let name = [
            "blobfish-zh-TW": "水滴鱼 · 繁体中文", "blobfish-en": "水滴鱼 · 英文",
            "grass-buddy-zh-CN": "小草团 · 简体中文", "grass-buddy-en": "小草团 · 英文",
        ][id] ?? fallback
        return InterfaceLanguage.authored(name, locale: locale)
    }

    private static func titleCaseID(_ id: String, fallback: String) -> String {
        let value = id.hasPrefix("face-") ? String(id.dropFirst(5)) : id
        let words = value.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }
        return words.isEmpty ? fallback : words.joined(separator: " ")
    }
}
