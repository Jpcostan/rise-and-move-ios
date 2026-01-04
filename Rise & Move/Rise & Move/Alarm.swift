//
//  Alarm.swift
//  Rise & Move
//
//  Created by Joshua Costanza on 12/29/25.
//

import Foundation

struct Alarm: Identifiable, Codable, Equatable {
    let id: UUID
    var time: Date
    var repeatDays: Set<Weekday>
    var isEnabled: Bool
    var label: String

    // ✅ NEW: Backup Alert (follow-up notification)
    var backupEnabled: Bool
    var backupMinutes: Int

    init(
        id: UUID = UUID(),
        time: Date,
        repeatDays: Set<Weekday> = [],
        isEnabled: Bool = true,
        label: String = "Alarm",
        backupEnabled: Bool = false,
        backupMinutes: Int = 10
    ) {
        self.id = id
        self.time = time
        self.repeatDays = repeatDays
        self.isEnabled = isEnabled
        self.label = label
        self.backupEnabled = backupEnabled
        self.backupMinutes = backupMinutes
    }

    // ✅ Backward-compatible decoding (older saved alarms won’t have backup fields)
    private enum CodingKeys: String, CodingKey {
        case id, time, repeatDays, isEnabled, label
        case backupEnabled, backupMinutes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        id = try c.decode(UUID.self, forKey: .id)
        time = try c.decode(Date.self, forKey: .time)
        repeatDays = try c.decode(Set<Weekday>.self, forKey: .repeatDays)
        isEnabled = try c.decode(Bool.self, forKey: .isEnabled)
        label = try c.decode(String.self, forKey: .label)

        // Default if missing in old stored JSON
        backupEnabled = try c.decodeIfPresent(Bool.self, forKey: .backupEnabled) ?? false
        backupMinutes = try c.decodeIfPresent(Int.self, forKey: .backupMinutes) ?? 10

        // Clamp to a sane range so corrupted values can’t create weird schedules
        backupMinutes = min(max(backupMinutes, 1), 60)
    }
}

enum Weekday: Int, Codable, CaseIterable, Hashable, Identifiable {
    case sun = 1, mon, tue, wed, thu, fri, sat
    var id: Int { rawValue }

    var short: String {
        switch self {
        case .sun: return "Sun"
        case .mon: return "Mon"
        case .tue: return "Tue"
        case .wed: return "Wed"
        case .thu: return "Thu"
        case .fri: return "Fri"
        case .sat: return "Sat"
        }
    }
}
