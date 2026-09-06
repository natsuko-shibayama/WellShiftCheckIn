import SwiftUI

/// メニューバーに常に表示されるラベル。
/// - ポモドーロが動いている間は残り時間を表示（例: "🍅 18:32"）
/// - 動いていない場合はアプリアイコンのみ
struct MenuBarLabelView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.seal")
            if !appState.pomodoroState.menuBarLabel.isEmpty {
                Text(appState.pomodoroState.menuBarLabel)
                    .monospacedDigit()
            }
        }
    }
}
