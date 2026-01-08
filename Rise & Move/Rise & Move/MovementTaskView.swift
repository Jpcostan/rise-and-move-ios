import Combine
import SwiftUI
import UIKit
import CoreHaptics
import AVFoundation

struct MovementTaskView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    let secondsRequired: Double
    let onCompleted: () -> Void

    @State private var isHolding = false
    @State private var elapsed: Double = 0

    // Reminder haptics when user lets go mid-task
    @State private var remindToHold = false

    // Haptics: progress buckets
    @State private var lastHapticProgressBucket: Int = -1

    // ✅ Success state + one-shot haptic
    @State private var showSuccess = false
    @State private var didFireSuccess = false

    // ✅ Breathing animation (only while holding)
    @State private var breathe = false

    // ✅ VoiceOver announcements (throttled)
    @State private var lastVOProgressBucket: Int = -1
    @State private var didAnnounceHoldStart = false
    @State private var didAnnounceSuccess = false

    // ✅ Interruption state (for calm messaging + avoiding repeats)
    @State private var isInterrupted = false
    @State private var lastInterruptionBeganAt: Date? = nil

    // Haptics generators (reused + prepared)
    private let holdStartHaptic = UIImpactFeedbackGenerator(style: .soft)
    private let progressTickHaptic = UIImpactFeedbackGenerator(style: .light)
    private let releaseNudgeHaptic = UIImpactFeedbackGenerator(style: .medium)
    private let reminderHaptic = UIImpactFeedbackGenerator(style: .medium)
    private let successHaptic = UINotificationFeedbackGenerator()

    private let tick = 0.05 // 20 ticks per second

    private var progress: Double { min(elapsed / secondsRequired, 1.0) }
    private var remainingSeconds: Int { max(Int(ceil(secondsRequired - elapsed)), 0) }
    private var progressPercentInt: Int { Int((progress * 100.0).rounded()) }

    // Used to add a subtle “presence” glow tied to progress
    private var presenceColor: Color {
        if progress < 0.5 {
            return Color(
                red: 1.0,
                green: 0.2 + (progress / 0.5) * 0.8,
                blue: 0.15
            )
        } else {
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

            VStack(spacing: 0) {
                if showSuccess {
                    successState
                        .padding(.top, 44)
                } else {
                    mainContent
                        .padding(.top, 18)
                }

                Spacer(minLength: 0)

                bottomActions
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 14)
        }
        .onAppear {
            resetState()
            prepareHaptics()
        }
        .onDisappear {
            isHolding = false
            remindToHold = false
            stopBreathing()
        }

        // ✅ Fail-safe: if app leaves active state while holding, treat as release.
        .onChange(of: scenePhase) { _, newPhase in
            guard !showSuccess else { return }

            switch newPhase {
            case .active:
                // Coming back — don’t auto-resume. Keep user in control.
                if isInterrupted {
                    // Small VO hint if they rely on it; don’t spam.
                    announce("Resume holding to stop the alarm.")
                    isInterrupted = false
                }
            case .inactive, .background:
                // If they were holding, release it (fail-safe).
                if isHolding {
                    onHoldEnded(suppressReleaseNudge: true)
                }
                stopBreathing()
            @unknown default:
                break
            }
        }

        // ✅ iOS 17+ signature (no deprecation warning)
        .onChange(of: isHolding) { _, newValue in
            if newValue {
                prepareHaptics()
                startBreathing()
            } else {
                stopBreathing()
            }
        }

        // Main progress tick
        .onReceive(Timer.publish(every: tick, on: .main, in: .common).autoconnect()) { _ in
            guard isHolding, !showSuccess else { return }

            elapsed += tick
            fireProgressHapticIfNeeded()
            announceProgressIfNeeded()

            if elapsed >= secondsRequired {
                completeSuccess()
            }
        }

        // Reminder haptics when released early
        .onReceive(Timer.publish(every: 1.1, on: .main, in: .common).autoconnect()) { _ in
            guard remindToHold, !isHolding, !showSuccess else { return }
            guard elapsed > 0, elapsed < secondsRequired else { return }
            guard supportsHaptics else { return }

            reminderHaptic.prepare()
            reminderHaptic.impactOccurred(intensity: 0.95)
        }

        // ✅ Audio interruptions (calls / Siri / system)
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { note in
            handleAudioInterruption(note)
        }

        // ✅ Route changes (headphones/Bluetooth). No behavior change, just safe hook.
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { note in
            handleAudioRouteChange(note)
        }
    }

    private func resetState() {
        elapsed = 0
        isHolding = false
        remindToHold = false
        lastHapticProgressBucket = -1
        showSuccess = false
        didFireSuccess = false
        breathe = false

        // VoiceOver state
        lastVOProgressBucket = -1
        didAnnounceHoldStart = false
        didAnnounceSuccess = false

        // Interruption state
        isInterrupted = false
        lastInterruptionBeganAt = nil
    }

    private var supportsHaptics: Bool {
        CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }

    private var voiceOverRunning: Bool {
        UIAccessibility.isVoiceOverRunning
    }

    private func prepareHaptics() {
        guard supportsHaptics else { return }
        holdStartHaptic.prepare()
        progressTickHaptic.prepare()
        releaseNudgeHaptic.prepare()
        reminderHaptic.prepare()
        successHaptic.prepare()
    }

    private func startBreathing() {
        // Respect Reduce Motion: keep the hold surface stable.
        guard !reduceMotion else {
            breathe = false
            return
        }

        breathe = false
        withAnimation(.easeInOut(duration: 10.0).repeatForever(autoreverses: true)) {
            breathe = true
        }
    }

    private func stopBreathing() {
        breathe = false
    }

    private func announce(_ message: String) {
        guard voiceOverRunning else { return }
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    private func onHoldStarted() {
        guard !showSuccess else { return }
        if !isHolding {
            isHolding = true
            remindToHold = false
            isInterrupted = false

            // Haptics
            if supportsHaptics {
                holdStartHaptic.prepare()
                holdStartHaptic.impactOccurred(intensity: 0.95)
            }

            // VoiceOver (one-shot)
            if !didAnnounceHoldStart {
                didAnnounceHoldStart = true
                announce("Holding. \(Int(secondsRequired)) seconds to stop.")
            }
        }
    }

    private func onHoldEnded(suppressReleaseNudge: Bool = false) {
        guard !showSuccess else { return }
        if isHolding {
            isHolding = false

            if elapsed > 0, elapsed < secondsRequired {
                remindToHold = true

                // Haptics
                if supportsHaptics, !suppressReleaseNudge {
                    releaseNudgeHaptic.prepare()
                    releaseNudgeHaptic.impactOccurred(intensity: 1.0)
                }

                // VoiceOver: gentle nudge (skip when backgrounding to avoid noise)
                if !suppressReleaseNudge {
                    announce("Released. Keep holding to stop.")
                }
            } else {
                remindToHold = false
            }
        }
    }

    private func completeSuccess() {
        guard !showSuccess else { return }

        isHolding = false
        remindToHold = false
        showSuccess = true

        if supportsHaptics, !didFireSuccess {
            didFireSuccess = true
            successHaptic.notificationOccurred(.success)
        }

        if !didAnnounceSuccess {
            didAnnounceSuccess = true
            announce("Alarm stopped.")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
            onCompleted()
            dismiss()
        }
    }

    // MARK: - Audio interruptions / route changes

    private func handleAudioInterruption(_ note: Notification) {
        guard !showSuccess else { return }

        guard
            let info = note.userInfo,
            let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }

        switch type {
        case .began:
            // Debounce repeated began notifications in a short window.
            let now = Date()
            if let last = lastInterruptionBeganAt, now.timeIntervalSince(last) < 0.5 {
                return
            }
            lastInterruptionBeganAt = now

            isInterrupted = true

            // Fail-safe: if holding, release (don’t let progress run during interruption).
            if isHolding {
                onHoldEnded(suppressReleaseNudge: true)
            }
            stopBreathing()

            announce("Interrupted. Resume holding to stop the alarm.")

        case .ended:
            // Don’t auto-resume. Keep user in control.
            // Some interruptions provide options; we ignore and stay safe.
            break

        @unknown default:
            break
        }
    }

    private func handleAudioRouteChange(_ note: Notification) {
        guard !showSuccess else { return }
        // Intentionally no behavioral change. Route changes are common (AirPods, Bluetooth).
        // If you want later: show a subtle banner if audio output changed during ringing.
        // For now we just stay stable and fail-safe.
    }

    // MARK: - Main content

    private var mainContent: some View {
        VStack(spacing: 18) {
            headerBlock
            progressBlock

            HoldSurfaceView(
                isHolding: isHolding,
                breathe: breathe,
                showSuccess: showSuccess,
                progress: progress,
                presenceColor: presenceColor,
                reduceMotion: reduceMotion,
                onHoldStart: { onHoldStarted() },
                onHoldEnd: { onHoldEnded() }
            )
            .padding(.top, 6)

            // ✅ Make the whole surface one VoiceOver element (stable, predictable)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Stop alarm")
            .accessibilityHint(isHolding
                               ? "Keep holding until complete."
                               : "Press and hold until complete.")
            .accessibilityValue(showSuccess ? "Complete" : "\(progressPercentInt) percent")

            // ✅ Magic Tap (two-finger double tap) toggles hold for VoiceOver users
            .accessibilityAction(.magicTap) {
                guard !showSuccess else { return }
                isHolding ? onHoldEnded() : onHoldStarted()
            }

            // ✅ Explicit actions so VO users aren’t blocked by a drag gesture
            .accessibilityAction(named: isHolding ? "Stop holding" : "Start holding") {
                guard !showSuccess else { return }
                isHolding ? onHoldEnded() : onHoldStarted()
            }
            .disabled(showSuccess)
        }
    }

    // ✅ Polished header: badge-style remaining time + cleaner hierarchy
    private var headerBlock: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "sunrise.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white.opacity(0.90))

                Text("Rise & Move")
                    .font(.system(.title2, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
            }

            Text("Stay present for a moment")
                .font(.system(.title3, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(.white.opacity(0.88))

            remainingPill
        }
        .padding(.top, 4)
    }

    private var remainingPill: some View {
        let text = remainingSeconds > 0 ? "\(remainingSeconds)s remaining" : "Almost there"

        return Text(text)
            .font(.system(.footnote, design: .rounded))
            .fontWeight(.semibold)
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(.white.opacity(0.10))
                    .overlay(Capsule().stroke(.white.opacity(0.10), lineWidth: 1))
            )
            .animation(.easeOut(duration: 0.12), value: remainingSeconds)
            .accessibilityLabel(Text(text))
    }

    private var progressBlock: some View {
        VStack(spacing: 12) {
            GradientProgressBar(progress: progress, reduceMotion: reduceMotion)
                .padding(.horizontal, 6)

            Text(isHolding ? "Keep holding…" : "Hold to stop the alarm")
                .font(.system(.callout, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(.white.opacity(0.78))
        }
    }

    // MARK: - Bottom tray

    private var bottomActions: some View {
        VStack(spacing: 10) {
            Text("Press and hold until complete")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
                .opacity(showSuccess ? 0 : 1)
                .animation(.easeOut(duration: 0.15), value: showSuccess)

            cancelButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(.white.opacity(0.10), lineWidth: 1)
                )
        )
        .padding(.bottom, 8)
        .disabled(showSuccess)
    }

    private var cancelButton: some View {
        Button {
            isHolding = false
            remindToHold = false
            stopBreathing()
            announce("Cancelled.")
            dismiss()
        } label: {
            Text("Cancel")
                .font(.system(.callout, design: .rounded))
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .foregroundStyle(.white.opacity(0.90))
        }
        .buttonStyle(.bordered)
        .tint(.white.opacity(0.18))
        .accessibilityHint("Dismiss the alarm screen.")
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Done")
    }

    private func fireProgressHapticIfNeeded() {
        let bucket = Int((progress * 10.0).rounded(.down))
        guard bucket != lastHapticProgressBucket else { return }
        lastHapticProgressBucket = bucket

        guard bucket > 0, bucket < 10 else { return }
        guard supportsHaptics else { return }

        progressTickHaptic.prepare()
        progressTickHaptic.impactOccurred(intensity: 0.70)
    }

    private func announceProgressIfNeeded() {
        guard voiceOverRunning else { return }
        guard isHolding, !showSuccess else { return }

        // Announce every 20% (0..5 buckets), calm + not spammy.
        let bucket = Int((progress * 5.0).rounded(.down)) // 0=0%, 1=20%, ... 5=100%
        guard bucket != lastVOProgressBucket else { return }
        lastVOProgressBucket = bucket

        // Skip 0% (too noisy). Announce 20/40/60/80, and optionally 100 via success.
        guard bucket >= 1, bucket <= 4 else { return }

        let pct = bucket * 20
        announce("\(pct) percent.")
    }
}

