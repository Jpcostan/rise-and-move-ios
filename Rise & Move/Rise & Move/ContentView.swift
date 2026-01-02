//
//  ContentView.swift
//  Rise & Move
//

import SwiftUI

private struct EditingAlarmItem: Identifiable {
    let id: UUID
}

struct ContentView: View {
    @EnvironmentObject private var store: AlarmStore
    @State private var showingAddAlarm = false
    @State private var editingAlarmItem: EditingAlarmItem?
    @State private var didRequestNotifications = false
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        NavigationStack {
            ZStack {
                dawnBackground

                Group {
                    if store.alarms.isEmpty {
                        emptyState
                    } else {
                        alarmList
                    }
                }
            }
            .preferredColorScheme(.dark)
            .navigationTitle("Rise & Move")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddAlarm = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(
                                Circle().stroke(.white.opacity(0.10), lineWidth: 1)
                            )
                    }
                    .accessibilityLabel("Add alarm")
                }
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
            .task {
                guard !didRequestNotifications else { return }
                didRequestNotifications = true
                _ = await NotificationManager.shared.requestAuthorization()
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
                        store.setEnabled(alarmID: alarm.id, isEnabled: newValue)
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
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "alarm")
                .font(.system(size: 44, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white.opacity(0.75))

            Text("No alarms yet")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.white)

            Text("Add one, then try Rise & Move once for free.")
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

        // Default: chips
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
                        .background(
                            Capsule().fill(.white.opacity(0.12))
                        )
                        .overlay(
                            Capsule().stroke(.white.opacity(0.10), lineWidth: 1)
                        )
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

