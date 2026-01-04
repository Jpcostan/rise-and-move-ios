import Combine
import SwiftUI
import UIKit
import CoreHaptics

struct MovementTaskView: View {
    @Environment(\.dismiss) private var dismiss

    let secondsRequired: Double
    let onCompleted: () -> Void

    @State private var isHolding = false
    @State private var elapsed: Double = 0

    // Reminder haptics when user lets go mid-task
    @State private var remindToHold = false

    // Haptics: progress buckets
    @State private var lastHapticProgressBucket: Int = -1

    // ✅ NEW: Success state + one-shot haptic
    @State private var showSuccess = false
    @State private var didFireSuccess = false

    // ✅ NEW: Breathing animation (only while holding)
    @State private var breathe = false

    // Haptics generators (reused + prepared)
    private let holdStartHaptic = UIImpactFeedbackGenerator(style: .soft)
    private let progressTickHaptic = UIImpactFeedbackGenerator(style: .light)
    private let releaseNudgeHaptic = UIImpactFeedbackGenerator(style: .medium)
    private let reminderHaptic = UIImpactFeedbackGenerator(style: .medium)
    private let successHaptic = UINotificationFeedbackGenerator()

    private let tick = 0.05 // 20 ticks per second

    private var progress: Double { min(elapsed / secondsRequired, 1.0) }
    private var remainingSeconds: Int { max(Int(ceil(secondsRequired - elapsed)), 0) }

    // Used to add a subtle “presence” glow tied to progress
    private var presenceColor: Color {
        // Smoothly moves Red -> Yellow -> Green as progress advances
        if progress < 0.5 {
            // 0.0..0.5 => red->yellow
            return Color(
                red: 1.0,
                green: 0.2 + (progress / 0.5) * 0.8,
                blue: 0.15
            )
        } else {
            // 0.5..1.0 => yellow->green
            let t = (progress - 0.5) / 0.5
            return Color(
                red: 1.0 - (t * 0.9),
                green: 1.0,
                blue: 0.15
            )
        }
    }

