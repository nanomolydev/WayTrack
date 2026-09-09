import SwiftUI

struct TimelineScreen: View {
    @EnvironmentObject var store: Store
    @State private var vertical = true
    @State private var selection: UUID?
    @State private var drag: (id: UUID, minutes: Int)?
    @State private var conflict: (moved: ActiveTask, other: ActiveTask)?
    @State private var newFixed = false
    @State private var newActive = false
    @State private var renaming: RenameBox?
    @State private var now = currentMinute()

    private let tick = Timer.publish(every: 20, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let flask = makeFlask(in: geo.size)
                ZStack {
                    Theme.background.ignoresSafeArea()
                    board(flask)
                    if let selected = selectedTask {
                        AdjustPanel(task: selected, vertical: vertical) { newStart in
                            apply(move: selected, to: newStart)
                        }
                        .transition(.opacity.combined(with: .scale))
                    }
                    if let conflict {
                        PriorityPicker(a: conflict.moved, b: conflict.other) { winner in
                            let loser = winner.id == conflict.moved.id ? conflict.other : conflict.moved
                            store.resolve(priority: winner, over: loser)
                            self.conflict = nil
                        }
                    }
                }
            }
            .navigationTitle("Таймлайн")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { withAnimation { vertical.toggle() } } label: {
                        Image(systemName: vertical ? "arrow.up.and.down" : "arrow.left.and.right")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Постоянная задача") { newFixed = true }
                        Button("Активная задача") { newActive = true }
                    } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $newFixed) { FixedEditor() }
            .sheet(isPresented: $newActive) { ActiveEditor() }
            .sheet(item: $renaming) { box in
                RenameSheet(box: box) { title in
                    store.rename(segmentSource: box.sourceID, in: box.task, to: title)
                    renaming = nil
                }
            }
            .onReceive(tick) { _ in now = currentMinute() }
        }
        .preferredColorScheme(.dark)
    }

    private var selectedTask: ActiveTask? { store.day.active.first { $0.id == selection } }

    private func makeFlask(in size: CGSize) -> Flask {
        let padding: CGFloat = vertical ? 56 : 24
        let box = vertical
            ? CGSize(width: min(150, size.width - padding * 2), height: size.height - 120)
            : CGSize(width: size.width - padding * 2, height: min(150, size.height - 160))
        return Flask(vertical: vertical, size: box, range: store.dayStart..<store.dayEnd)
    }

    @ViewBuilder
    private func board(_ flask: Flask) -> some View {
        FlaskShell(flask: flask) {
            ForEach(store.day.fixed) { fixedTask in
                let r = flask.rect(start: fixedTask.start, duration: fixedTask.duration)
                FixedBlock(task: fixedTask, vertical: flask.vertical)
                    .frame(width: r.width, height: r.height)
                    .offset(x: r.minX, y: r.minY)
            }
            ForEach(store.day.active) { task in
                activeBlock(task, flask)
            }
            // прошедшее время — «выпитая» часть колбы
            if now > store.dayStart {
                let r = flask.rect(start: store.dayStart, duration: now - store.dayStart)
                Rectangle().fill(Color.black.opacity(0.35))
                    .frame(width: r.width, height: r.height)
                    .offset(x: r.minX, y: r.minY)
                    .allowsHitTesting(false)
            }
        }
        .overlay {
            ZStack(alignment: .topLeading) {
                TimeRule(flask: flask, minute: store.dayStart)
                TimeRule(flask: flask, minute: store.dayEnd - 1)
                TimeRule(flask: flask, minute: now, color: Color(hex: "FF375F"), bold: true)
            }
            .frame(width: flask.size.width, height: flask.size.height, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.snappy) { selection = nil } }
    }

    @ViewBuilder
    private func activeBlock(_ task: ActiveTask, _ flask: Flask) -> some View {
        let shift = drag?.id == task.id ? (drag?.minutes ?? 0) : 0
        ZStack(alignment: .topLeading) {
            ForEach(task.segments) { segment in
                let r = flask.rect(start: segment.start + shift, duration: segment.duration, padding: 6)
                Rectangle()
                    .fill(Color(hex: segment.colorHex ?? task.colorHex)
                        .opacity(Theme.opacity(for: segment.kind)))
                    .frame(width: r.width, height: r.height)
                    .offset(x: r.minX, y: r.minY)
            }
            if selection == task.id, !task.segments.isEmpty {
                let r = flask.rect(start: task.start + shift, duration: task.end - task.start, padding: 4)
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color(hex: task.colorHex), lineWidth: 2.5)
                    .frame(width: r.width, height: r.height)
                    .offset(x: r.minX, y: r.minY)
                    .shadow(color: Color(hex: task.colorHex).opacity(0.8), radius: 8)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.snappy) { selection = task.id } }
        .gesture(
            LongPressGesture(minimumDuration: 0.25)
                .onEnded { _ in withAnimation(.snappy) { selection = task.id } }
                .sequenced(before: DragGesture(minimumDistance: 1))
                .onChanged { value in
                    guard case .second(_, let d?) = value else { return }
                    let points = flask.vertical ? d.translation.height : d.translation.width
                    drag = (task.id, Engine.snap(flask.minutes(points)))
                }
                .onEnded { value in
                    guard case .second(_, let d?) = value else { drag = nil; return }
                    let points = flask.vertical ? d.translation.height : d.translation.width
                    apply(move: task, to: task.start + Engine.snap(flask.minutes(points)))
                    drag = nil
                }
        )
        .contextMenu {
            Section(task.name) {
                ForEach(Engine.items(of: task)) { segment in
                    Button(segment.title ?? "Без названия") {
                        renaming = RenameBox(task: task, sourceID: segment.sourceID, title: segment.title ?? "")
                    }
                }
            }
            Button("Удалить", role: .destructive) { store.remove(task) }
        }
    }

    private func apply(move task: ActiveTask, to start: Int) {
        guard let other = store.move(task, to: start),
              let moved = store.day.active.first(where: { $0.id == task.id }) else { return }
        conflict = (moved, other)
    }
}

