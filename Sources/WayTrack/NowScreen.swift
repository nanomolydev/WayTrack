import SwiftUI

struct NowScreen: View {
    @EnvironmentObject var store: Store
    @State private var now = currentMinute()
    @State private var beat = Date()
    @State private var askingUnpredictable = false
    @State private var unpredictableTitle = ""

    private let tick = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 28) {
                    ForEach(Engine.suggestions(from: store.day)) { suggestion in
                        SuggestionRow(title: suggestion.title, count: suggestion.count)
                    }
                    ProgressRing(slot: current, next: next, now: now)
                        .frame(width: 240, height: 240)
                    VStack(spacing: 6) {
                        Text(current?.title ?? "Свободно")
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                        if let next {
                            Text("далее: \(next.title) · \(clockString(next.start))")
                                .font(.system(size: 14, design: .rounded))
                                .foregroundStyle(Theme.faint)
                        }
                    }
                    HStack(spacing: 12) {
                        Button {
                            if store.runningSince == nil { store.startTimer() } else { store.runningSince = nil }
                        } label: {
                            Label(store.runningSince == nil ? "Запустить" : "Остановить",
                                  systemImage: store.runningSince == nil ? "play.fill" : "pause.fill")
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .padding(.horizontal, 18).padding(.vertical, 12)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                        if let since = store.runningSince {
                            Text(elapsed(since)).id(beat)
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(Theme.faint)
                        }
                    }
                    Button {
                        askingUnpredictable = true
                    } label: {
                        Label("Непредсказуемая задача", systemImage: "bolt.fill")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .padding(.horizontal, 18).padding(.vertical, 12)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    Spacer()
                }
                .padding(.top, 24)
                .foregroundStyle(Theme.ink)
            }
            .navigationTitle("Сейчас")
            .navigationBarTitleDisplayMode(.inline)
            .onReceive(tick) { _ in now = currentMinute(); beat = Date() }

            .alert("Что это было?", isPresented: $askingUnpredictable) {
                TextField("Описание", text: $unpredictableTitle)
                Button("Сохранить") {
                    store.captureUnpredictable(title: unpredictableTitle)
                    unpredictableTitle = ""
                    store.startTimer()
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Таймер остановлен, время зафиксировано.")
            }
        }
        .preferredColorScheme(.dark)
    }

    private var current: Engine.Slot? { Engine.slot(at: now, in: store.day) }
    private var next: Engine.Slot? { Engine.nextSlot(after: now, in: store.day) }

    /// Прошедшее время текущего прогона — вторая половина п.22 к оставшемуся в кольце.
    private func elapsed(_ since: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(since)))
        return String(format: "%d:%02d прошло", seconds / 60, seconds % 60)
    }
}

/// Круговой прогресс текущего отрезка: кольцо убывает, в центре — остаток.
private struct ProgressRing: View {
    var slot: Engine.Slot?
    var next: Engine.Slot?
    var now: Int

    /// В паузе между задачами кольцо отсчитывает время до следующей,
    /// иначе пустой день выглядит сломанным.
    private var window: (start: Int, end: Int, color: String)? {
        if let slot { return (slot.start, slot.end, slot.colorHex) }
        if let next { return (now, next.start, next.colorHex) }
        return nil
    }

    private var fraction: Double {
        guard let window, window.end > window.start else { return 0 }
        return 1 - Double(now - window.start) / Double(window.end - window.start)
    }

    private var remaining: Int { max(0, (window?.end ?? now) - now) }

    var body: some View {
        ZStack {
            Circle().stroke(Theme.flask, lineWidth: 16)
            Circle()
                .trim(from: 0, to: max(0, min(1, fraction)))
                .stroke(Color(hex: window?.color ?? "8E8E93").opacity(slot == nil ? 0.4 : 1),
                        style: StrokeStyle(lineWidth: 16, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.4), value: fraction)
            VStack(spacing: 2) {
                Text("\(remaining)")
                    .font(.system(size: 52, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(slot == nil ? "мин до следующей" : "мин осталось")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Theme.faint)
            }
        }
    }
}

private struct SuggestionRow: View {
    @EnvironmentObject var store: Store
    var title: String
    var count: Int

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("«\(title)» — \(count) раз за неделю")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                Text("Сделать постоянной задачей?")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Theme.faint)
            }
            Spacer()
            Button("Да") { store.acceptSuggestion(title) }.buttonStyle(.borderedProminent)
            Button("Нет") { store.dismissSuggestion(title) }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 16)
    }
}
