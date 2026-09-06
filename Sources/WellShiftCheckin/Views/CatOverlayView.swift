import SwiftUI

/// 休憩中に画面上を歩き回る猫の見た目。
///
/// NOTE: 要件6.1では「ちょいリアルめ（実写寄り）」なスプライトが求められているが、
/// 本実装では素材未確定のためプレースホルダー（SF Symbols + 簡易モーション）で代替している。
/// 実写寄りのスプライトシート/Lottieが用意でき次第、`CatSpriteView` の中身を差し替えれば
/// 上位の `CatMovementController` のロジックはそのまま流用できる構成にしてある。
struct CatOverlayView: View {
    @ObservedObject var movement = CatMovementController.shared

    var body: some View {
        CatSpriteView(action: movement.action, facingRight: movement.facingRight)
            .frame(width: 96, height: 64)
            .position(x: movement.position.x, y: movement.position.y)
            .opacity(movement.isVisible ? 1 : 0)
            .animation(.easeInOut(duration: 0.6), value: movement.isVisible)
            .allowsHitTesting(false)
    }
}

private struct CatSpriteView: View {
    let action: CatAction
    let facingRight: Bool

    var body: some View {
        Image(systemName: symbolName)
            .resizable()
            .scaledToFit()
            .foregroundStyle(.primary)
            .shadow(radius: 2)
            .scaleEffect(x: facingRight ? 1 : -1, y: 1)
            .rotationEffect(action == .lieDown ? .degrees(90) : .degrees(0))
            .animation(.easeInOut(duration: 0.3), value: action)
    }

    private var symbolName: String {
        switch action {
        case .walk: return "cat.fill"
        case .sit: return "cat.fill"
        case .lieDown: return "cat.fill"
        case .stretch: return "cat.fill"
        case .groom: return "cat.fill"
        }
    }
}
