import AppKit
import Foundation

final class SoundPlayer {
    private var sound: NSSound?
    private var lastPlayedAt = Date.distantPast

    func play(id: String) {
        guard Date().timeIntervalSince(lastPlayedAt) >= 0.3 else { return }
        let allowed = Set(["Glass", "Ping", "Hero", "Submarine", "Tink", "Pop", "Purr", "Bottle", "Funk"])
        guard allowed.contains(id) else { return }
        let url = URL(fileURLWithPath: "/System/Library/Sounds/\(id).aiff")
        guard let next = NSSound(contentsOf: url, byReference: true) else {
            NSSound.beep()
            return
        }
        sound?.stop()
        sound = next
        lastPlayedAt = Date()
        next.play()
    }
}
