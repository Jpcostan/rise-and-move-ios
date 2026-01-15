import SwiftUI
import AVFoundation

struct AlarmRingingView: View {
    @EnvironmentObject private var router: AppRouter

    let alarm: Alarm
    let onStop: () -> Void

    /// ✅ If true, this is a test alarm (from onboarding/settings).
    /// Test alarms should NEVER paywall and should NEVER consume the free try.
    let isTestMode: Bool

    init(alarm: Alarm, isTestMode: Bool = false, onStop: @escaping () -> Void) {
        self.alarm = alarm
        self.isTestMode = isTestMode
        self.onStop = onStop
    }

    @State private var player: AVAudioPlayer?
    @State private var showingMovementTask = false

    // Audio state
    @State private var audioObservers: [NSObjectProtocol] = []
    @State private var shouldResumeAfterInterruption = false

    // ✅ Low-volume guardrail
    @State private var isLowVolume = false
    private let lowVolumeThreshold: Float = 0.06

    // ✅ KVO observer for outputVolume
    @State private var volumeObserver: NSKeyValueObservation?

    // ✅ Stop press-and-hold
    @State private var stopHoldProgress: CGFloat = 0
    private let stopHoldDuration: TimeInterval = 0.7

    // Calm “confirm” accent (matches your other screens)
    private let accent = Color(red: 0.33, green: 0.87, blue: 0.56)

    /// ✅ In test mode we ALWAYS allow Rise & Move (no paywall, no “free try” consumption)
    private var canUseRiseAndMove: Bool {
        isTestMode ? true : router.canUseRiseAndMove
    }

    var body: some View {
        ZStack {
            dawnBackground

            VStack(spacing: 0) {
                VStack(spacing: 18) {
                    if isLowVolume {
                        lowVolumeBanner
                    }

                    header

                    Text(alarm.time, style: .time)
                        .font(.system(size: 64, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.top, 6)

                    Spacer(minLength: 0)

                    actionStack
                }
                .padding(20)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(.white.opacity(0.10), lineWidth: 1)
                )
                .padding(.horizontal, 18)
                .padding(.vertical, 22)
            }
        }
        .onAppear {
            configureAudioSessionAndStart()
            installAudioObservers()

            startVolumeMonitoring()
            syncLowVolumeAfterActivation()
        }
        .onDisappear {
            stopVolumeMonitoring()
            removeAudioObservers()
            stopSoundAndDeactivateSession()
        }
        .sheet(isPresented: $showingMovementTask) {
            MovementTaskView(secondsRequired: 20) {
                // ✅ IMPORTANT:
                // Only consume the free try for REAL alarms (and never in test mode).
                if !isTestMode, !router.effectiveIsPro {
                    router.markFreeRiseAndMoveUsed()
                }
                stopAndClose()
            }
        }
    }

    // MARK: - Subviews

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

