import SwiftUI
import AppKit

/// 休憩中に画面上を歩き回る猫の見た目。
///
/// アクション（`CatAction`）と位置は `CatMovementController` から流し込まれる。
/// 見た目の実体は `CatSpriteView` が担当し、
/// - `Resources/CatSprites/` に該当アクションのPNG連番があればそれをコマ送り再生
/// - 無ければ従来のベクター描画（`CatArtist`）へフォールバック
/// する。Phase 0 では素材未同梱のため常にフォールバック＝従来と同じ見た目。
///
/// 座標系：`CatMovementController` は NSScreen 系（左下原点・y は上向き）で位置を持つ。
/// SwiftUI の `.position` は左上原点・y は下向きなので、ここで y を反転して橋渡しする。
struct CatOverlayView: View {
    @ObservedObject var movement = CatMovementController.shared

    var body: some View {
        GeometryReader { geo in
            CatSpriteView(action: movement.action, facingRight: movement.facingRight)
                .frame(width: movement.displaySize.width, height: movement.displaySize.height)
                .position(
                    x: movement.position.x,
                    y: geo.size.height - movement.position.y // NSScreen(下原点) → SwiftUI(上原点)
                )
                .opacity(movement.isVisible ? 1 : 0)
                .animation(.easeInOut(duration: 0.6), value: movement.isVisible)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - 猫スプライト（スプライト再生 or ベクター描画フォールバック）

struct CatSpriteView: View {
    let action: CatAction
    let facingRight: Bool

    var body: some View {
        Group {
            if let frames = CatSpriteCatalog.shared.frames(for: action) {
                SpriteAnimationView(
                    frames: frames,
                    fps: action.behavior.fps,
                    loops: action.behavior.loops,
                    facingRight: facingRight
                )
                .id(action) // アクションが変わったら再生位置をリセット
            } else {
                // 素材が無いアクションは従来どおりベクター描画へフォールバック
                VectorCatView(action: action, facingRight: facingRight)
            }
        }
        .allowsHitTesting(false)
    }
}

/// PNG連番スプライトのコマ送り再生。
private struct SpriteAnimationView: View {
    let frames: [NSImage]
    let fps: Double
    let loops: Bool
    let facingRight: Bool

    @State private var startedAt = Date.timeIntervalSinceReferenceDate

    var body: some View {
        TimelineView(.animation) { timeline in
            let elapsed = timeline.date.timeIntervalSinceReferenceDate - startedAt
            let raw = max(0, Int((elapsed * fps).rounded(.down)))
            let index = loops ? raw % frames.count : min(raw, frames.count - 1)
            Image(nsImage: frames[index])
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .scaleEffect(x: facingRight ? 1 : -1, y: 1)
        }
    }
}

/// 従来のベクター描画（`TimelineView` + `Canvas` + `CatArtist`）。
/// スプライト素材が無いときのフォールバックとして常に利用可能。
private struct VectorCatView: View {
    let action: CatAction
    let facingRight: Bool

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                var context = context
                // 進行方向にあわせて左右反転
                if !facingRight {
                    context.translateBy(x: size.width, y: 0)
                    context.scaleBy(x: -1, y: 1)
                }
                CatArtist(action: action, time: t, size: size).draw(in: &context)
            }
        }
        .drawingGroup()
    }
}

/// 猫1匹ぶんの描画。基準は「右向き・足元が下端」。
struct CatArtist {
    let action: CatAction
    let time: TimeInterval
    let size: CGSize

    // パレット（キジトラ寄りのオレンジ）
    private let fur = Color(red: 0.97, green: 0.64, blue: 0.33)
    private let furShade = Color(red: 0.86, green: 0.47, blue: 0.18)
    private let belly = Color(red: 1.0, green: 0.96, blue: 0.90)
    private let outline = Color(red: 0.28, green: 0.16, blue: 0.10)
    private let pink = Color(red: 0.99, green: 0.71, blue: 0.73)
    private let eyeColor = Color(red: 0.22, green: 0.38, blue: 0.30)

    private var u: CGFloat { size.height / 72 }        // 基準ユニット
    private var groundY: CGFloat { size.height - 2 * u }
    private var centerX: CGFloat { size.width / 2 }

