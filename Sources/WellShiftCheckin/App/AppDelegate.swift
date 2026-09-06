import AppKit
import UserNotifications

/// アプリ全体のライフサイクルを管理する AppDelegate。
/// - 通知センターの delegate 設定
/// - バックグラウンドサービス（スケジューラ／ポモドーロ／猫）の起動
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let notificationService = NotificationService.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Dock アイコンは表示しない（LSUIElement = true でメニューバー常駐のみ）
        NSApp.setActivationPolicy(.accessory)

        notificationService.configure()
        notificationService.requestAuthorizationIfNeeded()

        // 通知タイミングのスケジューラ・ポモドーロ・猫コントローラは
        // AppState 初期化時（WellShiftCheckinApp）に起動される。
    }

    func applicationWillTerminate(_ notification: Notification) {
        ScheduleManager.shared.stop()
        PomodoroManager.shared.stop()
        CatWindowController.shared.hide()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // メニューバーアプリなのでウィンドウが全て閉じても終了しない
        false
    }
}
