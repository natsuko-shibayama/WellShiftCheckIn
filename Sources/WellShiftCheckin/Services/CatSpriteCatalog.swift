import AppKit

/// `Resources/CatSprites/` に同梱したPNG連番スプライトを、アクション別に読み込み・キャッシュする。
///
/// 想定する同梱レイアウト（いずれか）:
/// ```
/// Resources/CatSprites/walk/walk_00.png, walk_01.png, ...      // フォルダ参照でバンドルに構造保持
/// Resources/CatSprites/walk_00.png, walk_01.png, ...           // グループ取り込みでフラット化
/// Assets.xcassets 内の "walk_00", "walk_01", ...               // アセットカタログ
/// ```
/// ファイル名は `<spriteName>_<2桁連番>.png`（`spriteName` は `CatBehavior.spriteName`）。
/// 連番は `_00` から始め、見つからなくなった時点で打ち切る。
///
/// **フォールバック契約**：素材が1枚も見つからないアクションでは `frames(for:)` が `nil` を返し、
/// 呼び出し側（`CatSpriteView`）は必ず既存のベクター描画（`CatArtist`）へフォールバックする。
/// Phase 0 では素材を同梱していないため、常に `nil`（＝フォールバック）となる。
@MainActor
final class CatSpriteCatalog {
    static let shared = CatSpriteCatalog()
    private init() {}

    private var cache: [CatAction: [NSImage]] = [:]
    private var scanned: Set<CatAction> = []
    private let maxFrames = 64

    /// アクションのスプライト連番。素材が無ければ `nil`（＝ `CatArtist` フォールバック）。
    func frames(for action: CatAction) -> [NSImage]? {
        if !scanned.contains(action) {
            cache[action] = loadFrames(for: action)
            scanned.insert(action)
        }
        guard let frames = cache[action], !frames.isEmpty else { return nil }
        return frames
    }

    /// 同梱スプライトが1つでも存在するか（デバッグ確認用）。
    var hasAnySprites: Bool {
        CatAction.allCases.contains { frames(for: $0) != nil }
    }

    /// 開発中に素材を差し替えたときのキャッシュ破棄。
    func reload() {
        cache.removeAll()
        scanned.removeAll()
    }

    // MARK: - 読み込み

    private func loadFrames(for action: CatAction) -> [NSImage] {
        let name = action.behavior.spriteName
        var frames: [NSImage] = []
        var index = 0
        while index < maxFrames {
            guard let image = loadFrame(spriteName: name, index: index) else { break }
            frames.append(image)
            index += 1
        }
        return frames
    }

    private func loadFrame(spriteName name: String, index: Int) -> NSImage? {
        let file = String(format: "%@_%02d", name, index)
        let bundle = Bundle.main
        let urls: [URL] = [
            bundle.url(forResource: file, withExtension: "png", subdirectory: "CatSprites/\(name)"),
            bundle.url(forResource: file, withExtension: "png", subdirectory: "CatSprites"),
            bundle.url(forResource: file, withExtension: "png")
        ].compactMap { $0 }

        if let url = urls.first, let image = NSImage(contentsOf: url) {
            return image
        }
        // アセットカタログに入れた場合のフォールバック
        return NSImage(named: file)
    }
}
