import Foundation
import AppKit
import CoreGraphics
import Combine

// NOTE: `CatAction` enum は `Models/CatAction.swift`、
//       アクション別のパラメータは `Models/CatBehavior.swift` に分離した。

/// 6章「休憩中の猫アニメーション」の移動ロジック。
/// - 画面下端（床）をランダムウォークし、「歩く→座って休む→また歩く」の緩急をつける
/// - 完全な物理演算は行わない
///
/// 座標系：オーバーレイ窓は対象スクリーン全体を覆い、`CatOverlayView` は SwiftUI の
/// 左上原点・y 下向きで描画する。**このコントローラも同じ左上原点・y 下向き**で位置を持つ
/// （＝ビュー側で座標変換しない）。床の高さ・画面端の余白は `displaySize` と
/// スクリーン情報から導出する。
///
/// 行動選択は `CatBehavior` テーブル駆動。Phase 0 では従来と同じく
/// 「移動（walk）↔ 休息（sit/lieDown/stretch/groom）の交互」に落ち着く設定。
///
/// NOTE: 以前あった「他アプリのウィンドウを避けて歩く」処理は座標系の取り違えで
///       猫が固まる原因になっていたため撤去した。休憩中／オーバーレイは最前面・
///       クリックスルーなので、ウィンドウの前を横切っても作業の邪魔にはならない。
@MainActor
final class CatMovementController: ObservableObject {
    static let shared = CatMovementController()
    private init() {}

    @Published var position: CGPoint = .zero
    @Published var action: CatAction = .sit
    @Published var facingRight: Bool = true
    @Published var isVisible: Bool = false

    // MARK: - 調整ポイント

    /// 猫の高さを画面高さの何割にするか。**見た目の大きさはここだけ触ればよい。**
    /// 休憩を促したいので大きめ。1.0 に近づけるほど画面いっぱい（ただし大きすぎると歩ける幅が減る）。
    var displayHeightRatio: CGFloat = 0.7

    /// 猫の縦横比（幅 = 高さ × これ）。
    private let aspectRatio: CGFloat = 1.43

    /// 実際の描画サイズ（画面サイズ × `displayHeightRatio` から算出）。
    /// `CatOverlayView` もこの値を参照する。移動の余白・床位置もここから導出される。
    var displaySize: CGSize {
        let base = screenSize.height > 0 ? screenSize.height : 800
        let h = max(160, base * displayHeightRatio)
        return CGSize(width: h * aspectRatio, height: h)
    }

    /// Phase 1A: walk スプライト（半リアル猫PNG）の高さを画面高さの何割にするか。
    /// 実写寄りは大きいと圧迫感が出るため、ベクター猫（`displayHeightRatio`）より小さめが自然。
    /// **walk スプライトの大きさ調整はここだけ。** 0.45〜0.60 で試せる。
    var walkSpriteHeightRatio: CGFloat = 0.55

    /// walk スプライトの表示高さ（pt）。幅は画像のアスペクト比に従う（`CatWalkSpriteView`）。
    var walkSpriteHeight: CGFloat {
        let base = screenSize.height > 0 ? screenSize.height : 800
        return max(120, base * walkSpriteHeightRatio)
    }

    /// `walk` の基準速度（pt/sec）。実際の速度は `action.behavior.speedMultiplier` を掛ける。
    private let baseSpeed: CGFloat = 80

    /// y方向（画面の上下）にも歩き回るか。
    /// `false`＝画面下端（床）だけを水平移動（既定）。`true` で床から最大160ptだけ上も歩く。
    /// （Phase 2 で他ウィンドウの天面を歩く等に発展させるための拡張ポイント）
    var verticalRoamingEnabled = false

    // MARK: - 内部状態

    private var moveTimer: Timer?
    private var actionTimer: Timer?
    private let stepInterval: TimeInterval = 0.05
    private var targetPosition: CGPoint?

    private var isRunning = false
    /// オーバーレイが乗っている画面のサイズ（＝窓のサイズ）。
    private var screenSize: CGSize = .zero
    /// 画面下端の Dock（下配置時）の高さ。0＝サイド配置／自動非表示。
    private var bottomInset: CGFloat = 0

