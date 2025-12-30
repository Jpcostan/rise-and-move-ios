import Foundation
import Combine
import SwiftUI

@MainActor
final class AlarmStore: ObservableObject {
    
    private let storageKey = "alarms_storage_v1"

    @Published var alarms: [Alarm] = [] {
        didSet {
            save()
        }
    }

    init() {
        load()
    }

    func add(_ alarm: Alarm) {
        alarms.append(alarm)
    }

    func update(_ alarm: Alarm) {
        guard let idx = alarms.firstIndex(where: { $0.id == alarm.id }) else { return }
        alarms[idx] = alarm
    }

    func delete(atOffsets offsets: IndexSet) {
        for index in offsets {
            let alarmID = alarms[index].id
            NotificationManager.shared.clearPendingRequests(for: alarmID)
        }
        alarms.remove(atOffsets: offsets)
    }

    func setEnabled(alarmID: Alarm.ID, isEnabled: Bool) {
        guard let idx = alarms.firstIndex(where: { $0.id == alarmID }) else { return }
        alarms[idx].isEnabled = isEnabled
    }
    
    func markAlarmFired(_ alarmID: UUID) {
        guard let idx = alarms.firstIndex(where: { $0.id == alarmID }) else { return }

        // If it has no repeat days, treat it as a one-time alarm and disable it.
        if alarms[idx].repeatDays.isEmpty {
            alarms[idx].isEnabled = false
        }

        // Either way, schedule/clear appropriately based on enabled + repeats
        Task {
            await NotificationManager.shared.scheduleNotification(for: alarms[idx])
        }
    }
    
    private func save() {
        do {
            let data = try JSONEncoder().encode(alarms)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            print("Failed to save alarms:", error)
        }

        Task {
            for alarm in alarms {
                await NotificationManager.shared.scheduleNotification(for: alarm)
            }
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            // First launch: seed with one example alarm
            alarms = [
                Alarm(
                    time: Calendar.current.date(bySettingHour: 7, minute: 30, second: 0, of: Date()) ?? Date(),
                    repeatDays: [.mon, .tue, .wed, .thu, .fri],
                    isEnabled: true,
                    label: "Weekday Alarm"
                )
            ]
            return
        }

        do {
            alarms = try JSONDecoder().decode([Alarm].self, from: data)
        } catch {
            print("Failed to load alarms:", error)
            alarms = []
        }
    }

}
