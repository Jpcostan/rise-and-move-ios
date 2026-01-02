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

        delegate.onAlarmTap = { alarmID in
            Task { @MainActor in
                router.openAlarm(id: alarmID)
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
            ContentView()
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

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    var onAlarmTap: ((UUID) -> Void)?
    var onStopAction: ((UUID) -> Void)?

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        guard
            let idString = response.notification.request.content.userInfo["alarmID"] as? String,
            let alarmID = UUID(uuidString: idString)
        else { return }

        if response.actionIdentifier == "STOP_ACTION" {
            onStopAction?(alarmID)
        } else {
            // Default tap on notification (or any other action): open the alarm screen
            onAlarmTap?(alarmID)
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        return [.banner, .sound]
    }
}

