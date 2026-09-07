import Foundation
import CoreGraphics

/// アクション1種類ぶんの振る舞い定義。
/// スケジューラ（`CatMovementController`）とスプライト再生（`CatSpriteView`）の
/// 双方がこのテーブルを参照する。
///
/// Phase 0 時点の数値は「現行挙動をそのまま維持する」ことを最優先にしている：
/// - 既存5アクションは `schedulingWeight = 1.0` / `durationRange = 4...9` で従来どおり
/// - 追加アクションは `schedulingWeight = 0`（スケジューラが選ばない＝定義のみ）
struct CatBehavior {
    /// 画面内の水平移動を伴うか。
    var isMoving: Bool
    /// `walk` の基準速度に対する速度倍率。
    var speedMultiplier: CGFloat
    /// このアクションを継続する秒数の範囲。
    var durationRange: ClosedRange<TimeInterval>
    /// スケジューラがこのアクションを選ぶ相対ウェイト。0 なら選ばれない。
    var schedulingWeight: Double
    /// スプライトをループ再生するか（false は1周したら最終フレームで停止）。
    var loops: Bool
    /// `Resources/CatSprites/<spriteName>/` のフォルダ名。
    var spriteName: String
    /// スプライトのおおよそのコマ数（素材未確定のうちは目安）。
    var frameCount: Int
    /// スプライト再生 fps。
    var fps: Double
}

extension CatAction {
    var behavior: CatBehavior {
        switch self {
        // --- 既存アクション（現行挙動を維持）---
        case .walk:
            return CatBehavior(isMoving: true, speedMultiplier: 1.0, durationRange: 4...9,
                               schedulingWeight: 1.0, loops: true, spriteName: "walk", frameCount: 8, fps: 12)
        case .sit:
            return CatBehavior(isMoving: false, speedMultiplier: 1.0, durationRange: 4...9,
                               schedulingWeight: 1.0, loops: true, spriteName: "sit", frameCount: 4, fps: 8)
        case .lieDown:
            return CatBehavior(isMoving: false, speedMultiplier: 1.0, durationRange: 4...9,
                               schedulingWeight: 1.0, loops: true, spriteName: "lie_down", frameCount: 3, fps: 6)
        case .stretch:
            return CatBehavior(isMoving: false, speedMultiplier: 1.0, durationRange: 4...9,
                               schedulingWeight: 1.0, loops: true, spriteName: "stretch", frameCount: 4, fps: 12)
        case .groom:
            return CatBehavior(isMoving: false, speedMultiplier: 1.0, durationRange: 4...9,
                               schedulingWeight: 1.0, loops: true, spriteName: "groom", frameCount: 4, fps: 10)

        // --- 追加アクション（Phase 2 以降で有効化・現在は schedulingWeight = 0）---
        case .run:
            return CatBehavior(isMoving: true, speedMultiplier: 2.6, durationRange: 2...4,
                               schedulingWeight: 0, loops: true, spriteName: "run", frameCount: 8, fps: 16)
        case .explore:
            return CatBehavior(isMoving: true, speedMultiplier: 0.7, durationRange: 5...10,
                               schedulingWeight: 0, loops: true, spriteName: "explore", frameCount: 8, fps: 10)
        case .exitScreen:
            return CatBehavior(isMoving: true, speedMultiplier: 1.6, durationRange: 2...5,
                               schedulingWeight: 0, loops: true, spriteName: "walk", frameCount: 8, fps: 12)
        case .enterScreen:
            return CatBehavior(isMoving: true, speedMultiplier: 1.2, durationRange: 2...4,
                               schedulingWeight: 0, loops: true, spriteName: "walk", frameCount: 8, fps: 12)
        case .lookAtViewer:
            return CatBehavior(isMoving: false, speedMultiplier: 1.0, durationRange: 2...4,
                               schedulingWeight: 0, loops: false, spriteName: "look_at_viewer", frameCount: 2, fps: 6)
        case .lookAround:
            return CatBehavior(isMoving: false, speedMultiplier: 1.0, durationRange: 3...5,
                               schedulingWeight: 0, loops: true, spriteName: "look_around", frameCount: 4, fps: 6)
        case .tiltHead:
            return CatBehavior(isMoving: false, speedMultiplier: 1.0, durationRange: 2...3,
                               schedulingWeight: 0, loops: false, spriteName: "tilt_head", frameCount: 2, fps: 6)
        case .yawn:
            return CatBehavior(isMoving: false, speedMultiplier: 1.0, durationRange: 2...3,
                               schedulingWeight: 0, loops: false, spriteName: "yawn", frameCount: 4, fps: 10)
        case .sleepCurl:
            return CatBehavior(isMoving: false, speedMultiplier: 1.0, durationRange: 12...24,
                               schedulingWeight: 0, loops: true, spriteName: "sleep_curl", frameCount: 3, fps: 4)
        case .rollOver:
            return CatBehavior(isMoving: false, speedMultiplier: 1.0, durationRange: 3...6,
                               schedulingWeight: 0, loops: true, spriteName: "roll_over", frameCount: 5, fps: 10)
        case .play:
            return CatBehavior(isMoving: false, speedMultiplier: 1.0, durationRange: 3...6,
                               schedulingWeight: 0, loops: true, spriteName: "play", frameCount: 6, fps: 14)
        }
    }

    /// スケジューラが「移動フェーズ」で選ぶ候補（`schedulingWeight > 0` のもの）。
    /// Phase 0 では `[.walk]` のみ。
    static var movingCandidates: [CatAction] {
        allCases.filter { $0.behavior.isMoving && $0.behavior.schedulingWeight > 0 }
    }

    /// スケジューラが「休息フェーズ」で選ぶ候補（`schedulingWeight > 0` のもの）。
    /// Phase 0 では `[.sit, .lieDown, .stretch, .groom]`。
    static var restingCandidates: [CatAction] {
        allCases.filter { !$0.behavior.isMoving && $0.behavior.schedulingWeight > 0 }
    }
}
