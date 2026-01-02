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
    // - Pro users: always yes
    // - Non-Pro: yes only if they haven't used their one free trial yet
    var canUseRiseAndMove: Bool {
        isPro || !hasUsedFreeRiseAndMove
    }

    // Call this after the user successfully completes the movement task once.
    func markFreeRiseAndMoveUsed() {
        guard !hasUsedFreeRiseAndMove else { return }
        hasUsedFreeRiseAndMove = true
        UserDefaults.standard.set(true, forKey: DefaultsKey.hasUsedFreeRiseAndMove)
    }

    // Optional: use this for testing in DEBUG builds
    #if DEBUG
    // DEBUG-only: force the Paywall to appear even if entitlements say Pro.
    // Flip to false when you want to test the Pro flow.
    @Published var forcePaywallForTesting: Bool = false

    // DEBUG-only reset to re-test the one-time free trial
    func resetFreeRiseAndMoveTrialForTesting() {
        hasUsedFreeRiseAndMove = false
        UserDefaults.standard.set(false, forKey: DefaultsKey.hasUsedFreeRiseAndMove)
    }
    #endif

    func openAlarm(id: UUID) {
        activeAlarmID = id
    }

    func clearActiveAlarm() {
        activeAlarmID = nil
    }
}
