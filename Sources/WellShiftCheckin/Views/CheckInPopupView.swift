import SwiftUI

/// 通知の「確認する」から開く、独立ウィンドウ形式のチェックインポップアップ。
/// メニューバーのポップオーバーと内容は共通（4.5節）だが、通知経由で最前面に出したい場合に使う。
struct CheckInPopupView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        MenuBarContentView()
            .environmentObject(appState)
    }
}
