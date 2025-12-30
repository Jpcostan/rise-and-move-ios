//
//  EditAlarmView.swift
//  Rise & Move
//
//  Created by Joshua Costanza on 12/29/25.
//
import SwiftUI

struct EditAlarmView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var time: Date
    @State private var label: String
    @State private var repeatDays: Set<Weekday>
    @State private var isEnabled: Bool

    let onSave: (Alarm) -> Void
    let original: Alarm

    init(alarm: Alarm, onSave: @escaping (Alarm) -> Void) {
        self.original = alarm
        self.onSave = onSave

        _time = State(initialValue: alarm.time)
        _label = State(initialValue: alarm.label)
        _repeatDays = State(initialValue: alarm.repeatDays)
        _isEnabled = State(initialValue: alarm.isEnabled)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Enabled", isOn: $isEnabled)

                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                }

                Section("Label") {
                    TextField("Alarm label", text: $label)
                }

                Section("Repeat") {
                    ForEach(Weekday.allCases) { day in
                        Toggle(day.short, isOn: Binding(
                            get: { repeatDays.contains(day) },
                            set: { isOn in
                                if isOn { repeatDays.insert(day) }
                                else { repeatDays.remove(day) }
                            }
                        ))
                    }
                }
            }
            .navigationTitle("Edit Alarm")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let updated = Alarm(
                            id: original.id,
                            time: time,
                            repeatDays: repeatDays,
                            isEnabled: isEnabled,
                            label: label.isEmpty ? "Alarm" : label
                        )
                        onSave(updated)
                        dismiss()
                    }
                }
            }
        }
    }
}

