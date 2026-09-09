import SwiftUI

struct FixedEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var start = 480
    @State private var duration = 30
    @State private var color = Theme.palette[0]

    var body: some View {
        NavigationStack {
            Form {
                TextField("Название", text: $name)
                Stepper("Начало · \(clockString(start))", value: $start, in: 0...(minutesInDay - 1), step: 5)
                Stepper("Длительность · \(duration) мин", value: $duration, in: 5...480, step: 5)
                ColorRow(selection: $color)
                Section("Постоянные задачи") {
                    ForEach(store.day.fixed) { task in
                        HStack {
                            Circle().fill(Color(hex: task.colorHex)).frame(width: 10, height: 10)
                            Text(task.name)
                            Spacer()
                            Text("\(clockString(task.start))–\(clockString(task.end))")
                                .foregroundStyle(Theme.faint).monospacedDigit()
                        }
                    }
                    .onDelete { indexes in
                        for task in indexes.map({ store.day.fixed[$0] }) { store.removeFixed(task) }
                    }
                }
            }
            .navigationTitle("Постоянная задача")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Добавить") {
                        store.addFixed(FixedTask(name: name, start: start, duration: duration, colorHex: color))
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } }
            }
        }
    }
}

struct ActiveEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var start = 540
    @State private var config = CycleConfig()
    @State private var color = Theme.palette[1]

    var body: some View {
        NavigationStack {
            Form {
                TextField("Название", text: $name)
                Stepper("Начало · \(clockString(start))", value: $start, in: 0...(minutesInDay - 1), step: 5)
                Section("Разбиение") {
                    Stepper("Цикл · \(config.cycle) мин", value: $config.cycle, in: 5...180, step: 5)
                    Stepper("Отдых · \(config.rest) мин", value: $config.rest, in: 0...60, step: 1)
                    Stepper("Перерыв каждые \(config.cyclesPerPause) цикла", value: $config.cyclesPerPause, in: 0...10)
                    Stepper("Перерыв · \(config.pause) мин", value: $config.pause, in: 0...120, step: 5)
                    Stepper("Всего работы · \(config.total) мин", value: $config.total, in: 5...720, step: 5)
                }
                ColorRow(selection: $color)
            }
            .navigationTitle("Активная задача")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Добавить") {
                        store.addActive(ActiveTask(name: name, colorHex: color, start: start, config: config))
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } }
            }
        }
    }
}

private struct ColorRow: View {
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Theme.palette, id: \.self) { hex in
                Circle()
                    .fill(Color(hex: hex))
                    .frame(width: 26, height: 26)
                    .overlay { Circle().strokeBorder(.primary, lineWidth: selection == hex ? 2 : 0) }
                    .onTapGesture { selection = hex }
            }
        }
    }
}
