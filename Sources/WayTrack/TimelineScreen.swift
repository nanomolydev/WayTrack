import SwiftUI

struct TimelineScreen: View {
    @EnvironmentObject var store: Store
    @State private var vertical = !ProcessInfo.processInfo.arguments.contains("--horizontal")
    @State private var zoom: CGFloat = 1
    @State private var pinchBase: CGFloat = 1
    @State private var selection: UUID?
    @State private var drag: (id: UUID, minutes: Int)?
    @State private var conflict: (moved: ActiveTask, other: ActiveTask)?
    @State private var newFixed = false
    @State private var newActive = false
    @State private var showAI = false
    @State private var showSettings = false
    @State private var renaming: RenameBox?
    @State private var editingTime: TimeEdit?
    @State private var now = currentMinute()

    private let tick = Timer.publish(every: 20, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let flask = makeFlask(in: geo.size)
                ZStack {
                    Theme.background.ignoresSafeArea()
                    ScrollView(vertical ? .vertical : .horizontal, showsIndicators: false) {
                        canvas(flask)
                            .padding(.top, vertical ? 10 : 34)
                            .padding(.bottom, vertical ? 16 : 26)
                            .padding(.leading, vertical ? 62 : 30)
                            .padding(.trailing, vertical ? 16 : 30)
                    }
                    .simultaneousGesture(
                        MagnifyGesture()
                            .onChanged { zoom = min(10, max(1, pinchBase * $0.magnification)) }
                            .onEnded { _ in pinchBase = zoom }
                    )
                    if let selected = selectedTask {
                        AdjustPanel(task: selected,
                                    move: { apply(move: selected, to: $0) },
                                    editStart: { editingTime = TimeEdit(task: selected, minute: selected.start) })
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
            .navigationTitle(vertical ? "Колба дня" : "Таймлайн")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { withAnimation { vertical.toggle() } } label: {
                        Image(systemName: vertical ? "capsule.portrait" : "rectangle")
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showAI = true } label: { Image(systemName: "sparkles") }
                    Menu {
                        Button("Постоянная задача") { newFixed = true }
                        Button("Активная задача") { newActive = true }
                        Divider()
                        Button("Настройки") { showSettings = true }
                        Button("Сбросить масштаб") { zoom = 1; pinchBase = 1 }
                    } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $newFixed) { FixedEditor() }
            .sheet(isPresented: $newActive) { ActiveEditor() }
            .sheet(isPresented: $showAI) { AIScreen() }
            .sheet(isPresented: $showSettings) { SettingsScreen() }
            .sheet(item: $renaming) { box in
                RenameSheet(box: box) { title in
                    store.rename(segmentSource: box.sourceID, in: box.task, to: title)
                    renaming = nil
                }
            }
            .sheet(item: $editingTime) { edit in
                TimePickerSheet(minute: edit.minute) { minute in
                    apply(move: edit.task, to: minute)
                    editingTime = nil
                }
            }
            .onReceive(tick) { _ in now = currentMinute() }
        }
        .preferredColorScheme(.dark)
    }

    private var selectedTask: ActiveTask? { store.day.active.first { $0.id == selection } }

    private func makeFlask(in size: CGSize) -> Flask {
        let box = vertical
            ? CGSize(width: min(150, size.width - 110), height: (size.height - 30) * zoom)
            : CGSize(width: (size.width - 64) * zoom, height: min(160, size.height - 190))
        return Flask(vertical: vertical, size: box, range: store.dayStart..<store.dayEnd)
    }

    @ViewBuilder
    private func canvas(_ flask: Flask) -> some View {
        FlaskShell(flask: flask) {
            ForEach(store.day.fixed) { task in
                let r = flask.rect(start: task.start, duration: task.duration)
                FixedBlock(task: task, vertical: flask.vertical)
                    .frame(width: r.width, height: r.height)
                    .offset(x: r.minX, y: r.minY)
            }
            if now > store.dayStart {
                let r = flask.rect(start: store.dayStart, duration: now - store.dayStart)
                Rectangle().fill(Color.black.opacity(0.3))
                    .frame(width: r.width, height: r.height)
                    .offset(x: r.minX, y: r.minY)
                    .allowsHitTesting(false)
            }
            ForEach(store.day.active) { task in
                TaskBlock(task: task,
                          flask: flask,
                          selected: selection == task.id,
                          shift: drag?.id == task.id ? (drag?.minutes ?? 0) : 0,
                          select: { withAnimation(.snappy) { selection = task.id } },
                          dragged: { drag = (task.id, $0) },
                          commit: { minutes in
                              drag = nil
                              apply(move: task, to: task.start + minutes)
                          },
                          rename: { renaming = RenameBox(task: task, sourceID: $0.sourceID, title: $0.title ?? "") },
                          delete: { store.remove(task) })
            }
            NowRule(flask: flask, minute: now)
        }
        .overlay { TimeScale(flask: flask) }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.snappy) { selection = nil } }
    }

    private func apply(move task: ActiveTask, to start: Int) {
        guard let other = store.move(task, to: start),
              let moved = store.day.active.first(where: { $0.id == task.id }) else { return }
        conflict = (moved, other)
    }
}

