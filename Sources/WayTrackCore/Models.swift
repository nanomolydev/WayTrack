import Foundation

/// Всё время в приложении — минуты от начала суток (0..1440).
public let minutesInDay = 1440

public enum SegmentKind: String, Codable, Sendable, Hashable {
    case cycle   // работа
    case rest    // отдых между циклами
    case pause   // перерыв после N циклов
}

/// Кусок активной задачи на таймлайне. Один логический цикл может быть нарезан
/// на несколько Segment с общим sourceID (обволакивание постоянной задачи).
public struct Segment: Identifiable, Codable, Hashable, Sendable {
    public var id = UUID()
    public var sourceID = UUID()
    public var kind: SegmentKind
    public var start: Int
    public var duration: Int
    public var title: String?
    /// nil = цвет владеющей задачи; заполняется при смешивании.
    public var colorHex: String?

    public init(id: UUID = UUID(), sourceID: UUID = UUID(), kind: SegmentKind,
                start: Int = 0, duration: Int, title: String? = nil, colorHex: String? = nil) {
        self.id = id; self.sourceID = sourceID; self.kind = kind
        self.start = start; self.duration = duration; self.title = title; self.colorHex = colorHex
    }

    public var end: Int { start + duration }
    public func contains(_ minute: Int) -> Bool { minute >= start && minute < end }
}

/// Постоянная задача: неизменный отрезок дня без циклов.
public struct FixedTask: Identifiable, Codable, Hashable, Sendable {
    public var id = UUID()
    public var name: String
    public var start: Int
    public var duration: Int
    public var colorHex: String = "8E8E93"

    public init(id: UUID = UUID(), name: String, start: Int, duration: Int, colorHex: String = "8E8E93") {
        self.id = id; self.name = name; self.start = start; self.duration = duration; self.colorHex = colorHex
    }

    public var end: Int { start + duration }
    public func contains(_ minute: Int) -> Bool { minute >= start && minute < end }
}

public struct CycleConfig: Codable, Hashable, Sendable {
    public var cycle: Int = 25
    public var rest: Int = 5
    public var cyclesPerPause: Int = 4
    public var pause: Int = 15
    /// Суммарное рабочее время (без отдыхов и перерывов).
    public var total: Int = 100

    public init(cycle: Int = 25, rest: Int = 5, cyclesPerPause: Int = 4, pause: Int = 15, total: Int = 100) {
        self.cycle = cycle; self.rest = rest; self.cyclesPerPause = cyclesPerPause
        self.pause = pause; self.total = total
    }
}

public struct ActiveTask: Identifiable, Codable, Hashable, Sendable {
    public var id = UUID()
    public var name: String
    public var colorHex: String
    public var start: Int
    public var config: CycleConfig
    public var segments: [Segment] = []

    public init(id: UUID = UUID(), name: String, colorHex: String, start: Int, config: CycleConfig = .init()) {
        self.id = id; self.name = name; self.colorHex = colorHex; self.start = start; self.config = config
    }

    public var end: Int { segments.last?.end ?? start }
    public func segment(at minute: Int) -> Segment? { segments.first { $0.contains(minute) } }
}

/// Незапланированная задача, зафиксированная кнопкой «Непредсказуемая».
public struct UnpredictableTask: Identifiable, Codable, Hashable, Sendable {
    public var id = UUID()
    public var title: String
    public var date: Date
    public var duration: Int

    public init(id: UUID = UUID(), title: String, date: Date, duration: Int) {
        self.id = id; self.title = title; self.date = date; self.duration = duration
    }
}

public struct DaySchedule: Codable, Hashable, Sendable {
    public var fixed: [FixedTask] = []
    public var active: [ActiveTask] = []
    public var unpredictable: [UnpredictableTask] = []
    /// Сколько повторов за неделю нужно, чтобы предложить перевод в постоянные.
    public var suggestionThreshold: Int = 3
    /// Уже отклонённые пользователем предложения.
    public var dismissedSuggestions: [String] = []

    public init() {}
}
