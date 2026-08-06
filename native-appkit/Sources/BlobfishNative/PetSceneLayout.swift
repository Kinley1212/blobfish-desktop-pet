import AppKit

enum PetMessageSpeaker: String, Hashable {
    case owner
    case visitor
}

struct PetMessageBubble: Equatable, Identifiable {
    let id: UUID
    let contactID: UUID?
    let text: String
    let color: String?
    let speaker: PetMessageSpeaker
    let expiresAt: Date
}

enum PetMessageBubbleStack {
    static let maximumVisiblePerSpeaker = 3
    static let fadeOutDuration: TimeInterval = 1

    static func inserting(
        _ bubble: PetMessageBubble,
        into current: [PetMessageBubble],
        now: Date
    ) -> [PetMessageBubble] {
        let active = current.filter { $0.expiresAt > now && $0.id != bubble.id }
        return bounded(active + [bubble])
    }

    static func active(_ current: [PetMessageBubble], now: Date) -> [PetMessageBubble] {
        bounded(current.filter { $0.expiresAt > now })
    }

    static func opacity(
        distanceFromNewest: Int,
        expiresAt: Date,
        now: Date
    ) -> CGFloat {
        let rankOpacity: CGFloat
        switch distanceFromNewest {
        case 0, 1: rankOpacity = 1
        default: rankOpacity = 0.45
        }
        let remaining = expiresAt.timeIntervalSince(now)
        let fadeProgress = min(1, max(0, remaining / fadeOutDuration))
        return rankOpacity * CGFloat(fadeProgress)
    }

    private static func bounded(_ bubbles: [PetMessageBubble]) -> [PetMessageBubble] {
        var keptPerSpeaker: [PetMessageSpeaker: Int] = [:]
        var result: [PetMessageBubble] = []
        for bubble in bubbles.reversed() {
            let count = keptPerSpeaker[bubble.speaker, default: 0]
            guard count < maximumVisiblePerSpeaker else { continue }
            keptPerSpeaker[bubble.speaker] = count + 1
            result.append(bubble)
        }
        return Array(result.reversed())
    }
}

struct PetSpeakingPresentation: Equatable {
    let token: UUID
    let expiresAt: Date
}

enum PetSpeakingPresentationPolicy {
    static let minimumDuration: TimeInterval = 1.2
    static let maximumDuration: TimeInterval = 4

    static func duration(for text: String) -> TimeInterval {
        min(maximumDuration, max(minimumDuration, minimumDuration + Double(text.count) * 0.06))
    }

    static func starting(
        token: UUID = UUID(),
        text: String,
        now: Date
    ) -> PetSpeakingPresentation {
        PetSpeakingPresentation(
            token: token,
            expiresAt: now.addingTimeInterval(duration(for: text))
        )
    }

    static func isActive(_ presentation: PetSpeakingPresentation?, now: Date) -> Bool {
        guard let presentation else { return false }
        return presentation.expiresAt > now
    }

    static func shouldEnd(
        _ presentation: PetSpeakingPresentation?,
        token: UUID,
        now: Date
    ) -> Bool {
        guard let presentation, presentation.token == token else { return false }
        return !isActive(presentation, now: now)
    }
}

struct PetSceneLayoutInput {
    let canvas: CGRect
    let characterBounds: CGRect
    let companionBounds: CGRect?
    let timerSize: CGSize?
    let visitStatusSize: CGSize?
    let clockAlertSize: CGSize?
    let taskStackSize: CGSize?
    let ownerSpeechSize: CGSize?
    let ownerFriendBubbleSizes: [CGSize]
    let visitorFriendBubbleSizes: [CGSize]
    let performancePanelSize: CGSize?
    let performancePanelSide: String
    let performancePanelVerticalPosition: Double
    let performancePanelDistance: Double
}

struct PetSceneLayout: Equatable {
    let timerRect: CGRect?
    let visitStatusRect: CGRect?
    let clockAlertRect: CGRect?
    let taskStackRect: CGRect?
    let ownerSpeechRect: CGRect?
    let ownerFriendBubbleRects: [CGRect]
    let visitorFriendBubbleRects: [CGRect]
    let performancePanelRect: CGRect?

