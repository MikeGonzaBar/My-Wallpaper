import AppKit
import CoreGraphics

enum DisplayIdentifier {
    static func stableID(for screen: NSScreen) -> String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        if let number = screen.deviceDescription[key] as? NSNumber {
            let displayID = CGDirectDisplayID(number.uint32Value)
            if let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() {
                return CFUUIDCreateString(nil, uuid) as String
            }
            return number.stringValue
        }
        return screen.localizedName
    }
}
