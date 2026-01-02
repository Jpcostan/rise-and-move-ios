import Foundation
import UserNotifications

final class NotificationManager {
    static let shared = NotificationManager()
    private init() {}

    // MARK: - Public API

    func registerCategories() {
        let stop = UNNotificationAction(
            identifier: "STOP_ACTION",
            title: "Stop",
            options: [.foreground]
        )

        let category = UNNotificationCategory(
            identifier: "ALARM_CATEGORY",
            actions: [stop],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        } catch {
            print("Notification auth error:", error)
            return false
        }
    }

    func clearPendingRequests(for alarmID: UUID) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [alarmID.uuidString])
    }

    func scheduleNotification(for alarm: Alarm) async {
        guard alarm.isEnabled else {
            clearPendingRequests(for: alarm.id)
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Rise & Move"
        content.body = alarm.label.isEmpty ? "Time to get up." : alarm.label
        content.sound = .default

        content.categoryIdentifier = "ALARM_CATEGORY"
        content.userInfo = ["alarmID": alarm.id.uuidString]

        var calendar = Calendar.current
        calendar.timeZone = .current

        let now = Date()
        let timeParts = calendar.dateComponents([.hour, .minute], from: alarm.time)

        let next = nextFireDate(
            now: now,
            hour: timeParts.hour ?? 7,
            minute: timeParts.minute ?? 0,
            repeatDays: alarm.repeatDays
        )

        let triggerComponents = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: next
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)

        let request = UNNotificationRequest(
            identifier: alarm.id.uuidString,
            content: content,
            trigger: trigger
        )

        clearPendingRequests(for: alarm.id)

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            print("Failed to schedule notification:", error)
        }
    }

    // MARK: - Internal helpers

    private func nextFireDate(now: Date, hour: Int, minute: Int, repeatDays: Set<Weekday>) -> Date {
        var calendar = Calendar.current
        calendar.timeZone = .current

        // Build “time of day” components
        var timeMatch = DateComponents()
        timeMatch.hour = hour
        timeMatch.minute = minute
        timeMatch.second = 0

        // No repeat days: DST-safe “next occurrence of time”
        if repeatDays.isEmpty {
            return calendar.nextDate(
                after: now,
                matching: timeMatch,
                matchingPolicy: .nextTimePreservingSmallerComponents,
                direction: .forward
            ) ?? now
        }

        // Repeat days: map Weekday.short -> Calendar weekday (1=Sun ... 7=Sat)
        // This avoids any assumptions about Weekday.rawValue ordering.
        let allowedWeekdays: [Int] = repeatDays.compactMap { calendarWeekday(fromShort: $0.short) }

        var best: Date?

        for weekday in Set(allowedWeekdays) {
            var match = timeMatch
            match.weekday = weekday

            if let candidate = calendar.nextDate(
                after: now,
                matching: match,
                matchingPolicy: .nextTimePreservingSmallerComponents,
                direction: .forward
            ) {
                if best == nil || candidate < best! {
                    best = candidate
                }
            }
        }

        if let best { return best }

        // Fallback: tomorrow at the chosen time
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        var comps = calendar.dateComponents([.year, .month, .day], from: tomorrow)
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        return calendar.date(from: comps) ?? tomorrow
    }

    /// Maps your UI abbreviations to Calendar weekday values (1=Sun ... 7=Sat)
    private func calendarWeekday(fromShort short: String) -> Int? {
        let s = short
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        // Accept both 2-letter ("mo") and 3-letter ("mon") forms
        if s.hasPrefix("su") { return 1 }
        if s.hasPrefix("mo") { return 2 }
        if s.hasPrefix("tu") { return 3 }
        if s.hasPrefix("we") { return 4 }
        if s.hasPrefix("th") { return 5 }
        if s.hasPrefix("fr") { return 6 }
        if s.hasPrefix("sa") { return 7 }

        return nil
    }
}
