import AppKit

extension SelfCheck {
    static func coralHidingPolicy() -> Bool {
        let now = Date(timeIntervalSince1970: 1_000)
        for minutes in PetCoralHide.minutes {
            let hide = PetCoralHide(minutes: minutes, now: now)
            guard hide.deadline.timeIntervalSince(now) == Double(minutes * 60),
                  hide.progress(at: now) == 0,
                  hide.progress(at: now.addingTimeInterval(2)) == 0,
                  abs(hide.progress(at: now.addingTimeInterval(2.9)) - 0.5) < 0.001,
                  hide.progress(at: now.addingTimeInterval(4)) == 1,
                  hide.progress(at: hide.deadline.addingTimeInterval(3600)) == 1 else { return false }
        }
        let entering = CoralHideFrame(progress: 0.2)
        let behind = CoralHideFrame(progress: 0.75)
        let gone = CoralHideFrame(progress: 1)
        guard entering.travel == 0, entering.coralOpacity == 1, entering.sceneOpacity == 1,
              behind.travel == 1, behind.sceneOpacity == 1,
              gone.travel == 1, gone.sceneOpacity == 0 else { return false }
        // Reverse playback must reveal the scene before the fish moves out.
        let reappearing = CoralHideFrame(progress: 0.875)
        guard reappearing.travel == 1, reappearing.sceneOpacity == 0.5 else { return false }
        let view = PetView(frame: NSRect(x: 0, y: 0, width: 340, height: 165))
        let bounds = view.characterBounds
        view.animationsSuspended = true
        for progress in [CGFloat(0), 0.5, 1] {
            view.coralRetreatProgress = progress
            guard view.characterBounds == bounds else { return false }
        }
        view.coralRetreatProgress = 0
        view.animationsSuspended = false
        return view.characterBounds == bounds
    }
}
