import Foundation

/// Чистая логика таймлайна: генерация циклов, обволакивание постоянных задач,
/// смешивание активных задач. Ни одного импорта UI — тестируется отдельно.
public enum Engine {

    /// Шаг перемещения по таймлайну — 1 минута (см. ТЗ «масштаб изменения»).
    public static let step = 1

    public static func snap(_ minute: Int) -> Int { (minute / step) * step }

    // MARK: - Генерация циклов

    /// Логическая последовательность цикл → отдых → … → перерыв → … из конфига.
    /// `start`/`id` здесь неважны: раскладывает по времени `layout`.
    public static func build(_ config: CycleConfig) -> [Segment] {
        guard config.cycle > 0, config.total > 0 else { return [] }
        var items: [Segment] = []
        var worked = 0
        var index = 0
        while worked < config.total {
            let len = min(config.cycle, config.total - worked)
            index += 1
            items.append(Segment(kind: .cycle, duration: len, title: "Цикл \(index)"))
            worked += len
            if worked >= config.total { break }
            let pauseDue = config.cyclesPerPause > 0 && index % config.cyclesPerPause == 0 && config.pause > 0
            if pauseDue {
                items.append(Segment(kind: .pause, duration: config.pause, title: "Перерыв"))
            } else if config.rest > 0 {
                items.append(Segment(kind: .rest, duration: config.rest, title: "Отдых"))
            }
        }
        return items
    }

    /// Обратная операция: склеить нарезанные куски обратно в логические сегменты.
    public static func items(of task: ActiveTask) -> [Segment] {
        var out: [Segment] = []
        for s in task.segments.sorted(by: { $0.start < $1.start }) {
            if var last = out.last, last.sourceID == s.sourceID {
                last.duration += s.duration
                out[out.count - 1] = last
            } else {
                var copy = s
                copy.start = 0
                out.append(copy)
            }
        }
        return out
    }

    // MARK: - Обволакивание

    /// Укладывает последовательность сегментов начиная с `start`, обходя постоянные задачи.
    /// Сегмент, заступивший на территорию постоянной, делится: часть до неё остаётся
    /// на месте, остаток переносится за неё — вместе со всем, что шло следом.
    public static func layout(_ items: [Segment], from start: Int,
                              avoiding fixed: [FixedTask], dayEnd: Int = minutesInDay) -> [Segment] {
        let blocks = fixed.sorted { $0.start < $1.start }
        var out: [Segment] = []
        var t = max(0, snap(start))
        for item in items {
            var remaining = item.duration
            while remaining > 0 && t < dayEnd {
                if let hit = blocks.first(where: { $0.contains(t) }) { t = hit.end; continue }
                let next = blocks.first(where: { $0.start > t })?.start ?? dayEnd
                let take = min(remaining, next - t)
                if take <= 0 { break }
                var piece = item
                piece.id = UUID()
                piece.start = t
                piece.duration = take
                out.append(piece)
                t += take
                remaining -= take
            }
        }
        return out
    }

    /// Пересобрать задачу из её текущих сегментов (после перетаскивания).
    public static func relayout(_ task: ActiveTask, at start: Int, fixed: [FixedTask]) -> ActiveTask {
        var task = task
        let source = task.segments.isEmpty ? build(task.config) : items(of: task)
        task.start = max(0, snap(start))
        task.segments = layout(source, from: task.start, avoiding: fixed)
        return task
    }

    /// Свежая задача из конфига.
    public static func materialize(_ task: ActiveTask, fixed: [FixedTask]) -> ActiveTask {
        var task = task
        task.segments = layout(build(task.config), from: task.start, avoiding: fixed)
        return task
    }

    // MARK: - Смешивание

    /// `a` — приоритетная задача, наехавшая на `b`. Возвращает обе после разрешения.
    ///
    /// Правила ТЗ:
    /// * начало `a` попало в отдых/перерыв `b` → отдых `b` не трогаем, `a` начинается после него;
    /// * начало `a` попало в цикл `b` → цикл `b` режется в точке касания, между хвостом
    ///   и первым циклом `a` встаёт отдых длиной `a.config.rest`;
    /// * на перекрытом отрезке сегменты `b` затираются сегментами `a`.
    /// Столкновение «задом» — зеркально относительно конца `a`.
    public static func mix(priority a: ActiveTask, over b: ActiveTask,
                           fixed: [FixedTask]) -> (ActiveTask, ActiveTask) {
        guard a.start < b.end, a.end > b.start else { return (a, b) }
        return a.start >= b.start
            ? mixForward(a, b, fixed)
            : mixBackward(a, b, fixed)
    }

