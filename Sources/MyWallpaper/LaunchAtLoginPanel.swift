import SwiftUI

struct LaunchAtLoginPanel: View {
    @ObservedObject var controller: LaunchAtLoginController

    var body: some View {
        RetroWindow(title: "LAUNCH AT LOGIN") {
            VStack(alignment: .leading, spacing: 10) {
                RetroCheckbox(
                    title: "OPEN MY WALLPAPER AT LOGIN",
                    isOn: controller.state.isEnabled,
                    action: {
                        Task { await controller.setEnabled(!controller.state.isEnabled) }
                    }
                )
                .disabled(!controller.state.canToggle || controller.isUpdating)

                Text(controller.isUpdating ? "UPDATING LOGIN ITEM…" : controller.state.statusText)
                    .font(RetroFont.body(size: 9))
                    .foregroundStyle(RetroPalette.secondaryInk)

                if controller.state == .requiresApproval {
                    Button("OPEN LOGIN ITEMS SETTINGS…") {
                        controller.openSystemSettings()
                    }
                    .buttonStyle(RetroButtonStyle(compact: true))
                }

                if let errorMessage = controller.errorMessage {
                    Text(errorMessage.uppercased())
                        .font(RetroFont.body(size: 9))
                        .foregroundStyle(RetroPalette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
