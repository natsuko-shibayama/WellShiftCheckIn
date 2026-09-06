import SwiftUI

/// 4.6節「設定・カスタマイズ項目」に対応する設定画面。
struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            ConnectionSettingsTab()
                .environmentObject(appState)
                .tabItem { Label("連携", systemImage: "link") }

            NotificationSettingsTab()
                .environmentObject(appState)
                .tabItem { Label("通知", systemImage: "bell") }

            PomodoroSettingsTab()
                .environmentObject(appState)
                .tabItem { Label("ポモドーロ", systemImage: "timer") }

            GeneralSettingsTab()
                .environmentObject(appState)
                .tabItem { Label("一般", systemImage: "gearshape") }
        }
        .padding(20)
        .frame(width: 460, height: 380)
    }
}

// MARK: - 連携（Notion / Claude）

private struct ConnectionSettingsTab: View {
    @EnvironmentObject var appState: AppState

    @State private var notionToken: String = KeychainService.shared.read(.notionToken) ?? ""
    @State private var claudeAPIKey: String = KeychainService.shared.read(.claudeAPIKey) ?? ""
    @State private var savedMessage: String?

    var body: some View {
        Form {
            Section("Notion連携") {
                SecureField("Integration Token", text: $notionToken)
                TextField("対象ページID", text: Binding(
                    get: { appState.settings.notionPageID },
                    set: { appState.settings.notionPageID = $0 }
                ))
                Text("週次TODOページのURL末尾32桁がページIDです")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Claude API連携") {
                SecureField("APIキー", text: $claudeAPIKey)
                TextField("モデル", text: Binding(
                    get: { appState.settings.claudeModel },
                    set: { appState.settings.claudeModel = $0 }
                ))
            }

            HStack {
                Button("保存") {
                    KeychainService.shared.save(notionToken, for: .notionToken)
                    KeychainService.shared.save(claudeAPIKey, for: .claudeAPIKey)
                    savedMessage = "保存しました"
                    Task { await appState.syncWithNotion() }
                }
                if let savedMessage {
                    Text(savedMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.top, 8)
    }
}

// MARK: - 通知

private struct NotificationSettingsTab: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Toggle("チェックイン通知を有効にする", isOn: Binding(
                get: { appState.settings.isCheckInEnabled },
                set: { appState.settings.isCheckInEnabled = $0 }
            ))
            Toggle("おやすみモード（一時停止）", isOn: Binding(
                get: { appState.settings.isDoNotDisturb },
                set: { appState.settings.isDoNotDisturb = $0 }
            ))

            Section("時間ベース通知") {
                ForEach(appState.settings.timeBasedSlots) { slot in
                    TimeSlotRow(slot: slot)
                        .environmentObject(appState)
                }
            }

            Section("タスク連動通知") {
                Toggle("タスクの開始予定時刻に合わせて通知する", isOn: Binding(
                    get: { appState.settings.isTaskLinkedNotificationEnabled },
                    set: { appState.settings.isTaskLinkedNotificationEnabled = $0 }
                ))
                Stepper(
                    "何分前に通知するか: \(appState.settings.taskLinkedLeadMinutes)分前",
                    value: Binding(
                        get: { appState.settings.taskLinkedLeadMinutes },
                        set: { appState.settings.taskLinkedLeadMinutes = $0 }
                    ),
                    in: 5...60,
                    step: 5
                )
                Stepper(
                    "近接通知の統合しきい値: \(appState.settings.notificationDedupeWindowMinutes)分以内",
                    value: Binding(
                        get: { appState.settings.notificationDedupeWindowMinutes },
                        set: { appState.settings.notificationDedupeWindowMinutes = $0 }
                    ),
                    in: 5...60,
                    step: 5
                )
            }
        }
        .padding(.top, 8)
    }
}

private struct TimeSlotRow: View {
    let slot: TimeBasedNotificationSlot
    @EnvironmentObject var appState: AppState

    private var index: Int? {
        appState.settings.timeBasedSlots.firstIndex(where: { $0.id == slot.id })
    }

    var body: some View {
        if let index {
            HStack {
                Toggle(isOn: Binding(
                    get: { appState.settings.timeBasedSlots[index].isEnabled },
                    set: { appState.settings.timeBasedSlots[index].isEnabled = $0 }
                )) {
                    Text(slot.label)
                        .frame(width: 110, alignment: .leading)
                }
                .toggleStyle(.checkbox)

                Stepper(
                    String(format: "%02d:%02d", appState.settings.timeBasedSlots[index].hour, appState.settings.timeBasedSlots[index].minute),
                    value: Binding(
                        get: { appState.settings.timeBasedSlots[index].hour * 60 + appState.settings.timeBasedSlots[index].minute },
                        set: {
                            appState.settings.timeBasedSlots[index].hour = $0 / 60
                            appState.settings.timeBasedSlots[index].minute = $0 % 60
                        }
                    ),
                    in: 0...1439,
                    step: 15
                )
            }
        }
    }
}

// MARK: - ポモドーロ

private struct PomodoroSettingsTab: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Toggle("ポモドーロ機能を有効にする", isOn: Binding(
                get: { appState.settings.pomodoro.isEnabled },
                set: { appState.settings.pomodoro.isEnabled = $0 }
            ))

            Stepper(
                "作業時間: \(appState.settings.pomodoro.workMinutes)分",
                value: Binding(
                    get: { appState.settings.pomodoro.workMinutes },
                    set: { appState.settings.pomodoro.workMinutes = $0 }
                ),
                in: 5...90,
                step: 5
            )

            Stepper(
                "休憩時間: \(appState.settings.pomodoro.breakMinutes)分",
                value: Binding(
                    get: { appState.settings.pomodoro.breakMinutes },
                    set: { appState.settings.pomodoro.breakMinutes = $0 }
                ),
                in: 1...30
            )

            Text("休憩中は猫アニメーションが画面上に登場します")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }
}

// MARK: - 一般

private struct GeneralSettingsTab: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Toggle("ログイン時に自動起動する", isOn: Binding(
                get: { appState.settings.launchAtLogin },
                set: { newValue in
                    appState.settings.launchAtLogin = newValue
                    LoginItemManager.shared.setEnabled(newValue)
                }
            ))
            Toggle("起動時にNotionと同期する", isOn: Binding(
                get: { appState.settings.syncOnLaunch },
                set: { appState.settings.syncOnLaunch = $0 }
            ))
        }
        .padding(.top, 8)
    }
}
