import AppKit
import Foundation

enum SVGAppearanceRenderer {
    static func image(
        character: CharacterPack,
        customization: JSONValue?,
        blinking: Bool,
        hidesBaseEyes: Bool = false
    ) -> NSImage? {
        guard let data = renderedSVGData(
            character: character,
            customization: customization,
            blinking: blinking,
            hidesBaseEyes: hidesBaseEyes
        ) else { return nil }
        return NSImage(data: data)
    }

    static func renderedSVGData(
        character: CharacterPack,
        customization: JSONValue?,
        blinking: Bool,
        hidesBaseEyes: Bool = false
    ) -> Data? {
        guard let document = try? XMLDocument(contentsOf: character.artURL, options: [.nodePreserveAll]),
              let root = document.rootElement(), root.name?.lowercased() == "svg" else { return nil }
        sanitize(root)
        hideRestingTearsAndCoveredEyes(root, hidesBaseEyes: hidesBaseEyes)
        applyShapes(root, manifest: character.manifest, customization: customization)
        applyTransforms(root, customization: customization, blinking: blinking)
        return document.xmlData(options: [])
    }

    private static func hideRestingTearsAndCoveredEyes(_ root: XMLElement, hidesBaseEyes: Bool) {
        // The Electron character CSS keeps tears invisible until a hit/failure
        // reaction. Native rendering has no CSS engine, so remove them from the
        // resting image instead of accidentally showing a permanent cry face.
        elements(class: "tears", in: root).forEach { $0.detach() }
        elements(class: "tear", in: root).forEach { $0.detach() }
        guard hidesBaseEyes else { return }
        elements(class: "eyes", in: root).forEach { $0.detach() }
        elements(class: "eye", in: root).forEach { $0.detach() }
    }

    private static func sanitize(_ root: XMLElement) {
        let dangerous = Set(["script", "foreignobject", "iframe", "object", "embed"])
        for node in (try? root.nodes(forXPath: ".//*")) ?? [] {
            guard let element = node as? XMLElement else { continue }
            if dangerous.contains(element.name?.lowercased() ?? "") {
                element.detach()
                continue
            }
            for attribute in element.attributes ?? [] {
                let name = attribute.name?.lowercased() ?? ""
                let value = attribute.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if name.hasPrefix("on") || ((name == "href" || name == "xlink:href") && !value.hasPrefix("#")) {
                    element.removeAttribute(forName: attribute.name ?? "")
                }
            }
        }
    }

    private static func applyShapes(_ root: XMLElement, manifest: CharacterPack.Manifest, customization: JSONValue?) {
        guard let shapes = manifest.diy?.shapes else { return }
        let spec = customization?.objectValue ?? [:]
        let bodyID = spec["body"]?.objectValue?["shape"]?.stringValue ?? "default"
        if let shape = shapes["body"]?.first(where: { $0.id == bodyID }), let path = shape.d,
           let body = elements(class: "body-shape", in: root).first {
            replaceGeometry(of: body, path: path)
            if shape.hideShading == true { elements(class: "body-shading", in: root).forEach { $0.detach() } }
        }
        let finID = spec["fins"]?.objectValue?["shape"]?.stringValue ?? "default"
        if let shape = shapes["fins"]?.first(where: { $0.id == finID }) {
            if let path = shape.left, let left = elements(class: "fin-left", in: root).first { replaceGeometry(of: left, path: path) }
            if let path = shape.right, let right = elements(class: "fin-right", in: root).first { replaceGeometry(of: right, path: path) }
        }
    }

    private static func replaceGeometry(of element: XMLElement, path: String) {
        for name in ["cx", "cy", "rx", "ry", "r", "x", "y", "width", "height", "points", "d"] {
            element.removeAttribute(forName: name)
        }
        element.name = "path"
        element.addAttribute(XMLNode.attribute(withName: "d", stringValue: path) as! XMLNode)
    }

