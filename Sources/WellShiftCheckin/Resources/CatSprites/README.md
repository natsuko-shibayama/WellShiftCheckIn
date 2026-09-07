# 猫スプライト素材の格納場所（現状は未使用）

現在の猫アニメーションは `Views/CatOverlayView.swift` の `CatArtist` が
SwiftUI の `Canvas` でベクター描画しており、画像素材は使っていません。

要件6章の「ちょいリアルめ」なスプライト素材（スプライトシート／GIF／Lottie／Rive 等）に
差し替えたくなったら、このフォルダに素材を置き、`CatOverlayView.swift` の
`CatSpriteView`（＝1フレームの見た目）を差し替えてください。
移動ロジック（`Services/CatMovementController.swift`）側の変更は不要です。

フリー素材を使う場合は著作権・ライセンス条件を必ず確認してください（要件6.2参照）。
