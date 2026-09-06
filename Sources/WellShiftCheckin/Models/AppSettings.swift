import Foundation

/// 通知1件分の時刻ベース設定（例: "朝活後 08:00"）
struct TimeBasedNotificationSlot: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var label: String
    var hour: Int
    var minute: Int
    var isEnabled: Bool = true
}

struct PomodoroSettings: Codable, Equatable {
    var isEnabled: Bool = false
    var workMinutes: Int = 30
    var breakMinutes: Int = 5
}

/// アプリ全体の設定（Notion / Claude 接続先を除く「値」はここに、
/// APIキー・トークン等の秘匿情報は KeychainService に分離して保存する）
struct AppSettings: Codable, Equatable {
    // Notion
    var notionPageID: String = ""

    // Claude
    var claudeModel: String = "claude-sonnet-4-5"

    // 通知
    var isCheckInEnabled: Bool = true
    var isDoNotDisturb: Bool = false
    var timeBasedSlots: [TimeBasedNotificationSlot] = [
        TimeBasedNotificationSlot(label: "朝活後", hour: 8, minute: 0),
        TimeBasedNotificationSlot(label: "午後の作業前", hour: 13, minute: 0),
        TimeBasedNotificationSlot(label: "夜の振り返り前", hour: 20, minute: 0)
    ]
    var isTaskLinkedNotificationEnabled: Bool = true
    var taskLinkedLeadMinutes: Int = 30
    /// 通知同士がこの分数以内に近接する場合は統合（間引き）する
    var notificationDedupeWindowMinutes: Int = 15

    // データ取得頻度
    var syncOnLaunch: Bool = true

    // ログイン時自動起動
    var launchAtLogin: Bool = false

    // ポモドーロ
    var pomodoro: PomodoroSettings = PomodoroSettings()
}

/// UserDefaults への保存を担当（APIキーなどの秘匿値は含まない）
final class AppSettingsStore {
    static let shared = AppSettingsStore()
    private let key = "com.nacchan.wellshift.appSettings"
    private let defaults = UserDefaults.standard

    func load() -> AppSettings {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return decoded
    }

    func save(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}
