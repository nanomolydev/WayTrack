import Foundation
import UserNotifications

enum Notifications {
    /// Явный запрос — только по кнопке в настройках: системный алерт на первом
    /// запуске закрывает весь экран и ничего не объясняет.
    static func requestAccess() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Перепланировать уведомления на границы всех отрезков дня.
    /// ponytail: перепланируем целиком при каждом сохранении — дешевле, чем диффить расписание.
    static func reschedule(_ day: DaySchedule) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            Task { @MainActor in schedule(day, center: center) }
        }
    }

    private static func schedule(_ day: DaySchedule, center: UNUserNotificationCenter) {
        center.removeAllPendingNotificationRequests()
        var points: [(Int, String, String)] = []
        for task in day.fixed {
            points.append((task.start, task.name, "Начало"))
        }
        for task in day.active {
            for segment in task.segments {
                let body: String
                switch segment.kind {
                case .cycle: body = segment.title ?? task.name
                case .rest: body = "Отдых · \(task.name)"
                case .pause: body = "Перерыв · \(task.name)"
                }
                points.append((segment.start, task.name, body))
            }
        }
        // iOS держит не больше 64 запросов — берём ближайшие по времени.
        let nowMinute = currentMinute()
        for (minute, title, body) in points.filter({ $0.0 >= nowMinute }).sorted(by: { $0.0 < $1.0 }).prefix(60) {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            var components = DateComponents()
            components.hour = minute / 60
            components.minute = minute % 60
            let request = UNNotificationRequest(
                identifier: "waytrack-\(minute)-\(body.hashValue)",
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
            center.add(request)
        }
    }
}