    var overlayRects: [CGRect] {
        [timerRect, visitStatusRect, clockAlertRect, taskStackRect, ownerSpeechRect, performancePanelRect]
            .compactMap { $0 }
            + ownerFriendBubbleRects
            + visitorFriendBubbleRects
    }
}

enum PetOverlayScreenGeometry {
    static let maximumSceneSize = CGSize(width: 800, height: 600)

    static func visibleFrame(for formationBounds: CGRect, from visibleFrames: [CGRect]) -> CGRect? {
        guard !visibleFrames.isEmpty else { return nil }
        let overlapping = visibleFrames.map { frame in
            (frame: frame, area: PetSceneLayoutCoordinator.intersectionArea(formationBounds, frame))
        }
        if let best = overlapping.max(by: { $0.area < $1.area }), best.area > 0 {
            return best.frame
        }
        return visibleFrames.min {
            squaredDistance(from: formationBounds.center, to: $0)
                < squaredDistance(from: formationBounds.center, to: $1)
        }
    }

    static func localRect(for screenRect: CGRect, visibleFrame: CGRect) -> CGRect {
        screenRect.offsetBy(dx: -visibleFrame.minX, dy: -visibleFrame.minY)
    }

    static func sceneFrame(
        around formationBounds: CGRect,
        inside visibleFrame: CGRect,
        maximumSize: CGSize = maximumSceneSize
    ) -> CGRect {
        let size = CGSize(
            width: min(maximumSize.width, visibleFrame.width),
            height: min(maximumSize.height, visibleFrame.height)
        )
        let ideal = CGPoint(
            x: formationBounds.midX - size.width / 2,
            y: formationBounds.midY - size.height / 2
        )
        return CGRect(
            x: min(max(ideal.x, visibleFrame.minX), visibleFrame.maxX - size.width),
            y: min(max(ideal.y, visibleFrame.minY), visibleFrame.maxY - size.height),
            width: size.width,
            height: size.height
        )
    }

    private static func squaredDistance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let x = min(max(point.x, rect.minX), rect.maxX)
        let y = min(max(point.y, rect.minY), rect.maxY)
        let dx = x - point.x
        let dy = y - point.y
        return dx * dx + dy * dy
    }
}

struct PetSceneAnchor: Equatable {
    let primaryFrame: CGRect
    let formationFrame: CGRect
    let visibleFrame: CGRect
}

enum PetAttachedWindowGeometry {
    static let gap: CGFloat = 10

    static func anchor(
        primaryFrame: CGRect,
        formationFrame: CGRect,
        visibleFrames: [CGRect]
    ) -> PetSceneAnchor? {
        guard let visibleFrame = PetOverlayScreenGeometry.visibleFrame(
            for: formationFrame,
            from: visibleFrames
        ) else { return nil }
        return PetSceneAnchor(
            primaryFrame: primaryFrame,
            formationFrame: formationFrame,
            visibleFrame: visibleFrame
        )
    }

    static func frame(windowSize: CGSize, anchor: PetSceneAnchor) -> CGRect {
        let primary = anchor.primaryFrame
        let formation = anchor.formationFrame
        let candidates = [
            CGRect(
                x: primary.midX - windowSize.width / 2,
                y: formation.maxY + gap,
                width: windowSize.width,
                height: windowSize.height
            ),
            CGRect(
                x: primary.midX - windowSize.width / 2,
                y: formation.minY - gap - windowSize.height,
                width: windowSize.width,
                height: windowSize.height
            ),
            CGRect(
                x: formation.maxX + gap,
                y: primary.midY - windowSize.height / 2,
                width: windowSize.width,
                height: windowSize.height
            ),
            CGRect(
                x: formation.minX - gap - windowSize.width,
                y: primary.midY - windowSize.height / 2,
                width: windowSize.width,
                height: windowSize.height
            ),
        ]
        if let contained = candidates.first(where: { anchor.visibleFrame.contains($0) }) {
            return contained
        }
        let clampedCandidates = candidates.map { clamped($0, inside: anchor.visibleFrame) }
        return clampedCandidates.first(where: { !$0.intersects(formation) }) ?? clampedCandidates[0]
    }

