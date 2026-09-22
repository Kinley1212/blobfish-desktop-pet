import AppKit

extension SelfCheck {
    static func tongueExpressionPreservesLowerFace() throws -> Bool {
        let catalog = try PackCatalog()
        guard let face = try catalog.accessories().first(where: { $0.id == "face-teasing" }) else { return false }
        for id in ["blobfish", "blobfish-wotou"] {
            let character = try catalog.character(id: id)
            guard let data = SVGAppearanceRenderer.renderedSVGData(
                character: character, customization: nil, blinking: false, hidesBaseEyes: true, tongueArtworkURL: face.artURL
            ), NSImage(data: data) != nil else { return false }
            let document = try XMLDocument(data: data)
            guard let tongue = try document.nodes(forXPath: ".//*[@id='tongue']").first,
                  let nose = try document.nodes(forXPath: ".//*[@class='nose']").first,
                  tongue.parent === nose.parent,
                  let siblings = tongue.parent?.children,
                  let ti = siblings.firstIndex(where: { $0 === tongue }),
                  let ni = siblings.firstIndex(where: { $0 === nose }), ti < ni else { return false }
            for name in ["mouth", "nose"] {
                guard !(try document.nodes(forXPath: ".//*[@class='\(name)']")).isEmpty else { return false }
            }
        }
        return SVGAppearanceRenderer.tongueExpressionEyesImage(artURL: face.artURL) != nil
    }

    static func batchedArtworkPreservesFrameTransforms() -> Bool {
        let frame = NSRect(x: 0, y: 0, width: 170, height: 165)
        let immediate = PetView(frame: frame, contentMode: .artwork)
        let batched = PetView(frame: frame, contentMode: .artwork)
        guard let reference = immediate.layer?.sublayers?.first,
              let result = batched.layer?.sublayers?.first else { return false }
        let bounds = batched.movementBounds
        for tick in 0...360 {
            let elapsed = Double(tick) / 120
            let arrival = FishVisitArrival(elapsed: elapsed)
            let offset = NSPoint(x: 30 * (1 - arrival.guestProgress), y: arrival.walkingBob)
            let oldTransform = result.transform
            let oldPosition = result.position
            var deferred = false
            let update: (PetView) -> Void = { view in
                view.arrivalProgress = arrival.guestProgress
                view.arrivalOffset = offset
                view.motionState = tick < 180 ? .working : .waiting
                view.direction = tick < 120 ? 1 : -1
                view.updateMotion(elapsed: elapsed, bobOffset: CGFloat(sin(elapsed) * 5))
            }
            update(immediate)
            batched.performArtworkUpdates {
                batched.performArtworkUpdates { update(batched) }
                deferred = CATransform3DEqualToTransform(result.transform, oldTransform)
                    && result.position == oldPosition
            }
            guard deferred,
                  CATransform3DEqualToTransform(result.transform, reference.transform),
                  result.position == reference.position,
                  result.anchorPoint == reference.anchorPoint,
                  result.opacity == reference.opacity,
                  batched.movementBounds == bounds else { return false }
        }
        // Outside a frame batch, interactive changes must still apply immediately.
        batched.arrivalOffset = .zero
        immediate.arrivalOffset = .zero
        return result.position == reference.position
    }

    static func timerUpdatesRetainArtwork() -> Bool {
        let view = PetView(frame: NSRect(x: 0, y: 0, width: 300, height: 190))
        guard let layers = view.layer?.sublayers, layers.count >= 2,
              let original = layers[0].contents as AnyObject? else { return false }
        let artwork = layers[0], overlay = layers[1]
        let bounds = view.movementBounds
        let transform = artwork.transform
        for text: String? in ["01:00", "00:59", "00:01", nil] {
            overlay.displayIfNeeded()
            view.timerText = text
            guard original === (artwork.contents as AnyObject?),
                  overlay.needsDisplay(),
                  view.movementBounds == bounds,
                  CATransform3DEqualToTransform(artwork.transform, transform) else { return false }
        }
        return true
    }
}
