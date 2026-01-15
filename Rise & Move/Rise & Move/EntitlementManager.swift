import Foundation
import StoreKit
import Combine

@MainActor
final class EntitlementManager: ObservableObject {
    @Published var isPro: Bool = false

    // ✅ Single source of truth for product IDs (must match App Store Connect exactly)
    private let proProductIDs: Set<String> = [
        "com.jpcostan.riseandmove.pro.monthly",
        "com.jpcostan.riseandmove.pro.yearly"
    ]

    func refreshEntitlements() async {
        var pro = false

        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                // Only treat our subscription products as "Pro"
                guard proProductIDs.contains(transaction.productID) else { continue }

                // Ignore revoked or expired subscriptions
                if transaction.revocationDate != nil { continue }
                if let expirationDate = transaction.expirationDate, expirationDate < Date() { continue }

                pro = true

            case .unverified:
                continue
            }
        }

        isPro = pro
    }
}
