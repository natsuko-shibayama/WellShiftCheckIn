import AppKit
import SwiftUI

/// 猫アニメーションを表示するための、透明・最前面・クリックスルーの
/// デスクトップ全体を覆うオーバーレイウィンドウ。
@MainActor
final class CatWindowController {
    static let shared = CatWindowController()
    private init() {}

    private var window: NSWindow?

    func show() {
        if window == nil {
            createWindow()
        }
        window?.orderFrontRegardless()
        CatMovementController.shared.start(on: window?.screen ?? NSScreen.main)
    }

    func hide() {
        CatMovementController.shared.stop()
        // フェードアウトのアニメーション時間を待ってからウィンドウを隠す
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            self?.window?.orderOut(nil)
        }
    }

    private func createWindow() {
        guard let screen = NSScreen.main else { return }

        let panel = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.ignoresMouseEvents = true // クリックスルー：作業の邪魔をしない
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false

        let hosting = NSHostingView(rootView: CatOverlayView())
        hosting.frame = screen.frame
        panel.contentView = hosting

        self.window = panel
    }
}
