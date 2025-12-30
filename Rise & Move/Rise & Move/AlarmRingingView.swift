import SwiftUI
import AVFoundation

struct AlarmRingingView: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var entitlements: EntitlementManager

    let alarm: Alarm
    let onStop: () -> Void

    @State private var player: AVAudioPlayer?
    @State private var showingMovementTask = false
    @State private var showingPaywall = false

    // DEBUG-only bypass to test Pro flows without Sandbox / App Store Connect.
    // Set to false when you’re ready to test real entitlements.
    #if DEBUG
    private let DEBUG_FORCE_PRO = true
    #endif

    // Helper so we don’t duplicate logic everywhere
    private var hasProAccess: Bool {
        #if DEBUG
        return DEBUG_FORCE_PRO || router.isPro
        #else
        return router.isPro
        #endif
    }

    var body: some View {
        ZStack {
            // Dawn background (subtle, calm, premium)
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.10, blue: 0.16), // deep blue
                    Color(red: 0.12, green: 0.13, blue: 0.22), // night indigo
                    Color(red: 0.24, green: 0.18, blue: 0.20), // muted plum
                    Color(red: 0.38, green: 0.27, blue: 0.22)  // warm dawn
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Content card feel (Apple-esque material)
            VStack(spacing: 18) {
                VStack(spacing: 6) {
                    Text("Rise & Move")
                        .font(.system(.title, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)

                    Text(alarm.label)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.75))
                }
                .padding(.top, 6)

                Text(alarm.time, style: .time)
                    .font(.system(size: 64, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.top, 6)

                Spacer(minLength: 20)

                VStack(spacing: 12) {
                    // FREE DISMISSAL (baseline)
                    Button {
                        stopAndClose()
                    } label: {
                        Text("Free Stop")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.bordered)
                    .tint(.white.opacity(0.30))
                    .foregroundStyle(.white)

                    // PRO DISMISSAL (paywalled)
                    Button {
                        if hasProAccess {
                            showingMovementTask = true
                        } else {
                            showingPaywall = true
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: hasProAccess ? "checkmark.seal.fill" : "lock.fill")
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(hasProAccess ? Color.blue : Color.white.opacity(0.9))

                            Text(hasProAccess ? "Rise & Move Stop" : "Rise & Move Stop (Pro)")
                                .foregroundStyle(.white)

                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white.opacity(0.28))

                    Text("Pro requires a wake-up action to stop the alarm.")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .padding(.top, 2)

                    #if DEBUG
                    if DEBUG_FORCE_PRO && !router.isPro {
                        Text("DEBUG: Pro is forced ON")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.75))
                            .padding(.top, 2)
                    }
                    #endif
                }
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
        .onAppear { startSound() }
        .onDisappear { stopSound() }

        // Movement task (Pro only)
        .sheet(isPresented: $showingMovementTask) {
            // Alarm keeps playing underneath because this is a sheet.
            MovementTaskView(secondsRequired: 20) {
                stopAndClose()
            }
        }

        // Paywall (when not Pro)
        .sheet(isPresented: $showingPaywall) {
            PaywallView {
                Task { await entitlements.refreshEntitlements() }
                router.isPro = entitlements.isPro
            }
        }
    }

    private func stopAndClose() {
        stopSound()
        onStop()
        router.clearActiveAlarm()
    }

    private func startSound() {
        guard let url = Bundle.main.url(forResource: "alarm", withExtension: "mp3")
                ?? Bundle.main.url(forResource: "alarm", withExtension: "m4a")
                ?? Bundle.main.url(forResource: "alarm", withExtension: "wav")
        else {
            print("Alarm sound file not found in bundle.")
            return
        }

        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.numberOfLoops = -1
            p.prepareToPlay()
            p.play()
            player = p
        } catch {
            print("Failed to start alarm sound:", error)
        }
    }

    private func stopSound() {
        player?.stop()
        player = nil
    }
}
