import Foundation
import AppKit
import CoreGraphics
import Combine

enum CatAction: CaseIterable {
    case walk
    case sit
    case lieDown
    case stretch
    case groom
}

/// 6章「休憩中の猫アニメーション」の移動ロジック。
/// - デスクトップ全体を行動範囲とし、他アプリウィンドウの上に重ならないよう避けて歩く
/// - 「歩く→座って休む→また歩く」のような緩急をランダムに切り替える
///
/// 実装方針：完全な物理演算は行わず、ランダムウォーク＋障害物（他ウィンドウの矩形）回避程度に留める。
@MainActor
final class CatMovementController: ObservableObject {
    static let shared = CatMovementController()
    private init() {}

    @Published var position: CGPoint = .zero
    @Published var action: CatAction = .sit
    @Published var facingRight: Bool = true
    @Published var isVisible: Bool = false

    private var moveTimer: Timer?
    private var actionTimer: Timer?
    private let catSize = CGSize(width: 104, height: 72)
    private let stepInterval: TimeInterval = 0.05
    private let speed: CGFloat = 60 // pt/sec

    private var targetPosition: CGPoint?

    func start() {
        guard let screen = NSScreen.main else { return }
        if position == .zero {
            position = CGPoint(x: screen.frame.midX, y: screen.frame.minY + catSize.height)
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
        let restActions: [CatAction] = [.sit, .lieDown, .stretch, .groom]

        // 「歩く」フェーズと「休む」フェーズを緩急つけて切り替える
        let duration = TimeInterval.random(in: 4...9)
        actionTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.action == .walk {
                    self.action = restActions.randomElement() ?? .sit
                    self.targetPosition = nil
                } else {
                    self.action = .walk
                    self.targetPosition = self.pickNextTarget()
                }
                self.scheduleNextAction()
            }
        }
    }

    private func pickNextTarget() -> CGPoint {
        guard let screen = NSScreen.main else { return position }
        let bounds = screen.visibleFrame
        guard bounds.width > catSize.width * 2 else { return position }
        let obstacles = Self.currentWindowFrames()

        for _ in 0..<12 {
            let candidate = CGPoint(
                x: CGFloat.random(in: bounds.minX + catSize.width...bounds.maxX - catSize.width),
                y: bounds.minY + catSize.height // 基本は地面（画面下部）を歩く想定
            )
            let catRect = CGRect(x: candidate.x - catSize.width / 2, y: candidate.y, width: catSize.width, height: catSize.height)
            let overlapsWindow = obstacles.contains { $0.intersects(catRect) }
            if !overlapsWindow {
                return candidate
            }
        }
        return position // 良い候補が見つからなければ現在地に留まる
    }

    private func stepMove() {
        guard action == .walk, let target = targetPosition else { return }
        let dx = target.x - position.x
        let distance = abs(dx)
        let step = speed * stepInterval

        if distance <= step {
            position.x = target.x
            targetPosition = nil
            action = [.sit, .lieDown].randomElement() ?? .sit
        } else {
            facingRight = dx > 0
            position.x += (dx > 0 ? step : -step)
        }
    }

    /// 現在画面に表示されている他アプリのウィンドウ矩形一覧（大まかな回避判定用）
    private static func currentWindowFrames() -> [CGRect] {
        guard let infoList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return [] }

        return infoList.compactMap { info -> CGRect? in
            guard let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat] else { return nil }
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { return nil } // 通常のアプリウィンドウのみ
            return CGRect(
                x: boundsDict["X"] ?? 0,
                y: boundsDict["Y"] ?? 0,
                width: boundsDict["Width"] ?? 0,
                height: boundsDict["Height"] ?? 0
            )
        }
    }
}
