import SwiftUI

enum AISettings {
    static let endpointKey = "ai.endpoint"
    static let tokenKey = "ai.token"
    static let modelKey = "ai.model"
    static let allowDeleteKey = "ai.allowDelete"

    static let models = [
        "claude-opus-5",
        "claude-sonnet-5",
        "claude-fable-5-1",
        "claude-haiku-4-5-20251001",
    ]

    static var client: AIClient {
        let defaults = UserDefaults.standard
        return AIClient(endpoint: defaults.string(forKey: endpointKey) ?? "",
                        token: defaults.string(forKey: tokenKey) ?? "",
                        model: defaults.string(forKey: modelKey) ?? models[1])
    }

    static var allowDelete: Bool { UserDefaults.standard.bool(forKey: allowDeleteKey) }
}

struct SettingsScreen: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AISettings.endpointKey) private var endpoint = ""
    @AppStorage(AISettings.tokenKey) private var token = ""
    @AppStorage(AISettings.modelKey) private var model = AISettings.models[1]
    @AppStorage(AISettings.allowDeleteKey) private var allowDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Мост claude-vpn") {
                    TextField("http://адрес:8765", text: $endpoint)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Токен", text: $token)
                    Picker("Модель", selection: $model) {
                        ForEach(AISettings.models, id: \.self) { Text($0).tag($0) }
                    }
                }
                Section {
                    Toggle("Разрешить ИИ удалять задачи", isOn: $allowDelete)
                } footer: {
                    Text("Создавать и менять задачи ИИ может всегда, удалять — только с этим разрешением.")
                }
                Section("Уведомления") {
                    Button("Разрешить уведомления") { Notifications.requestAccess() }
                }
                Section("Границы дня") {
                    Stepper("Начало · \(clockString(store.dayStart))", value: $store.dayStart,
                            in: 0...(store.dayEnd - 60), step: 30)
                    Stepper("Конец · \(clockString(store.dayEnd))", value: $store.dayEnd,
                            in: (store.dayStart + 60)...minutesInDay, step: 30)
                }
                Section("Непредсказуемые задачи") {
                    Stepper("Предлагать после \(store.day.suggestionThreshold) повторов",
                            value: $store.day.suggestionThreshold, in: 2...10)
                }
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Готово") { dismiss() } }
        }
    }
}
