import Foundation

/// Одна операция над расписанием, присланная моделью.
/// Одна плоская структура вместо enum с ассоциированными значениями:
/// модели проще стабильно выдавать такой JSON, а нам — его декодировать.
public struct TaskOp: Codable, Hashable, Sendable {
    public var op: String            // add_fixed | add_active | move | update | delete
    public var name: String
    public var newName: String?
    public var start: String?        // "9:30" или "570"
    public var duration: Int?
    public var cycle: Int?
    public var rest: Int?
    public var cyclesPerPause: Int?
    public var pause: Int?
    public var total: Int?
    public var color: String?

    public init(op: String, name: String, newName: String? = nil, start: String? = nil,
                duration: Int? = nil, cycle: Int? = nil, rest: Int? = nil,
                cyclesPerPause: Int? = nil, pause: Int? = nil, total: Int? = nil, color: String? = nil) {
        self.op = op; self.name = name; self.newName = newName; self.start = start
        self.duration = duration; self.cycle = cycle; self.rest = rest
        self.cyclesPerPause = cyclesPerPause; self.pause = pause; self.total = total; self.color = color
    }
}

public struct AIResponse: Codable, Sendable {
    public var reply: String
    public var ops: [TaskOp]

    public init(reply: String, ops: [TaskOp] = []) {
        self.reply = reply; self.ops = ops
    }
}

public extension Engine {

    /// "9:30" / "09:30" / "570" → минуты от начала суток.
    static func parseTime(_ text: String?) -> Int? {
        guard let text = text?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        if text.contains(":") {
            let parts = text.split(separator: ":")
            guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
            return max(0, min(minutesInDay - 1, h * 60 + m))
        }
        return Int(text).map { max(0, min(minutesInDay - 1, $0)) }
    }

    /// Применяет операции модели. Удаление выполняется только при `allowDelete`.
    /// Возвращает новое расписание и человекочитаемый отчёт о каждой операции.
    static func apply(_ ops: [TaskOp], to day: DaySchedule,
                      allowDelete: Bool, palette: [String]) -> (DaySchedule, [String]) {
        var day = day
        var log: [String] = []

        func color(_ op: TaskOp) -> String {
            op.color.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "#")) }
                ?? palette.randomElement() ?? "8E8E93"
        }

        for op in ops {
            let key = op.name.lowercased()
            switch op.op {
            case "add_fixed":
                guard let start = parseTime(op.start), let duration = op.duration, duration > 0 else {
                    log.append("✗ \(op.name): нужны start и duration"); continue
                }
                day.fixed.append(FixedTask(name: op.name, start: start, duration: duration, colorHex: color(op)))
                day.fixed.sort { $0.start < $1.start }
                log.append("+ постоянная «\(op.name)» \(start / 60):\(String(format: "%02d", start % 60))")

            case "add_active":
                guard let start = parseTime(op.start) else {
                    log.append("✗ \(op.name): нужен start"); continue
                }
                let config = CycleConfig(cycle: op.cycle ?? 25, rest: op.rest ?? 5,
                                         cyclesPerPause: op.cyclesPerPause ?? 4,
                                         pause: op.pause ?? 15, total: op.total ?? op.duration ?? 100)
                let task = ActiveTask(name: op.name, colorHex: color(op), start: start, config: config)
                day.active.append(materialize(task, fixed: day.fixed))
                day.active.sort { $0.start < $1.start }
                log.append("+ активная «\(op.name)»")

            case "move":
                guard let start = parseTime(op.start) else { log.append("✗ \(op.name): нужен start"); continue }
                if let i = day.active.firstIndex(where: { $0.name.lowercased() == key }) {
                    day.active[i] = relayout(day.active[i], at: start, fixed: day.fixed)
                    log.append("→ «\(op.name)» на \(start / 60):\(String(format: "%02d", start % 60))")
                } else if let i = day.fixed.firstIndex(where: { $0.name.lowercased() == key }) {
                    day.fixed[i].start = start
                    day.active = day.active.map { relayout($0, at: $0.start, fixed: day.fixed) }
                    log.append("→ «\(op.name)» на \(start / 60):\(String(format: "%02d", start % 60))")
                } else {
                    log.append("✗ «\(op.name)» не найдена")
                }

            case "update":
                if let i = day.active.firstIndex(where: { $0.name.lowercased() == key }) {
                    var task = day.active[i]
                    if let newName = op.newName { task.name = newName }
                    if let hex = op.color { task.colorHex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")) }
                    if let cycle = op.cycle { task.config.cycle = cycle }
                    if let rest = op.rest { task.config.rest = rest }
                    if let n = op.cyclesPerPause { task.config.cyclesPerPause = n }
                    if let pause = op.pause { task.config.pause = pause }
                    if let total = op.total { task.config.total = total }
                    task.segments = []
                    day.active[i] = materialize(task, fixed: day.fixed)
                    if let start = parseTime(op.start) {
                        day.active[i] = relayout(day.active[i], at: start, fixed: day.fixed)
                    }
                    log.append("~ «\(op.name)» обновлена")
                } else if let i = day.fixed.firstIndex(where: { $0.name.lowercased() == key }) {
                    if let newName = op.newName { day.fixed[i].name = newName }
                    if let start = parseTime(op.start) { day.fixed[i].start = start }
                    if let duration = op.duration { day.fixed[i].duration = duration }
                    if let hex = op.color { day.fixed[i].colorHex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")) }
                    day.active = day.active.map { relayout($0, at: $0.start, fixed: day.fixed) }
                    log.append("~ «\(op.name)» обновлена")
                } else {
                    log.append("✗ «\(op.name)» не найдена")
                }

            case "delete":
                guard allowDelete else {
                    log.append("⛔️ удаление «\(op.name)» запрещено в настройках"); continue
                }
                let before = day.active.count + day.fixed.count
                day.active.removeAll { $0.name.lowercased() == key }
                day.fixed.removeAll { $0.name.lowercased() == key }
                let removed = before - (day.active.count + day.fixed.count)
                log.append(removed > 0 ? "− «\(op.name)» удалена" : "✗ «\(op.name)» не найдена")

            default:
                log.append("✗ неизвестная операция \(op.op)")
            }
        }
        return (day, log)
    }

    /// Снимок расписания для модели — компактный текст вместо простыни JSON.
    static func describe(_ day: DaySchedule) -> String {
        var lines: [String] = []
        for task in day.fixed.sorted(by: { $0.start < $1.start }) {
            lines.append("постоянная «\(task.name)» \(hhmm(task.start))–\(hhmm(task.end))")
        }
        for task in day.active.sorted(by: { $0.start < $1.start }) {
            let c = task.config
            lines.append("активная «\(task.name)» \(hhmm(task.start))–\(hhmm(task.end)), "
                + "цикл \(c.cycle)м, отдых \(c.rest)м, перерыв \(c.pause)м каждые \(c.cyclesPerPause), всего работы \(c.total)м")
        }
        return lines.isEmpty ? "расписание пустое" : lines.joined(separator: "\n")
    }

    static func hhmm(_ minute: Int) -> String {
        String(format: "%d:%02d", minute / 60, minute % 60)
    }
}
