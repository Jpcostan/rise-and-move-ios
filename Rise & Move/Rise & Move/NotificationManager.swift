//
//  NotificationManager.swift
//  Rise & Move
//
//  Created by Joshua Costanza on 12/29/25.
//

import Foundation
import UserNotifications

final class NotificationManager {
    static let shared = NotificationManager()
    private init() {}

    // MARK: - Public API

    func registerCategories() {
        // Foreground action — tapping it opens the app via delegate handling
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
        // Only schedule if enabled
        guard alarm.isEnabled else {
            clearPendingRequests(for: alarm.id)
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Rise & Move"
        content.body = alarm.label.isEmpty ? "Time to get up." : alarm.label
        content.sound = .default

        // Routing + actions
        content.categoryIdentifier = "ALARM_CATEGORY"
        content.userInfo = ["alarmID": alarm.id.uuidString]

        // Fire at the next occurrence of the chosen time
        let calendar = Calendar.current
        let now = Date()
        var dateComponents = calendar.dateComponents([.hour, .minute], from: alarm.time)
        dateComponents.second = 0

        let next = nextFireDate(
            now: now,
            hour: dateComponents.hour ?? 7,
            minute: dateComponents.minute ?? 0,
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

        // Replace any existing pending request for this alarm
        clearPendingRequests(for: alarm.id)

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            print("Failed to schedule notification:", error)
        }
    }

    // MARK: - Internal helpers

    private func nextFireDate(now: Date, hour: Int, minute: Int, repeatDays: Set<Weekday>) -> Date {
        let calendar = Calendar.current

        // If no repeat days: schedule next occurrence (today if still in future, else tomorrow)
        if repeatDays.isEmpty {
            var comps = calendar.dateComponents([.year, .month, .day], from: now)
            comps.hour = hour
            comps.minute = minute
            comps.second = 0

            let todayAtTime = calendar.date(from: comps) ?? now
            if todayAtTime > now { return todayAtTime }

            return calendar.date(byAdding: .day, value: 1, to: todayAtTime) ?? now
        }

        // Repeat days: find next matching weekday (Calendar weekday: 1=Sun ... 7=Sat)
        let allowed = Set(repeatDays.map { $0.rawValue })

        for offset in 0..<7 {
            guard let candidateDay = calendar.date(byAdding: .day, value: offset, to: now) else { continue }

            let weekday = calendar.component(.weekday, from: candidateDay)
            guard allowed.contains(weekday) else { continue }

            var comps = calendar.dateComponents([.year, .month, .day], from: candidateDay)
            comps.hour = hour
            comps.minute = minute
            comps.second = 0

            let candidate = calendar.date(from: comps) ?? candidateDay
            if candidate > now { return candidate }
        }

        // Fallback: tomorrow
        return calendar.date(byAdding: .day, value: 1, to: now) ?? now
    }
}

