import XCTest
@testable import WayTrackCore

final class EngineTests: XCTestCase {

    func testBuildAlternatesRestAndPause() {
        let items = Engine.build(CycleConfig(cycle: 10, rest: 5, cyclesPerPause: 2, pause: 20, total: 40))
        XCTAssertEqual(items.map(\.kind), [.cycle, .rest, .cycle, .pause, .cycle, .rest, .cycle])
        XCTAssertEqual(items.filter { $0.kind == .cycle }.reduce(0) { $0 + $1.duration }, 40)
    }

    func testWrapSplitsSegmentAroundFixedTask() {
        // Цикл 60 мин с 9:00; постоянная 9:20–9:30 → 20 мин до, 40 мин после.
        let lunch = FixedTask(name: "Завтрак", start: 560, duration: 10)
        let laid = Engine.layout([Segment(kind: .cycle, duration: 60)], from: 540, avoiding: [lunch])
        XCTAssertEqual(laid.map { [$0.start, $0.duration] }, [[540, 20], [570, 40]])
        XCTAssertEqual(Set(laid.map(\.sourceID)).count, 1, "куски одного цикла сохраняют sourceID")
    }

    func testWrapMovesShortRestEntirelyPastFixedTask() {
        // Маленький отдых целиком внутри постоянной задачи уезжает за неё.
        let fixedTask = FixedTask(name: "Прогулка", start: 550, duration: 30)
        let laid = Engine.layout([Segment(kind: .cycle, duration: 10), Segment(kind: .rest, duration: 5)],
                                 from: 540, avoiding: [fixedTask])
        XCTAssertEqual(laid.map { [$0.start, $0.duration] }, [[540, 10], [580, 5]])
    }

    func testMixCutsCycleAndInsertsPriorityRest() {
        // ТЗ: синий цикл 20 мин, оранжевый входит на 10-й минуте, отдых приоритетной 10 мин.
        var blue = ActiveTask(name: "Синяя", colorHex: "0A84FF", start: 600,
                              config: CycleConfig(cycle: 20, rest: 5, cyclesPerPause: 0, pause: 0, total: 40))
        blue = Engine.materialize(blue, fixed: [])
        var orange = ActiveTask(name: "Оранжевая", colorHex: "FF9F0A", start: 610,
                                config: CycleConfig(cycle: 20, rest: 10, cyclesPerPause: 0, pause: 0, total: 20))
        orange = Engine.materialize(orange, fixed: [])

        let (a, b) = Engine.mix(priority: orange, over: blue, fixed: [])
        XCTAssertEqual(a.start, 620, "оранжевая сдвинулась на длину своего отдыха")
        XCTAssertEqual(b.segments.first.map { [$0.start, $0.duration] }, [600, 10], "цикл синей обрезан")
        let bridge = b.segments.first { $0.kind == .rest && $0.start == 610 }
        XCTAssertEqual(bridge?.duration, 10, "между ними отдых приоритетной задачи")
        XCTAssertFalse(b.segments.contains { $0.start < a.end && $0.end > a.start && $0.id != bridge?.id },
                       "территория приоритетной задачи очищена")
    }

    func testMixKeepsRestOfLowerTaskIntact() {
        var blue = ActiveTask(name: "Синяя", colorHex: "0A84FF", start: 600,
                              config: CycleConfig(cycle: 20, rest: 10, cyclesPerPause: 0, pause: 0, total: 40))
        blue = Engine.materialize(blue, fixed: [])   // 600-620 цикл, 620-630 отдых, 630-650 цикл
        var orange = ActiveTask(name: "Оранжевая", colorHex: "FF9F0A", start: 625,
                                config: CycleConfig(cycle: 20, rest: 5, cyclesPerPause: 0, pause: 0, total: 20))
        orange = Engine.materialize(orange, fixed: [])

        let (a, b) = Engine.mix(priority: orange, over: blue, fixed: [])
        XCTAssertEqual(a.start, 630, "приоритетная начинается после отдыха, отдых не тронут")
        XCTAssertTrue(b.segments.contains { $0.kind == .rest && $0.start == 620 && $0.duration == 10 })
    }

    func testMixBackwardMirrorsFromEnd() {
        var blue = ActiveTask(name: "Синяя", colorHex: "0A84FF", start: 620,
                              config: CycleConfig(cycle: 20, rest: 5, cyclesPerPause: 0, pause: 0, total: 40))
        blue = Engine.materialize(blue, fixed: [])   // 620-640, 640-645, 645-665
        var orange = ActiveTask(name: "Оранжевая", colorHex: "FF9F0A", start: 610,
                                config: CycleConfig(cycle: 20, rest: 10, cyclesPerPause: 0, pause: 0, total: 20))
        orange = Engine.materialize(orange, fixed: [])   // 610-630, наезжает хвостом

        let (a, b) = Engine.mix(priority: orange, over: blue, fixed: [])
        XCTAssertEqual(a.end, 620, "хвост приоритетной отодвинулся на длину её отдыха")
        XCTAssertTrue(b.segments.contains { $0.kind == .rest && $0.start == 620 && $0.duration == 10 })
        XCTAssertFalse(b.segments.contains { $0.start < 620 && $0.kind == .cycle })
    }

    func testSuggestionsRespectThresholdAndDismissals() {
        var day = DaySchedule()
        day.suggestionThreshold = 3
        day.unpredictable = (0..<3).map { _ in UnpredictableTask(title: "Кофе", date: Date(), duration: 10) }
            + [UnpredictableTask(title: "Звонок", date: Date(), duration: 5)]
        XCTAssertEqual(Engine.suggestions(from: day).map(\.title), ["Кофе"])
        day.dismissedSuggestions = ["кофе"]
        XCTAssertTrue(Engine.suggestions(from: day).isEmpty)
    }

    func testSlotAndNextSlot() {
        var day = DaySchedule()
        day.fixed = [FixedTask(name: "Завтрак", start: 480, duration: 30)]
        var work = ActiveTask(name: "Программирование", colorHex: "30D158", start: 500,
                              config: CycleConfig(cycle: 25, rest: 5, cyclesPerPause: 0, pause: 0, total: 50))
        work = Engine.materialize(work, fixed: day.fixed)
        day.active = [work]
        XCTAssertEqual(Engine.slot(at: 490, in: day)?.title, "Завтрак")
        XCTAssertEqual(Engine.nextSlot(after: 490, in: day)?.title, "Цикл 1")
    }
}
