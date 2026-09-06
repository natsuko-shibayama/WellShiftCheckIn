import Foundation
import UserNotifications

/// macOSネイティブ通知（UNUserNotificationCenter）まわりを一手に扱うサービス。
/// - チェックイン用の声かけ通知
/// - ポモドーロの作業終了／休憩終了通知
final class NotificationService: NSObject {
    static let shared = NotificationService()
    private override init() {}

    private let center = UNUserNotificationCenter.current()

    private let checkInCategoryID = "CHECK_IN_CATEGORY"
    private let openActionID = "OPEN_CHECKIN_ACTION"

    /// メニューバーからチェックインポップアップを開くための橋渡し
    var onOpenCheckInRequested: (() -> Void)?

    func configure() {
        center.delegate = self

        let openAction = UNNotificationAction(
            identifier: openActionID,
            title: "確認する",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: checkInCategoryID,
            actions: [openAction],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    func requestAuthorizationIfNeeded() {
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            self.center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
    }

    // MARK: - チェックイン通知

    func postCheckInNotification(message: String, reason: CheckInReason) {
        let content = UNMutableNotificationContent()
        content.title = "Well Shift Check-in"
        content.body = message
        content.sound = .default
        content.categoryIdentifier = checkInCategoryID
        content.userInfo = ["kind": "checkIn"]

        let request = UNNotificationRequest(
            identifier: "checkin-\(UUID().uuidString)",
            content: content,
            trigger: nil // 即時発火（タイミング制御はScheduleManager側で実施）
        )
        center.add(request)
    }

    // MARK: - ポモドーロ通知

    func postPomodoroNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["kind": "pomodoro"]

        let request = UNNotificationRequest(
            identifier: "pomodoro-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        center.add(request)
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {
    // フォアグラウンドでも通知バナーを表示する
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let kind = response.notification.request.content.userInfo["kind"] as? String
        if kind == "checkIn" {
            DispatchQueue.main.async {
                self.onOpenCheckInRequested?()
            }
        }
        completionHandler()
    }
}