    func draw(in context: inout GraphicsContext) {
        drawGroundShadow(&context)
        // 新規アクションも既存5ポーズのいずれかにマッピングして描く（CatAction.artistBase）
        switch action.artistBase {
        case .walk:    drawWalking(&context)
        case .sit:     drawSitting(&context)
        case .lieDown: drawLying(&context)
        case .stretch: drawStretching(&context)
        case .groom:   drawGrooming(&context)
        }
    }

    // MARK: 歩く

    private func drawWalking(_ context: inout GraphicsContext) {
        let cadence = 7.6
        let bob = sin(time * cadence * 2) * 1.0 * u
        let bodyCenter = CGPoint(x: centerX, y: groundY - 17 * u + bob)
        let hipY = bodyCenter.y + 7 * u

        // 奥の脚（暗め・逆位相）
        drawLeg(&context, hipX: centerX - 15 * u, hipY: hipY, phase: time * cadence + .pi, color: furShade)
        drawLeg(&context, hipX: centerX + 10 * u, hipY: hipY, phase: time * cadence + .pi * 0.5, color: furShade)

        // しっぽ（歩調にあわせて左右に）
        drawTail(&context, base: CGPoint(x: centerX - 21 * u, y: bodyCenter.y - 2 * u),
                 curl: 0.2 + sin(time * cadence) * 0.18, length: 20 * u)

        drawBody(&context, center: bodyCenter, width: 46 * u, height: 25 * u)

        // 手前の脚（対角の歩様：後ろ左と前右が同時に出る）
        drawLeg(&context, hipX: centerX - 12 * u, hipY: hipY, phase: time * cadence, color: fur)
        drawLeg(&context, hipX: centerX + 12 * u, hipY: hipY, phase: time * cadence + .pi, color: fur)

        let headCenter = CGPoint(x: centerX + 21 * u, y: bodyCenter.y - 8 * u + sin(time * cadence) * 0.6 * u)
        drawHead(&context, center: headCenter, tilt: sin(time * 1.7) * 0.05, blink: blink(period: 4.5))
    }

    // MARK: 座る

    private func drawSitting(_ context: inout GraphicsContext) {
        let breathe = sin(time * 1.6) * 0.4 * u
        let hipY = groundY
        let bodyCenter = CGPoint(x: centerX, y: groundY - 15 * u + breathe)

        // 前脚（そろえて着地）
        drawStraightLeg(&context, at: CGPoint(x: centerX + 9 * u, y: bodyCenter.y + 4 * u), footY: groundY, color: fur)
        drawStraightLeg(&context, at: CGPoint(x: centerX + 13 * u, y: bodyCenter.y + 4 * u), footY: groundY, color: furShade)

        // 体（やや立て気味）
        drawBody(&context, center: bodyCenter, width: 30 * u, height: 30 * u)

        // しっぽ：足元をぐるっと回して先っぽをたまにピクッと
        let flick = (fmod(time, 3.4) < 0.25) ? sin(time * 40) * 0.25 : 0
        drawFrontCurlTail(&context, from: CGPoint(x: centerX - 12 * u, y: hipY - 2 * u),
                          to: CGPoint(x: centerX + 16 * u, y: hipY - 1 * u), wobble: flick)

        let headCenter = CGPoint(x: centerX + 10 * u, y: bodyCenter.y - 16 * u)
        drawHead(&context, center: headCenter, tilt: sin(time * 0.8) * 0.06, blink: blink(period: 3.6))
    }

    // MARK: 寝そべる

    private func drawLying(_ context: inout GraphicsContext) {
        let breathe = 1 + sin(time * 1.3) * 0.05
        let bodyCenter = CGPoint(x: centerX, y: groundY - 6 * u)

        drawTail(&context, base: CGPoint(x: centerX - 24 * u, y: bodyCenter.y),
                 curl: 0.15 + sin(time * 1.1) * 0.1, length: 16 * u)

        var body = context
        body.translateBy(x: bodyCenter.x, y: bodyCenter.y)
        body.scaleBy(x: 1, y: breathe)
        body.translateBy(x: -bodyCenter.x, y: -bodyCenter.y)
        drawBody(&body, center: bodyCenter, width: 54 * u, height: 15 * u)

        // 頭は前足の上にぺたっと
        let headCenter = CGPoint(x: centerX + 21 * u, y: bodyCenter.y - 1 * u)
        drawHead(&context, center: headCenter, tilt: 0.12, blink: 1) // 目は閉じたまま

        // Zzz
        let zAlpha = 0.4 + 0.4 * sin(time * 2)
        context.draw(
            Text("Z z z").font(.system(size: 9 * u, weight: .bold)).foregroundStyle(outline.opacity(zAlpha)),
            at: CGPoint(x: headCenter.x + 12 * u, y: headCenter.y - 12 * u - (sin(time * 2) * 2 * u))
        )
    }

