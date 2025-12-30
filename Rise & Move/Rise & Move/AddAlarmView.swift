//
//  AddAlarmView.swift
//  Rise & Move
//
//  Created by Joshua Costanza on 12/29/25.
//
import SwiftUI

struct AddAlarmView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var time: Date = Date()
    @State private var label: String = "Alarm"
    @State private var repeatDays: Set<Weekday> = []

    let onSave: (Alarm) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        "Time",
                        selection: $time,
                        displayedComponents: .hourAndMinute
                    )
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
                                if isOn {
                                    repeatDays.insert(day)
                                } else {
                                    repeatDays.remove(day)
                                }
                            }
                        ))
                    }
                }
            }
            .navigationTitle("Add Alarm")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let newAlarm = Alarm(
                            time: time,
                            repeatDays: repeatDays,
                            isEnabled: true,
                            label: label.isEmpty ? "Alarm" : label
                        )
                        onSave(newAlarm)
                        dismiss()
                    }
                }
            }
        }
    }
}