private struct FixedBlock: View {
    var task: FixedTask
    var vertical: Bool

    var body: some View {
        ZStack {
            Rectangle().fill(Color(hex: task.colorHex).opacity(0.28))
            Rectangle().fill(.ultraThinMaterial).opacity(0.25)
            Text(task.name)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.ink.opacity(0.9))
                .rotationEffect(.degrees(vertical ? 0 : -90))
                .lineLimit(1)
        }
    }
}

/// Маленький выбор приоритета: два квадрата цвета задач, таймлайн остаётся виден.
private struct PriorityPicker: View {
    var a: ActiveTask
    var b: ActiveTask
    var pick: (ActiveTask) -> Void

    var body: some View {
        HStack(spacing: 14) {
            ForEach([a, b]) { task in
                Button { pick(task) } label: {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(hex: task.colorHex))
                        .frame(width: 30, height: 30)
                }
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(radius: 12)
    }
}

/// Регулировка времени: «+»/«−», поля начала и конца, шаг в минутах.
private struct AdjustPanel: View {
    var task: ActiveTask
    var vertical: Bool
    var move: (Int) -> Void
    @State private var step = 5

    var body: some View {
        VStack(spacing: 8) {
            Spacer()
            HStack(spacing: 10) {
                Button { move(task.start - step) } label: { Image(systemName: "minus") }
                Text(clockString(task.start)).monospacedDigit()
                Text("→").foregroundStyle(Theme.faint)
                Text(clockString(task.end)).monospacedDigit()
                Button { move(task.start + step) } label: { Image(systemName: "plus") }
                TextField("мин", value: $step, format: .number)
                    .keyboardType(.numberPad)
                    .frame(width: 40)
                    .multilineTextAlignment(.center)
            }
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.bottom, 12)
        }
    }
}

struct RenameBox: Identifiable {
    var task: ActiveTask
    var sourceID: UUID
    var title: String
    var id: UUID { sourceID }
}

private struct RenameSheet: View {
    var box: RenameBox
    var save: (String) -> Void
    @State private var title = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Название цикла", text: $title)
            }
            .navigationTitle("Название")
            .toolbar { Button("Готово") { save(title) } }
            .onAppear { title = box.title }
        }
        .presentationDetents([.height(180)])
    }
}