    // MARK: のび

    private func drawStretching(_ context: inout GraphicsContext) {
        // プレイバウ（伏せ拝み）のポーズ。入り→キープ→戻りをなめらかに、ただし常に「のび」て見える下限つき。
        let shape = pow(sin(min(fmod(time, 6.0), .pi)), 0.6)
        let s = 0.35 + 0.65 * shape
        let reach = 14 * u * s                          // 前脚を前へ突き出す量
        let rump = groundY - 22 * u - 3 * u * s         // 腰の高さ

        // 後ろ脚（突っ張り・腰高）
        drawStraightLeg(&context, at: CGPoint(x: centerX - 17 * u, y: rump + 3 * u), footY: groundY, color: furShade)
        drawStraightLeg(&context, at: CGPoint(x: centerX - 13 * u, y: rump + 3 * u), footY: groundY, color: fur)

        // しっぽはピンと上へ
        drawTail(&context, base: CGPoint(x: centerX - 17 * u, y: rump + 1 * u),
                 curl: -0.7 - 0.2 * s, length: 22 * u)

        // 前脚をぐーっと前へ（地面すれすれ）
        let pawX = centerX + 20 * u + reach
        drawStraightLeg(&context, at: CGPoint(x: centerX + 12 * u, y: groundY - 7 * u),
                        footY: groundY - 0.5 * u, footX: pawX, color: furShade)
        drawStraightLeg(&context, at: CGPoint(x: centerX + 12 * u, y: groundY - 7 * u),
                        footY: groundY - 0.5 * u, footX: pawX + 3 * u, color: fur)

        // 反らせた胴：高い腰 → 低く沈んだ胸
        let body = Path { p in
            p.move(to: CGPoint(x: centerX - 17 * u, y: rump))
            p.addQuadCurve(to: CGPoint(x: centerX + 16 * u, y: groundY - 11 * u),
                           control: CGPoint(x: centerX + 1 * u, y: rump - 3 * u))
            p.addQuadCurve(to: CGPoint(x: centerX + 19 * u, y: groundY - 3 * u),
                           control: CGPoint(x: centerX + 22 * u, y: groundY - 6 * u))
            p.addQuadCurve(to: CGPoint(x: centerX - 15 * u, y: groundY - 11 * u),
                           control: CGPoint(x: centerX + 1 * u, y: groundY - 4 * u))
            p.closeSubpath()
        }
        context.fill(body, with: .color(fur))
        // おなかの白
        context.fill(
            Ellipse().path(in: CGRect(x: centerX - 6 * u, y: groundY - 12 * u, width: 22 * u, height: 8 * u)),
            with: .color(belly)
        )
        // 縞
        for i in 0..<3 {
            let x = centerX - 8 * u + CGFloat(i) * 8 * u
            var stripe = Path()
            stripe.move(to: CGPoint(x: x, y: rump - 1 * u + CGFloat(i) * 2 * u))
            stripe.addQuadCurve(to: CGPoint(x: x + 3 * u, y: groundY - 8 * u),
                                control: CGPoint(x: x + 5 * u, y: groundY - 14 * u))
            context.stroke(stripe, with: .color(furShade), style: StrokeStyle(lineWidth: 2 * u, lineCap: .round))
        }
        context.stroke(body, with: .color(outline), lineWidth: 1.4 * u)

        let headCenter = CGPoint(x: centerX + 19 * u + reach * 0.5, y: groundY - 6 * u)
        drawHead(&context, center: headCenter, tilt: 0.5, blink: 0.55 + 0.35 * shape)
    }

    // MARK: 毛づくろい

