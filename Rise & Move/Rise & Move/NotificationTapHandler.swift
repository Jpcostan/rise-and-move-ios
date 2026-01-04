//
//  NotificationTapHandler.swift
//  Rise & Move
//
//  Created by Joshua Costanza on 1/3/26.
//

import Foundation
import UserNotifications

@MainActor
final class NotificationTapHandler: NSObject, UNUserNotificationCenterDelegate {

    static let shared = NotificationTapHandler()

    // We’ll set this from the App layer once the router exists.
    var onAlarmTapped: ((UUID) -> Void)?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }

        let userInfo = response.notification.request.content.userInfo
        guard
            let idString = userInfo["alarmID"] as? String,
            let id = UUID(uuidString: idString)
        else { return }

        onAlarmTapped?(id)
    }
}
