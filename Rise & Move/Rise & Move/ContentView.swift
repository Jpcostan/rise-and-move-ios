//
//  ContentView.swift
//  Rise & Move
//

import SwiftUI

private struct EditingAlarmItem: Identifiable {
    let id: UUID
}

// ✅ NEW: Identifiable wrapper for presenting a test alarm
private struct TestAlarmItem: Identifiable {
    let id = UUID()
    let alarm: Alarm
}

struct ContentView: View {
    @EnvironmentObject private var store: AlarmStore
    @State private var showingAddAlarm = false
    @State private var showingSettings = false
    @State private var editingAlarmItem: EditingAlarmItem?
    @State private var didRequestNotifications = false
    @EnvironmentObject private var router: AppRouter

    // ✅ Notification health + foreground refresh
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var notificationHealth = NotificationHealth()

    // ✅ Toggle guardrail state
    @State private var showNotificationsGate = false
    @State private var pendingToggleAlarmID: UUID? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                dawnBackground

                VStack(spacing: 0) {
                    // ✅ Banner only when notifications aren't alarm-capable
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {

                // Settings button (top-left)
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingSettings = true
                    } label: {
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

            // Settings sheet
            .sheet(isPresented: $showingSettings) {
                SettingsView()
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

            // ✅ NEW: Test alarm full-screen cover (separate from real alarms)
            .fullScreenCover(
                item: Binding<TestAlarmItem?>(
                    get: {
                        router.activeTestAlarm.map { TestAlarmItem(alarm: $0) }
                    },
                    set: { item in
                        if item == nil { router.clearTestAlarm() }
                    }
                )
            ) { item in
                AlarmRingingView(alarm: item.alarm) {
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

            // Existing: initial permission request
            .task {
                guard !didRequestNotifications else { return }
                didRequestNotifications = true
                _ = await NotificationManager.shared.requestAuthorization()
            }

            // Keep notification status current
            .task {
                await notificationHealth.refresh()
            }
            .onChange(of: scenePhase) { _, newValue in
                if newValue == .active {
                    Task { await notificationHealth.refresh() }
                }
            }
            // ✅ If a notification tries to open an alarm while a sheet is up,
            // dismiss sheets so the fullScreenCover can present.
            .onChange(of: router.activeTestAlarm) { _, newValue in
                guard newValue != nil else { return }
                showingSettings = false
                showingAddAlarm = false
                editingAlarmItem = nil
            }

            .onChange(of: router.activeAlarmID) { _, newValue in
                guard newValue != nil else { return }
                showingSettings = false
                showingAddAlarm = false
                editingAlarmItem = nil
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

#Preview {
    ContentView()
}
