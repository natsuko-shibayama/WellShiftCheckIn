import Foundation

enum PomodoroPhase: Equatable {
    case work
    case breakTime
}

enum PomodoroState: Equatable {
    case idle
    case working(remainingSeconds: Int, totalSeconds: Int)
    case breakTime(remainingSeconds: Int, totalSeconds: Int)
    case paused(phase: PomodoroPhase, remainingSeconds: Int, totalSeconds: Int)

    /// メニューバー表示用の短い文字列（例: "🍅 18:32"）
    var menuBarLabel: String {
        switch self {
        case .idle:
            return ""
        case .working(let remaining, _):
            return "🍅 \(Self.format(remaining))"
        case .breakTime(let remaining, _):
            return "☕️ \(Self.format(remaining))"
        case .paused(_, let remaining, _):
            return "⏸ \(Self.format(remaining))"
        }
    }

    private static func format(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }
}
