import Foundation
import Combine
import SwiftUI

@MainActor
final class AlarmStore: ObservableObject {

    private let storageKey = "alarms_storage_v1"

    @Published var alarms: [Alarm] = [] {
        didSet { saveToDisk() }
    }

    init() {
        loadFromDisk()
    }

    // MARK: - CRUD

    func add(_ alarm: Alarm) {
        alarms.append(alarm)
        scheduleOrClear(alarm)
    }

    func update(_ alarm: Alarm) {
        guard let idx = alarms.firstIndex(where: { $0.id == alarm.id }) else { return }
        alarms[idx] = alarm
        scheduleOrClear(alarm)
    }

    func delete(atOffsets offsets: IndexSet) {
        let idsToDelete = offsets.map { alarms[$0].id }

        // Update model first
        alarms.remove(atOffsets: offsets)

        // Then clear pending notifications for removed alarms
        for id in idsToDelete {
            NotificationManager.shared.clearPendingRequests(for: id)
        }
    }

    func setEnabled(alarmID: Alarm.ID, isEnabled: Bool) {
        guard let idx = alarms.firstIndex(where: { $0.id == alarmID }) else { return }
        alarms[idx].isEnabled = isEnabled
        scheduleOrClear(alarms[idx])
    }

    /// Called when the alarm is actually stopped (after ringing).
    /// - One-time alarms: disable after firing.
    /// - Repeat alarms: keep enabled and schedule next occurrence.
    func markAlarmFired(_ alarmID: UUID) {
        guard let idx = alarms.firstIndex(where: { $0.id == alarmID }) else { return }

        if alarms[idx].repeatDays.isEmpty {
            alarms[idx].isEnabled = false
        }

        scheduleOrClear(alarms[idx])
    }

    // MARK: - Persistence

    private func saveToDisk() {
        do {
            let data = try JSONEncoder().encode(alarms)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            print("Failed to save alarms:", error)
        }
    }

    private func loadFromDisk() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            // First launch: start empty (safer for production than seeding)
            // If you want a demo alarm for dev builds only, we can add it behind #if DEBUG.
            alarms = []
            return
        }

        do {
            alarms = try JSONDecoder().decode([Alarm].self, from: data)
        } catch {
            print("Failed to load alarms:", error)
            alarms = []
        }

        // On app launch, ensure enabled alarms are scheduled.
        Task {
            for alarm in alarms where alarm.isEnabled {
                await NotificationManager.shared.scheduleNotification(for: alarm)
            }
        }
    }

    // MARK: - Scheduling helper

    private func scheduleOrClear(_ alarm: Alarm) {
        Task {
            await NotificationManager.shared.scheduleNotification(for: alarm)
        }
    }
}
