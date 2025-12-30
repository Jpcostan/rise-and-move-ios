import Foundation
import StoreKit
import Combine

@MainActor
final class EntitlementManager: ObservableObject {
    @Published var isPro: Bool = false

    // Update these to match your App Store Connect product IDs
    private let proProductIDs: Set<String> = [
        "rise_move_monthly",
        "rise_move_yearly"
    ]

    func refreshEntitlements() async {
        var pro = false

        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                if proProductIDs.contains(transaction.productID) {
                    pro = true
                }
            case .unverified(_, _):
                continue
            }
        }

        isPro = pro
    }
}