    private static func applyTransforms(_ root: XMLElement, customization: JSONValue?, blinking: Bool) {
        let spec = customization?.objectValue ?? [:]
        let viewBox = root.attribute(forName: "viewBox")?.stringValue?
            .split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { Double($0) } ?? []
        let width = viewBox.count == 4 ? viewBox[2] : 140
        let height = viewBox.count == 4 ? viewBox[3] : 120
        transform(elements(class: "body-shape", in: root) + elements(class: "body-shading", in: root),
                  scaleX: number(spec, "body", "width", 1), scaleY: number(spec, "body", "height", 1), pivotX: width / 2, pivotY: height / 2)

        let finSize = number(spec, "fins", "size", 1)
        let finX = number(spec, "fins", "offsetX", 0)
        let finY = number(spec, "fins", "offsetY", 0)
        transformAroundElements(elements(class: "fin-left", in: root), scaleX: finSize, scaleY: finSize, dx: -finX, dy: finY, fallback: (width * 0.2, height * 0.58))
        transformAroundElements(elements(class: "fin-right", in: root), scaleX: finSize, scaleY: finSize, dx: finX, dy: finY, fallback: (width * 0.8, height * 0.58))

        let eyeSize = number(spec, "eyes", "size", 1)
        let eyeSpacing = number(spec, "eyes", "spacing", 0)
        let eyeY = number(spec, "eyes", "offsetY", 0)
        let blinkY = blinking ? 0.08 : eyeSize
        transformAroundElements(elements(class: "eye-left", in: root) + elements(class: "tear-left", in: root), scaleX: eyeSize, scaleY: blinkY, dx: -eyeSpacing, dy: eyeY, fallback: (width * 0.33, height * 0.42))
        transformAroundElements(elements(class: "eye-right", in: root) + elements(class: "tear-right", in: root), scaleX: eyeSize, scaleY: blinkY, dx: eyeSpacing, dy: eyeY, fallback: (width * 0.67, height * 0.42))

        let mouthSize = number(spec, "mouth", "size", 1)
        transformAroundElements(elements(class: "mouth", in: root), scaleX: mouthSize, scaleY: mouthSize, dy: number(spec, "mouth", "offsetY", 0), fallback: (width / 2, height * 0.7))
        let noseSize = number(spec, "nose", "size", 1)
        transformAroundElements(elements(class: "nose", in: root), scaleX: noseSize, scaleY: noseSize, dy: number(spec, "nose", "offsetY", 0), fallback: (width / 2, height * 0.67))
    }

    private static func transformAroundElements(
        _ elements: [XMLElement], scaleX: Double, scaleY: Double, dx: Double = 0, dy: Double = 0,
        fallback: (Double, Double)
    ) {
        for element in elements {
            let point = pivot(of: element) ?? fallback
            transform([element], scaleX: scaleX, scaleY: scaleY, dx: dx, dy: dy, pivotX: point.0, pivotY: point.1)
        }
    }

    private static func pivot(of element: XMLElement) -> (Double, Double)? {
        if let x = Double(element.attribute(forName: "cx")?.stringValue ?? ""),
           let y = Double(element.attribute(forName: "cy")?.stringValue ?? "") { return (x, y) }
        let pathElement: XMLElement
        if element.name?.lowercased() == "path" {
            pathElement = element
        } else if let descendant = ((try? element.nodes(forXPath: ".//path[@d]")) ?? []).first as? XMLElement {
            pathElement = descendant
        } else { return nil }
        guard let path = pathElement.attribute(forName: "d")?.stringValue else { return nil }
        let pattern = try! NSRegularExpression(pattern: #"[-+]?(?:\d*\.)?\d+"#)
        let matches = pattern.matches(in: path, range: NSRange(path.startIndex..., in: path))
        guard matches.count >= 2,
              let first = Range(matches[0].range, in: path), let second = Range(matches[1].range, in: path),
              let x = Double(path[first]), let y = Double(path[second]) else { return nil }
        return (x, y)
    }

    private static func transform(
        _ elements: [XMLElement], scaleX: Double, scaleY: Double, dx: Double = 0, dy: Double = 0,
        pivotX: Double, pivotY: Double
    ) {
        guard scaleX != 1 || scaleY != 1 || dx != 0 || dy != 0 else { return }
        let transform = "translate(\(pivotX + dx) \(pivotY + dy)) scale(\(scaleX) \(scaleY)) translate(\(-pivotX) \(-pivotY))"
        for element in elements {
            let previous = element.attribute(forName: "transform")?.stringValue ?? ""
            element.removeAttribute(forName: "transform")
            element.addAttribute(XMLNode.attribute(withName: "transform", stringValue: previous.isEmpty ? transform : "\(previous) \(transform)") as! XMLNode)
        }
    }

    private static func elements(class name: String, in root: XMLElement) -> [XMLElement] {
        let expression = ".//*[contains(concat(' ', normalize-space(@class), ' '), ' \(name) ')]"
        return ((try? root.nodes(forXPath: expression)) ?? []).compactMap { $0 as? XMLElement }
    }

    private static func number(_ spec: [String: JSONValue], _ part: String, _ key: String, _ fallback: Double) -> Double {
        guard let value = spec[part]?.objectValue?[key]?.numberValue, value.isFinite else { return fallback }
        return value
    }
}
