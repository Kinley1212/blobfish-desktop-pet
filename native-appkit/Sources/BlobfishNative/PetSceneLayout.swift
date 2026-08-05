import AppKit

enum PetMessageSpeaker: String, Equatable {
    case owner
    case visitor
}

struct PetMessageBubble: Equatable, Identifiable {
    let id: UUID
    let text: String
    let color: String?
    let speaker: PetMessageSpeaker
    let expiresAt: Date
}

enum PetMessageBubbleStack {
    static let maximumVisible = 3

    static func inserting(
        _ bubble: PetMessageBubble,
        into current: [PetMessageBubble],
        now: Date
    ) -> [PetMessageBubble] {
        let active = current.filter { $0.expiresAt > now && $0.id != bubble.id }
        return Array((active + [bubble]).suffix(maximumVisible))
    }

    static func active(_ current: [PetMessageBubble], now: Date) -> [PetMessageBubble] {
        Array(current.filter { $0.expiresAt > now }.suffix(maximumVisible))
    }

    static func opacity(distanceFromNewest: Int) -> CGFloat {
        switch distanceFromNewest {
        case 0: return 1
        case 1: return 0.68
        default: return 0.38
        }
    }
}

enum PetSceneLayoutCoordinator {
    static let canvasInset: CGFloat = 8
    static let satelliteGap: CGFloat = 7
    static let bubbleGap: CGFloat = 6

    static func performancePanelRect(
        in canvas: CGRect,
        characterBounds: CGRect,
        companionBounds: CGRect?,
        size: CGSize,
        preferredSide: String,
        verticalPosition: Double
    ) -> CGRect {
        let value = CGFloat(min(1, max(0, verticalPosition)))
        let verticalTravel = min(
            characterBounds.height,
            max(0, canvas.height - size.height - canvasInset * 2)
        )
        let y = characterBounds.midY - size.height / 2 + (value - 0.5) * verticalTravel
        let left = CGRect(
            x: characterBounds.minX - satelliteGap - size.width,
            y: y,
            width: size.width,
            height: size.height
        )
        let right = CGRect(
            x: characterBounds.maxX + satelliteGap,
            y: y,
            width: size.width,
            height: size.height
        )
        let ordered = preferredSide == "right" ? [right, left] : [left, right]
        return ordered.enumerated().map { index, rect in
            let clamped = clamp(rect, inside: canvas.insetBy(dx: canvasInset, dy: canvasInset))
            let overlap = companionBounds.map { intersectionArea(clamped, $0) } ?? 0
            let displacement = abs(clamped.minX - rect.minX) + abs(clamped.minY - rect.minY)
            return (rect: clamped, score: overlap * 100 + displacement + CGFloat(index) * 2)
        }.min(by: { $0.score < $1.score })?.rect ?? clamp(left, inside: canvas)
    }

    static func stackedBubbleRects(
        sizesOldestFirst: [CGSize],
        anchor: CGRect,
        in canvas: CGRect,
        avoiding occupied: [CGRect]
    ) -> [CGRect] {
        guard !sizesOldestFirst.isEmpty else { return [] }
        var baseY = anchor.maxY + bubbleGap
        let horizontalLane = CGRect(
            x: anchor.midX - 132,
            y: canvas.minY,
            width: 264,
            height: canvas.height
        )
        for rect in occupied where rect.intersects(horizontalLane) {
            baseY = max(baseY, rect.maxY + bubbleGap)
        }

        var result = Array(repeating: CGRect.zero, count: sizesOldestFirst.count)
        var y = baseY
        for index in sizesOldestFirst.indices.reversed() {
            let size = sizesOldestFirst[index]
            let rect = CGRect(
                x: anchor.midX - size.width / 2,
                y: y,
                width: size.width,
                height: size.height
            )
            result[index] = clamp(rect, inside: canvas.insetBy(dx: canvasInset, dy: canvasInset))
            y += size.height + bubbleGap
        }

        guard let top = result.map(\.maxY).max(), top > canvas.maxY - canvasInset else {
            return result
        }
        let shift = top - (canvas.maxY - canvasInset)
        return result.map { $0.offsetBy(dx: 0, dy: -shift) }
    }

    static func taskStackBounds(in canvas: CGRect, characterBounds: CGRect) -> CGRect {
        CGRect(
            x: canvas.midX - 142,
            y: characterBounds.maxY + 12,
            width: 284,
            height: 61
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

    private static func intersectionArea(_ left: CGRect, _ right: CGRect) -> CGFloat {
        let intersection = left.intersection(right)
        guard !intersection.isNull else { return 0 }
        return intersection.width * intersection.height
    }
}
