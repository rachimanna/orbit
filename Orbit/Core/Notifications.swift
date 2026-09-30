import UserNotifications

/// Local reminders before a signature expires. Nothing leaves the device.
enum Notifications {
    static func request() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    static func statusText() async -> String {
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: "Разрешено"
        case .denied: "Запрещено в Настройках iOS"
        default: "Не запрошено"
        }
    }

    static func scheduleExpiryReminder(for item: AppItem) {
        guard let expires = item.signed?.expiresAt else { return }
        let fire = expires.addingTimeInterval(-86_400)
        guard fire > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Подпись «\(item.name)» скоро истечёт"
        content.body = "Переподпишите приложение, чтобы оно продолжило запускаться."
        content.sound = .default

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        let request = UNNotificationRequest(identifier: "expiry-\(item.id)", content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
        UNUserNotificationCenter.current().add(request)
    }
}
