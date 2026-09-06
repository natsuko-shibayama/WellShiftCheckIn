import SwiftUI
import AppKit
import Combine

/// アプリ全体で共有する状態のハブ。
/// UI（メニューバー／設定／ポップアップ）とサービス層（Notion, Claude, 通知, ポモドーロ, 猫）を橋渡しする。
@MainActor
final class AppState: ObservableObject {

    // MARK: - 設定（AppSettingsStore がまとめて永続化）
    @Published var settings: AppSettings

    // MARK: - 週次タスク
    @Published var weeklyTasks: [WeeklyTask] = []
    @Published var lastSyncedAt: Date?
    @Published var lastSyncError: String?
    @Published var isSyncing: Bool = false

    // MARK: - ポモドーロ
    @Published var pomodoroState: PomodoroState = .idle

    // MARK: - チェックイン
    @Published var latestCheckInMessage: String?
    @Published var isCheckInPopupPresented: Bool = false

    private var cancellables = Set<AnyCancellable>()

    init() {
        let store = AppSettingsStore.shared
        self.settings = store.load()

        // 設定変更を永続化し、各サービスへ反映する
        $settings
            .dropFirst()
            .sink { [weak self] newValue in
                AppSettingsStore.shared.save(newValue)
                self?.applySettingsToServices(newValue)
            }
            .store(in: &cancellables)

        wireUpServices()
        applySettingsToServices(settings)
    }

    private func wireUpServices() {
        // スケジューラからのチェックイン要求を受けてポップアップ通知を出す
        ScheduleManager.shared.onCheckInTriggered = { [weak self] reason in
            Task { await self?.performCheckIn(reason: reason) }
        }
        ScheduleManager.shared.currentTasksProvider = { [weak self] in
            self?.weeklyTasks ?? []
        }

        // 通知バナーの「確認する」タップでポップアップを開く
        NotificationService.shared.onOpenCheckInRequested = { [weak self] in
            self?.openCheckInPopup()
        }

        // ポモドーロの状態変化を反映
        PomodoroManager.shared.onStateChanged = { [weak self] state in
            self?.pomodoroState = state
            switch state {
            case .breakTime:
                CatWindowController.shared.show()
            case .idle, .working, .paused:
                CatWindowController.shared.hide()
            }
        }
    }

    private func applySettingsToServices(_ settings: AppSettings) {
        ScheduleManager.shared.updateSettings(settings)
        PomodoroManager.shared.updateSettings(settings.pomodoro)
        NotionService.shared.updateConfig(pageID: settings.notionPageID)
        ClaudeService.shared.updateConfig(model: settings.claudeModel)
    }

    // MARK: - Notion同期

    func syncWithNotion() async {
        guard !settings.notionPageID.isEmpty else {
            lastSyncError = "Notion の対象ページIDが未設定です"
            return
        }
        isSyncing = true
        lastSyncError = nil
        do {
            let tasks = try await NotionService.shared.fetchWeeklyTasks()
            self.weeklyTasks = tasks
            self.lastSyncedAt = Date()
        } catch {
            self.lastSyncError = error.localizedDescription
        }
        isSyncing = false
    }

    func toggleTask(_ task: WeeklyTask) async {
        guard let index = weeklyTasks.firstIndex(where: { $0.id == task.id }) else { return }
        let newValue = !weeklyTasks[index].isCompleted
        weeklyTasks[index].isCompleted = newValue
        do {
            try await NotionService.shared.updateTaskCompletion(task, isCompleted: newValue)
        } catch {
            // 失敗したらUIを元に戻す
            weeklyTasks[index].isCompleted = !newValue
            lastSyncError = "Notionへの書き戻しに失敗しました: \(error.localizedDescription)"
        }
    }

    // MARK: - チェックイン（声かけ生成〜通知）

    func performCheckIn(reason: CheckInReason) async {
        await syncWithNotion()
        guard settings.isCheckInEnabled, !settings.isDoNotDisturb else { return }

        do {
            let message = try await ClaudeService.shared.generateCheckInMessage(
                tasks: weeklyTasks,
                reason: reason,
                recentHistory: latestCheckInMessage
            )
            latestCheckInMessage = message
            NotificationService.shared.postCheckInNotification(message: message, reason: reason)
        } catch {
            lastSyncError = "声かけメッセージの生成に失敗しました: \(error.localizedDescription)"
        }
    }

    /// 通知の「確認する」タップ時に呼ばれる。
    /// MenuBarExtra(.window) はプログラムから直接開くAPIが無いため、
    /// アプリを前面化してユーザーにメニューバーアイコンのクリックを促す形にしている。
    /// （TODO: 独立ウィンドウでのポップアップ表示に切り替える場合は isCheckInPopupPresented を使う）
    func openCheckInPopup() {
        Task { await syncWithNotion() }
        isCheckInPopupPresented = true
        NSApp.activate(ignoringOtherApps: true)
    }
}