    static func shouldReposition(
        isWindowVisible: Bool,
        force: Bool = false,
        currentFrame: CGRect,
        proposedFrame: CGRect
    ) -> Bool {
        (force || isWindowVisible) && currentFrame != proposedFrame
    }

    private static func clamped(_ frame: CGRect, inside visibleFrame: CGRect) -> CGRect {
        CGRect(
            x: frame.width <= visibleFrame.width
                ? min(max(frame.minX, visibleFrame.minX), visibleFrame.maxX - frame.width)
                : visibleFrame.minX,
            y: frame.height <= visibleFrame.height
                ? min(max(frame.minY, visibleFrame.minY), visibleFrame.maxY - frame.height)
                : visibleFrame.minY,
            width: frame.width,
            height: frame.height
        )
    }
}

enum PetOverlayHitTesting {
    static func needsSceneLayout(
        hasClockAlert: Bool,
        unreadCount: Int,
        hasClickableMessengerSpeech: Bool,
        friendBubbleCount: Int
    ) -> Bool {
        hasClockAlert || unreadCount > 0 || hasClickableMessengerSpeech || friendBubbleCount > 0
    }

    static func contains(_ point: CGPoint, in interactiveRects: [CGRect]) -> Bool {
        interactiveRects.contains { $0.contains(point) }
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}

enum PetSceneLayoutCoordinator {
    static let canvasInset: CGFloat = 8
    static let satelliteGap: CGFloat = 6
    static let bubbleGap: CGFloat = 6

