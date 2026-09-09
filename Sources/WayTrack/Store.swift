import Foundation
import SwiftUI

@MainActor
final class Store: ObservableObject {
    @Published var day = DaySchedule() { didSet { persist() } }
    @Published var dayStart = 0
    @Published var dayEnd = minutesInDay
    /// Запущенный таймер: момент старта прогона (для «непредсказуемой задачи»).
    @Published var runningSince: Date?

    private let url = URL.documentsDirectory.appending(path: "waytrack.json")

    init() {
        if let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder().decode(DaySchedule.self, from: data) {
            day = saved
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(day) else { return }
        try? data.write(to: url, options: .atomic)
        Notifications.reschedule(day)
    }

    // MARK: - Постоянные задачи

    func addFixed(_ task: FixedTask) {
        day.fixed.append(task)
        day.fixed.sort { $0.start < $1.start }
        rebuildAll()
    }

    func removeFixed(_ task: FixedTask) {
        day.fixed.removeAll { $0.id == task.id }
        rebuildAll()
    }

    /// Постоянные задачи двигаться не должны — активные перестраиваются вокруг них.
    private func rebuildAll() {
        day.active = day.active.map { Engine.relayout($0, at: $0.start, fixed: day.fixed) }
    }

    // MARK: - Активные задачи

    func addActive(_ task: ActiveTask) {
        day.active.append(Engine.materialize(task, fixed: day.fixed))
        day.active.sort { $0.start < $1.start }
    }

    func remove(_ task: ActiveTask) { day.active.removeAll { $0.id == task.id } }

    func replace(_ task: ActiveTask) {
        guard let i = day.active.firstIndex(where: { $0.id == task.id }) else { return }
        day.active[i] = task
    }

    /// Перетаскивание с шагом в 1 минуту; обволакивание постоянных задач — внутри layout.
    /// Возвращает задачу, с которой возник конфликт (нужен выбор приоритета).
    @discardableResult
    func move(_ task: ActiveTask, to start: Int) -> ActiveTask? {
        let moved = Engine.relayout(task, at: start, fixed: day.fixed)
        replace(moved)
        return Engine.overlaps(moved, in: day.active).first
    }

    /// Пользователь выбрал приоритетную задачу в конфликте.
    func resolve(priority: ActiveTask, over other: ActiveTask) {
        let (a, b) = Engine.mix(priority: priority, over: other, fixed: day.fixed)
        replace(a)
        replace(b)
        day.active.sort { $0.start < $1.start }
    }

    func rename(segmentSource: UUID, in task: ActiveTask, to title: String) {
        var task = task
        for i in task.segments.indices where task.segments[i].sourceID == segmentSource {
            task.segments[i].title = title
        }
        replace(task)
    }

    // MARK: - Непредсказуемые задачи

    func startTimer() { runningSince = Date() }

    /// Кнопка «Непредсказуемая задача»: стоп таймера и фиксация затраченного времени.
    func captureUnpredictable(title: String) {
        let started = runningSince ?? Date()
        let minutes = max(1, Int(Date().timeIntervalSince(started) / 60))
        day.unpredictable.append(UnpredictableTask(title: title, date: Date(), duration: minutes))
        runningSince = nil
    }

    func acceptSuggestion(_ title: String) {
        let average = day.unpredictable
            .filter { $0.title.lowercased() == title.lowercased() }
            .map(\.duration)
        let duration = average.isEmpty ? 15 : average.reduce(0, +) / average.count
        addFixed(FixedTask(name: title, start: currentMinute(), duration: duration,
                           colorHex: Theme.palette.randomElement() ?? "8E8E93"))
        dismissSuggestion(title)
    }

    func dismissSuggestion(_ title: String) {
        day.dismissedSuggestions.append(title.lowercased())
    }
}
