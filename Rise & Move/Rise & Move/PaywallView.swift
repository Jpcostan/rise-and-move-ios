//
//  PaywallView.swift
//  Rise & Move
//

import SwiftUI
import StoreKit
import OSLog

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var entitlements: EntitlementManager

    @State private var products: [Product] = []
    @State private var isLoading = true
    @State private var isRestoring = false
    @State private var loadErrorMessage: String?
    @State private var actionMessage: String?
    @State private var purchasingProductID: String?

    /// ✅ Called when Pro successfully unlocks.
    let onPurchased: () -> Void

    /// ✅ Called when the user closes the paywall (clears router paywall context).
    /// This is critical now that the paywall is presented from a single global sheet in ContentView.
    let onClose: () -> Void

    // ✅ MUST match App Store Connect product IDs exactly
    private let proMonthlyID = "com.jpcostan.riseandmove.pro.monthly"
    private let proYearlyID  = "com.jpcostan.riseandmove.pro.yearly"

    private var productIDs: [String] { [proMonthlyID, proYearlyID] }

    var body: some View {
        NavigationStack {
            ZStack {
                dawnBackground

                VStack(spacing: 16) {
                    header

                    if isLoading {
                        loadingState
                    } else if let loadErrorMessage {
                        errorState(loadErrorMessage)
                    } else {
                        plans
                    }

                    Spacer(minLength: 0)

                    footer
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 14)
            }
            .preferredColorScheme(.dark)
            .navigationTitle("Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { close() }
                        .foregroundStyle(.white)
                }
            }
            .task { await loadProducts() }
        }
    }

    // MARK: - Close handling

    @MainActor
    private func close() {
        // ✅ Clear router-driven presentation state first
        onClose()
        // ✅ Then dismiss the sheet (safe even if already dismissed)
        dismiss()
    }

    // MARK: - UI

    private var header: some View {
        VStack(spacing: 10) {
            Text("Make waking up intentional")
                .font(.system(.title2, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text("Rise & Move Pro adds a simple action before your alarm can be dismissed — so you’re awake, not on autopilot.")
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(.white.opacity(0.78))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 6)
        }
        .padding(.top, 6)
    }

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(.white)
                .scaleEffect(1.1)

            Text("Loading plans…")
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text("Couldn’t load subscriptions")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(.white)

            Text(message)
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(.white.opacity(0.78))
                .multilineTextAlignment(.center)

            Button {
                Task { await loadProducts() }
            } label: {
                Text("Try again")
                    .font(.system(.headline, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.white.opacity(0.22))
        }
        .padding(18)
        .background(cardBackground)
        .padding(.top, 16)
    }

    private var plans: some View {
        VStack(spacing: 12) {
            Text("Cancel anytime. Restore available. No ads.")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(.white.opacity(0.70))
                .multilineTextAlignment(.center)
                .padding(.top, 8)

            VStack(spacing: 10) {
                ForEach(productsSortedForDisplay, id: \.id) { product in
                    let isYearly = (product.id == proYearlyID)

                    Button {
                        Task { await purchase(product) }
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    Text(planTitle(for: product))
                                        .font(.system(.headline, design: .rounded))
                                        .foregroundStyle(.white)

                                    if isYearly {
                                        Text("Best value")
                                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(.white.opacity(0.16), in: Capsule())
                                            .foregroundStyle(.white.opacity(0.90))
                                    }
                                }

                                Text(planSubtitle(for: product))
                                    .font(.system(.subheadline, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.75))
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 6) {
                                Text(product.displayPrice)
                                    .font(.system(.headline, design: .rounded))
                                    .foregroundStyle(.white)

                                if purchasingProductID == product.id {
                                    ProgressView()
                                        .tint(.white.opacity(0.9))
                                        .scaleEffect(0.9)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .padding(.horizontal, 14)
                    }
                    .buttonStyle(.plain)
                    .background(planBackground(isYearly: isYearly))
                    .overlay(planBorder(isYearly: isYearly))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .disabled(purchasingProductID != nil || isRestoring)
                }
            }
            .padding(.top, 6)

            if let actionMessage {
                Text(actionMessage)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.white.opacity(0.12), in: Capsule())
                    .padding(.top, 4)
            }

            Button {
                Task { await restore() }
            } label: {
                HStack(spacing: 10) {
                    Text("Restore Purchases")
                        .font(.system(.headline, design: .rounded))
                    if isRestoring {
                        ProgressView()
                            .tint(.white.opacity(0.9))
                            .scaleEffect(0.9)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.bordered)
            .tint(.white.opacity(0.18))
            .foregroundStyle(.white)
            .padding(.top, 6)
            .disabled(purchasingProductID != nil || isRestoring)
        }
        .padding(18)
        .background(cardBackground)
        .padding(.top, 14)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Text("You can use Rise & Move once for free. After that, Pro unlocks it anytime.")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(.white.opacity(0.70))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 6)
        }
        .padding(.bottom, 6)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(.white.opacity(0.10), lineWidth: 1)
            )
    }

    private func planBackground(isYearly: Bool) -> some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(.white.opacity(isYearly ? 0.18 : 0.14))
    }

    private func planBorder(isYearly: Bool) -> some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(.white.opacity(isYearly ? 0.20 : 0.12), lineWidth: 1)
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

    // MARK: - Sorting & Copy

    private var productsSortedForDisplay: [Product] {
        let yearly = products.filter { $0.id == proYearlyID }
        let monthly = products.filter { $0.id == proMonthlyID }
        let others = products.filter { ![proYearlyID, proMonthlyID].contains($0.id) }
        return yearly + monthly + others
    }

    private func planTitle(for product: Product) -> String {
        if product.id == proYearlyID { return "Yearly" }
        if product.id == proMonthlyID { return "Monthly" }
        return product.displayName
    }

    private func planSubtitle(for product: Product) -> String {
        if product.id == proYearlyID { return "One payment, full year of Pro" }
        if product.id == proMonthlyID { return "Flexible month to month" }
        return product.description
    }

    // MARK: - StoreKit

    private func loadProducts() async {
        isLoading = true
        loadErrorMessage = nil
        actionMessage = nil

        do {
            let ids = productIDs
            products = try await Product.products(for: ids)

            if products.isEmpty {
                StoreKitSupport.logger.error("No products returned for ids: \(ids, privacy: .public)")
                loadErrorMessage = "Subscriptions are unavailable right now. Please try again later."
            } else {
                let returnedIDs = Set(products.map(\.id))
                let missing = ids.filter { !returnedIDs.contains($0) }
                if !missing.isEmpty {
                    StoreKitSupport.logger.error("Missing products for ids: \(missing, privacy: .public)")
                }
            }
        } catch {
            StoreKitSupport.logger.error("Failed to load products: \(error.localizedDescription, privacy: .public)")
            loadErrorMessage = StoreKitSupport.userMessage(for: error, context: .loadProducts)
        }

        isLoading = false
    }

    private func purchase(_ product: Product) async {
        actionMessage = nil
        purchasingProductID = product.id
        defer { purchasingProductID = nil }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    await entitlements.refreshEntitlements()
                    if entitlements.isPro {
                        onPurchased()
                        close()
                    } else {
                        actionMessage = "Purchase completed, but Pro hasn’t unlocked yet. Please try Restore Purchases."
                    }
                case .unverified(_, let verificationError):
                    StoreKitSupport.logger.error("Unverified purchase: \(verificationError.localizedDescription, privacy: .public)")
                    actionMessage = "Purchase could not be verified."
                }
            case .userCancelled:
                break
            case .pending:
                actionMessage = "Purchase pending approval."
            @unknown default:
                break
            }
        } catch {
            StoreKitSupport.logger.error("Purchase failed: \(error.localizedDescription, privacy: .public)")
            actionMessage = StoreKitSupport.userMessage(for: error, context: .purchase)
        }
    }

    private func restore() async {
        actionMessage = nil
        do {
            isRestoring = true
            defer { isRestoring = false }
            try await AppStore.sync()
            await entitlements.refreshEntitlements()
            if entitlements.isPro {
                onPurchased()
                close()
            } else {
                actionMessage = "No active subscription found to restore."
            }
        } catch {
            StoreKitSupport.logger.error("Restore failed: \(error.localizedDescription, privacy: .public)")
            actionMessage = StoreKitSupport.userMessage(for: error, context: .restore)
        }
    }
}