    private func drawGrooming(_ context: inout GraphicsContext) {
        let lick = sin(time * 7)
        let bodyCenter = CGPoint(x: centerX, y: groundY - 15 * u)
        let hipY = groundY

        drawStraightLeg(&context, at: CGPoint(x: centerX + 13 * u, y: bodyCenter.y + 4 * u), footY: groundY, color: furShade)
        drawBody(&context, center: bodyCenter, width: 30 * u, height: 30 * u)

        // 持ち上げた前脚（なめる対象）
        let pawTip = CGPoint(x: centerX + 15 * u, y: bodyCenter.y - 8 * u + lick * 1.5 * u)
        var leg = Path()
        leg.move(to: CGPoint(x: centerX + 8 * u, y: bodyCenter.y + 3 * u))
        leg.addQuadCurve(to: pawTip, control: CGPoint(x: centerX + 16 * u, y: bodyCenter.y - 2 * u))
        context.stroke(leg, with: .color(fur), style: StrokeStyle(lineWidth: 6 * u, lineCap: .round))
        context.stroke(leg, with: .color(outline), style: StrokeStyle(lineWidth: 7.4 * u, lineCap: .round))
        context.stroke(leg, with: .color(fur), style: StrokeStyle(lineWidth: 6 * u, lineCap: .round))

        let flick = (fmod(time, 3.4) < 0.25) ? sin(time * 40) * 0.25 : 0
        drawFrontCurlTail(&context, from: CGPoint(x: centerX - 12 * u, y: hipY - 2 * u),
                          to: CGPoint(x: centerX + 4 * u, y: hipY - 1 * u), wobble: flick)

        // 頭を下げて舌でペロペロ
        let headCenter = CGPoint(x: centerX + 11 * u, y: bodyCenter.y - 11 * u + lick * 2.4 * u)
        drawHead(&context, center: headCenter, tilt: 0.55 + lick * 0.05, blink: 1)
    }

    /// 足元にふわっと落ちる楕円の影。歩行中は歩調で少し伸び縮みする。
    private func drawGroundShadow(_ context: inout GraphicsContext) {
        let base = action.artistBase
        let pulse = base == .walk ? 1 + sin(time * 15.2) * 0.08 : 1
        let w = (base == .lieDown || base == .stretch ? 58 : 40) * u * pulse
        let rect = CGRect(x: centerX - w / 2, y: groundY - 1.5 * u, width: w, height: 7 * u)
        context.fill(Ellipse().path(in: rect), with: .color(.black.opacity(0.16)))
    }

    // MARK: - パーツ

    private func drawBody(_ context: inout GraphicsContext, center: CGPoint, width: CGFloat, height: CGFloat) {
        let rect = CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
        let path = Path(roundedRect: rect, cornerSize: CGSize(width: height / 2, height: height / 2))
        context.fill(path, with: .color(fur))

        // おなかの白
        let bellyRect = rect.insetBy(dx: width * 0.14, dy: height * 0.18).offsetBy(dx: 0, dy: height * 0.22)
        context.fill(Ellipse().path(in: bellyRect), with: .color(belly))

        // キジトラの縞
        for i in 0..<3 {
            let x = rect.minX + width * (0.32 + CGFloat(i) * 0.18)
            var stripe = Path()
            stripe.move(to: CGPoint(x: x, y: rect.minY + height * 0.12))
            stripe.addQuadCurve(to: CGPoint(x: x + 3 * u, y: rect.midY),
                                control: CGPoint(x: x + 5 * u, y: rect.minY + height * 0.3))
            context.stroke(stripe, with: .color(furShade), style: StrokeStyle(lineWidth: 2 * u, lineCap: .round))
        }
        context.stroke(path, with: .color(outline), lineWidth: 1.4 * u)
    }

    private func drawHead(_ context: inout GraphicsContext, center: CGPoint, tilt: CGFloat, blink: CGFloat) {
        var context = context
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: .radians(tilt))
        context.translateBy(x: -center.x, y: -center.y)

        let r: CGFloat = 12 * u

