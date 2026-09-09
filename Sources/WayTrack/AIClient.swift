import Foundation

/// Клиент моста к claude-vpn на сервере.
/// Мост держит сессию Claude Code: первый запрос её будит, после простоя она засыпает.
struct AIClient {
    var endpoint: String
    var token: String
    var model: String

    struct BridgeReply: Decodable {
        var reply: String
        var session: String?
        var sleepsIn: Int?

        enum CodingKeys: String, CodingKey {
            case reply, session
            case sleepsIn = "sleeps_in"
        }
    }

    enum Failure: LocalizedError {
        case notConfigured
        case http(Int, String)

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Укажите адрес моста и токен в настройках."
            case let .http(code, body): return "Мост ответил \(code): \(body.prefix(200))"
            }
        }
    }

    func ask(_ message: String, schedule: String, allowDelete: Bool,
             session: String?) async throws -> (AIResponse, String?) {
        guard let url = URL(string: endpoint.trimmingCharacters(in: .whitespaces) + "/chat"),
              !token.isEmpty else { throw Failure.notConfigured }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "prompt": prompt(message, schedule: schedule, allowDelete: allowDelete),
            "model": model,
            "session": session as Any,
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            throw Failure.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        let bridge = try JSONDecoder().decode(BridgeReply.self, from: data)
        return (parse(bridge.reply), bridge.session)
    }

    /// Модель отвечает JSON-объектом; вытаскиваем его даже из обрамляющего текста.
    private func parse(_ text: String) -> AIResponse {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end,
              let data = String(text[start...end]).data(using: .utf8),
              let decoded = try? JSONDecoder().decode(AIResponse.self, from: data)
        else { return AIResponse(reply: text) }
        return decoded
    }

    private func prompt(_ message: String, schedule: String, allowDelete: Bool) -> String {
        """
        Ты — планировщик в приложении WayTrack. Отвечай ТОЛЬКО JSON-объектом, без markdown-обёртки:
        {"reply": "короткий ответ пользователю", "ops": [операции]}

        Операции (поле op):
        add_fixed  — постоянная задача: name, start ("9:30"), duration (минуты)
        add_active — активная задача: name, start, cycle, rest, cyclesPerPause, pause, total (минуты работы)
        move       — сдвинуть: name, start
        update     — изменить: name + любые из newName, start, duration, cycle, rest, cyclesPerPause, pause, total, color
        delete     — удалить: name\(allowDelete ? "" : " (ЗАПРЕЩЕНО пользователем — не предлагай)")

        Постоянная задача — неизменный отрезок дня без циклов. Активная — работа циклами
        с отдыхами между ними и перерывами после нескольких циклов.
        Если операций не нужно, верни "ops": [].

        Текущее расписание:
        \(schedule)

        Запрос пользователя: \(message)
        """
    }
}