    // MARK: - ライフサイクル

    /// 休憩開始時に呼ばれる。`PomodoroManager` が休憩中は毎秒 `show()` を呼ぶため、
    /// **2回目以降の呼び出しはスクリーン情報の更新だけ行い、タイマーは再作成しない**
    /// （でないと行動タイマーが毎秒リセットされ、猫が一生 sit のまま動かない）。
    func start(on screen: NSScreen?) {
        guard let screen else { return }
        screenSize = screen.frame.size
        bottomInset = max(0, screen.visibleFrame.minY - screen.frame.minY)
        isVisible = true

        guard !isRunning else { return }
        isRunning = true

        if position == .zero || !CGRect(origin: .zero, size: screenSize).contains(position) {
            position = CGPoint(x: screenSize.width / 2, y: floorY)
        }
        action = .sit
        targetPosition = nil
        scheduleNextAction()
        restartMoveTimer()
    }

    func stop() {
        isRunning = false
        isVisible = false
        action = .sit
        targetPosition = nil
        moveTimer?.invalidate(); moveTimer = nil
        actionTimer?.invalidate(); actionTimer = nil
    }

    // MARK: - 行動スケジュール

    private func scheduleNextAction() {
        actionTimer?.invalidate()
        let duration = TimeInterval.random(in: action.behavior.durationRange)
        let timer = Timer(timeInterval: duration, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.action.behavior.isMoving {
                    self.beginRestPhase()
                } else {
                    self.beginMovePhase()
                }
                self.scheduleNextAction()
            }
        }
        // ユーザーがスクロール等で操作中でも猫が止まらないよう .common モードで回す
        RunLoop.main.add(timer, forMode: .common)
        actionTimer = timer
    }

    private func beginRestPhase() {
        // Phase 0: [.sit, .lieDown, .stretch, .groom] から一様ランダム
        action = CatAction.restingCandidates.randomElement() ?? .sit
        targetPosition = nil
    }

    private func beginMovePhase() {
        // Phase 0: 移動系は walk のみ（run/explore/exitScreen は behavior.schedulingWeight = 0）。
        // 拡張ポイント：behavior の schedulingWeight を上げれば run/explore もここに入る。
        // exitScreen を有効化するときは、ここで画面外を目標にし、到達後（stepMove）に
        // isVisible=false → 別の端から enterScreen で再登場させる再登場タイマーを足す。
        action = CatAction.movingCandidates.randomElement() ?? .walk
        targetPosition = pickNextTarget()
    }

    // MARK: - 移動

    private func restartMoveTimer() {
        moveTimer?.invalidate()
        let timer = Timer(timeInterval: stepInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.stepMove() }
        }
        RunLoop.main.add(timer, forMode: .common)
        moveTimer = timer
    }

    /// 猫が床に立ったときの中心 y（左上原点）。足元が Dock の上に来るよう表示高さの半分持ち上げる。
    private var floorY: CGFloat {
        max(displaySize.height / 2, screenSize.height - bottomInset - displaySize.height / 2)
    }

    private func pickNextTarget() -> CGPoint {
        let margin = displaySize.width / 2
        guard screenSize.width > margin * 2 + 40 else { return position }

        let x = CGFloat.random(in: margin...(screenSize.width - margin))
        let y: CGFloat
        if verticalRoamingEnabled {
            let lift = min(160, floorY - displaySize.height / 2)
            y = floorY - CGFloat.random(in: 0...max(0, lift))
        } else {
            y = floorY
        }
        return CGPoint(x: x, y: y)
    }

    private func stepMove() {
        guard action.behavior.isMoving, let target = targetPosition else { return }
        let dx = target.x - position.x
        let dy = target.y - position.y
        let distance = hypot(dx, dy)
        let step = baseSpeed * action.behavior.speedMultiplier * stepInterval

        if distance <= step {
            position = target
            targetPosition = nil
            action = [.sit, .lieDown].randomElement() ?? .sit
        } else {
            if abs(dx) > 0.5 { facingRight = dx > 0 }
            position.x += step * (dx / distance)
            position.y += step * (dy / distance)
        }
    }
}