/// Блок активной задачи: собственный frame по своей территории,
/// поэтому зажатие и перетаскивание попадают именно в него.
private struct TaskBlock: View {
    var task: ActiveTask
    var flask: Flask
    var selected: Bool
    var shift: Int
    var select: () -> Void
    var dragged: (Int) -> Void
    var commit: (Int) -> Void
    var rename: (Segment) -> Void
    var delete: () -> Void

    private var frame: CGRect {
        flask.rect(start: task.start + shift, duration: max(1, task.end - task.start), padding: 6)
    }

    var body: some View {
        let box = frame
        ZStack(alignment: .topLeading) {
            ForEach(task.segments) { segment in
                let a = flask.span(segment.start - task.start)
                let b = flask.span(segment.duration)
                Rectangle()
                    .fill(Color(hex: segment.colorHex ?? task.colorHex)
                        .opacity(Theme.opacity(for: segment.kind)))
                    .frame(width: flask.vertical ? box.width : b,
                           height: flask.vertical ? b : box.height)
                    .offset(x: flask.vertical ? 0 : a, y: flask.vertical ? a : 0)
            }
            Text(task.name)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.black.opacity(0.75))
                .padding(4)
                .lineLimit(1)
        }
        .frame(width: box.width, height: box.height, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(hex: task.colorHex), lineWidth: selected ? 2.5 : 0)
                .shadow(color: Color(hex: task.colorHex).opacity(selected ? 0.9 : 0), radius: 8)
        }
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .offset(x: box.minX, y: box.minY)
        .onTapGesture(perform: select)
        .gesture(
            LongPressGesture(minimumDuration: 0.2)
                .sequenced(before: DragGesture(minimumDistance: 0))
                .onChanged { value in
                    guard case .second(true, let d) = value else { return }
                    guard let d else { select(); return }
                    dragged(Engine.snap(flask.minutes(flask.vertical ? d.translation.height : d.translation.width)))
                }
                .onEnded { value in
                    guard case .second(true, let d) = value, let d else { commit(0); return }
                    commit(Engine.snap(flask.minutes(flask.vertical ? d.translation.height : d.translation.width)))
                }
        )
        .contextMenu {
            Section(task.name) {
                ForEach(Engine.items(of: task)) { segment in
                    Button(segment.title ?? "Без названия") { rename(segment) }
                }
            }
            Button("Удалить", role: .destructive, action: delete)
        }
    }
}

private struct FixedBlock: View {
    var task: FixedTask
    var vertical: Bool

    var body: some View {
        ZStack {
            Rectangle().fill(Color(hex: task.colorHex).opacity(0.3))
            Rectangle().fill(.ultraThinMaterial).opacity(0.2)
            Text(task.name)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.ink.opacity(0.9))
                .rotationEffect(.degrees(vertical ? 0 : -90))
                .fixedSize()
                .lineLimit(1)
        }
    }
}

private struct PriorityPicker: View {
    var a: ActiveTask
    var b: ActiveTask
    var pick: (ActiveTask) -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text("Кто главный?").font(.system(size: 12, design: .rounded)).foregroundStyle(Theme.faint)
            HStack(spacing: 14) {
                ForEach([a, b]) { task in
                    Button { pick(task) } label: {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(hex: task.colorHex))
                            .frame(width: 30, height: 30)
                    }
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(radius: 12)
    }
}

/// Регулировка времени: «+»/«−» с настраиваемым шагом и время нажатием.
private struct AdjustPanel: View {
    var task: ActiveTask
    var move: (Int) -> Void
    var editStart: () -> Void
    @State private var step = 5

    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 10) {
                Button { move(task.start - step) } label: { Image(systemName: "minus.circle.fill") }
                Button(action: editStart) {
                    Text("\(clockString(task.start)) → \(clockString(task.end))")
                        .monospacedDigit()
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Theme.flask, in: RoundedRectangle(cornerRadius: 7))
                }
                Button { move(task.start + step) } label: { Image(systemName: "plus.circle.fill") }
                Divider().frame(height: 18)
                TextField("мин", value: $step, format: .number)
                    .keyboardType(.numberPad)
                    .frame(width: 34)
                    .multilineTextAlignment(.center)
            }
            .font(.system(size: 15, weight: .medium, design: .rounded))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.bottom, 10)
        }
    }
}

struct TimeEdit: Identifiable {
    var task: ActiveTask
    var minute: Int
    var id: UUID { task.id }
}

/// Ввод времени нажатием, а не только «+»/«−».
struct TimePickerSheet: View {
    var minute: Int
    var save: (Int) -> Void
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            DatePicker("Начало", selection: $date, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .onAppear {
                    date = Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60,
                                                 second: 0, of: Date()) ?? Date()
                }
            .navigationTitle("Начало задачи")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Готово") { save(currentMinute(date)) } }
        }
        .presentationDetents([.height(280)])
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
            Form { TextField("Название цикла", text: $title) }
                .navigationTitle("Название")
                .toolbar { Button("Готово") { save(title) } }
                .onAppear { title = box.title }
        }
        .presentationDetents([.height(180)])
    }
}
