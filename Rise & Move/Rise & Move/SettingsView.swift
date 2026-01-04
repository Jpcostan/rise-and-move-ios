//
//  SettingsView.swift
//  Rise & Move
//
//  Created by Joshua Costanza on 1/3/26.
//

import SwiftUI
import StoreKit
import UIKit
import AVFoundation

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var entitlements: EntitlementManager

    @StateObject private var notificationHealth = NotificationHealth()

    // ✅ Volume monitor
    @StateObject private var volumeMonitor = VolumeMonitor()
    @State private var showingVolumeHelp = false

    @State private var isRestoring = false
    @State private var restoreMessage: String?

    // ✅ Test alarm UI state
    @State private var showingTestScheduledAlert = false
    @State private var testScheduledSeconds = 15
    @State private var testErrorMessage: String?

    private let supportEmail = "info@sleepwalkersoft.com"

    var body: some View {
        NavigationStack {
            Form {
                Section("Pro") {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(router.isPro ? "Pro" : "Free")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(router.isPro ? .green : .secondary)
                    }

                    Button {
                        Task { await openManageSubscriptions() }
                    } label: {
                        Text("Manage Subscription")
                    }

                    Button {
                        Task { await restorePurchases() }
                    } label: {
                        HStack {
                            Text("Restore Purchases")
                            Spacer()
                            if isRestoring { ProgressView() }
                        }
                    }
                    .disabled(isRestoring)

                    if let restoreMessage {
                        Text(restoreMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                // ✅ Test Alarm section
                Section("Test Alarm") {
                    Stepper(value: $testScheduledSeconds, in: 5...60, step: 5) {
                        Text("In \(testScheduledSeconds) seconds")
                    }

                    Button {
                        Task { await sendTestAlarm() }
                    } label: {
                        Text("Send Test Alarm")
                    }

                    if let testErrorMessage {
                        Text(testErrorMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .alert("Test Scheduled", isPresented: $showingTestScheduledAlert) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text("A test alarm will fire in \(testScheduledSeconds) seconds.")
                }

                // ✅ Audio guardrail (volume)
                Section("Audio") {
                    HStack {
                        Text("Volume")
                        Spacer()
                        Text(volumeMonitor.isLow ? "Low" : "OK")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(volumeMonitor.isLow ? .orange : .secondary)
                    }

                    if volumeMonitor.isLow {
                        Text("Your volume is very low. You may not hear the alarm sound.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Button("Fix Volume") {
                            showingVolumeHelp = true
                        }
                    }
                }
                .alert("Turn Up Volume", isPresented: $showingVolumeHelp) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text("""
                    Use the side volume buttons or Control Center to raise the media volume.

                    Tip: While a test alarm is ringing, turn volume up to confirm you can hear it.
                    """)
                }

                Section("Support") {
                    Link("Contact Support", destination: mailtoURL())
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(versionString)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }

            // ✅ Refresh + start volume monitoring whenever Settings becomes visible
            .onAppear {
                volumeMonitor.start()
                Task {
                    await refreshProStatus()
                    await notificationHealth.refresh()
                }
            }

            // ✅ Stop monitoring when leaving Settings
            .onDisappear {
                volumeMonitor.stop()
            }
        }
    }

    // MARK: - Test Alarm

    @MainActor
    private func sendTestAlarm() async {
        testErrorMessage = nil

        // Refresh capability
        await notificationHealth.refresh()

        // Ensure permission or route user to Settings
        let ok = await notificationHealth.ensurePermissionOrSettings()
        guard ok else {
            notificationHealth.openAppSettings()
            testErrorMessage = "Enable notifications (and Sounds) in Settings to run a test."
            return
        }

        // Schedule test notification
        await NotificationManager.shared.scheduleTestNotification(secondsFromNow: testScheduledSeconds)
        showingTestScheduledAlert = true
    }

    // MARK: - Entitlements refresh

    @MainActor
    private func refreshProStatus() async {
        await entitlements.refreshEntitlements()
        router.isPro = entitlements.isPro
    }

    // MARK: - Manage subscription

    @MainActor
    private func openManageSubscriptions() async {
        restoreMessage = nil

        guard
            let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first
        else {
            restoreMessage = "Couldn't open subscriptions right now. Please try again."
            return
        }

        do {
            try await AppStore.showManageSubscriptions(in: scene)
            await refreshProStatus()
        } catch {
            restoreMessage = "Couldn't open subscriptions. Please try again."
        }
    }

    // MARK: - Restore purchases

    private func restorePurchases() async {
        restoreMessage = nil
        isRestoring = true
        defer { isRestoring = false }

        do {
            try await AppStore.sync()
            await refreshProStatus()

            restoreMessage = router.isPro
                ? "Restored successfully."
                : "No active subscription found to restore."
        } catch {
            restoreMessage = "Restore failed. Please try again."
        }
    }

    // MARK: - Support mailto

    private func mailtoURL() -> URL {
        let subject = "Rise & Move Support"
        let body = """
        Hi! I need help with:

        App version: \(versionString)
        """

        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? subject
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? body

        return URL(string: "mailto:\(supportEmail)?subject=\(encodedSubject)&body=\(encodedBody)")!
    }

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}