enum StoreKitSupport {
    static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "RiseAndMove", category: "StoreKit")

    enum Context {
        case loadProducts
        case purchase
        case restore
    }

    static func userMessage(for error: Error, context: Context) -> String? {
        if isCancellation(error) { return nil }

        let nsError = error as NSError

        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
                return "You appear to be offline. Please check your connection and try again."
            case NSURLErrorTimedOut:
                return "The request timed out. Please try again."
            default:
                break
            }
        }

        if nsError.domain == SKErrorDomain, let code = SKError.Code(rawValue: nsError.code) {
            switch code {
            case .paymentCancelled:
                return nil
            case .paymentNotAllowed:
                return "In-app purchases aren’t allowed on this device."
            case .storeProductNotAvailable:
                return "This subscription isn’t available in your region."
            case .cloudServiceNetworkConnectionFailed:
                return "Couldn’t connect to the App Store. Please try again."
            case .clientInvalid:
                return "Your App Store account isn’t valid for purchases."
            default:
                break
            }
        }

        switch context {
        case .loadProducts:
            return "Couldn’t load subscriptions. Please try again."
        case .purchase:
            return "Purchase failed. Please try again."
        case .restore:
            return "Restore failed. Please try again."
        }
    }

    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }

        let nsError = error as NSError
        if nsError.domain == SKErrorDomain, nsError.code == SKError.paymentCancelled.rawValue {
            return true
        }
        return false
    }
}
