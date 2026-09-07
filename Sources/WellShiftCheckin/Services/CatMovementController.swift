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
/// 行動の選択は `CatBehavior` テーブル駆動。Phase 0 では従来と同じく
/// 「移動（walk）↔ 休息（sit/lieDown/stretch/groom）の交互」に落ち着くよう
/// 各 behavior のウェイト・継続時間を設定している。
///
/// NOTE: 以前あった「他アプリのウィンドウを避けて歩く」処理は、座標系の取り違えで
///       猫が固まる原因になっていたため撤去した。休憩中／オーバーレイは最前面・
///       クリックスルーなので、ウィンドウの前を横切っても作業の邪魔にはならない。
///       ウィンドウ天面を歩く等は Phase 2 で別途設計する。
@MainActor
final class CatMovementController: ObservableObject {
    static let shared = CatMovementController()
    private init() {}

    @Published var position: CGPoint = .zero
    @Published var action: CatAction = .sit
    @Published var facingRight: Bool = true
    @Published var isVisible: Bool = false

    // MARK: - 調整ポイント

    /// 画面に描画する猫の大きさ。**見た目のサイズ変更はここだけ触ればよい。**
    /// （`CatOverlayView` もこの値を参照する。移動計算の余白・床位置もこの値から導出される）
    let displaySize = CGSize(width: 260, height: 182)

    /// `walk` の基準速度（pt/sec）。実際の速度は `action.behavior.speedMultiplier` を掛ける。
    private let baseSpeed: CGFloat = 80

    /// y方向（画面の上下）にも歩き回るか。
    /// `false`＝画面下端（床）だけを水平移動（既定）。`true` で床から最大160ptの高さ範囲を歩く。
    /// （Phase 2 で他ウィンドウの天面を歩く等に発展させるための拡張ポイント）
    var verticalRoamingEnabled = false

    // MARK: -

    private var moveTimer: Timer?
    private var actionTimer: Timer?
    private let stepInterval: TimeInterval = 0.05

    private var targetPosition: CGPoint?

    func start() {
        guard let screen = NSScreen.main else { return }
        if position == .zero {
            let bounds = screen.visibleFrame
            position = CGPoint(x: bounds.midX, y: floorY(in: bounds))
        }
        isVisible = true
        scheduleNextAction()
        moveTimer?.invalidate()
        moveTimer = Timer.scheduledTimer(withTimeInterval: stepInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.stepMove() }
        }
    }

    func stop() {
        isVisible = false
        moveTimer?.invalidate()
        moveTimer = nil
        actionTimer?.invalidate()
        actionTimer = nil
    }

    private func scheduleNextAction() {
        actionTimer?.invalidate()

        // 「移動」フェーズと「休息」フェーズを緩急つけて切り替える
        let duration = TimeInterval.random(in: action.behavior.durationRange)
        actionTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
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
    }

    private func beginRestPhase() {
        // Phase 0: [.sit, .lieDown, .stretch, .groom] から一様ランダム（従来と同じ）
        action = CatAction.restingCandidates.randomElement() ?? .sit
        targetPosition = nil
    }

    private func beginMovePhase() {
        // Phase 0: 移動系は walk のみ（run/explore/exitScreen は behavior.schedulingWeight = 0）。
        //
        // 拡張ポイント：
        // - run / explore を有効化 → behavior の schedulingWeight を上げるだけでここに入る
        // - exitScreen を有効化 → ここで画面外を目標にし、到達後（stepMove）に isVisible=false、
        //   別の端から enterScreen で再登場させる再登場タイマーを追加する
        action = CatAction.movingCandidates.randomElement() ?? .walk
        targetPosition = pickNextTarget()
    }

    private func pickNextTarget() -> CGPoint {
        guard let screen = NSScreen.main else { return position }
        let bounds = screen.visibleFrame
        let margin = displaySize.width / 2
        guard bounds.width > margin * 2 + 40 else { return position }

        let x = CGFloat.random(in: (bounds.minX + margin)...(bounds.maxX - margin))
        let floor = floorY(in: bounds)
        let ceiling = min(floor + 160, bounds.maxY - displaySize.height / 2)
        let y = (verticalRoamingEnabled && ceiling > floor)
            ? CGFloat.random(in: floor...ceiling)
            : floor
        return CGPoint(x: x, y: y)
    }

    /// 画面下端（床）に立ったときの猫の中心 y。`.position` は中心指定なので、
    /// 足元が下端に来るよう表示高さの半分ぶん持ち上げる。
    private func floorY(in bounds: CGRect) -> CGFloat {
        bounds.minY + displaySize.height / 2
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
            facingRight = dx > 0
            position.x += step * (dx / distance)
            position.y += step * (dy / distance)
        }
    }

}
