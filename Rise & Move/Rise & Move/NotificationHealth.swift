//
//  NotificationHealth.swift
//  Rise & Move
//
//  Created by Joshua Costanza on 1/3/26.
//

import Foundation
import Combine
import UserNotifications
import SwiftUI
import UIKit

@MainActor
final class NotificationHealth: ObservableObject {
    enum AlarmCapability {
        case ok
        case notDetermined
        case denied
        case alertsDisabled
        case soundsDisabled   // ✅ NEW
        case unknown

        var isAlarmCapable: Bool {
            switch self {
            case .ok: return true
            case .notDetermined, .denied, .alertsDisabled, .soundsDisabled, .unknown:
                return false
            }
        }

        var title: String {
            switch self {
            case .ok:
                return "Notifications Enabled"
            case .notDetermined:
                return "Notifications Needed"
            case .denied, .alertsDisabled:
                return "Notifications Disabled"
            case .soundsDisabled:
                return "Sounds Are Off"
            case .unknown:
                return "Notification Status Unknown"
            }
        }

        var message: String {
            switch self {
            case .ok:
                return "Alarms can alert you as expected."
            case .notDetermined:
                return "Rise & Move needs notification permission to ring alarms."
            case .denied:
                return "Notifications are denied. Alarms will not ring until enabled in Settings."
            case .alertsDisabled:
                return "Alerts are turned off for Rise & Move. Alarms will not ring until enabled in Settings."
            case .soundsDisabled:
                return "Notification sounds are turned off for Rise & Move. You may miss alarms unless Sounds are enabled."
            case .unknown:
                return "We couldn’t confirm notification settings. Please check Settings if alarms don’t ring."
            }
        }

        var ctaTitle: String {
            switch self {
            case .notDetermined:
                return "Allow Notifications"
            case .denied, .alertsDisabled, .soundsDisabled, .unknown:
                return "Open Settings"
            case .ok:
                return "OK"
            }
        }
    }

    @Published private(set) var capability: AlarmCapability = .unknown

    func refresh() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        // Authorization
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            break
        case .notDetermined:
            capability = .notDetermined
            return
        case .denied:
            capability = .denied
            return
        @unknown default:
            capability = .unknown
            return
        }

        // “Authorized” but alerts disabled is a real thing
        if settings.alertSetting != .enabled {
            capability = .alertsDisabled
            return
        }

        // “Authorized” but sounds disabled (also real)
        if settings.soundSetting != .enabled {
            capability = .soundsDisabled
            return
        }

        capability = .ok
    }

    func ensurePermissionOrSettings() async -> Bool {
        // Returns true only if alarm-capable after potential permission request.
        await refresh()

        // If we can’t request (already denied/disabled), just return capability.
        guard capability == .notDetermined else {
            return capability.isAlarmCapable
        }

        // Ask once if not determined, then re-check settings.
        let granted = await requestPermission()
        await refresh()

        return granted && capability.isAlarmCapable
    }

    func requestPermission() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            DebugOnly.run {
                print("Notification permission request failed:", error)
            }
            return false
        }
    }

    func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

private extension UNUserNotificationCenter {
    func notificationSettings() async -> UNNotificationSettings {
        await withCheckedContinuation { cont in
            getNotificationSettings { cont.resume(returning: $0) }
        }
    }
}