    var body: some View {
        ZStack {
            // Stronger contrast background for readability
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.06, blue: 0.10),
                    Color(red: 0.07, green: 0.08, blue: 0.14),
                    Color(red: 0.10, green: 0.09, blue: 0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                if showSuccess {
                    successState
                } else {
                    mainContent
                }
            }
            .padding(.top, 22)
            .padding(.bottom, 18)
        }
        .onAppear {
            elapsed = 0
            isHolding = false
            remindToHold = false
            lastHapticProgressBucket = -1

            // ✅ NEW
            showSuccess = false
            didFireSuccess = false
            breathe = false

            // Warm up generators for immediate response
            prepareHaptics()
        }
        .onDisappear {
            // ✅ NEW: Ensure no timers/haptics continue if dismissed mid-hold
            isHolding = false
            remindToHold = false
            stopBreathing()
        }
        // Also keep them warmed if the user is about to interact
        .onChange(of: isHolding) { newValue in
            if newValue {
                prepareHaptics()
                startBreathing()
            } else {
                stopBreathing()
            }
        }
        // Progress timer
        .onReceive(Timer.publish(every: tick, on: .main, in: .common).autoconnect()) { _ in
            guard isHolding, !showSuccess else { return }

            elapsed += tick
            fireProgressHapticIfNeeded()

            if elapsed >= secondsRequired {
                completeSuccess()
            }
        }
        // Reminder haptics timer (fires only when user let go mid-hold)
        .onReceive(Timer.publish(every: 1.1, on: .main, in: .common).autoconnect()) { _ in
            guard remindToHold, !isHolding, !showSuccess else { return }
            guard elapsed > 0, elapsed < secondsRequired else { return }

            guard supportsHaptics else { return }

            // “Hey!” reminder (noticeable, but not harsh)
            reminderHaptic.prepare()
            reminderHaptic.impactOccurred(intensity: 0.95)
        }
    }

    private var supportsHaptics: Bool {
        CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }

    private func prepareHaptics() {
        guard supportsHaptics else { return }
        holdStartHaptic.prepare()
        progressTickHaptic.prepare()
        releaseNudgeHaptic.prepare()
        reminderHaptic.prepare()
        successHaptic.prepare()
    }

    // ✅ NEW: Breathing control (only while holding)
    private func startBreathing() {
        breathe = false
        withAnimation(.easeInOut(duration: 10.0).repeatForever(autoreverses: true)) {
            breathe = true
        }
    }

    private func stopBreathing() {
        // Stop modulation immediately when not holding
        breathe = false
    }

    // ✅ NEW: Completion sequence with success state + perceived delay
    private func completeSuccess() {
        guard !showSuccess else { return }

        isHolding = false
        remindToHold = false
        showSuccess = true

        // Fire success haptic once
        if supportsHaptics, !didFireSuccess {
            didFireSuccess = true
            successHaptic.notificationOccurred(.success)
        }

        // Let success state be perceived, then finish
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
            onCompleted()
            dismiss()
        }
    }

    private var mainContent: some View {
        VStack(spacing: 18) {
            headerBlock

            progressBlock

            holdSurface
                .padding(.top, 6)

            cancelButton

            Spacer(minLength: 0)
        }
    }

    private var headerBlock: some View {
        VStack(spacing: 10) {
            Text("Rise & Move")
                .font(.system(.title2, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(.white)

            Text("Stay present for a moment")
                .font(.system(.title3, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(.white.opacity(0.88))

            Text(remainingSeconds > 0 ? "\(remainingSeconds)s remaining" : "Almost there")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(.white.opacity(0.78))
        }
        .padding(.top, 6)
    }

    private var progressBlock: some View {
        VStack(spacing: 12) {
            // Gradient progress (red -> yellow -> green)
            GradientProgressBar(progress: progress)
                .padding(.horizontal)

            // ✅ Copy pass: keep 1 instruction line, avoid repeating "press and hold" twice
            Text(isHolding ? "Keep holding…" : "Hold to stop the alarm")
                .font(.system(.callout, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(.white.opacity(0.78))
        }
    }

    private var cancelButton: some View {
        Button {
            // ✅ NEW: Hard-stop task state so Cancel always feels immediate
            isHolding = false
            remindToHold = false
            stopBreathing()
            dismiss()
        } label: {
            Text("Cancel")
                .font(.system(.callout, design: .rounded))
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .foregroundStyle(.white.opacity(0.88))
        }
        .buttonStyle(.bordered)
        .tint(.white.opacity(0.18)) // visible, but clearly secondary
        .padding(.horizontal)
        .disabled(showSuccess)
    }

    private var successState: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white.opacity(0.92))

            Text("Done")
                .font(.system(.title2, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(.white.opacity(0.92))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Done")
    }

    private var holdSurface: some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)

        return ZStack {
            shape
                .fill(Color.white.opacity(isHolding ? 0.18 : 0.10)) // ✅ tuned: lower idle
                .overlay(
                    shape.stroke(Color.white.opacity(isHolding ? 0.34 : 0.16), lineWidth: 1) // ✅ tuned: lower idle
                )
                // Subtle “presence” glow that shifts toward green as they progress
                .shadow(
                    color: presenceColor.opacity(
                        // ✅ PRODUCTION: subtle but perceptible breathing
                        isHolding ? (breathe ? 0.32 : 0.22) : 0.10
                    ),
                    radius: isHolding ? (breathe ? 24 : 20) : 12,
                    y: 10
                )
                .shadow(
                    color: .black.opacity(isHolding ? 0.35 : 0.22),
                    radius: isHolding ? 18 : 10,
                    y: 10
                )
                .frame(height: 92)

            VStack(spacing: 6) {
                Text(isHolding ? "Holding…" : "Hold")
                    .font(.system(.title3, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundStyle(.white)

                // ✅ Copy pass: avoid repeating hold instructions
                Text(isHolding ? "Stay steady" : "Ready when you are")
                    .font(.system(.callout, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(.white.opacity(0.82))
            }
            .padding(.horizontal, 18)
        }
        .padding(.horizontal)
        .contentShape(Rectangle())
        // ✅ PRODUCTION: subtle but perceptible breathing
        .scaleEffect(isHolding ? (breathe ? 1.015 : 0.985) : 1.0)
        .opacity(isHolding ? (breathe ? 1.0 : 0.96) : 1.0)
        .animation(.easeInOut(duration: 0.20), value: isHolding)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !showSuccess else { return }
                    if !isHolding {
                        isHolding = true
                        remindToHold = false // stop reminder as soon as they resume

                        guard supportsHaptics else { return }
                        holdStartHaptic.prepare()
                        holdStartHaptic.impactOccurred(intensity: 0.95)
                    }
                }
                .onEnded { _ in
                    guard !showSuccess else { return }
                    if isHolding {
                        isHolding = false

                        // If they let go mid-task, start reminders
                        if elapsed > 0, elapsed < secondsRequired {
                            remindToHold = true

                            guard supportsHaptics else { return }
                            releaseNudgeHaptic.prepare()
                            releaseNudgeHaptic.impactOccurred(intensity: 1.0)
                        } else {
                            remindToHold = false
                        }
                    }
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hold to stop the alarm")
        .accessibilityHint("Press and hold until progress completes")
        .disabled(showSuccess)
    }

    private func fireProgressHapticIfNeeded() {
        let bucket = Int((progress * 10.0).rounded(.down))
        guard bucket != lastHapticProgressBucket else { return }
        lastHapticProgressBucket = bucket

        // Skip 0% and 100%
        guard bucket > 0, bucket < 10 else { return }
        guard supportsHaptics else { return }

        // Subtle “tick” every 10%
        progressTickHaptic.prepare()
        progressTickHaptic.impactOccurred(intensity: 0.70)
    }
}

// MARK: - Gradient Progress Bar (Red -> Yellow -> Green)

private struct GradientProgressBar: View {
    let progress: Double // 0...1

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let clamped = max(0, min(progress, 1))
            let fill = width * clamped

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.14))

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.red, .yellow, .green],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: fill)
                    .animation(.linear(duration: 0.05), value: clamped)
            }
        }
        .frame(height: 10)
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int(progress * 100)) percent")
    }
}
