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

    // ✅ Onboarding replay request (not persisted)
    @Published var forceShowOnboarding: Bool = false

    // Source of truth (typically set from EntitlementManager)
    @Published var isPro: Bool = false

    // ✅ Paywall presentation (single source of truth)
    enum PaywallSource: String, Codable {
        case gate
        case onboarding
        case settings
        case unknown
    }

    struct PaywallContext: Identifiable, Equatable {
        let id = UUID()
        let source: PaywallSource
    }

    @Published var paywallContext: PaywallContext? = nil

    func presentPaywall(source: PaywallSource = .unknown) {
        // Prevent double-presenting the sheet
        guard paywallContext == nil else { return }
        paywallContext = PaywallContext(source: source)
    }

    func dismissPaywall() {
        paywallContext = nil
    }

    // ✅ Deferred paywall request (used when onboarding is covering ContentView)
    // When true, ContentView should present the paywall immediately after onboarding dismisses.
    @Published var presentPaywallAfterOnboarding: Bool = false

    func requestPaywallAfterOnboarding() {
        presentPaywallAfterOnboarding = true
    }

    func clearDeferredPaywallRequest() {
        presentPaywallAfterOnboarding = false
    }

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

    // MARK: - DEBUG Overrides (MUST NOT SHIP)

    #if DEBUG
    /// ✅ Debug-only: forces app to behave as if user is NOT Pro AND has already used the free Rise & Move.
    /// This is intentionally "effective only" and does NOT persist any trial usage.
    @Published var forcePaywallForTesting: Bool = false
    #endif

    /// ✅ Single source of truth for debug forcing.
    /// In Release/TestFlight builds this is ALWAYS false (and contains no debug references).
    private var isPaywallForced: Bool {
        DebugOnly.value(
            debug: {
                #if DEBUG
                return forcePaywallForTesting
                #else
                return false
                #endif
            }(),
            release: false
        )
    }

    /// ✅ Effective Pro status used by gating logic (never reports Pro when forced).
    var effectiveIsPro: Bool {
        isPro && !isPaywallForced
    }

    /// ✅ Effective free-trial usage used by gating logic.
    /// When forced, behave as if the free Rise & Move has already been used,
    /// but do NOT write anything to UserDefaults.
    var effectiveHasUsedFreeRiseAndMove: Bool {
        hasUsedFreeRiseAndMove || isPaywallForced
    }

    /// ✅ This is the value UI / AlarmRingingView should trust.
    var canUseRiseAndMove: Bool {
        effectiveIsPro || !effectiveHasUsedFreeRiseAndMove
    }

    func markFreeRiseAndMoveUsed() {
        // ✅ Critical: never burn the user's persisted one-time free while forcing paywall.
        guard !isPaywallForced else {
            DebugOnly.assertDebugOnly("Attempted to persist free-trial usage while paywall forcing is active.")
            return
        }
        guard !hasUsedFreeRiseAndMove else { return }

        hasUsedFreeRiseAndMove = true
        UserDefaults.standard.set(true, forKey: DefaultsKey.hasUsedFreeRiseAndMove)
    }

    #if DEBUG
    func resetFreeRiseAndMoveTrialForTesting() {
        hasUsedFreeRiseAndMove = false
        UserDefaults.standard.set(false, forKey: DefaultsKey.hasUsedFreeRiseAndMove)
    }
    #endif

    // MARK: - Onboarding

    /// Presents onboarding again from places like Settings.
    /// This does NOT reset any persisted onboarding completion flag.
    func showOnboarding() {
        forceShowOnboarding = true
    }

    func clearOnboardingRequest() {
        forceShowOnboarding = false
    }

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
