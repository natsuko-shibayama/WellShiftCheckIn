import SwiftUI

/// メニューバーアイコンをクリックした時に開くウィンドウ（.menuBarExtraStyle(.window)）。
/// チェックインのタスクチェックリスト表示、ポモドーロ操作、設定への導線をまとめる。
struct MenuBarContentView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Divider()

            CheckInTaskListView()
                .environmentObject(appState)

            Divider()

            pomodoroSection

            Divider()

            footer
        }
        .padding(14)
        .frame(width: 340)
        .task {
            if appState.settings.syncOnLaunch {
                await appState.syncWithNotion()
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Well Shift Check-in")
                .font(.headline)
            Spacer()
            if appState.isSyncing {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    Task { await appState.syncWithNotion() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Notionから再取得")
            }
        }
    }

    private var pomodoroSection: some View {
        HStack {
            Toggle("ポモドーロ", isOn: Binding(
                get: { appState.settings.pomodoro.isEnabled },
                set: { appState.settings.pomodoro.isEnabled = $0 }
            ))
            .toggleStyle(.switch)

            Spacer()

            if appState.settings.pomodoro.isEnabled {
                Text(appState.pomodoroState.menuBarLabel)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                Button {
                    PomodoroManager.shared.togglePause()
                } label: {
                    Image(systemName: "playpause.fill")
                }
                .buttonStyle(.plain)

                Button {
                    PomodoroManager.shared.skip()
                } label: {
                    Image(systemName: "forward.end.fill")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var footer: some View {
        HStack {
            Toggle("おやすみモード", isOn: Binding(
                get: { appState.settings.isDoNotDisturb },
                set: { appState.settings.isDoNotDisturb = $0 }
            ))
            .toggleStyle(.switch)
            .font(.caption)

            Spacer()

            settingsButton

            Button("終了") {
                NSApp.terminate(nil)
            }
        }
        .font(.caption)
    }

    /// 設定ウィンドウを開くボタン。
    /// macOS 14以降は `NSApp.sendAction(showSettingsWindow:)` が非推奨のため、
    /// `openSettings` environment action を使う（デプロイ対象をmacOS 14以降に統一）。
    /// LSUIElementアプリ（Dockアイコンなし）はウィンドウを開いた後に明示的にactivateしないと
    /// 前面に出てこないことがあるため、openSettings呼び出し後にもactivateしている。
    private var settingsButton: some View {
        Button("設定…") {
            openSettings()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}

/// 週次タスクのチェックリスト表示。チェック操作は即Notionへ書き戻す。
private struct CheckInTaskListView: View {
    @EnvironmentObject var appState: AppState

    private var groupedBySection: [(section: String, tasks: [WeeklyTask])] {
        let grouped = Dictionary(grouping: appState.weeklyTasks, by: \.section)
        return grouped
            .sorted { $0.key < $1.key }
            .map { (section: $0.key.isEmpty ? "タスク" : $0.key, tasks: $0.value) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let message = appState.latestCheckInMessage {
                Text(message)
                    .font(.callout)
                    .padding(8)
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            if appState.weeklyTasks.isEmpty {
                Text(appState.lastSyncError ?? "今週のタスクはまだありません")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(groupedBySection, id: \.section) { group in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(group.section)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                ForEach(group.tasks) { task in
                                    Toggle(isOn: Binding(
                                        get: { task.isCompleted },
                                        set: { _ in Task { await appState.toggleTask(task) } }
                                    )) {
                                        Text(task.title)
                                            .strikethrough(task.isCompleted)
                                    }
                                    .toggleStyle(.checkbox)
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 220)
            }

            if let error = appState.lastSyncError, !appState.weeklyTasks.isEmpty {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
    }
}
