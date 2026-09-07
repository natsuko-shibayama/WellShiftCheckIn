import SwiftUI
import AppKit

/// Phase 1A：`walk` アクション時だけ表示する、飼い猫ベースの半リアル猫PNGスプライト。
///
/// - フレーム進行は **経過時間ベース**（Timer のカウント回数ではない）。`CatBehavior.walk.fps`（既定12）を使う。
/// - 4〜6枚を12fpsで切り替えるだけのパタパタ感を、**控えめな上下動**と**微小スケール**で補う（半リアルなので誇張しない）。
/// - 左右反転は `CatMovementController.facingRight` をそのまま利用（向き判定を二重実装しない）。
/// - 表示基準は画像中心ではなく **足元（フレーム下端）**。`CatOverlayView` 側で下寄せ配置し、
///   このビューは下端アンカーで拡縮・上下動する。素材の微妙な接地ズレは `baselineOffset` で最小限だけ補正。
///
/// walk 素材が無い／読めない場合はこのビュー自体が使われない（`CatOverlayView` が `CatArtist` を選ぶ）。
struct CatWalkSpriteView: View {
    let frames: [NSImage]
    /// 再生 fps（`CatAction.walk.behavior.fps`）。
    let fps: Double
    /// 進行方向。true=右向き（素材そのまま）／false=左向き（水平反転）。
    let facingRight: Bool
    /// スプライトの表示高さ（pt）。幅は画像のアスペクト比に従う。
    let height: CGFloat

    // MARK: - 手続きモーションの調整（半リアル向けに控えめ）

    /// 歩行中の上下動の振幅（pt）。ぴょこぴょこ跳ねて見えない程度に。
    var bobAmplitude: CGFloat = 3
    /// 上下動1往復ぶんの「ループ数」。1.0 = フレーム1ループで上下1回。
    var bobLoopsPerCycle: Double = 1
    /// ごく軽い伸縮の強さ（0 で無効）。Cartoon 的 squash/stretch は避けるため既定はごく小。
    var scaleJitter: CGFloat = 0.006
    /// 足元の微調整（+ で下、- で上）。素材全体の一定ズレだけをここで吸収する。
    var baselineOffset: CGFloat = 0

    @State private var startedAt = Date.timeIntervalSinceReferenceDate

    var body: some View {
        let count = max(frames.count, 1)

        TimelineView(.animation) { timeline in
            let elapsed = max(0, timeline.date.timeIntervalSinceReferenceDate - startedAt)
            let framePos = elapsed * fps                                   // 経過フレーム（実数）
            let index = clampedIndex(Int(framePos.rounded(.down)) % count, count: count)

            // 歩調（0…1 を繰り返す）。フレームループに同期させて上下動・伸縮を作る。
            let loopProgress = (framePos / Double(count)).truncatingRemainder(dividingBy: 1)
            let wave = sin(loopProgress * bobLoopsPerCycle * 2 * .pi)
            // 上下動は「接地線より上」だけで揺らす（足が地面にめり込まないよう wave-1 を使う）
            let bob = CGFloat((wave - 1) / 2) * bobAmplitude
            let sx = 1 + CGFloat(wave) * scaleJitter
            let sy = 1 - CGFloat(wave) * scaleJitter

            Image(nsImage: frames[index])
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(height: height)
                .scaleEffect(x: (facingRight ? 1 : -1) * sx, y: sy, anchor: .bottom)
                .offset(y: bob + baselineOffset)
        }
    }

    private func clampedIndex(_ i: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let wrapped = ((i % count) + count) % count
        return frames.indices.contains(wrapped) ? wrapped : 0
    }
}
