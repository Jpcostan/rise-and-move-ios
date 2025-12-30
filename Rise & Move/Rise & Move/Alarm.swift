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

    init(
        id: UUID = UUID(),
        time: Date,
        repeatDays: Set<Weekday> = [],
        isEnabled: Bool = true,
        label: String = "Alarm"
    ) {
        self.id = id
        self.time = time
        self.repeatDays = repeatDays
        self.isEnabled = isEnabled
        self.label = label
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