    static func layout(_ input: PetSceneLayoutInput) -> PetSceneLayout {
        let container = input.canvas.insetBy(dx: canvasInset, dy: canvasInset)
        let formation = input.companionBounds.map { input.characterBounds.union($0) }
            ?? input.characterBounds
        // The formation itself is the hard obstacle. Each element's preferred
        // candidate owns its own gap contract (performance supports 2...28 pt;
        // cards and bubbles default to 6 pt), so a fixed expansion here would
        // silently override the user's performance distance.
        var occupied = [formation]

        var timerRect: CGRect?
        var visitStatusRect: CGRect?
        let statusSizes = [input.timerSize, input.visitStatusSize].compactMap { $0 }
        if !statusSizes.isEmpty {
            let compositeSize = CGSize(
                width: statusSizes.reduce(0) { $0 + $1.width }
                    + satelliteGap * CGFloat(max(0, statusSizes.count - 1)),
                height: statusSizes.map(\.height).max() ?? 0
            )
            let statusGroup = place(
                size: compositeSize,
                around: formation,
                in: container,
                avoiding: occupied,
                preferred: verticalCandidates(size: compositeSize, anchor: formation)
            )
            var x = statusGroup.minX
            if let size = input.timerSize {
                timerRect = CGRect(
                    x: x,
                    y: statusGroup.midY - size.height / 2,
                    width: size.width,
                    height: size.height
                )
                x += size.width + satelliteGap
            }
            if let size = input.visitStatusSize {
                visitStatusRect = CGRect(
                    x: x,
                    y: statusGroup.midY - size.height / 2,
                    width: size.width,
                    height: size.height
                )
            }
            occupied.append(statusGroup.insetBy(dx: -satelliteGap, dy: -satelliteGap))
        }

        func placeCard(_ size: CGSize?, preferred: [CGRect]) -> CGRect? {
            guard let size else { return nil }
            let rect = place(
                size: size,
                around: formation,
                in: container,
                avoiding: occupied,
                preferred: preferred
            )
            occupied.append(rect.insetBy(dx: -satelliteGap, dy: -satelliteGap))
            return rect
        }

        let clockAlertRect = placeCard(
            input.clockAlertSize,
            preferred: verticalCandidates(size: input.clockAlertSize ?? .zero, anchor: formation)
        )
        let taskStackRect = placeCard(
            input.taskStackSize,
            preferred: verticalCandidates(size: input.taskStackSize ?? .zero, anchor: formation)
        )
        let ownerSpeechRect = placeCard(
            input.ownerSpeechSize,
            preferred: verticalCandidates(size: input.ownerSpeechSize ?? .zero, anchor: input.characterBounds)
        )

        func placeBubbleStack(sizesOldestFirst: [CGSize], anchor: CGRect) -> [CGRect] {
            guard !sizesOldestFirst.isEmpty else { return [] }
            let stackSize = CGSize(
                width: sizesOldestFirst.map(\.width).max() ?? 0,
                height: sizesOldestFirst.reduce(0) { $0 + $1.height }
                    + bubbleGap * CGFloat(max(0, sizesOldestFirst.count - 1))
            )
            let group = place(
                size: stackSize,
                around: anchor,
                in: container,
                avoiding: occupied,
                preferred: verticalCandidates(size: stackSize, anchor: anchor)
                    + horizontalCandidates(size: stackSize, anchor: anchor)
            )
            occupied.append(group.insetBy(dx: -bubbleGap, dy: -bubbleGap))
            var result = Array(repeating: CGRect.zero, count: sizesOldestFirst.count)
            if group.maxY <= anchor.minY {
                var y = group.maxY
                for index in sizesOldestFirst.indices.reversed() {
                    let size = sizesOldestFirst[index]
                    y -= size.height
                    result[index] = CGRect(
                        x: group.midX - size.width / 2,
                        y: y,
                        width: size.width,
                        height: size.height
                    )
                    y -= bubbleGap
                }
            } else {
                var y = group.minY
                for index in sizesOldestFirst.indices.reversed() {
                    let size = sizesOldestFirst[index]
                    result[index] = CGRect(
                        x: group.midX - size.width / 2,
                        y: y,
                        width: size.width,
                        height: size.height
                    )
                    y += size.height + bubbleGap
                }
            }
            return result
        }

        let ownerFriendBubbleRects = placeBubbleStack(
            sizesOldestFirst: input.ownerFriendBubbleSizes,
            anchor: input.characterBounds
        )
        let visitorFriendBubbleRects = placeBubbleStack(
            sizesOldestFirst: input.visitorFriendBubbleSizes,
            anchor: input.companionBounds ?? input.characterBounds
        )

        var performancePanelRect: CGRect?
        if let size = input.performancePanelSize {
            let preferred = performanceCandidates(
                size: size,
                anchor: formation,
                side: input.performancePanelSide,
                verticalPosition: input.performancePanelVerticalPosition,
                distance: input.performancePanelDistance
            )
            performancePanelRect = place(
                size: size,
                around: formation,
                in: container,
                avoiding: occupied,
                preferred: preferred
            )
        }

        return PetSceneLayout(
            timerRect: timerRect,
            visitStatusRect: visitStatusRect,
            clockAlertRect: clockAlertRect,
            taskStackRect: taskStackRect,
            ownerSpeechRect: ownerSpeechRect,
            ownerFriendBubbleRects: ownerFriendBubbleRects,
            visitorFriendBubbleRects: visitorFriendBubbleRects,
            performancePanelRect: performancePanelRect
        )
    }

    static func clamp(_ rect: CGRect, inside container: CGRect) -> CGRect {
        guard rect.width <= container.width, rect.height <= container.height else {
            return CGRect(
                x: container.minX,
                y: container.minY,
                width: min(rect.width, container.width),
                height: min(rect.height, container.height)
            )
        }
        return CGRect(
            x: min(max(rect.minX, container.minX), container.maxX - rect.width),
            y: min(max(rect.minY, container.minY), container.maxY - rect.height),
            width: rect.width,
            height: rect.height
        )
    }

