//
//  PaywallView.swift
//  Rise & Move
//
//  Created by Joshua Costanza on 12/29/25.
//
import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var products: [Product] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    let onPurchased: () -> Void

    private let productIDs = ["rise_move_monthly", "rise_move_yearly"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Unlock Rise & Move Pro")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Stop morning autopilot with a wake-up action.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if isLoading {
                    ProgressView()
                        .padding(.top, 10)
                } else if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                } else {
                    VStack(spacing: 10) {
                        ForEach(products, id: \.id) { product in
                            Button {
                                Task { await purchase(product) }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(product.displayName)
                                            .font(.headline)
                                        Text(product.description)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(product.displayPrice)
                                        .font(.headline)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        Button("Restore Purchases") {
                            Task { await restore() }
                        }
                        .padding(.top, 4)
                    }
                    .padding(.top, 8)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Pro")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await loadProducts() }
        }
    }

    private func loadProducts() async {
        isLoading = true
        errorMessage = nil
        do {
            products = try await Product.products(for: productIDs)
                .sorted(by: { $0.displayPrice < $1.displayPrice }) // simple ordering
        } catch {
            errorMessage = "Couldn’t load subscription options."
        }
        isLoading = false
    }

    private func purchase(_ product: Product) async {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(_) = verification {
                    onPurchased()
                    dismiss()
                } else {
                    errorMessage = "Purchase could not be verified."
                }
            case .userCancelled:
                break
            case .pending:
                errorMessage = "Purchase pending approval."
            @unknown default:
                break
            }
        } catch {
            errorMessage = "Purchase failed."
        }
    }

    private func restore() async {
        do {
            try await AppStore.sync()
            onPurchased()
            dismiss()
        } catch {
            errorMessage = "Restore failed."
        }
    }
}

