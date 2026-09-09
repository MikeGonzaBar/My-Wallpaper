enum FullScreenPreviewDismissalEvent: Equatable {
    case localInput
    case applicationResignedActive
    case displayConfigurationChanged
    case systemWillSleep
    case sessionResigned
    case timeout
}

struct FullScreenPreviewDismissalPolicy {
    private(set) var isActive = false
    private(set) var isInputArmed = false

    mutating func activate() {
        isActive = true
        isInputArmed = false
    }

    mutating func armInput() {
        guard isActive else { return }
        isInputArmed = true
    }

    mutating func deactivate() {
        isActive = false
        isInputArmed = false
    }

    mutating func shouldDismiss(for event: FullScreenPreviewDismissalEvent) -> Bool {
        guard isActive else { return false }
        if event == .localInput, !isInputArmed {
            return false
        }
        deactivate()
        return true
    }
}
