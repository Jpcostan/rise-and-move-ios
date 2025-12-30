import Combine
import SwiftUI
import UIKit

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

                VStack(spacing: 12) {
                    // Gradient progress (red -> yellow -> green)
                    GradientProgressBar(progress: progress)
                        .padding(.horizontal)

                    Text(isHolding ? "Keep holding…" : "Press and hold to stop")
                        .font(.system(.callout, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(.white.opacity(0.78))
                }

                holdSurface
                    .padding(.top, 6)

                Button {
                    // Stop any reminder loop
                    remindToHold = false
                    dismiss()
                } label: {
                    Text("Cancel")
                        .font(.system(.headline, design: .rounded))
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(.white)
                }
                .buttonStyle(.bordered)
                .tint(.white.opacity(0.28)) // visible, but clearly secondary
                .padding(.horizontal)

                Spacer(minLength: 0)
            }
            .padding(.top, 22)
            .padding(.bottom, 18)
        }
        .onAppear {
            elapsed = 0
            isHolding = false
            remindToHold = false
            lastHapticProgressBucket = -1
        }
        // Progress timer
        .onReceive(Timer.publish(every: tick, on: .main, in: .common).autoconnect()) { _ in
            guard isHolding else { return }

            elapsed += tick
            fireProgressHapticIfNeeded()

            if elapsed >= secondsRequired {
                isHolding = false
                remindToHold = false
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onCompleted()
                dismiss()
            }
        }
        // Reminder haptics timer (fires only when user let go mid-hold)
        .onReceive(Timer.publish(every: 1.1, on: .main, in: .common).autoconnect()) { _ in
            guard remindToHold, !isHolding else { return }
            guard elapsed > 0, elapsed < secondsRequired else { return }

            // “Hey!” reminder (noticeable, but not harsh)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.9)
        }
    }

    private var holdSurface: some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)

        return ZStack {
            shape
                .fill(Color.white.opacity(isHolding ? 0.18 : 0.12))
                .overlay(
                    shape.stroke(Color.white.opacity(isHolding ? 0.34 : 0.18), lineWidth: 1)
                )
                // Subtle “presence” glow that shifts toward green as they progress
                .shadow(color: presenceColor.opacity(isHolding ? 0.28 : 0.14),
                        radius: isHolding ? 22 : 14,
                        y: 10)
                .shadow(color: .black.opacity(isHolding ? 0.35 : 0.25),
                        radius: isHolding ? 18 : 12,
                        y: 10)
                .frame(height: 92)

            VStack(spacing: 6) {
                Text(isHolding ? "Holding…" : "Hold")
                    .font(.system(.title3, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundStyle(.white)

                Text(isHolding ? "Stay steady" : "Press and keep your finger down")
                    .font(.system(.callout, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(.white.opacity(0.82))
            }
            .padding(.horizontal, 18)
        }
        .padding(.horizontal)
        .contentShape(Rectangle())
        .scaleEffect(isHolding ? 0.995 : 1.0)
        .animation(.easeInOut(duration: 0.20), value: isHolding)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isHolding {
                        isHolding = true
                        remindToHold = false // stop reminder as soon as they resume
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.9)
                    }
                }
                .onEnded { _ in
                    if isHolding {
                        isHolding = false

                        // If they let go mid-task, start reminders
                        if elapsed > 0, elapsed < secondsRequired {
                            remindToHold = true
                            // Immediate nudge on release
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 1.0)
                        } else {
                            remindToHold = false
                        }
                    }
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hold to stop the alarm")
        .accessibilityHint("Press and hold until progress completes")
    }

    private func fireProgressHapticIfNeeded() {
        let bucket = Int((progress * 10.0).rounded(.down))
        guard bucket != lastHapticProgressBucket else { return }
        lastHapticProgressBucket = bucket

        // Skip 0% and 100%
        guard bucket > 0, bucket < 10 else { return }

        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.55)
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
