import CoreServices
import Foundation

enum ApplicationLaunchPolicy {
    static func shouldStartHidden(for appleEvent: NSAppleEventDescriptor?) -> Bool {
        guard let appleEvent,
              appleEvent.eventID == kAEOpenApplication,
              let loginItemFlag = appleEvent.paramDescriptor(
                  forKeyword: keyAELaunchedAsLogInItem
              ) else {
            return false
        }
        return loginItemFlag.booleanValue
    }
}
