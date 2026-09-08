import AppKit

enum StatusBarFishIcon {
    static func image(catalog: PackCatalog?) -> NSImage? {
        let character = try? catalog?.character(id: "blobfish")
        let image = character.flatMap {
            SVGAppearanceRenderer.image(character: $0, customization: nil, blinking: false)
        }
        image?.size = NSSize(width: 21, height: 18)
        image?.isTemplate = false
        image?.accessibilityDescription = "水滴鱼"
        return image
    }
}
