import Foundation

enum NotionServiceError: LocalizedError {
    case missingToken
    case missingPageID
    case httpError(status: Int, body: String)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .missingToken:
            return "Notion Integration Tokenが設定されていません（設定画面で入力してください）"
        case .missingPageID:
            return "Notionの対象ページIDが設定されていません"
        case .httpError(let status, let body):
            return "Notion API エラー (\(status)): \(body)"
        case .decodingFailed:
            return "Notionのレスポンス解析に失敗しました"
        }
    }
}

/// Notion API 連携:
/// - 週次TODOページ配下のブロックを取得し `to_do` ブロックを WeeklyTask としてパース
/// - 見出しブロック（heading_1/2/3）をセクション名として各タスクに付与
/// - タスク本文中の "14:00-14:30" のような時刻表記を開始/終了予定時刻としてパース
/// - チェック操作をNotion側の `to_do.checked` に書き戻す（双方向同期）
final class NotionService {
    static let shared = NotionService()
    private init() {}

    private let apiBase = URL(string: "https://api.notion.com/v1")!
    private let notionVersion = "2022-06-28"

    private var pageID: String = ""

    func updateConfig(pageID: String) {
        self.pageID = pageID
    }

    private var token: String? {
        KeychainService.shared.read(.notionToken)
    }

    // MARK: - 取得

    func fetchWeeklyTasks() async throws -> [WeeklyTask] {
        guard let token, !token.isEmpty else { throw NotionServiceError.missingToken }
        guard !pageID.isEmpty else { throw NotionServiceError.missingPageID }

        var tasks: [WeeklyTask] = []
        var currentSection = ""
        var cursor: String? = nil

        repeat {
            let (blocks, nextCursor) = try await fetchChildrenPage(blockID: pageID, token: token, cursor: cursor)
            for block in blocks {
                if let heading = block.headingText {
                    currentSection = heading
                    continue
                }
                if let todo = block.toDo {
                    let rawTitle = todo.plainText
                    let (cleanTitle, start, end) = TaskTimeParser.extractTimes(from: rawTitle)
                    let task = WeeklyTask(
                        id: block.id,
                        title: cleanTitle,
                        isCompleted: todo.checked,
                        section: currentSection,
                        scheduledStart: start,
                        scheduledEnd: end,
                        dueDate: nil
                    )
                    tasks.append(task)
                }
            }
            cursor = nextCursor
        } while cursor != nil

        return tasks
    }

    private func fetchChildrenPage(
        blockID: String,
        token: String,
        cursor: String?
    ) async throws -> (blocks: [NotionBlock], nextCursor: String?) {
        var components = URLComponents(url: apiBase.appendingPathComponent("blocks/\(blockID)/children"), resolvingAgainstBaseURL: false)!
        var queryItems = [URLQueryItem(name: "page_size", value: "100")]
        if let cursor {
            queryItems.append(URLQueryItem(name: "start_cursor", value: cursor))
        }
        components.queryItems = queryItems

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(notionVersion, forHTTPHeaderField: "Notion-Version")

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response: response, data: data)

        let decoded = try JSONDecoder().decode(NotionListResponse.self, from: data)
        return (decoded.results, decoded.hasMore ? decoded.nextCursor : nil)
    }

    // MARK: - 書き戻し

    func updateTaskCompletion(_ task: WeeklyTask, isCompleted: Bool) async throws {
        guard let token, !token.isEmpty else { throw NotionServiceError.missingToken }

        let url = apiBase.appendingPathComponent("blocks/\(task.id)")
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(notionVersion, forHTTPHeaderField: "Notion-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "to_do": ["checked": isCompleted]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response: response, data: data)
    }

    // MARK: - Helpers

    private static func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NotionServiceError.httpError(status: http.statusCode, body: body)
        }
    }
}

// MARK: - Notion レスポンスのデコード用モデル

private struct NotionListResponse: Decodable {
    let results: [NotionBlock]
    let hasMore: Bool
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case results
        case hasMore = "has_more"
        case nextCursor = "next_cursor"
    }
}

private struct NotionBlock: Decodable {
    let id: String
    let type: String
    let toDoRaw: NotionToDo?
    let headingRaw: NotionHeading?

    enum CodingKeys: String, CodingKey {
        case id, type
        case toDo = "to_do"
        case heading1 = "heading_1"
        case heading2 = "heading_2"
        case heading3 = "heading_3"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(String.self, forKey: .type)

        switch type {
        case "to_do":
            toDoRaw = try container.decodeIfPresent(NotionToDo.self, forKey: .toDo)
            headingRaw = nil
        case "heading_1":
            headingRaw = try container.decodeIfPresent(NotionHeading.self, forKey: .heading1)
            toDoRaw = nil
        case "heading_2":
            headingRaw = try container.decodeIfPresent(NotionHeading.self, forKey: .heading2)
            toDoRaw = nil
        case "heading_3":
            headingRaw = try container.decodeIfPresent(NotionHeading.self, forKey: .heading3)
            toDoRaw = nil
        default:
            toDoRaw = nil
            headingRaw = nil
        }
    }

    var toDo: NotionToDo? { toDoRaw }
    var headingText: String? { headingRaw?.plainText }
}

private struct NotionToDo: Decodable {
    let checked: Bool
    let richText: [NotionRichText]

    enum CodingKeys: String, CodingKey {
        case checked
        case richText = "rich_text"
    }

    var plainText: String {
        richText.map(\.plainText).joined()
    }
}

private struct NotionHeading: Decodable {
    let richText: [NotionRichText]

    enum CodingKeys: String, CodingKey {
        case richText = "rich_text"
    }

    var plainText: String {
        richText.map(\.plainText).joined()
    }
}

private struct NotionRichText: Decodable {
    let plainText: String

    enum CodingKeys: String, CodingKey {
        case plainText = "plain_text"
    }
}

// MARK: - タスク本文からの時刻抽出

enum TaskTimeParser {
    /// "Rさんコンサル 14:00-14:30" のようなタスク本文から開始/終了時刻を抽出する。
    /// 対応形式: "14:00-14:30" "14:00〜14:30" "14:00~14:30" "14:00"（終了時刻なし）
    /// 見つからない場合は nil を返し、タイトルはそのまま返す。
    static func extractTimes(from text: String) -> (title: String, start: DateComponents?, end: DateComponents?) {
        let pattern = #"(\d{1,2}):(\d{2})\s*[-〜~]\s*(\d{1,2}):(\d{2})|(\d{1,2}):(\d{2})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return (text, nil, nil)
        }
        let nsText = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)) else {
            return (text, nil, nil)
        }

        func intAt(_ idx: Int) -> Int? {
            guard match.range(at: idx).location != NSNotFound else { return nil }
            return Int(nsText.substring(with: match.range(at: idx)))
        }

        var start: DateComponents?
        var end: DateComponents?

        if let sh = intAt(1), let sm = intAt(2) {
            start = DateComponents(hour: sh, minute: sm)
            if let eh = intAt(3), let em = intAt(4) {
                end = DateComponents(hour: eh, minute: em)
            }
        } else if let sh = intAt(5), let sm = intAt(6) {
            start = DateComponents(hour: sh, minute: sm)
        }

        var cleanTitle = nsText.replacingCharacters(in: match.range, with: "")
        cleanTitle = cleanTitle.trimmingCharacters(in: .whitespaces)
        // 前後に残る括弧やハイフンの掃除
        cleanTitle = cleanTitle.trimmingCharacters(in: CharacterSet(charactersIn: "()（） -"))
        if cleanTitle.isEmpty { cleanTitle = text }

        return (cleanTitle, start, end)
    }
}
