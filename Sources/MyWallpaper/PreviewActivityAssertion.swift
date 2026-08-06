import IOKit.pwr_mgt

protocol PreviewActivityAsserting: AnyObject {
    func acquire() -> Bool
    func release()
}

final class PreviewActivityAssertion: PreviewActivityAsserting {
    typealias AcquireOperation = (inout IOPMAssertionID) -> IOReturn
    typealias ReleaseOperation = (IOPMAssertionID) -> IOReturn

    private var assertionID = IOPMAssertionID(kIOPMNullAssertionID)
    private let acquireOperation: AcquireOperation
    private let releaseOperation: ReleaseOperation

    init(
        acquireOperation: AcquireOperation? = nil,
        releaseOperation: ReleaseOperation? = nil
    ) {
        self.acquireOperation = acquireOperation ?? { assertionID in
            IOPMAssertionCreateWithDescription(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                "My Wallpaper Preview" as CFString,
                "Full-screen video preview" as CFString,
                "Previewing My Wallpaper videos" as CFString,
                nil,
                60,
                kIOPMAssertionTimeoutActionRelease as CFString,
                &assertionID
            )
        }
        self.releaseOperation = releaseOperation ?? IOPMAssertionRelease
    }

    func acquire() -> Bool {
        release()
        let status = acquireOperation(&assertionID)
        guard status == kIOReturnSuccess else {
            assertionID = IOPMAssertionID(kIOPMNullAssertionID)
            return false
        }
        return true
    }

    func release() {
        guard assertionID != kIOPMNullAssertionID else { return }
        _ = releaseOperation(assertionID)
        assertionID = IOPMAssertionID(kIOPMNullAssertionID)
    }

    deinit {
        release()
    }
}
