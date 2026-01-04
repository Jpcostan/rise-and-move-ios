//
//  AppRouter.swift
//  Rise & Move
//
//  Created by Joshua Costanza on 12/29/25.
//

import Foundation
import Combine

@MainActor
final class AppRouter: ObservableObject {
    @Published var activeAlarmID: UUID? = nil

    // ✅ Transient “test alarm” presentation (not persisted)
    @Published var activeTestAlarm: Alarm? = nil

    // Source of truth (typically set from EntitlementManager)
    @Published var isPro: Bool = false

    // One-time free trial flag (persisted)
    @Published private(set) var hasUsedFreeRiseAndMove: Bool

    // MARK: - Keys

    private enum DefaultsKey {
        static let hasUsedFreeRiseAndMove = "hasUsedFreeRiseAndMove"
    }

    // MARK: - Init

    init() {
        self.hasUsedFreeRiseAndMove = UserDefaults.standard.bool(forKey: DefaultsKey.hasUsedFreeRiseAndMove)
    }

    // Can the user use the Rise & Move stop right now?
    var canUseRiseAndMove: Bool {
        isPro || !hasUsedFreeRiseAndMove
    }

    func markFreeRiseAndMoveUsed() {
        guard !hasUsedFreeRiseAndMove else { return }
        hasUsedFreeRiseAndMove = true
        UserDefaults.standard.set(true, forKey: DefaultsKey.hasUsedFreeRiseAndMove)
    }

    #if DEBUG
    @Published var forcePaywallForTesting: Bool = false

    func resetFreeRiseAndMoveTrialForTesting() {
        hasUsedFreeRiseAndMove = false
        UserDefaults.standard.set(false, forKey: DefaultsKey.hasUsedFreeRiseAndMove)
    }
    #endif

    // MARK: - Routing

    func openAlarm(id: UUID) {
        activeAlarmID = id
    }

    func clearActiveAlarm() {
        activeAlarmID = nil
    }

    // MARK: - Test Alarm Routing

    /// ✅ Preferred: create a test alarm that matches the notification's alarmID.
    func openTestAlarm(id: UUID, label: String? = nil) {
        activeTestAlarm = Alarm(
            id: id,
            time: Date(),
            repeatDays: [],
            isEnabled: true,
            label: (label?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                ? label!
                : "Test Alarm"
        )
    }

    /// Back-compat: if any old code still calls openTestAlarm() without args.
    func openTestAlarm() {
        openTestAlarm(id: UUID(), label: "Test Alarm")
    }

    func clearTestAlarm() {
        activeTestAlarm = nil
    }
}
