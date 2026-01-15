//
//  ContentView.swift
//  Rise & Move
//

import SwiftUI

private struct EditingAlarmItem: Identifiable {
    let id: UUID
}

// ✅ Identifiable wrapper for presenting a test alarm
// ✅ IMPORTANT: Use the alarm's UUID as the Identifiable ID so the cover doesn't
// re-create a brand-new identity every render (prevents "flash/dismiss/reopen").
private struct TestAlarmItem: Identifiable {
    let alarm: Alarm
    var id: UUID { alarm.id }
}

struct ContentView: View {
    @EnvironmentObject private var store: AlarmStore
    @EnvironmentObject private var router: AppRouter

    @State private var showingAddAlarm = false
    @State private var showSettingsNav = false
    @State private var editingAlarmItem: EditingAlarmItem?

    // ✅ Notification health + foreground refresh
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var notificationHealth = NotificationHealth()

    // ✅ Volume guardrail (soft banner)
    @StateObject private var volumeMonitor = VolumeMonitor()
    @State private var showingVolumeHelp = false

    // ✅ Toggle guardrail state
    @State private var showNotificationsGate = false
    @State private var pendingToggleAlarmID: UUID? = nil

    // ✅ Step 4: First-run onboarding gate
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false

    // ✅ Helps avoid doing volume monitoring / banners while ringing
    private var isRingingOrTesting: Bool {
        router.activeAlarmID != nil || router.activeTestAlarm != nil
    }

    // ✅ Source-of-truth for whether onboarding should be shown
    private var shouldShowOnboarding: Bool {
        // Never cover an alarm or test alarm.
        guard !isRingingOrTesting else { return false }
        // Show if first-run not completed OR Settings requested a replay.
        return !hasCompletedOnboarding || router.forceShowOnboarding
    }

