import SwiftUI
import UserNotifications
import StoreKit
import OSLog

@main
struct Rise_MoveApp: App {
    @StateObject private var router: AppRouter
    @StateObject private var store: AlarmStore
    @StateObject private var entitlements: EntitlementManager

    private let notificationDelegate: NotificationDelegate

    init() {
        let router = AppRouter()
        let store = AlarmStore()
        let delegate = NotificationDelegate()
        let entitlements = EntitlementManager()
        let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "RiseAndMove", category: "StoreKit")

        _router = StateObject(wrappedValue: router)
        _store = StateObject(wrappedValue: store)
        _entitlements = StateObject(wrappedValue: entitlements)

        self.notificationDelegate = delegate

        UNUserNotificationCenter.current().delegate = delegate
        NotificationManager.shared.registerCategories()

        // Existing: open real alarm screen from notification tap
        delegate.onAlarmTap = { alarmID in
            Task { @MainActor in
                router.openAlarm(id: alarmID)
            }
        }

        // ✅ Test notifications: route using payload when available
        delegate.onTestTap = { testID, label in
            Task { @MainActor in
                router.openTestAlarm(id: testID, label: label)
            }
        }

        delegate.onStopAction = { alarmID in
            Task { @MainActor in
                // Treat notification "Stop" like the user dismissed the alarm.
                // One-time alarms will disable; repeating alarms will schedule next.
                store.markAlarmFired(alarmID)
                router.clearActiveAlarm()
            }
        }

        Task { @MainActor in
            await entitlements.refreshEntitlements()
            router.isPro = entitlements.isPro
        }

        Task.detached {
            for await result in Transaction.updates {
                switch result {
                case .verified(let transaction):
                    await transaction.finish()
                    await entitlements.refreshEntitlements()
                    await MainActor.run {
                        router.isPro = entitlements.isPro
                    }
                case .unverified(_, let error):
                    logger.error("Unverified transaction update: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(router)
                .environmentObject(store)
                .environmentObject(entitlements)
                .task {
                    await entitlements.refreshEntitlements()
                    router.isPro = entitlements.isPro
                }
        }
    }
}

/// Decides whether to show onboarding or the main app.
/// Stored locally in UserDefaults via AppStorage.
private struct RootView: View {
    @EnvironmentObject private var router: AppRouter
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false

    var body: some View {
        if hasCompletedOnboarding {
            ContentView()
        } else {
            OnboardingFlowView(
                onFinish: {
                    hasCompletedOnboarding = true
                },
                onTryTestAlarm: {
                    // Optional CTA. Doesn’t mark onboarding complete.
                    router.openTestAlarm()
                }
            )
        }
    }
}

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    var onAlarmTap: ((UUID) -> Void)?
    var onStopAction: ((UUID) -> Void)?

    /// ✅ Test notification tap (passes payload when available)
    var onTestTap: ((UUID, String?) -> Void)?

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {

        let userInfo = response.notification.request.content.userInfo

        // ✅ Test notifications
        let kind = userInfo["kind"] as? String
        let isTest = (userInfo["isTest"] as? Bool) == true

        if kind == "test" || isTest {
            if
                let idString = userInfo["alarmID"] as? String,
                let id = UUID(uuidString: idString)
            {
                let label = userInfo["label"] as? String
                onTestTap?(id, label)
            } else {
                // Fallback (should be rare)
                onTestTap?(UUID(), userInfo["label"] as? String)
            }
            return
        }

        // Real alarms require alarmID
        guard
            let idString = userInfo["alarmID"] as? String,
            let alarmID = UUID(uuidString: idString)
        else { return }

        if response.actionIdentifier == "STOP_ACTION" {
            onStopAction?(alarmID)
        } else {
            onAlarmTap?(alarmID)
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        return [.banner, .sound]
    }
}
