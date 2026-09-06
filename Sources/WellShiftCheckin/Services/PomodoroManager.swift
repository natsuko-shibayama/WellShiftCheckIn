import Foundation

/// 5章「ポモドーロ機能」の状態遷移を管理する。
/// [作業中(30分)] → 終了 → [休憩中(5分): 猫が登場] → 終了 → [作業中(30分)] → ...
final class PomodoroManager {
    static let shared = PomodoroManager()
    private init() {}

    var onStateChanged: ((PomodoroState) -> Void)?

    private var settings = PomodoroSettings()
    private var timer: Timer?
    private var phase: PomodoroPhase = .work
    private var remainingSeconds: Int = 0
    private var totalSeconds: Int = 0
    private var isPaused: Bool = false
    private var isRunning: Bool = false

    func updateSettings(_ newSettings: PomodoroSettings) {
        let wasEnabled = settings.isEnabled
        settings = newSettings

        if newSettings.isEnabled && !wasEnabled {
            startWorkPhase()
        } else if !newSettings.isEnabled && wasEnabled {
            stop()
        }
    }

    func start() {
        guard settings.isEnabled else { return }
        startWorkPhase()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        isPaused = false
        onStateChanged?(.idle)
    }

    func togglePause() {
        guard isRunning else { return }
        isPaused.toggle()
        if isPaused {
            onStateChanged?(.paused(phase: phase, remainingSeconds: remainingSeconds, totalSeconds: totalSeconds))
        } else {
            emitCurrentState()
        }
    }

    func skip() {
        advancePhase()
    }

    // MARK: - Internal

    private func startWorkPhase() {
        phase = .work
        totalSeconds = settings.workMinutes * 60
        remainingSeconds = totalSeconds
        isPaused = false
        isRunning = true
        runTimer()
        emitCurrentState()
    }

    private func startBreakPhase() {
        phase = .breakTime
        totalSeconds = settings.breakMinutes * 60
        remainingSeconds = totalSeconds
        isPaused = false
        runTimer()
        emitCurrentState()
    }

    private func runTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        timer?.tolerance = 0.5
    }

    private func tick() {
        guard isRunning, !isPaused else { return }
        remainingSeconds -= 1
        if remainingSeconds <= 0 {
            advancePhase()
        } else {
            emitCurrentState()
        }
    }

    private func advancePhase() {
        switch phase {
        case .work:
            NotificationService.shared.postPomodoroNotification(
                title: "作業終了",
                body: "お疲れさま！\(settings.breakMinutes)分休憩しよう🍵"
            )
            startBreakPhase()
        case .breakTime:
            NotificationService.shared.postPomodoroNotification(
                title: "休憩終了",
                body: "作業を再開しよう。\(settings.workMinutes)分集中タイム💪"
            )
            startWorkPhase()
        }
    }

    private func emitCurrentState() {
        switch phase {
        case .work:
            onStateChanged?(.working(remainingSeconds: remainingSeconds, totalSeconds: totalSeconds))
        case .breakTime:
            onStateChanged?(.breakTime(remainingSeconds: remainingSeconds, totalSeconds: totalSeconds))
        }
    }
}
