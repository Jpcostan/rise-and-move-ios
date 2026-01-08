import SwiftUI
import UserNotifications

struct OnboardingFlowView: View {
    let onFinish: () -> Void
    let onTryTestAlarm: () -> Void

    @State private var step: Int = 0
    @State private var notificationsStatusText: String = "Not set"
    @State private var didRequestNotifications: Bool = false

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
                    pageNotificationTap.tag(3) // ✅ NEW
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
            refreshNotificationStatus()
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

            statusRow(
                title: "Status",
                value: notificationsStatusText
            )

            Button {
                Task { await requestNotifications() }
            } label: {
                Text(didRequestNotifications ? "Check Again" : "Enable Notifications")
                    .font(.system(.callout, design: .rounded))
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.white.opacity(0.18))
            .foregroundStyle(.white)
            .accessibilityHint("Requests notification permission.")
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
                onTryTestAlarm()
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

    // ✅ NEW: Explain that user must tap notification to open the alarm screen
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
                    if step < 3 {
                        withAnimation(.easeOut(duration: 0.18)) {
                            step += 1
                        }
                    } else {
                        onFinish()
                    }
                } label: {
                    Text(step < 3 ? "Continue" : "Get Started")
                        .font(.system(.callout, design: .rounded))
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white.opacity(0.18))
                .foregroundStyle(.white)
                .accessibilityHint(step < 3 ? "Go to the next step." : "Finish onboarding and enter the app.")
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

    // MARK: - Notifications

    private func refreshNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let text: String
            switch settings.authorizationStatus {
            case .notDetermined:
                text = "Not requested"
            case .denied:
                text = "Denied"
            case .authorized, .provisional, .ephemeral:
                text = "Enabled"
            @unknown default:
                text = "Unknown"
            }

            DispatchQueue.main.async {
                notificationsStatusText = text
            }
        }
    }

    @MainActor
    private func requestNotifications() async {
        didRequestNotifications = true
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            notificationsStatusText = granted ? "Enabled" : "Denied"
        } catch {
            notificationsStatusText = "Error"
        }

        refreshNotificationStatus()
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