// MARK: - Hold Surface (no perimeter ring)

private struct HoldSurfaceView: View {
    let isHolding: Bool
    let breathe: Bool
    let showSuccess: Bool
    let progress: Double
    let presenceColor: Color
    let reduceMotion: Bool
    let onHoldStart: () -> Void
    let onHoldEnd: () -> Void

    private let corner: CGFloat = 26
    private let height: CGFloat = 92

    var body: some View {
        let cardShape = RoundedRectangle(cornerRadius: corner, style: .continuous)

        ZStack {
            cardShape
                .fill(Color.white.opacity(isHolding ? 0.18 : 0.10))
                .overlay(cardShape.stroke(Color.white.opacity(isHolding ? 0.34 : 0.16), lineWidth: 1))
                .shadow(
                    color: presenceColor.opacity(isHolding ? (breathe ? 0.32 : 0.22) : 0.10),
                    radius: isHolding ? (breathe ? 24 : 20) : 12,
                    y: 10
                )
                .shadow(
                    color: .black.opacity(isHolding ? 0.35 : 0.22),
                    radius: isHolding ? 18 : 10,
                    y: 10
                )
                .frame(maxWidth: .infinity)
                .frame(height: height)

            VStack(spacing: 6) {
                Text(isHolding ? "Holding…" : "Hold")
                    .font(.system(.title3, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundStyle(.white)

                Text(isHolding ? "Stay steady" : "Ready when you are")
                    .font(.system(.callout, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(.white.opacity(0.82))
            }
            .padding(.horizontal, 18)
        }
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        // Reduce Motion: keep stable size/opacity.
        .scaleEffect(reduceMotion ? 1.0 : (isHolding ? (breathe ? 1.015 : 0.985) : 1.0))
        .opacity(reduceMotion ? 1.0 : (isHolding ? (breathe ? 1.0 : 0.96) : 1.0))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.20), value: isHolding)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in onHoldStart() }
                .onEnded { _ in onHoldEnd() }
        )
    }
}

// MARK: - Gradient Progress Bar (Red -> Yellow -> Green)

private struct GradientProgressBar: View {
    let progress: Double // 0...1
    let reduceMotion: Bool

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
                    .animation(reduceMotion ? nil : .linear(duration: 0.05), value: clamped)
            }
        }
        .frame(height: 10)
        .accessibilityLabel("Hold progress")
        .accessibilityValue("\(Int(progress * 100)) percent")
    }
}
