# walk スプライト（Phase 1A）

`walk` アクション時に表示する、飼い猫ベースの半リアル猫の透過PNG連番をここに置く。

## ファイル名

```
walk_01.png
walk_02.png
walk_03.png
walk_04.png
walk_05.png   （任意）
walk_06.png   （任意）
```

- `_01` 始まり（`_00` 始まりでも可）。連番が途切れた時点で打ち切り。
- 4〜6枚程度。枚数は固定しない。
- このフォルダに1枚も無ければ、`walk` も従来のベクター描画（`CatArtist`）にフォールバックする。

## 素材の条件（重要）

- PNG・透過背景
- **全フレーム同一キャンバスサイズ**
- 同一の猫・基本的に同じ向き（逆向きは Swift 側で左右反転するので用意不要）
- **足元（接地点）を全フレームで揃える。** 特に「キャンバス下端から足先までの余白」を一定にする
  - 余白が全フレーム一定なら、`CatWalkSpriteView.baselineOffset` の1値で接地位置を合わせられる
  - フレームごとに足位置がバラつくと猫がブルブル見える → これは素材側で直す

## 差し替え手順

1. PNG をこのフォルダに置く
2. `xcodegen generate`（ファイルを増やしたため）
3. 再ビルド → 休憩に入って `walk` 時だけ半リアル猫になることを確認

## サイズ・動きの調整（コード側・各1か所）

| 調整項目 | 場所 |
|---|---|
| 表示サイズ | `CatMovementController.walkSpriteHeightRatio`（既定 0.55／0.45〜0.60で調整） |
| fps | `CatBehavior` の `.walk` の `fps`（既定 12） |
| 上下動の振幅 | `CatWalkSpriteView.bobAmplitude`（既定 3pt） |
| 伸縮の強さ | `CatWalkSpriteView.scaleJitter`（既定 0.006／0で無効） |
| 接地位置の微調整 | `CatWalkSpriteView.baselineOffset`（既定 0） |
