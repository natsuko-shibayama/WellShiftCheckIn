import Foundation

/// 4.4節「通知タイミング設計」を実装するスケジューラ。
/// - 時間ベース通知（1日数回、固定時刻）
/// - タスク連動通知（タスクの開始/終了予定時刻の前後）
/// - 近接時の間引き制御（`notificationDedupeWindowMinutes` 以内なら片方に統合）
///
/// 実装方針：1分ごとにポーリングし、「今このタイミングで発火すべきか」を判定する。
/// バックグラウンド常駐アプリなので Timer ベースで十分（正確なOS側スケジューリングAPIは不要）。
final class ScheduleManager {
    static let shared = ScheduleManager()
    private init() {}

    var onCheckInTriggered: ((CheckInReason) -> Void)?

    private var settings = AppSettings()
    private var timer: Timer?
    private var firedSlotKeys: Set<String> = [] // 当日中に発火済みのキー（日付が変わればリセット）
    private var lastFiredAt: Date?
    private var lastResetDay: Int = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0

    /// AppStateからその時点の週次タスクを取得するためのクロージャ
    var currentTasksProvider: (() -> [WeeklyTask])?

    func updateSettings(_ newSettings: AppSettings) {
        self.settings = newSettings
        start()
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.tick()
        }
        timer?.tolerance = 5
        // 起動直後にも一度評価
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        resetDailyStateIfNeeded()
        guard settings.isCheckInEnabled, !settings.isDoNotDisturb else { return }

        let now = Date()
        let calendar = Calendar.current
        let nowComponents = calendar.dateComponents([.hour, .minute], from: now)

        var candidates: [(key: String, reason: CheckInReason)] = []

        // 1) 時間ベース通知
        for slot in settings.timeBasedSlots where slot.isEnabled {
            if nowComponents.hour == slot.hour && nowComponents.minute == slot.minute {
                candidates.append((key: "time-\(slot.id.uuidString)", reason: .timeBased(label: slot.label)))
            }
        }

        // 2) タスク連動通知（開始予定時刻の leadMinutes 分前）
        if settings.isTaskLinkedNotificationEnabled, let tasks = currentTasksProvider?() {
            for task in tasks where task.hasScheduledTime && !task.isCompleted {
                guard let start = task.scheduledStart,
                      let startDate = calendar.nextDate(after: calendar.date(byAdding: .day, value: -1, to: now) ?? now,
                                                          matching: start,
                                                          matchingPolicy: .nextTime) else { continue }
                let leadDate = calendar.date(byAdding: .minute, value: -settings.taskLinkedLeadMinutes, to: startDate) ?? startDate
                let diff = abs(now.timeIntervalSince(leadDate))
                if diff < 60 { // 1分の粒度でポーリングしているため60秒以内なら一致とみなす
                    candidates.append((key: "task-\(task.id)", reason: .taskLinked(task: task)))
                }
            }
        }

        guard !candidates.isEmpty else { return }

        for candidate in candidates {
            guard !firedSlotKeys.contains(candidate.key) else { continue }

            // 3) 近接間引き：直前の発火からdedupeWindow以内なら間引く
            if let lastFiredAt,
               now.timeIntervalSince(lastFiredAt) < Double(settings.notificationDedupeWindowMinutes * 60) {
                firedSlotKeys.insert(candidate.key) // このタイミングは消費済み扱いにする
                continue
            }

            firedSlotKeys.insert(candidate.key)
            lastFiredAt = now
            onCheckInTriggered?(candidate.reason)
            break // 1tickにつき1通知まで
        }
    }

    private func resetDailyStateIfNeeded() {
        let today = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        if today != lastResetDay {
            lastResetDay = today
            firedSlotKeys.removeAll()
        }
    }
}
