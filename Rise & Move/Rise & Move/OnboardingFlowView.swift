import SwiftUI
import UserNotifications
import UIKit

struct OnboardingFlowView: View {
    let initialStep: Int
    let onFinish: () -> Void
    let onTryTestAlarm: (Int) -> Void
    let onUnlockPro: (Int) -> Void

    @State private var step: Int

    // ✅ Use NotificationHealth so onboarding matches Settings behavior
    @StateObject private var notificationHealth = NotificationHealth()

    // ✅ Router access for reading Pro status (presentation is handled by ContentView)
    @EnvironmentObject private var router: AppRouter

    // Keep this for the UI label + status row
    @State private var notificationsStatusText: String = "Not set"

    // Keep (used to choose initial button label)
    @State private var didRequestNotifications: Bool = false

    private static let maxStepIndex: Int = 4

    // ✅ Small "warm-up" to reduce first-time presentation latency feel
    @State private var tapHaptic = UIImpactFeedbackGenerator(style: .light)

    init(
        initialStep: Int = 0,
        onFinish: @escaping () -> Void,
        onTryTestAlarm: @escaping (Int) -> Void,
        onUnlockPro: @escaping (Int) -> Void
    ) {
        let clamped = min(max(initialStep, 0), Self.maxStepIndex)

        self.initialStep = clamped
        self.onFinish = onFinish
        self.onTryTestAlarm = onTryTestAlarm
        self.onUnlockPro = onUnlockPro

        _step = State(initialValue: clamped)
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
                Spacer(minLength: 18)

                TabView(selection: $step) {
                    pageWelcome.tag(0)
                    pageNotifications.tag(1)
                    pageTestAlarm.tag(2)
                    pageNotificationTap.tag(3)
                    pagePro.tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .padding(.horizontal, 18)

                Spacer(minLength: 18)

                bottomBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
            }
        }
        .onAppear {
            // ✅ Pre-warm haptics & (indirectly) the interaction pipeline
            tapHaptic.prepare()

            Task { await refreshNotificationStatus() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task { await refreshNotificationStatus() }
        }
        // ✅ If ContentView re-presents onboarding with a different resume step, sync it.
        .onChange(of: initialStep) { _, newValue in
            let clamped = min(max(newValue, 0), Self.maxStepIndex)
            if step != clamped {
                step = clamped
            }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Pages

    private var pageWelcome: some View {
        OnboardingCard(
            icon: "sunrise.fill",
            title: "Rise & Move",
            subtitle: "A calmer way to wake up.",
            bodyText: """
            Rise & Move helps you start the day with a small moment of intention.
            When an alarm rings, you’ll open it and press and hold briefly to stop it.
            """
        )
    }

    private var pageNotifications: some View {
        VStack(spacing: 16) {
            OnboardingCard(
                icon: "bell.badge.fill",
                title: "Notifications",
                subtitle: "So alarms can ring on time.",
                bodyText: "Rise & Move uses notifications to deliver alarms reliably, even when the app isn’t open."
            )

            statusRow(title: "Status", value: notificationsStatusText)

            Button {
                Task { await handleNotificationsCTA() }
            } label: {
                Text(notificationsButtonTitle)
                    .font(.system(.callout, design: .rounded))
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.white.opacity(0.18))
            .foregroundStyle(.white)
            .disabled(notificationHealth.capability == .ok)
            .accessibilityHint(notificationsButtonHint)
        }
        .padding(.top, 6)
    }

    private var pageTestAlarm: some View {
        VStack(spacing: 16) {
            OnboardingCard(
                icon: "hand.raised.fill",
                title: "Try a test alarm",
                subtitle: "Learn the hold interaction.",
                bodyText: "You can run a short test to see what the alarm screen looks like and how stopping it feels."
            )

            Button {
                // ✅ Immediate feedback so the tap never feels "dead"
                tapHaptic.impactOccurred()
                tapHaptic.prepare()

                // ✅ Ensure the callback runs on MainActor immediately
                Task { @MainActor in
                    onTryTestAlarm(step)
                }
            } label: {
                Text("Try Test Alarm")
                    .font(.system(.callout, design: .rounded))
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            .tint(.white.opacity(0.18))
            .foregroundStyle(.white.opacity(0.95))
            .accessibilityHint("Opens the test alarm experience.")

            Text("You can always run a test later from Settings.")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .padding(.top, 2)
        }
        .padding(.top, 6)
    }

    private var pageNotificationTap: some View {
        VStack(spacing: 16) {
            OnboardingCard(
                icon: "hand.tap.fill",
                title: "Tap to start the alarm",
                subtitle: "Alarms open when you tap the notification.",
                bodyText: """
                When an alarm goes off, tap the notification to open the alarm screen.
                This ensures alarms are reliable and gives you full control.
                """
            )

            Text("iOS requires user interaction for alarm experiences.")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .padding(.top, 2)
        }
        .padding(.top, 6)
    }

    private var pagePro: some View {
        VStack(spacing: 16) {
            OnboardingCard(
                icon: "sparkles",
                title: "Unlock Pro",
                subtitle: "Keep using Rise & Move anytime.",
                bodyText: """
                Your first Rise & Move stop is free.
                Pro unlocks unlimited use and supports ongoing (and calm) improvements.
                """
            )

            if router.effectiveIsPro {
                Text("You’re already Pro ✅")
                    .font(.system(.callout, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.top, 2)
            } else {
                Button {
                    // ✅ Delegate presentation + resume behavior to ContentView
                    Task { @MainActor in
                        onUnlockPro(step)
                    }
                } label: {
                    Text("Unlock Pro")
                        .font(.system(.callout, design: .rounded))
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white.opacity(0.18))
                .foregroundStyle(.white)
                .accessibilityHint("Opens the Pro upgrade screen.")
            }

            Text("You can upgrade anytime in Settings.")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .padding(.top, 2)
        }
        .padding(.top, 6)
    }

    // MARK: - Bottom controls

    private var bottomBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        step = max(step - 1, 0)
                    }
                } label: {
                    Text("Back")
                        .font(.system(.callout, design: .rounded))
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .tint(.white.opacity(0.18))
                .foregroundStyle(.white.opacity(0.95))
                .disabled(step == 0)

                Button {
                    if step < Self.maxStepIndex {
                        withAnimation(.easeOut(duration: 0.18)) {
                            step += 1
                        }
                    } else {
                        onFinish()
                    }
                } label: {
                    Text(step < Self.maxStepIndex ? "Continue" : "Get Started")
                        .font(.system(.callout, design: .rounded))
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white.opacity(0.18))
                .foregroundStyle(.white)
                .accessibilityHint(step < Self.maxStepIndex ? "Go to the next step." : "Finish onboarding and enter the app.")
            }

            Text(step == 1 || step == 3 ? "You can change this anytime in Settings." : " ")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
                .frame(maxWidth: .infinity)
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
    }

    // MARK: - Notifications (capability-driven)

    private var notificationsButtonTitle: String {
        switch notificationHealth.capability {
        case .ok:
            return "Enabled"
        case .notDetermined:
            return didRequestNotifications ? "Check Again" : notificationHealth.capability.ctaTitle
        case .denied, .alertsDisabled, .soundsDisabled, .unknown:
            return notificationHealth.capability.ctaTitle
        }
    }

    private var notificationsButtonHint: String {
        switch notificationHealth.capability {
        case .ok:
            return "Notifications are enabled."
        case .notDetermined:
            return "Requests notification permission."
        case .denied, .alertsDisabled, .soundsDisabled, .unknown:
            return "Opens Settings so you can enable notifications and sounds."
        }
    }

    @MainActor
    private func refreshNotificationStatus() async {
        await notificationHealth.refresh()
        notificationsStatusText = statusText(for: notificationHealth.capability)
    }

    private func statusText(for capability: NotificationHealth.AlarmCapability) -> String {
        switch capability {
        case .ok: return "Enabled"
        case .notDetermined: return "Not requested"
        case .denied: return "Denied"
        case .alertsDisabled: return "Alerts Off"
        case .soundsDisabled: return "Sounds Off"
        case .unknown: return "Unknown"
        }
    }

    @MainActor
    private func handleNotificationsCTA() async {
        didRequestNotifications = true

        if notificationHealth.capability == .notDetermined {
            _ = await notificationHealth.requestPermission()
            // Let the system commit changes before we re-read settings
            await Task.yield()
            await refreshNotificationStatus()
            return
        }

        if !notificationHealth.capability.isAlarmCapable {
            notificationHealth.openAppSettings()
            // didBecomeActive will refresh when the user returns, but a yield here helps too.
            await Task.yield()
            await refreshNotificationStatus()
            return
        }

        await refreshNotificationStatus()
    }

    // MARK: - Small UI helpers

    private func statusRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(.callout, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(.white.opacity(0.85))

            Spacer()

            Text(value)
                .font(.system(.callout, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(.white.opacity(0.70))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(.white.opacity(0.10), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(value)")
    }
}

private struct OnboardingCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let bodyText: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white.opacity(0.90))
                .padding(.top, 6)

            Text(title)
                .font(.system(.title2, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(.white)

            Text(subtitle)
                .font(.system(.title3, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(.white.opacity(0.86))
                .multilineTextAlignment(.center)

            Text(bodyText)
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(.white.opacity(0.70))
                .multilineTextAlignment(.center)
                .padding(.top, 2)

            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 360)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(.white.opacity(0.10), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
    }
}
