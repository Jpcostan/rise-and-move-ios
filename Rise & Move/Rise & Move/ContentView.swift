//
//  ContentView.swift
//  Rise & Move
//
//  Created by Joshua Costanza on 12/29/25.
//

import SwiftUI

private struct EditingAlarmItem: Identifiable {
    let id: UUID
}

struct ContentView: View {
    @StateObject private var store = AlarmStore()
    @State private var showingAddAlarm = false
    @State private var editingAlarmItem: EditingAlarmItem?
    @State private var didRequestNotifications = false
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.alarms) { alarm in
                    HStack {
                        Button {
                            editingAlarmItem = EditingAlarmItem(id: alarm.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(alarm.label)
                                    .font(.headline)

                                Text(alarm.time, style: .time)
                                    .font(.title2)
                                    .fontWeight(.semibold)

                                if !alarm.repeatDays.isEmpty {
                                    Text(
                                        alarm.repeatDays
                                            .sorted(by: { $0.rawValue < $1.rawValue })
                                            .map(\.short)
                                            .joined(separator: " ")
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                            }
                            // Key: make the tappable area include the whitespace
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Toggle(
                            "",
                            isOn: Binding(
                                get: { alarm.isEnabled },
                                set: { newValue in
                                    store.setEnabled(alarmID: alarm.id, isEnabled: newValue)
                                }
                            )
                        )
                        .labelsHidden()
                    }
                    .padding(.vertical, 6)
                }
                .onDelete { indexSet in
                    store.delete(atOffsets: indexSet)
                }
            }
            .navigationTitle("Rise & Move")
            .toolbar {
                Button {
                    showingAddAlarm = true
                } label: {
                    Image(systemName: "plus")
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
                } else {
                    EmptyView()
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
                    VStack(spacing: 12) {
                        Text("Alarm not found")
                        Button("Close") { router.clearActiveAlarm() }
                    }
                    .padding()
                }
            }
            .task {
                guard !didRequestNotifications else { return }
                didRequestNotifications = true

                let granted = await NotificationManager.shared.requestAuthorization()
                print("Notifications granted:", granted)
            }
        }
    }
}

#Preview {
    ContentView()
}

