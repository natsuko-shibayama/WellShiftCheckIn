import Foundation
import ServiceManagement

/// 「ログイン時自動起動」のON/OFFを扱う。macOS 13+ の SMAppService を使用。
final class LoginItemManager {
    static let shared = LoginItemManager()
    private init() {}

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            print("LoginItemManager: failed to \(enabled ? "register" : "unregister") - \(error)")
        }
    }
}
