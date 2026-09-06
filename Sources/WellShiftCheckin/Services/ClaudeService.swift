import Foundation

enum ClaudeServiceError: LocalizedError {
    case missingAPIKey
    case httpError(status: Int, body: String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Claude APIキーが設定されていません（設定画面で入力してください）"
        case .httpError(let status, let body):
            return "Claude API エラー (\(status)): \(body)"
        case .emptyResponse:
            return "Claude APIから空のレスポンスが返されました"
        }
    }
}

/// Claude API 連携: 週次タスク一覧をもとに1〜2文の声かけメッセージを生成する。
/// 4.3節のプロンプト設計に準拠。
final class ClaudeService {
    static let shared = ClaudeService()
    private init() {}

    private let apiURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private let anthropicVersion = "2023-06-01"
    private var model: String = "claude-sonnet-4-5"

    func updateConfig(model: String) {
        self.model = model
    }

    private var apiKey: String? {
        KeychainService.shared.read(.claudeAPIKey)
    }

    func generateCheckInMessage(
        tasks: [WeeklyTask],
        reason: CheckInReason,
        recentHistory: String?
    ) async throws -> String {
        guard let apiKey, !apiKey.isEmpty else { throw ClaudeServiceError.missingAPIKey }

        let prompt = buildPrompt(tasks: tasks, reason: reason, recentHistory: recentHistory)

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 200,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw ClaudeServiceError.httpError(status: http.statusCode, body: bodyText)
        }

        let decoded = try JSONDecoder().decode(ClaudeMessageResponse.self, from: data)
        guard let text = decoded.content.first(where: { $0.type == "text" })?.text,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ClaudeServiceError.emptyResponse
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - プロンプト生成（要件4.3準拠）

    private func buildPrompt(tasks: [WeeklyTask], reason: CheckInReason, recentHistory: String?) -> String {
        let taskListText: String
        if tasks.isEmpty {
            taskListText = "（今週のタスクはまだ登録されていません）"
        } else {
            taskListText = tasks.map { task in
                let mark = task.isCompleted ? "[x]" : "[ ]"
                return "- \(mark) \(task.title)（\(task.section)）"
            }.joined(separator: "\n")
        }

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        let currentTimeText = timeFormatter.string(from: Date())

        let historyText = recentHistory?.isEmpty == false ? recentHistory! : "（なし）"
        let triggerHint: String
        switch reason {
        case .timeBased(let label):
            triggerHint = "今回は「\(label)」のタイミングでの声かけです。"
        case .taskLinked(let task):
            triggerHint = "今回は「\(task.title)」の予定時刻が近いタイミングでの声かけです。"
        case .manual:
            triggerHint = "今回はユーザーが手動でチェックインを開いたタイミングです。"
        }

        return """
        あなたは「なっちゃん」を応援するやさしいコーチです。
        以下は今週のタスク一覧です（未完了・完了の状態付き）：
        \(taskListText)

        現在時刻：\(currentTimeText)
        直近のチェックイン履歴：\(historyText)
        \(triggerHint)

        上記を踏まえて、1〜2文程度の短い声かけメッセージを生成してください。
        - 具体的なタスク名に触れてよい
        - 詰めすぎず、優しいトーンで
        - たまには進捗を聞かず「ちゃんと休んでる？」のようなねぎらいだけでもよい
        - 絵文字は控えめに1つまで
        - メッセージ本文だけを出力し、前置きや説明は不要
        """
    }
}

// MARK: - Claude API レスポンス

private struct ClaudeMessageResponse: Decodable {
    let content: [ContentBlock]

    struct ContentBlock: Decodable {
        let type: String
        let text: String?
    }
}
