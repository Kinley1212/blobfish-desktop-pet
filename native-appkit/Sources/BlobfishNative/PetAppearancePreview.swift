import AppKit
import SwiftUI

struct PetAppearancePreview: NSViewRepresentable {
    let character: CharacterPack?
    let scale: Double
    let accessories: [AccessoryPack]
    let accessorySpec: CharacterAccessories
    let customization: JSONValue?
    var moodFaceID: String? = nil
    var showsAlarmClock = true
    var alarmClockAccessoryID = ClockAccessoryStyle.defaultID

    func makeNSView(context: Context) -> PetView {
        PetView(frame: NSRect(x: 0, y: 0, width: 300, height: 190))
    }

    func updateNSView(_ view: PetView, context: Context) {
        view.character = character
        view.characterScale = scale
        view.accessoryPacks = accessories
        view.accessorySpec = accessorySpec
        view.customization = customization
        view.setMoodFace(moodFaceID)
        view.alarmClockAccessoryID = alarmClockAccessoryID
        view.alarmClockVisible = showsAlarmClock
    }
}
