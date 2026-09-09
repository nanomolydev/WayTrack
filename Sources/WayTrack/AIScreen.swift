import SwiftUI

struct AIScreen: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var messages: [Message] = []
    @State private var busy = false

    struct Message: Identifiable {
        enum Role { case user, assistant, log, error }
        var id = UUID()
        var role: Role
        var text: String
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(messages) { message in
                                Bubble(message: message).id(message.id)
                            }
                        }
                        .padding(16)
                    }
                    .onChange(of: messages.count) {
                        if let last = messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                Divider()
                HStack(spacing: 10) {
                    TextField("Спорт в 18:00, циклы по 20 минут…", text: $input, axis: .vertical)
                        .lineLimit(1...4)
                        .textFieldStyle(.plain)
                    Button {
                        Task { await send() }
                    } label: {
                        Image(systemName: busy ? "hourglass" : "arrow.up.circle.fill").font(.system(size: 26))
                    }
                    .disabled(busy || input.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(12)
            }
            .background(Theme.background)
            .navigationTitle("Планировщик")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Закрыть") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Разбудить заново") { store.aiSession = nil }
                        .font(.system(size: 13))
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func send() async {
        let text = input.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        input = ""
        messages.append(Message(role: .user, text: text))
        busy = true
        defer { busy = false }

        do {
            let (response, session) = try await AISettings.client.ask(
                text,
                schedule: Engine.describe(store.day),
                allowDelete: AISettings.allowDelete,
                session: store.aiSession)
            store.aiSession = session
            messages.append(Message(role: .assistant, text: response.reply))
            if !response.ops.isEmpty {
                let log = store.applyAI(response.ops)
                messages.append(Message(role: .log, text: log.joined(separator: "\n")))
            }
        } catch {
            messages.append(Message(role: .error, text: error.localizedDescription))
        }
    }
}

private struct Bubble: View {
    var message: AIScreen.Message

    private var color: Color {
        switch message.role {
        case .user: return Color(hex: "0A84FF").opacity(0.25)
        case .assistant: return Theme.flask
        case .log: return Color(hex: "30D158").opacity(0.18)
        case .error: return Color(hex: "FF375F").opacity(0.22)
        }
    }

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            Text(message.text)
                .font(.system(size: 14, design: message.role == .log ? .monospaced : .rounded))
                .foregroundStyle(Theme.ink)
                .padding(10)
                .background(color, in: RoundedRectangle(cornerRadius: 12))
            if message.role != .user { Spacer(minLength: 40) }
        }
    }
}