    private var lowVolumeBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.slash.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white.opacity(0.9))

            Text("Volume is low — turn it up to hear the alarm.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .padding(.bottom, 2)
        .accessibilityLabel("Volume is low. Turn it up to hear the alarm.")
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("Rise & Move")
                .font(.system(.title, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(.white)

            Text(alarm.label.isEmpty ? "Alarm" : alarm.label)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.75))
        }
        .padding(.top, 6)
    }

    private var actionStack: some View {
        VStack(spacing: 12) {
            OptionCardButton(
                title: riseAndMoveTitle,
                subtitle: riseAndMoveSubtitle,
                leadingSystemImage: canUseRiseAndMove ? "figure.walk.motion" : "lock.fill",
                badgeText: riseAndMoveBadgeText,
                isPrimary: true,
                isLocked: !canUseRiseAndMove,
                accent: accent
            ) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()

                // ✅ In test mode: always go to the movement task (never paywall).
                if isTestMode {
                    showingMovementTask = true
                    return
                }

                if canUseRiseAndMove {
                    showingMovementTask = true
                } else {
                    // ✅ Single source of truth: present paywall via global ContentView sheet
                    router.presentPaywall(source: .gate)
                }
            }

            HoldToStopCard(
                title: "Stop",
                subtitle: "Press and hold to stop.",
                leadingSystemImage: "hand.tap",
                accent: accent,
                holdDuration: stopHoldDuration,
                progress: $stopHoldProgress
            ) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                stopAndClose()
            }
        }
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    // MARK: - Copy

    private var riseAndMoveTitle: String { "Rise & Move Stop" }

    private var riseAndMoveBadgeText: String? {
        if isTestMode { return "Test" }
        if router.effectiveIsPro { return nil }
        if !router.hasUsedFreeRiseAndMove { return "Try once free" }
        return "Pro required"
    }

    private var riseAndMoveSubtitle: String {
        if isTestMode { return "Practice the wake-up stop — no subscription needed." }
        if router.effectiveIsPro { return "Stops only after a short wake-up action." }
        if !router.hasUsedFreeRiseAndMove { return "Stops after a short wake-up action — try it once." }
        return "Unlock Pro to use wake-up stop anytime."
    }

    // MARK: - Actions

    private func stopAndClose() {
        stopSoundAndDeactivateSession()

        Task {
            await NotificationManager.shared.clearBackupRequest(for: alarm.id)
        }

        onStop()

        // ✅ Clear the correct routing state depending on mode.
        if isTestMode {
            router.clearTestAlarm()
        } else {
            router.clearActiveAlarm()
        }
    }

    // MARK: - Low volume detection

    private func startVolumeMonitoring() {
        guard volumeObserver == nil else { return }

        let session = AVAudioSession.sharedInstance()
        volumeObserver = session.observe(\.outputVolume, options: [.initial, .new]) { _, _ in
            Task { @MainActor in
                updateLowVolumeWarning()
            }
        }
    }

    private func stopVolumeMonitoring() {
        volumeObserver?.invalidate()
        volumeObserver = nil
    }

    private func syncLowVolumeAfterActivation() {
        Task { @MainActor in
            updateLowVolumeWarning()
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s
            updateLowVolumeWarning()
            try? await Task.sleep(nanoseconds: 800_000_000) // 0.8s
            updateLowVolumeWarning()
        }
    }

    private func updateLowVolumeWarning() {
        let vol = AVAudioSession.sharedInstance().outputVolume
        isLowVolume = vol <= lowVolumeThreshold
    }

    // MARK: - Audio session + playback

    private func configureAudioSessionAndStart() {
        let session = AVAudioSession.sharedInstance()

        do {
            try session.setCategory(
                .playback,
                mode: .default,
                options: [.duckOthers, .allowAirPlay]
            )

            try session.setActive(true)

            startSound()
            syncLowVolumeAfterActivation()
        } catch {
            DebugOnly.run {
                print("Audio session setup failed:", error)
            }
            startSound()
            syncLowVolumeAfterActivation()
        }
    }

    private func startSound() {
        guard let url = Bundle.main.url(forResource: "alarm", withExtension: "mp3")
                ?? Bundle.main.url(forResource: "alarm", withExtension: "m4a")
                ?? Bundle.main.url(forResource: "alarm", withExtension: "wav")
        else {
            DebugOnly.run {
                print("Alarm sound file not found in bundle.")
            }
            return
        }

        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.numberOfLoops = -1
            p.volume = 1.0
            p.prepareToPlay()
            p.play()
            player = p
        } catch {
            DebugOnly.run {
                print("Failed to start alarm sound:", error)
            }
        }
    }

    private func stopSoundAndDeactivateSession() {
        player?.stop()
        player = nil

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            DebugOnly.run {
                print("Failed to deactivate audio session:", error)
            }
        }
    }

    // MARK: - Audio observers (interruptions + route changes)

    private func installAudioObservers() {
        guard audioObservers.isEmpty else { return }

        let center = NotificationCenter.default

        let interruption = center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { note in
            handleInterruption(note)
        }

        let routeChange = center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { note in
            handleRouteChange(note)
        }

        audioObservers = [interruption, routeChange]
    }

    private func removeAudioObservers() {
        let center = NotificationCenter.default
        for o in audioObservers { center.removeObserver(o) }
        audioObservers.removeAll()
    }

    private func handleInterruption(_ note: Notification) {
        guard
            let info = note.userInfo,
            let typeRaw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeRaw)
        else { return }

        switch type {
        case .began:
            shouldResumeAfterInterruption = (player?.isPlaying == true)
            player?.pause()

        case .ended:
            guard let optionsRaw = info[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)

            if options.contains(.shouldResume), shouldResumeAfterInterruption {
                do {
                    try AVAudioSession.sharedInstance().setActive(true)
                } catch {
                    DebugOnly.run {
                        print("Failed to reactivate session after interruption:", error)
                    }
                }
                player?.play()
            }

            shouldResumeAfterInterruption = false

        @unknown default:
            break
        }

        updateLowVolumeWarning()
    }

    private func handleRouteChange(_ note: Notification) {
        guard
            let info = note.userInfo,
            let reasonRaw = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason = AVAudioSession.RouteChangeReason(rawValue: reasonRaw)
        else { return }

        switch reason {
        case .oldDeviceUnavailable, .newDeviceAvailable, .categoryChange, .override, .routeConfigurationChange:
            if player != nil {
                let wasPlaying = (player?.isPlaying == true)
                player?.stop()
                player?.currentTime = 0
                if wasPlaying { player?.play() }
            }
        default:
            break
        }

        updateLowVolumeWarning()
    }
}

