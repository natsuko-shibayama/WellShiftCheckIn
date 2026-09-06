# Well Shift Check-in（macOSアプリ v0.1）

要件定義書「Well Shift Check-in（仮称）要件定義書」に基づく、Swift/SwiftUIネイティブのmacOSメニューバー常駐アプリです。

実装済み範囲：4章（チェックイン通知）／5章（ポモドーロ）／6章（休憩中の猫アニメーション、※プレースホルダー実装）。

---

## 1. 必要なもの

- macOS 13以降・Xcode 15以降
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)（`.xcodeproj` を `project.yml` から生成するツール）
  ```bash
  brew install xcodegen
  ```
- Notion Integration Token（Notion API）
- Claude APIキー（Anthropic API）

## 2. ビルド手順

```bash
cd WellShiftCheckin
xcodegen generate
open WellShiftCheckin.xcodeproj
```

Xcodeが開いたら、通常通り ⌘R で実行できます。
（`project.yml` の `DEVELOPMENT_TEAM` は空にしてあるので、初回はXcodeのSigning設定でご自身のApple IDチームを選択してください）

## 3. 初期設定（アプリ起動後）

メニューバーのアイコン →「設定…」から以下を入力します。

### Notion連携
1. https://www.notion.so/my-integrations でIntegrationを作成し、Tokenを取得
2. 週次TODOページを開き、右上の「…」→「コネクト」で作成したIntegrationを接続
3. ページURL末尾の32桁の文字列がページID（例: `https://www.notion.so/xxxx/週次TODO-<ここ32桁>`）
4. Token・ページIDを設定画面に入力して「保存」

Notion側では `- [ ]` のMarkdown記法で入力すればNotionが自動的にto_doブロックへ変換するため、アプリはこの標準to_doブロックをそのまま読み書きします（要件3章の運用フローと互換）。

### Claude API連携
1. https://console.anthropic.com でAPIキーを発行
2. 設定画面にAPIキーを入力（モデル名は初期値 `claude-sonnet-4-5` のままでOK。変更したい場合は書き換え可）

いずれのキーもmacOS Keychainに保存され、平文ファイルには保存されません（要件7章準拠）。

## 4. 主な機能と要件書との対応

| 要件書の章 | 実装 |
|---|---|
| 4.2 データ取得 | `NotionService` が週次TODOページのto_doブロックを取得・パース |
| 4.3 声かけメッセージ生成 | `ClaudeService` が要件書記載のプロンプトでClaude APIを呼び出し |
| 4.4 通知タイミング設計 | `ScheduleManager` が時間ベース／タスク連動通知と近接間引きを制御 |
| 4.5 ポップアップ進捗チェック | メニューバーのウィンドウ上でチェック→Notionへ即書き戻し |
| 4.6 設定・カスタマイズ | 設定画面（連携／通知／ポモドーロ／一般タブ） |
| 5章 ポモドーロ | `PomodoroManager`。メニューバーに残り時間表示、ON/OFF設定可 |
| 6章 猫アニメーション | `CatMovementController` + `CatWindowController`（詳細は下記「既知の制約」） |
| 7章 非機能要件 | APIキーはKeychain保存、オフライン時はエラー表示のみでクラッシュしない設計 |

## 5. タスクへの時刻の付け方（タスク連動通知）

Notion側のタスク行に `14:00-14:30` のような時刻表記を含めると、アプリ側で自動的に開始/終了予定時刻としてパースします。

```
- [ ] Rさんコンサル 14:00-14:30
```

時刻表記がないタスクはタスク連動通知の対象外になります（要件4.4の仕様通り）。

## 6. 既知の制約・今後の実装余地（実装フェーズで夫と相談したい点）

- **猫アニメーション（6章）**：現状は SF Symbols（`cat.fill`）を使ったプレースホルダー実装です。要件にある「ちょいリアルめ・実写寄り」のスプライト素材はフリー素材の著作権確認が必要なため未着手です。`CatOverlayView.swift` の `CatSpriteView` を差し替えるだけで、移動ロジック（`CatMovementController`）はそのまま流用できる構成にしてあります。
- **他ウィンドウ回避**：`CGWindowListCopyWindowInfo` で取得した最前面ウィンドウの矩形を避けるようにしていますが、完全な衝突回避ではなく簡易的なランダムウォーク＋障害物回避です（要件6.2の想定通り簡易実装でよいとされています）。
- **通知からのポップアップ直接オープン**：`MenuBarExtra(.window)` はmacOS 13/14時点でプログラムから直接開く公式APIがないため、通知の「確認する」をタップするとアプリが前面化 → メニューバーアイコンをクリックしてもらう形になっています。独立ウィンドウ化したい場合は `CheckInPopupView` を実ウィンドウとして開く形に変更してください。
- **タスク連動通知の時刻抽出**：Notion側でタスクに時刻専用プロパティ（データベース化）を持たせる運用に変えれば、`TaskTimeParser` を使わずより堅牢にできます。
- **サンドボックス**：`project.yml` では App Sandbox + ネットワーク送信のみ許可しています。Keychainアクセス、ログイン項目登録（`SMAppService`）が問題なく動くことを実機で確認してください。

## 7. ディレクトリ構成

```
WellShiftCheckin/
  project.yml                 # XcodeGen設定
  Sources/WellShiftCheckin/
    App/                      # アプリエントリポイント・AppDelegate・AppState
    Models/                   # WeeklyTask, AppSettings, PomodoroState
    Services/                 # Notion/Claude/通知/スケジューラ/ポモドーロ/猫/Keychain/ログイン項目
    Views/                    # メニューバーUI・設定画面・猫オーバーレイ
    Resources/                # Assets.xcassets, 猫スプライト格納予定フォルダ
```
