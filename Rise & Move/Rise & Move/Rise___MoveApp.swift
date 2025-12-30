import SwiftUI
import UserNotifications
import StoreKit

@main
struct Rise_MoveApp: App {
    private let router: AppRouter
    private let notificationDelegate: NotificationDelegate
    private let entitlements: EntitlementManager

    init() {
        let router = AppRouter()
        let delegate = NotificationDelegate()
        let entitlements = EntitlementManager()

        self.router = router
        self.notificationDelegate = delegate
        self.entitlements = entitlements

        // Notifications
        UNUserNotificationCenter.current().delegate = delegate
        NotificationManager.shared.registerCategories()

        delegate.onAlarmTap = { alarmID in
            Task { @MainActor in
                router.openAlarm(id: alarmID)
            }
        }

        // Initial entitlement refresh
        Task { @MainActor in
            await entitlements.refreshEntitlements()
            router.isPro = entitlements.isPro
        }

        // Listen for entitlement changes (purchases, renewals, restores, etc.)
        Task.detached {
            for await _ in Transaction.updates {
                await entitlements.refreshEntitlements()
                await MainActor.run {
                    router.isPro = entitlements.isPro
                }
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(router)
                .environmentObject(entitlements)
                // Belt + suspenders: refresh on app launch / reattach
                .task {
                    await entitlements.refreshEntitlements()
                    router.isPro = entitlements.isPro
                }
        }
    }
}

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    var onAlarmTap: ((UUID) -> Void)?

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        if let idString = response.notification.request.content.userInfo["alarmID"] as? String,
           let alarmID = UUID(uuidString: idString) {
            onAlarmTap?(alarmID)
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        return [.banner, .sound]
    }
}