// MARK: - Hold-to-stop card

private struct HoldToStopCard: View {
    let title: String
    let subtitle: String
    let leadingSystemImage: String
    let accent: Color
    let holdDuration: TimeInterval

    @Binding var progress: CGFloat
    let onComplete: () -> Void

    @State private var holdTask: Task<Void, Never>?

    var body: some View {
        Button {} label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.10))
                        .frame(width: 42, height: 42)
                        .overlay(Circle().stroke(Color.white.opacity(0.10), lineWidth: 1))

                    Image(systemName: leadingSystemImage)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.white.opacity(0.85))
                        .font(.system(size: 18, weight: .semibold))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.white)

                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.75))
                }

                Spacer()

                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.18), lineWidth: 3)
                        .frame(width: 22, height: 22)

                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(accent.opacity(0.95), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 22, height: 22)
                        .rotationEffect(.degrees(-90))
                }
                .opacity(progress > 0 ? 1 : 0.55)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: holdDuration)
                .onEnded { _ in
                    holdTask?.cancel()
                    holdTask = nil
                    progress = 0
                    onComplete()
                }
        )
        .onLongPressGesture(minimumDuration: 0.01, pressing: { pressing in
            if pressing {
                startProgress()
            } else {
                cancelProgress()
            }
        }, perform: {})
        .accessibilityHint(Text("Press and hold to stop the alarm"))
    }

    private func startProgress() {
        holdTask?.cancel()
        progress = 0

        let steps = 20
        let stepNanos = UInt64((holdDuration / Double(steps)) * 1_000_000_000)

        holdTask = Task { @MainActor in
            for i in 1...steps {
                if Task.isCancelled { return }
                progress = CGFloat(i) / CGFloat(steps)
                try? await Task.sleep(nanoseconds: stepNanos)
            }
        }
    }

    private func cancelProgress() {
        holdTask?.cancel()
        holdTask = nil
        withAnimation(.easeOut(duration: 0.12)) {
            progress = 0
        }
    }
}

// MARK: - Option Card Button

private struct OptionCardButton: View {
    let title: String
    let subtitle: String
    let leadingSystemImage: String
    let badgeText: String?
    let isPrimary: Bool
    let isLocked: Bool
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(isPrimary ? accent.opacity(0.18) : Color.white.opacity(0.10))
                        .frame(width: 42, height: 42)
                        .overlay(
                            Circle().stroke(Color.white.opacity(0.10), lineWidth: 1)
                        )

                    Image(systemName: leadingSystemImage)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(isPrimary ? accent : Color.white.opacity(0.85))
                        .font(.system(size: 18, weight: .semibold))
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(.white)

                        if let badgeText {
                            Text(badgeText)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(isLocked ? 0.80 : 0.90))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule().fill(Color.white.opacity(isLocked ? 0.10 : 0.14))
                                )
                                .overlay(
                                    Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1)
                                )
                        }
                    }

                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(isPrimary ? 0.08 : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .opacity(isLocked ? 0.95 : 1.0)
        .accessibilityHint(Text(subtitle))
    }
}
