import Foundation
import UserNotifications

final class NotificationManager {
    static let shared = NotificationManager()
    private init() {}

    // MARK: - Identifiers

    private func primaryIdentifier(for alarmID: UUID) -> String {
        "alarm.\(alarmID.uuidString).primary"
    }

    private func backupIdentifier(for alarmID: UUID) -> String {
        "alarm.\(alarmID.uuidString).backup"
    }

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

    /// Clears any pending notifications for this alarm, including:
    /// - new identifiers (primary + backup)
    /// - legacy identifier (alarmID.uuidString) from older builds
    func clearPendingRequests(for alarmID: UUID) async {
        let ids = [
            alarmID.uuidString,                 // legacy
            primaryIdentifier(for: alarmID),    // new primary
            backupIdentifier(for: alarmID)      // new backup
        ]

        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ids)
    }
    
    /// Clears only the backup notification for this alarm.
    /// Also clears the legacy identifier as a safety net (older builds).
    func clearBackupRequest(for alarmID: UUID) async {
        let ids = [
            alarmID.uuidString,              // legacy safety
            backupIdentifier(for: alarmID)   // new backup
        ]

        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ids)
    }

    func scheduleNotification(for alarm: Alarm) async {
        // If disabled, ensure ALL pending requests are cleared.
        guard alarm.isEnabled else {
            await clearPendingRequests(for: alarm.id)
            return
        }

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

        // Clear anything outstanding first (primary/backup/legacy)
        await clearPendingRequests(for: alarm.id)

        // ---------------------------
        // Primary alarm notification
        // ---------------------------
        let primaryContent = UNMutableNotificationContent()
        primaryContent.title = "Rise & Move"
        primaryContent.body = alarm.label.isEmpty ? "Time to get up." : alarm.label
        primaryContent.sound = .default

        // ✅ Time Sensitive (does not bypass Silent; may break through Focus if user allows)
        if #available(iOS 15.0, *) {
            primaryContent.interruptionLevel = .timeSensitive
        }

        primaryContent.categoryIdentifier = "ALARM_CATEGORY"
        primaryContent.userInfo = [
            "alarmID": alarm.id.uuidString,
            "kind": "primary"
        ]

        let primaryTriggerComponents = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: next
        )
        let primaryTrigger = UNCalendarNotificationTrigger(dateMatching: primaryTriggerComponents, repeats: false)

        let primaryRequest = UNNotificationRequest(
            identifier: primaryIdentifier(for: alarm.id),
            content: primaryContent,
            trigger: primaryTrigger
        )

        do {
            try await UNUserNotificationCenter.current().add(primaryRequest)
        } catch {
            print("Failed to schedule PRIMARY notification:", error)
        }

        // ---------------------------
        // Backup alert (follow-up)
        // ---------------------------
        guard alarm.backupEnabled else { return }

        let clampedMinutes = min(max(alarm.backupMinutes, 1), 60)
        let backupFireDate = next.addingTimeInterval(TimeInterval(clampedMinutes * 60))

        let backupContent = UNMutableNotificationContent()
        backupContent.title = "Rise & Move"
        backupContent.body =
            (alarm.label.isEmpty ? "Time to get up." : alarm.label) + " (Backup alert)"
        backupContent.sound = .default

        if #available(iOS 15.0, *) {
            backupContent.interruptionLevel = .timeSensitive
        }

        backupContent.categoryIdentifier = "ALARM_CATEGORY"
        backupContent.userInfo = [
            "alarmID": alarm.id.uuidString,
            "kind": "backup",
            "backupMinutes": clampedMinutes
        ]

        let backupTriggerComponents = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: backupFireDate
        )
        let backupTrigger = UNCalendarNotificationTrigger(dateMatching: backupTriggerComponents, repeats: false)

        let backupRequest = UNNotificationRequest(
            identifier: backupIdentifier(for: alarm.id),
            content: backupContent,
            trigger: backupTrigger
        )

        do {
            try await UNUserNotificationCenter.current().add(backupRequest)
        } catch {
            print("Failed to schedule BACKUP notification:", error)
        }
    }
    
    // MARK: - Test Alarm

    func scheduleTestNotification(secondsFromNow seconds: Int = 15) async {
        let clamped = min(max(seconds, 5), 60)

        // Build a fake alarm we can show in AlarmRingingView
        let testAlarmID = UUID()
        let testAlarmLabel = "Test Alarm"

        let content = UNMutableNotificationContent()
        content.title = "Rise & Move"
        content.body = "Test alarm — if you see/hear this, notifications are working."
        content.sound = .default

        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
        }

        content.categoryIdentifier = "ALARM_CATEGORY"

        // ✅ Include alarmID so NotificationDelegate can parse it
        // ✅ Include explicit test marker so delegate can route to test flow
        content.userInfo = [
            "alarmID": testAlarmID.uuidString,
            "kind": "test",
            "isTest": true,
            "label": testAlarmLabel
        ]

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(clamped),
            repeats: false
        )

        let id = "test.\(testAlarmID.uuidString)"

        let request = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: trigger
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            print("Failed to schedule TEST notification:", error)
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