    private static func verticalCandidates(size: CGSize, anchor: CGRect) -> [CGRect] {
        [
            CGRect(
                x: anchor.midX - size.width / 2,
                y: anchor.maxY + satelliteGap,
                width: size.width,
                height: size.height
            ),
            CGRect(
                x: anchor.midX - size.width / 2,
                y: anchor.minY - satelliteGap - size.height,
                width: size.width,
                height: size.height
            ),
        ]
    }

    private static func horizontalCandidates(size: CGSize, anchor: CGRect) -> [CGRect] {
        [
            CGRect(
                x: anchor.minX - satelliteGap - size.width,
                y: anchor.midY - size.height / 2,
                width: size.width,
                height: size.height
            ),
            CGRect(
                x: anchor.maxX + satelliteGap,
                y: anchor.midY - size.height / 2,
                width: size.width,
                height: size.height
            ),
        ]
    }

    private static func performanceCandidates(
        size: CGSize,
        anchor: CGRect,
        side: String,
        verticalPosition: Double,
        distance: Double
    ) -> [CGRect] {
        let gap = CGFloat(min(28, max(2, distance)))
        let value = CGFloat(min(1, max(0, verticalPosition)))
        let y = anchor.midY - size.height / 2 + (value - 0.5) * anchor.height
        let left = CGRect(
            x: anchor.minX - gap - size.width,
            y: y,
            width: size.width,
            height: size.height
        )
        let right = CGRect(
            x: anchor.maxX + gap,
            y: y,
            width: size.width,
            height: size.height
        )
        return side == "right" ? [right, left] : [left, right]
    }

    private static func place(
        size: CGSize,
        around anchor: CGRect,
        in container: CGRect,
        avoiding occupied: [CGRect],
        preferred: [CGRect]
    ) -> CGRect {
        guard size.width > 0, size.height > 0 else { return .zero }
        let preferred = preferred.isEmpty
            ? verticalCandidates(size: size, anchor: anchor)
            : preferred
        var xValues = [
            container.minX,
            container.maxX - size.width,
            anchor.midX - size.width / 2,
            anchor.minX - satelliteGap - size.width,
            anchor.maxX + satelliteGap,
        ]
        var yValues = [
            container.minY,
            container.maxY - size.height,
            anchor.midY - size.height / 2,
            anchor.minY - satelliteGap - size.height,
            anchor.maxY + satelliteGap,
        ]
        for rect in occupied {
            xValues += [rect.minX - size.width, rect.maxX]
            yValues += [rect.minY - size.height, rect.maxY]
        }

        var candidates = preferred.map { clamp($0, inside: container) }
        for x in xValues {
            for y in yValues {
                candidates.append(clamp(
                    CGRect(x: x, y: y, width: size.width, height: size.height),
                    inside: container
                ))
            }
        }

        func score(_ rect: CGRect) -> (overlap: CGFloat, preference: CGFloat, anchorDistance: CGFloat) {
            let overlap = occupied.reduce(CGFloat.zero) { $0 + intersectionArea(rect, $1) }
            let preference = preferred.map {
                abs(rect.minX - $0.minX) + abs(rect.minY - $0.minY)
            }.min() ?? 0
            let anchorDistance = abs(rect.midX - anchor.midX) + abs(rect.midY - anchor.midY)
            return (overlap, preference, anchorDistance)
        }

        return candidates.min { left, right in
            let lhs = score(left)
            let rhs = score(right)
            if abs(lhs.overlap - rhs.overlap) > 0.001 { return lhs.overlap < rhs.overlap }
            if abs(lhs.preference - rhs.preference) > 0.001 { return lhs.preference < rhs.preference }
            return lhs.anchorDistance < rhs.anchorDistance
        } ?? clamp(preferred[0], inside: container)
    }

    static func intersectionArea(_ left: CGRect, _ right: CGRect) -> CGFloat {
        let intersection = left.intersection(right)
        guard !intersection.isNull else { return 0 }
        return intersection.width * intersection.height
    }
}
