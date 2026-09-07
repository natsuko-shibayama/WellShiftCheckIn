import Foundation
import AppKit
import CoreGraphics
import Combine

// NOTE: `CatAction` enum は `Models/CatAction.swift`、
//       アクション別のパラメータは `Models/CatBehavior.swift` に分離した。

/// 6章「休憩中の猫アニメーション」の移動ロジック。
/// - デスクトップ全体を行動範囲とし、他アプリウィンドウの上に重ならないよう避けて歩く
/// - 「歩く→座って休む→また歩く」のような緩急をランダムに切り替える
///
/// 実装方針：完全な物理演算は行わず、ランダムウォーク＋障害物（他ウィンドウの矩形）回避程度に留める。
///
/// 行動の選択は `CatBehavior` テーブル駆動。Phase 0 では従来と同じく
/// 「移動（walk）↔ 休息（sit/lieDown/stretch/groom）の交互」に落ち着くよう
/// 各 behavior のウェイト・継続時間を設定している。
@MainActor
final class CatMovementController: ObservableObject {
    static let shared = CatMovementController()
    private init() {}

    @Published var position: CGPoint = .zero
    @Published var action: CatAction = .sit
    @Published var facingRight: Bool = true
    @Published var isVisible: Bool = false

    /// y方向（画面の上下）にも歩き回るか。
    /// Phase 0 では `false` 固定＝従来どおり画面下端（床）だけを水平移動する。
    /// `true` にすると `pickNextTarget()` が床から `verticalRoamRange` の高さ範囲で目標 y を選ぶ。
    /// （Phase 2 で他ウィンドウの天面を歩く等に発展させるための拡張ポイント）
    var verticalRoamingEnabled = false
    private let verticalRoamRange: CGFloat = 160

    /// 猫の表示サイズ。`CatOverlayView` もこれを参照する（位置計算と一致させるため）。
    let catSize = CGSize(width: 200, height: 140)

    private var moveTimer: Timer?
    private var actionTimer: Timer?
    private let stepInterval: TimeInterval = 0.05
    /// `walk` の基準速度（pt/sec）。実際の速度は `action.behavior.speedMultiplier` を掛ける。
    private let baseSpeed: CGFloat = 60

    private var targetPosition: CGPoint?

    func start() {
        guard let screen = NSScreen.main else { return }
        if position == .zero {
            let bounds = screen.visibleFrame
            position = CGPoint(x: bounds.midX, y: bounds.minY + catSize.height)
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
        guard bounds.width > catSize.width * 2 else { return position }
        let obstacles = Self.currentWindowFrames()

        let floorY = bounds.minY + catSize.height // 基本は地面（画面下部）を歩く
        let ceilingY = min(floorY + verticalRoamRange, bounds.maxY - catSize.height)

        for _ in 0..<12 {
            let candidate = CGPoint(
                x: CGFloat.random(in: bounds.minX + catSize.width...bounds.maxX - catSize.width),
                y: (verticalRoamingEnabled && ceilingY > floorY)
                    ? CGFloat.random(in: floorY...ceilingY)
                    : floorY
            )
            let catRect = CGRect(x: candidate.x - catSize.width / 2, y: candidate.y, width: catSize.width, height: catSize.height)
            let overlapsWindow = obstacles.contains { $0.intersects(catRect) }
            if !overlapsWindow {
                return candidate
            }
        }
        // 空きが見つからなくても、多少ウィンドウに重なってでも歩き回る。
        // （休憩中／オーバーレイは最前面・クリックスルーなので作業の邪魔にはならない）
        let x = CGFloat.random(in: bounds.minX + catSize.width...bounds.maxX - catSize.width)
        return CGPoint(x: x, y: floorY)
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

    /// 現在表示されている他アプリのウィンドウ矩形一覧（大まかな回避判定用）。
    /// CGWindow は左上原点・y 下向きなので、猫の座標系（NSScreen 系・左下原点・y 上向き）へ
    /// 変換してから返す。※ この変換漏れが原因で、以前はどのウィンドウとも「重なり」判定になり
    ///   猫がその場から動かないことがあった。
    private static func currentWindowFrames() -> [CGRect] {
        guard let infoList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return [] }

        // グローバル座標の原点は主ディスプレイ。その高さで y を反転する。
        let primaryHeight = (NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.main)?.frame.height ?? 0

        return infoList.compactMap { info -> CGRect? in
            guard let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat] else { return nil }
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { return nil } // 通常のアプリウィンドウのみ
            let cg = CGRect(
                x: boundsDict["X"] ?? 0,
                y: boundsDict["Y"] ?? 0,
                width: boundsDict["Width"] ?? 0,
                height: boundsDict["Height"] ?? 0
            )
            return CGRect(x: cg.minX, y: primaryHeight - cg.maxY, width: cg.width, height: cg.height)
        }
    }
}