    private static func mixForward(_ a: ActiveTask, _ b: ActiveTask,
                                   _ fixed: [FixedTask]) -> (ActiveTask, ActiveTask) {
        var a = a, b = b
        let touch = a.start
        let hit = b.segment(at: touch)
        let cut: Int
        var bridge: Segment?
        if let hit, hit.kind != .cycle {
            cut = hit.end                                   // отдых/перерыв b остаётся целым
        } else if hit != nil, a.config.rest > 0 {
            cut = touch + a.config.rest
            bridge = Segment(kind: .rest, start: touch, duration: a.config.rest,
                             title: "Отдых", colorHex: a.colorHex)
        } else {
            cut = touch
        }

        a = relayout(a, at: cut, fixed: fixed)
        b.segments = trim(b.segments, erasing: min(touch, cut)..<a.end, keepWhole: hit?.kind == .cycle ? nil : hit?.id)
        if let bridge { b.segments.append(bridge) }
        b.segments.sort { $0.start < $1.start }
        return (a, b)
    }

    private static func mixBackward(_ a: ActiveTask, _ b: ActiveTask,
                                    _ fixed: [FixedTask]) -> (ActiveTask, ActiveTask) {
        var a = a, b = b
        let touch = a.end
        let hit = b.segment(at: touch) ?? b.segments.first
        let cut: Int
        var bridge: Segment?
        if let hit, hit.kind != .cycle {
            cut = hit.start                                 // отдых/перерыв b остаётся целым
        } else if hit != nil, a.config.rest > 0 {
            cut = touch - a.config.rest
            bridge = Segment(kind: .rest, start: cut, duration: a.config.rest,
                             title: "Отдых", colorHex: a.colorHex)
        } else {
            cut = touch
        }

        let length = a.end - a.start
        a = relayout(a, at: max(0, cut - length), fixed: fixed)
        b.segments = trim(b.segments, erasing: a.start..<max(touch, cut), keepWhole: hit?.kind == .cycle ? nil : hit?.id)
        if let bridge { b.segments.append(bridge) }
        b.segments.sort { $0.start < $1.start }
        return (a, b)
    }

    /// Вырезает интервал из набора сегментов; `keepWhole` — сегмент, который нельзя резать.
    private static func trim(_ segments: [Segment], erasing range: Range<Int>, keepWhole: UUID?) -> [Segment] {
        var out: [Segment] = []
        for s in segments {
            if s.id == keepWhole { out.append(s); continue }
            if s.end <= range.lowerBound || s.start >= range.upperBound { out.append(s); continue }
            if s.start < range.lowerBound {                 // хвост слева
                var head = s
                head.duration = range.lowerBound - s.start
                out.append(head)
            }
            if s.end > range.upperBound {                   // хвост справа
                var tail = s
                tail.id = UUID()
                tail.start = range.upperBound
                tail.duration = s.end - range.upperBound
                out.append(tail)
            }
        }
        return out
    }

    // MARK: - Запросы

    /// Активная задача, чья территория накрывает минуту.
    public static func overlaps(_ task: ActiveTask, in tasks: [ActiveTask]) -> [ActiveTask] {
        tasks.filter { $0.id != task.id && $0.start < task.end && $0.end > task.start }
    }

    public struct Slot: Hashable, Sendable {
        public var title: String
        public var kind: SegmentKind?
        public var start: Int
        public var end: Int
        public var colorHex: String
        public var isFixed: Bool
    }

    /// Что происходит в минуту `minute` и что будет следующим.
    public static func slot(at minute: Int, in day: DaySchedule) -> Slot? {
        if let f = day.fixed.first(where: { $0.contains(minute) }) {
            return Slot(title: f.name, kind: nil, start: f.start, end: f.end,
                        colorHex: f.colorHex, isFixed: true)
        }
        for t in day.active {
            if let s = t.segment(at: minute) {
                let label: String
                switch s.kind {
                case .cycle: label = s.title ?? t.name
                case .rest: label = "Отдых · \(t.name)"
                case .pause: label = "Перерыв · \(t.name)"
                }
                return Slot(title: label, kind: s.kind, start: s.start, end: s.end,
                            colorHex: s.colorHex ?? t.colorHex, isFixed: false)
            }
        }
        return nil
    }

    public static func nextSlot(after minute: Int, in day: DaySchedule) -> Slot? {
        var m = minute + 1
        let current = slot(at: minute, in: day)
        while m < minutesInDay {
            if let s = slot(at: m, in: day), s != current { return s }
            m += 1
        }
        return nil
    }

    public struct Suggestion: Identifiable, Hashable, Sendable {
        public var title: String
        public var count: Int
        public var id: String { title }
    }

    /// Непредсказуемые задачи, повторявшиеся за неделю чаще порога.
    public static func suggestions(from day: DaySchedule, now: Date = Date()) -> [Suggestion] {
        let weekAgo = now.addingTimeInterval(-7 * 86400)
        var counts: [String: (title: String, count: Int)] = [:]
        for t in day.unpredictable where t.date >= weekAgo {
            let key = t.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty, !day.dismissedSuggestions.contains(key) else { continue }
            counts[key] = (t.title, (counts[key]?.count ?? 0) + 1)
        }
        return counts.values
            .filter { $0.count >= day.suggestionThreshold }
            .sorted { $0.count > $1.count }
            .map { Suggestion(title: $0.title, count: $0.count) }
    }
}
