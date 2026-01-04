//
//  AddAlarmView.swift
//  Rise & Move
//

import SwiftUI

struct AddAlarmView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var time: Date = Date()
    @State private var label: String = "Alarm"
    @State private var repeatDays: Set<Weekday> = []

    // ✅ NEW: Backup alert settings
    @State private var backupEnabled: Bool = false
    @State private var backupMinutes: Int = 10

    // ✅ NEW: Default enabled depends on notification capability
    @StateObject private var notificationHealth = NotificationHealth()
    @State private var isEnabledDefault: Bool = true

    // Calm “confirm” accent (green, but not neon)
    private let accent = Color(red: 0.33, green: 0.87, blue: 0.56)

    let onSave: (Alarm) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                dawnBackground

                Form {
                    timeSection
                    labelSection
                    repeatSection
                    backupSection   // ✅ NEW
                }
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .tint(accent) // important: gives consistent selection/toggle/wheel tint
            }
            .preferredColorScheme(.dark)
            .navigationTitle("Add Alarm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
        }
        .modifier(DawnFormStyle())
        // ✅ NEW: determine default enabled state when the sheet appears
        .task {
            await notificationHealth.refresh()
            isEnabledDefault = notificationHealth.capability.isAlarmCapable
        }
    }

    // MARK: - Sections

    private var timeSection: some View {
        Section {
            DatePicker(
                "Time",
                selection: $time,
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .frame(maxWidth: .infinity)
            .listRowBackground(cardBackground)
        }
    }

    private var labelSection: some View {
        Section("Label") {
            TextField("Alarm label", text: $label)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .onSubmit { hideKeyboard() }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
        }
        .listRowBackground(cardBackground)
    }

    private var repeatSection: some View {
        Section("Repeat") {
            // Faster to parse than 7 toggles, and we control selected styling explicitly.
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                ForEach(Weekday.allCases) { day in
                    DayChip(
                        title: day.short,
                        isSelected: repeatDays.contains(day),
                        accent: accent
                    ) {
                        toggleDay(day)
                    }
                }
            }
            .padding(.vertical, 6)
            .accessibilityElement(children: .contain)

            // Small, calm helper line
            Text(repeatSummary)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.65))
                .padding(.top, 2)
        }
        .listRowBackground(cardBackground)
    }

    // ✅ NEW: Backup alert section
    private var backupSection: some View {
        Section("Backup Alert") {
            Toggle("Backup Alert", isOn: $backupEnabled)

            if backupEnabled {
                Stepper(value: $backupMinutes, in: 1...60, step: 1) {
                    Text("After \(backupMinutes) minute\(backupMinutes == 1 ? "" : "s")")
                }

                Text("Sends a follow-up alert if you haven’t stopped the alarm.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.65))
                    .padding(.top, 2)
            }
        }
        .listRowBackground(cardBackground)
    }

    // MARK: - Save

    private var canSave: Bool {
        true
    }

    private func save() {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)

        let newAlarm = Alarm(
            time: time,
            repeatDays: repeatDays,
            // ✅ CHANGED: default to OFF if notifications aren't alarm-capable
            isEnabled: isEnabledDefault,
            label: trimmed.isEmpty ? "Alarm" : trimmed,
            backupEnabled: backupEnabled,
            backupMinutes: backupMinutes
        )

        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        onSave(newAlarm)
        dismiss()
    }

    // MARK: - Repeat helpers

    private func toggleDay(_ day: Weekday) {
        if repeatDays.contains(day) {
            repeatDays.remove(day)
        } else {
            repeatDays.insert(day)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private var repeatSummary: String {
        if repeatDays.isEmpty { return "One-time alarm" }

        // Preserve Weekday.allCases ordering in summary
        let ordered = Weekday.allCases.filter { repeatDays.contains($0) }
        let names = ordered.map { $0.short }
        return "Repeats: " + names.joined(separator: " ")
    }

    // MARK: - Styling

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
    }

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

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }
}

// MARK: - Day Chip

private struct DayChip: View {
    let title: String
    let isSelected: Bool
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(ChipButtonStyle(isSelected: isSelected, accent: accent))
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

private struct ChipButtonStyle: ButtonStyle {
    let isSelected: Bool
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isSelected ? Color.black.opacity(0.95) : Color.white.opacity(0.90))
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? accent : Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? accent.opacity(0.85) : Color.white.opacity(0.10), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
