import Foundation

/// 休憩中の猫がとる行動。
///
/// 先頭の5つ（`walk` / `sit` / `lieDown` / `stretch` / `groom`）は従来からある行動で、
/// ベクター描画フォールバック（`CatArtist`）が直接描ける「ベースポーズ」でもある。
/// それ以降は Phase 2 以降で有効化予定の行動で、Phase 0 では
/// `behavior.schedulingWeight == 0` のためスケジューラには選ばれない（定義のみ）。
///
/// NOTE: 以前は `CatMovementController` 内に定義していたものを、
/// スケジューラ・スプライト再生の双方から参照できるよう独立ファイルへ移動した。
enum CatAction: String, CaseIterable {
    // 既存（名称・意味を維持）
    case walk
    case sit
    case lieDown
    case stretch
    case groom

    // Phase 2 以降で有効化（現在は定義のみ・スケジューラ対象外）
    case run
    case lookAtViewer
    case sleepCurl
    case rollOver
    case yawn
    case explore
    case play
    case exitScreen
    case enterScreen
    case lookAround
    case tiltHead
}

extension CatAction {
    /// スプライト素材が無いときに `CatArtist` が描くベースポーズ。
    /// 新規アクションも既存5ポーズのいずれかへマッピングして「それらしく」見せる。
    enum ArtistBase {
        case walk, sit, lieDown, stretch, groom
    }

    var artistBase: ArtistBase {
        switch self {
        case .walk, .run, .explore, .exitScreen, .enterScreen:
            return .walk
        case .sit, .lookAtViewer, .lookAround, .tiltHead, .yawn:
            return .sit
        case .lieDown, .sleepCurl, .rollOver:
            return .lieDown
        case .stretch:
            return .stretch
        case .groom, .play:
            return .groom
        }
    }
}
