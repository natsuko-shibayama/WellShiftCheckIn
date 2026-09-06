import SwiftUI

struct DemoCheckInPopupView: View {
    @State private var tasks: [DemoTask] = [
        DemoTask(title: "企画メモを15分だけ整理する 13:30-13:45", section: "今週の最優先タスク"),
        DemoTask(title: "休憩前に今日の残タスクを書き出す", section: "今日のチェックイン"),
        DemoTask(title: "午前中のメール返信を終える", section: "今日のチェックイン", isCompleted: true)
    ]

    private var groupedTasks: [(section: String, tasks: [DemoTask])] {
        Dictionary(grouping: tasks, by: \.section)
            .sorted { $0.key < $1.key }
            .map { (section: $0.key, tasks: $0.value) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Well Shift Check-in")
                .font(.headline)

            Divider()

            Text("午後の作業に入る前に、いま一番進めたいことを1つ選びましょう。完了済みのものは軽く振り返って、次の30分に集中できる状態を作ります。")
                .font(.callout)
                .padding(8)
                .background(Color.accentColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(groupedTasks, id: \.section) { group in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(group.section)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            ForEach(group.tasks) { task in
                                Toggle(isOn: binding(for: task)) {
                                    Text(task.title)
                                        .strikethrough(task.isCompleted)
                                }
                                .toggleStyle(.checkbox)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 240)

            Divider()

            HStack {
                Text("デモ表示中")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(14)
        .frame(width: 340)
    }

    private func binding(for task: DemoTask) -> Binding<Bool> {
        Binding(
            get: {
                tasks.first(where: { $0.id == task.id })?.isCompleted ?? false
            },
            set: { newValue in
                guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
                tasks[index].isCompleted = newValue
            }
        )
    }
}

private struct DemoTask: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var section: String
    var isCompleted: Bool = false
}
