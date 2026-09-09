import Combine
import ServiceManagement

enum LaunchAtLoginState: Equatable {
    case disabled
    case enabled
    case requiresApproval
    case unavailable

    var isEnabled: Bool { self == .enabled }

    var canToggle: Bool {
        self != .requiresApproval
    }

    var statusText: String {
        switch self {
        case .disabled:
            "OFF — OPEN MY WALLPAPER MANUALLY AFTER LOGIN."
        case .enabled:
            "ON — MY WALLPAPER WILL START IN THE MENU BAR AFTER YOU LOG IN."
        case .requiresApproval:
            "APPROVAL REQUIRED IN SYSTEM SETTINGS → LOGIN ITEMS."
        case .unavailable:
            "UNAVAILABLE — INSTALL AND OPEN THE APPLICATIONS COPY, THEN TRY AGAIN."
        }
    }
}

@MainActor
protocol LaunchAtLoginManaging {
    var state: LaunchAtLoginState { get }
    func register() throws
    func unregister() async throws
    func openSystemSettings()
}

@MainActor
struct SystemLaunchAtLoginManager: LaunchAtLoginManaging {
    var state: LaunchAtLoginState {
        Self.state(for: SMAppService.mainApp.status)
    }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() async throws {
        try await SMAppService.mainApp.unregister()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    static func state(for status: SMAppService.Status) -> LaunchAtLoginState {
        switch status {
        case .notRegistered:
            .disabled
        case .enabled:
            .enabled
        case .requiresApproval:
            .requiresApproval
        case .notFound:
            .unavailable
        @unknown default:
            .unavailable
        }
    }
}

@MainActor
final class LaunchAtLoginController: ObservableObject {
    @Published private(set) var state: LaunchAtLoginState
    @Published private(set) var isUpdating = false
    @Published private(set) var errorMessage: String?

    private let manager: LaunchAtLoginManaging

    convenience init() {
        self.init(manager: SystemLaunchAtLoginManager())
    }

    init(manager: LaunchAtLoginManaging) {
        self.manager = manager
        state = manager.state
    }

    func refresh() {
        state = manager.state
    }

    func setEnabled(_ enabled: Bool) async {
        guard !isUpdating else { return }
        refresh()
        guard state.canToggle, enabled != state.isEnabled else { return }

        isUpdating = true
        errorMessage = nil
        defer {
            refresh()
            isUpdating = false
        }

        do {
            if enabled {
                try manager.register()
            } else {
                try await manager.unregister()
            }
        } catch {
            let action = enabled ? "enabled" : "disabled"
            errorMessage = "Launch at Login couldn’t be \(action): \(error.localizedDescription)"
        }
    }

    func openSystemSettings() {
        manager.openSystemSettings()
    }
}
