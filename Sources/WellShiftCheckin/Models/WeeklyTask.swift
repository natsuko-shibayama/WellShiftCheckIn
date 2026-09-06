import Foundation

/// Notionの週次TODOページ内、1つの `- [ ]` / `- [x]` 行に対応するタスク。
struct WeeklyTask: Identifiable, Equatable, Hashable {
    /// Notionブロックのblock_id（書き戻し時に使用）
    let id: String
    /// タスク本文（チェックボックス記号を除いたテキスト）
    var title: String
    /// 完了状態
    var isCompleted: Bool
    /// タスクが属するセクション見出し（例: "🎯 今週の最優先タスク"）
    var section: String
    /// タスク行内に付記された開始予定時刻（あれば）。例: "14:00" のような表記をパースして保持
    var scheduledStart: DateComponents?
    /// タスク行内に付記された終了予定時刻（あれば）
    var scheduledEnd: DateComponents?
    /// タスク行内に付記された締切日（あれば）
    var dueDate: Date?

    var hasScheduledTime: Bool {
        scheduledStart != nil
    }
}

/// なぜチェックインが発火したか（メッセージ生成のトーン調整や重複制御に使う）
enum CheckInReason: Equatable {
    case timeBased(label: String)      // 例: "朝活後", "午後の作業前", "夜の振り返り前"
    case taskLinked(task: WeeklyTask)  // 特定タスクの開始/終了前後
    case manual                        // メニューバーから手動で開いた

    var displayLabel: String {
        switch self {
        case .timeBased(let label): return label
        case .taskLinked(let task): return task.title
        case .manual: return "手動チェックイン"
        }
    }
}