    var body: some View {
        NavigationStack {
            ZStack {
                dawnBackground

                VStack(spacing: 0) {
                    // ✅ Banner #1 (hard): Notifications aren't alarm-capable
                    if !notificationHealth.capability.isAlarmCapable {
                        NotificationDisabledBanner(
                            title: notificationHealth.capability.title,
                            message: notificationHealth.capability.message,
                            ctaTitle: notificationHealth.capability.ctaTitle
                        ) {
                            if notificationHealth.capability == .notDetermined {
                                Task { _ = await notificationHealth.ensurePermissionOrSettings() }
                            } else {
                                notificationHealth.openAppSettings()
                            }
                        }
                    }

                    // ✅ Banner #2 (soft): Volume is very low (only show if notifications are OK)
                    // ✅ IMPORTANT: don't show while ringing / testing
                    if !isRingingOrTesting,
                       notificationHealth.capability.isAlarmCapable,
                       volumeMonitor.isLowStable {
                        NotificationDisabledBanner(
                            title: "Volume is low",
                            message: "You may not hear the alarm sound. Turn up volume to be safe.",
                            ctaTitle: "How to fix"
                        ) {
                            showingVolumeHelp = true
                        }
                    }

                    Group {
                        if store.alarms.isEmpty {
                            emptyState
                        } else {
                            alarmList
                        }
                    }
                }
            }
            .preferredColorScheme(.dark)
            .navigationTitle("Rise & Move")
            .navigationDestination(isPresented: $showSettingsNav) {
                SettingsView()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {

                // Settings button (top-left)
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { @MainActor in
                            // Let the sheet dismissal finish and hit-testing settle
                            await Task.yield()
                            showSettingsNav = true
                        }
                    }  label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background {
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .overlay(
                                        Circle()
                                            .stroke(.white.opacity(0.12), lineWidth: 1)
                                    )
                            }
                    }
                    .accessibilityLabel("Settings")
                }

                // Add alarm button (top-right)
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddAlarm = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background {
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .overlay(
                                        Circle()
                                            .stroke(.white.opacity(0.12), lineWidth: 1)
                                    )
                            }
                    }
                    .accessibilityLabel("Add alarm")
                }
            }

            // ✅ Volume help
            .alert("Turn Up Volume", isPresented: $showingVolumeHelp) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("""
                Use the side volume buttons or Control Center to raise the media volume.

                Tip: Run “Send Test Alarm” in Settings to confirm you can hear it.
                """)
            }

            // ✅ Onboarding full-screen cover (first-run + Settings replay)
            .fullScreenCover(
                isPresented: Binding(
                    get: { shouldShowOnboarding },
                    set: { newValue in
                        // When the cover is dismissed (newValue becomes false), clear the Settings replay flag.
                        if !newValue {
                            router.clearOnboardingRequest()

                            // ✅ If onboarding dismissed due to "Unlock Pro", present paywall now.
                            if router.presentPaywallAfterOnboarding {
                                router.clearDeferredPaywallRequest()
                                router.presentPaywall(source: .onboarding)
                            }
                        }
                    }
                )
            ) {
                OnboardingFlowView(
                    onFinish: {
                        hasCompletedOnboarding = true
                        router.clearOnboardingRequest()
                    },
                    onTryTestAlarm: {
                        // Teach the hold interaction immediately (no notification delivery needed).
                        router.clearOnboardingRequest()
                        router.openTestAlarm()
                    }
                )
                .environmentObject(router) // ✅ ensure onboarding receives router for paywall presentation
                .interactiveDismissDisabled(true)
            }

            .sheet(isPresented: $showingAddAlarm) {
                AddAlarmView { newAlarm in
                    store.add(newAlarm)
                }
            }

            .sheet(item: $editingAlarmItem) { item in
                if let index = store.alarms.firstIndex(where: { $0.id == item.id }) {
                    EditAlarmView(alarm: store.alarms[index]) { updated in
                        store.update(updated)
                    }
                }
            }

            // ✅ Global Paywall sheet (single source of truth)
            .sheet(item: $router.paywallContext) { _ in
                PaywallView(
                    onPurchased: {
                        // ✅ No-op is fine: entitlements refresh drives router.isPro elsewhere.
                    },
                    onClose: {
                        router.dismissPaywall()
                    }
                )
            }
            .onChange(of: router.isPro) { _, isPro in
                // ✅ If purchase succeeds and entitlements update, auto-dismiss paywall
                if isPro {
                    router.dismissPaywall()
                }
            }

            // ✅ Test alarm full-screen cover (separate from real alarms)
            .fullScreenCover(
                item: Binding<TestAlarmItem?>(
                    get: { router.activeTestAlarm.map { TestAlarmItem(alarm: $0) } },
                    set: { item in
                        if item == nil { router.clearTestAlarm() }
                    }
                )
            ) { item in
                AlarmRingingView(alarm: item.alarm, isTestMode: true) {
                    // Test alarm stop: just dismiss
                    router.clearTestAlarm()
                }
                .environmentObject(router)
            }

            // Existing: real alarm full-screen cover (driven by alarm ID)
            .fullScreenCover(
                item: Binding(
                    get: { router.activeAlarmID.map { EditingAlarmItem(id: $0) } },
                    set: { item in if item == nil { router.clearActiveAlarm() } }
                )
            ) { item in
                if let alarm = store.alarms.first(where: { $0.id == item.id }) {
                    AlarmRingingView(alarm: alarm) {
                        store.markAlarmFired(alarm.id)
                    }
                    .environmentObject(router)
                } else {
                    // Alarm ID no longer exists (deleted / storage reset). Avoid blank cover.
                    Color.clear
                        .onAppear { router.clearActiveAlarm() }
                }
            }

            // ✅ Toggle guardrail alert
            .alert(notificationHealth.capability.title, isPresented: $showNotificationsGate) {
                if notificationHealth.capability == .notDetermined {
                    Button("Allow Notifications") {
                        Task {
                            let ok = await notificationHealth.ensurePermissionOrSettings()
                            if ok, let id = pendingToggleAlarmID {
                                store.setEnabled(alarmID: id, isEnabled: true)
                            }
                            pendingToggleAlarmID = nil
                        }
                    }
                } else {
                    Button("Open Settings") {
                        notificationHealth.openAppSettings()
                        pendingToggleAlarmID = nil
                    }
                }

                Button("Cancel", role: .cancel) {
                    pendingToggleAlarmID = nil
                }
            } message: {
                Text(notificationHealth.capability.message)
            }

            // ✅ Keep notification status current
            .task {
                await notificationHealth.refresh()
            }

            // ✅ Start/stop VolumeMonitor while ContentView is alive (but don't fight active alarms)
            .onAppear {
                if !isRingingOrTesting {
                    volumeMonitor.start()
                }
            }
            .onDisappear {
                volumeMonitor.stop()
            }

            // ✅ Scene phase handling
            .onChange(of: scenePhase) { _, newValue in
                switch newValue {
                case .active:
                    Task { await notificationHealth.refresh() }
                    if !isRingingOrTesting {
                        volumeMonitor.start()
                    }

                case .background:
                    volumeMonitor.stop()

                case .inactive:
                    // ✅ Do nothing to avoid session churn during transitions.
                    break

                @unknown default:
                    break
                }
            }

            // ✅ If a notification tries to open an alarm while a sheet/onboarding is up,
            // dismiss sheets so the fullScreenCover can present.
            .onChange(of: router.activeTestAlarm) { _, newValue in
                guard newValue != nil else { return }

                // ✅ NEW: make sure nothing else is presenting
                showSettingsNav = false
                router.dismissPaywall()

                showingAddAlarm = false
                editingAlarmItem = nil

                // ✅ Stop volume monitoring during ringing/test alarm
                volumeMonitor.stop()
            }

            .onChange(of: router.activeAlarmID) { _, newValue in
                guard newValue != nil else { return }

                // ✅ NEW: make sure nothing else is presenting
                showSettingsNav = false
                router.dismissPaywall()

                showingAddAlarm = false
                editingAlarmItem = nil

                // ✅ Stop volume monitoring during ringing
                volumeMonitor.stop()
            }
        }
    }

    // MARK: - Dawn Background

    private var dawnBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.08, green: 0.10, blue: 0.16),
                Color(red: 0.12, green: 0.13, blue: 0.22),
                Color(red: 0.24, green: 0.18, blue: 0.20),
                Color(red: 0.38, green: 0.27, blue: 0.22)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    // MARK: - Alarm List

    private var alarmList: some View {
        List {
            ForEach(store.alarms) { alarm in
                AlarmCardRow(
                    alarm: alarm,
                    onEdit: { editingAlarmItem = EditingAlarmItem(id: alarm.id) },
                    onToggle: { newValue in
                        // ✅ Guardrail: only gate turning ON
                        if newValue == false {
                            store.setEnabled(alarmID: alarm.id, isEnabled: false)
                            return
                        }

                        // Attempting to turn ON — verify notifications
                        Task {
                            let ok = await notificationHealth.ensurePermissionOrSettings()
                            if ok {
                                store.setEnabled(alarmID: alarm.id, isEnabled: true)
                            } else {
                                pendingToggleAlarmID = alarm.id
                                showNotificationsGate = true

                                // Ensure alarm stays OFF (in case toggle UI briefly flips)
                                store.setEnabled(alarmID: alarm.id, isEnabled: false)
                            }
                        }
                    }
                )
                .listRowInsets(.init(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
            }
            .onDelete { indexSet in
                store.delete(atOffsets: indexSet)
            }
        }
        .scrollContentBackground(.hidden)
        .listStyle(.plain)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(systemName: "alarm")
                .font(.system(size: 44, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white.opacity(0.75))
                .padding(.bottom, 6)

            Text("No alarms yet")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.white)

            Text("Create your first alarm and start your day with intention.")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            Button {
                showingAddAlarm = true
            } label: {
                Text("Add Alarm")
                    .font(.headline)
                    .frame(maxWidth: 220)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 6)

            Text("You can change this anytime.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.55))
                .padding(.top, 4)

            Spacer()
        }
        .padding()
    }
}

// MARK: - Alarm Card Row

private struct AlarmCardRow: View {
    let alarm: Alarm
    let onEdit: () -> Void
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(alarm.time, style: .time)
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)

                    HStack(spacing: 8) {
                        Text(alarm.label.isEmpty ? "Alarm" : alarm.label)
                            .font(.headline)
                            .foregroundStyle(.white)

                        Text(alarm.isEnabled ? "ON" : "OFF")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.white.opacity(0.15), in: Capsule())
                            .foregroundStyle(.white.opacity(0.85))
                    }

                    if !alarm.repeatDays.isEmpty {
                        repeatRow
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Toggle(
                "",
                isOn: Binding(
                    get: { alarm.isEnabled },
                    set: { onToggle($0) }
                )
            )
            .labelsHidden()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(.white.opacity(0.08))
                )
        )
    }

    // MARK: - Repeat display (Every day / Weekdays / Weekends / Chips)

    private var repeatRow: some View {
        if let label = repeatPatternLabel(for: alarm.repeatDays) {
            return AnyView(
                Text(label)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.80))
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.white.opacity(0.12)))
                    .overlay(Capsule().stroke(.white.opacity(0.10), lineWidth: 1))
                    .accessibilityLabel(Text("Repeats \(label.lowercased())"))
            )
        }

        return AnyView(
            HStack(spacing: 8) {
                ForEach(
                    alarm.repeatDays.sorted(by: { $0.rawValue < $1.rawValue }),
                    id: \.self
                ) { day in
                    Text(chipLabel(for: day))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .allowsTightening(true)
                        .frame(width: 34, height: 34)
                        .background(Capsule().fill(.white.opacity(0.12)))
                        .overlay(Capsule().stroke(.white.opacity(0.10), lineWidth: 1))
                        .accessibilityLabel(Text(dayAccessibilityLabel(for: day)))
                }
            }
        )
    }

    private func repeatPatternLabel(for days: Set<Weekday>) -> String? {
        let all = Set(Weekday.allCases)
        if days == all { return "Every day" }

        guard Weekday.allCases.count == 7 else { return nil }

        let first = Weekday.allCases.first!
        let last = Weekday.allCases.last!
        let weekend = Set([first, last])

        if days == weekend { return "Weekends" }

        let weekdays = all.subtracting(weekend)
        if days == weekdays { return "Weekdays" }

        return nil
    }

    private func chipLabel(for day: Weekday) -> String {
        let s = day.short.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(s.prefix(2))
    }

    private func dayAccessibilityLabel(for day: Weekday) -> String {
        day.short
    }
}

#if DEBUG
#Preview {
    // NOTE: Provide environment objects in previews if you want it to render.
    // If you prefer, you can remove the preview entirely.
    ContentView()
}
#endif
