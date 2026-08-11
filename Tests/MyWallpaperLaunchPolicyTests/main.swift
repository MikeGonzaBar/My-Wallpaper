import CoreServices
import Foundation

private func makeEvent(
    eventID: AEEventID = kAEOpenApplication,
    loginItemFlag: Bool? = nil
) -> NSAppleEventDescriptor {
    let event = NSAppleEventDescriptor(
        eventClass: kCoreEventClass,
        eventID: eventID,
        targetDescriptor: nil,
        returnID: AEReturnID(kAutoGenerateReturnID),
        transactionID: AETransactionID(kAnyTransactionID)
    )
    if let loginItemFlag {
        event.setParam(
            NSAppleEventDescriptor(boolean: loginItemFlag),
            forKeyword: keyAELaunchedAsLogInItem
        )
    }
    return event
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("Login launch policy test failed: \(message)\n", stderr)
        exit(1)
    }
}

expect(
    ApplicationLaunchPolicy.shouldStartHidden(
        for: makeEvent(loginItemFlag: true)
    ),
    "an open-application event marked as a login item should start hidden"
)
expect(
    !ApplicationLaunchPolicy.shouldStartHidden(
        for: makeEvent(loginItemFlag: false)
    ),
    "an explicitly false login-item flag should open normally"
)
expect(
    !ApplicationLaunchPolicy.shouldStartHidden(for: makeEvent()),
    "an ordinary open-application event should open normally"
)
expect(
    !ApplicationLaunchPolicy.shouldStartHidden(
        for: makeEvent(eventID: kAEReopenApplication, loginItemFlag: true)
    ),
    "a reopen event should not be treated as the initial login launch"
)
expect(
    !ApplicationLaunchPolicy.shouldStartHidden(for: nil),
    "a missing Apple event should open normally"
)

print("Application login launch policy tests passed.")