        // 耳
        for sign in [CGFloat(-1), CGFloat(1)] {
            var ear = Path()
            let baseX = center.x + sign * 7 * u
            ear.move(to: CGPoint(x: baseX - 4 * u, y: center.y - r * 0.6))
            ear.addLine(to: CGPoint(x: baseX + sign * 2 * u, y: center.y - r * 1.7))
            ear.addLine(to: CGPoint(x: baseX + 5 * u, y: center.y - r * 0.5))
            ear.closeSubpath()
            context.fill(ear, with: .color(fur))
            context.stroke(ear, with: .color(outline), lineWidth: 1.2 * u)
            var inner = Path()
            inner.move(to: CGPoint(x: baseX - 1 * u, y: center.y - r * 0.7))
            inner.addLine(to: CGPoint(x: baseX + sign * 1.5 * u, y: center.y - r * 1.35))
            inner.addLine(to: CGPoint(x: baseX + 3 * u, y: center.y - r * 0.65))
            inner.closeSubpath()
            context.fill(inner, with: .color(pink))
        }

        // 顔
        let face = Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r * 0.95, width: r * 2, height: r * 1.9))
        context.fill(face, with: .color(fur))
        context.stroke(face, with: .color(outline), lineWidth: 1.4 * u)

        // ほっぺの白
        context.fill(
            Ellipse().path(in: CGRect(x: center.x - r * 0.5, y: center.y + r * 0.1, width: r, height: r * 0.85)),
            with: .color(belly)
        )

        // 目（blink: 0=ぱっちり, 1=閉じ）
        let eyeH = max(0.12, 1 - blink) * 3.4 * u
        for sign in [CGFloat(-1), CGFloat(1)] {
            let ec = CGPoint(x: center.x + sign * 5 * u, y: center.y - 1 * u)
            if eyeH < 0.8 * u {
                var l = Path()
                l.move(to: CGPoint(x: ec.x - 2.4 * u, y: ec.y))
                l.addQuadCurve(to: CGPoint(x: ec.x + 2.4 * u, y: ec.y),
                               control: CGPoint(x: ec.x, y: ec.y + 1.6 * u))
                context.stroke(l, with: .color(outline), style: StrokeStyle(lineWidth: 1.3 * u, lineCap: .round))
            } else {
                context.fill(
                    Ellipse().path(in: CGRect(x: ec.x - 2.4 * u, y: ec.y - eyeH / 2, width: 4.8 * u, height: eyeH)),
                    with: .color(eyeColor)
                )
                context.fill(
                    Ellipse().path(in: CGRect(x: ec.x - 0.6 * u, y: ec.y - eyeH / 2, width: 1.6 * u, height: min(eyeH, 2 * u))),
                    with: .color(.white)
                )
            }
        }

        // 鼻と口
        var nose = Path()
        nose.move(to: CGPoint(x: center.x - 1.6 * u, y: center.y + 3.2 * u))
        nose.addLine(to: CGPoint(x: center.x + 1.6 * u, y: center.y + 3.2 * u))
        nose.addLine(to: CGPoint(x: center.x, y: center.y + 4.8 * u))
        nose.closeSubpath()
        context.fill(nose, with: .color(pink))

        var mouth = Path()
        mouth.move(to: CGPoint(x: center.x, y: center.y + 4.8 * u))
        mouth.addLine(to: CGPoint(x: center.x, y: center.y + 6 * u))
        mouth.addQuadCurve(to: CGPoint(x: center.x - 3 * u, y: center.y + 6.5 * u),
                           control: CGPoint(x: center.x - 1.5 * u, y: center.y + 7 * u))
        mouth.move(to: CGPoint(x: center.x, y: center.y + 6 * u))
        mouth.addQuadCurve(to: CGPoint(x: center.x + 3 * u, y: center.y + 6.5 * u),
                           control: CGPoint(x: center.x + 1.5 * u, y: center.y + 7 * u))
        context.stroke(mouth, with: .color(outline), style: StrokeStyle(lineWidth: 1 * u, lineCap: .round))

        // ひげ
        for row in [CGFloat(-1), 0, 1] {
            for sign in [CGFloat(-1), CGFloat(1)] {
                var w = Path()
                let y = center.y + 3.5 * u + row * 1.8 * u
                w.move(to: CGPoint(x: center.x + sign * 3 * u, y: y))
                w.addLine(to: CGPoint(x: center.x + sign * 13 * u, y: y + row * 1.2 * u))
                context.stroke(w, with: .color(outline.opacity(0.5)), lineWidth: 0.7 * u)
            }
        }
    }

    /// 歩行用の脚：股関節→ひざ→足先。位相で前後に振り、前に振り出すときだけ持ち上げる。
    private func drawLeg(_ context: inout GraphicsContext, hipX: CGFloat, hipY: CGFloat, phase: Double, color: Color) {
        let swing = CGFloat(sin(phase)) * 5 * u
        let lift = max(0, CGFloat(cos(phase))) * 3.5 * u
        let footX = hipX + swing
        let footY = groundY - lift
        let knee = CGPoint(x: hipX + swing * 0.45, y: (hipY + footY) / 2 + 1.5 * u)
        var leg = Path()
        leg.move(to: CGPoint(x: hipX, y: hipY))
        leg.addLine(to: knee)
        leg.addLine(to: CGPoint(x: footX, y: footY))
        context.stroke(leg, with: .color(outline), style: StrokeStyle(lineWidth: 5.8 * u, lineCap: .round, lineJoin: .round))
        context.stroke(leg, with: .color(color), style: StrokeStyle(lineWidth: 4.2 * u, lineCap: .round, lineJoin: .round))
        // 肉球
        context.fill(Ellipse().path(in: CGRect(x: footX - 3.2 * u, y: footY - 1.6 * u, width: 6.4 * u, height: 3.4 * u)),
                     with: .color(color))
    }

    private func drawStraightLeg(_ context: inout GraphicsContext, at hip: CGPoint, footY: CGFloat, footX: CGFloat? = nil, color: Color) {
        let foot = CGPoint(x: footX ?? hip.x, y: footY)
        var leg = Path()
        leg.move(to: hip)
        leg.addLine(to: foot)
        context.stroke(leg, with: .color(outline), style: StrokeStyle(lineWidth: 6 * u, lineCap: .round))
        context.stroke(leg, with: .color(color), style: StrokeStyle(lineWidth: 4.4 * u, lineCap: .round))
        context.fill(Ellipse().path(in: CGRect(x: foot.x - 3 * u, y: foot.y - 2 * u, width: 6 * u, height: 3.4 * u)),
                     with: .color(color))
    }

    /// 立っている/寝ているときの、後ろへ伸びるしっぽ。
    private func drawTail(_ context: inout GraphicsContext, base: CGPoint, curl: CGFloat, length: CGFloat) {
        let end = CGPoint(x: base.x - length, y: base.y - length * curl)
        let control = CGPoint(x: base.x - length * 0.5, y: base.y - length * (curl + 0.5))
        var tail = Path()
        tail.move(to: base)
        tail.addQuadCurve(to: end, control: control)
        context.stroke(tail, with: .color(outline), style: StrokeStyle(lineWidth: 6.4 * u, lineCap: .round))
        context.stroke(tail, with: .color(fur), style: StrokeStyle(lineWidth: 4.8 * u, lineCap: .round))
        context.stroke(Path { p in
            p.move(to: CGPoint(x: end.x + 2 * u, y: end.y)); p.addLine(to: end)
        }, with: .color(furShade), style: StrokeStyle(lineWidth: 4.8 * u, lineCap: .round))
    }

    /// 座り姿勢で、体の前をぐるっと回り込むしっぽ。
    private func drawFrontCurlTail(_ context: inout GraphicsContext, from: CGPoint, to: CGPoint, wobble: CGFloat) {
        var tail = Path()
        tail.move(to: from)
        tail.addQuadCurve(to: to, control: CGPoint(x: (from.x + to.x) / 2, y: from.y + 10 * u + wobble * 10 * u))
        context.stroke(tail, with: .color(outline), style: StrokeStyle(lineWidth: 6.4 * u, lineCap: .round))
        context.stroke(tail, with: .color(fur), style: StrokeStyle(lineWidth: 4.8 * u, lineCap: .round))
        context.fill(Ellipse().path(in: CGRect(x: to.x - 2.4 * u, y: to.y - 2.4 * u, width: 4.8 * u, height: 4.8 * u)),
                     with: .color(furShade))
    }

    /// period 秒ごとに一瞬だけ 1 に近づく（まばたき）。
    private func blink(period: Double) -> CGFloat {
        let x = fmod(time, period)
        return x < 0.14 ? CGFloat(sin(x / 0.14 * .pi)) : 0
    }
}
