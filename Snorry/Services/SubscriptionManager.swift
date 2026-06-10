import Foundation
import StoreKit

// MARK: - StoreKit 2 subscription state for Snorry Basic

enum SubscriptionPurchaseState: Equatable {
    case idle
    case loading
    case purchasing
    case restoring
}

@Observable
@MainActor
final class SubscriptionManager {

    private(set) var hasBasicAccess = false
    private(set) var basicProduct: Product?
    private(set) var purchaseState: SubscriptionPurchaseState = .idle
    private(set) var errorMessage: String?

    private var updateListenerTask: Task<Void, Never>?

    init() {
        updateListenerTask = listenForTransactions()
        Task { await refreshEntitlements() }
    }

    // MARK: - Public API

    func refreshEntitlements() async {
        if purchaseState == .idle {
            purchaseState = .loading
        }

        await loadProducts()
        await updateAccessFromEntitlements()

        if purchaseState == .loading {
            purchaseState = .idle
        }
    }

    @discardableResult
    func purchaseBasic() async -> Bool {
        guard let product = basicProduct else {
            errorMessage = "Subscription is not available right now. Please try again later."
            return false
        }

        purchaseState = .purchasing
        errorMessage = nil
        AppAnalytics.logPurchaseStarted()

        defer {
            if purchaseState == .purchasing {
                purchaseState = .idle
            }
        }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await updateAccessFromEntitlements()
                if hasBasicAccess {
                    AppAnalytics.logPurchaseCompleted()
                }
                return hasBasicAccess
            case .userCancelled:
                return false
            case .pending:
                errorMessage = "Your purchase is pending approval."
                return false
            @unknown default:
                return false
            }
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func restorePurchases() async {
        purchaseState = .restoring
        errorMessage = nil
        AppAnalytics.logRestoreTapped()

        defer {
            if purchaseState == .restoring {
                purchaseState = .idle
            }
        }

        do {
            try await AppStore.sync()
            await updateAccessFromEntitlements()
            if !hasBasicAccess {
                errorMessage = "No active Basic subscription was found for this Apple ID."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearError() {
        errorMessage = nil
    }

    // MARK: - Entitlements

    private func updateAccessFromEntitlements() async {
        var hasAccess = false

        for await result in Transaction.currentEntitlements {
            guard let transaction = unwrapVerified(result),
                  transaction.productID == SubscriptionProductID.basicMonthly,
                  transaction.revocationDate == nil else { continue }
            hasAccess = true
        }

        hasBasicAccess = hasAccess
    }

    private func loadProducts() async {
        do {
            let products = try await Product.products(for: SubscriptionProductID.all)
            basicProduct = products.first { $0.id == SubscriptionProductID.basicMonthly }
        } catch {
            basicProduct = nil
        }
    }

    // MARK: - Transaction listener

    private func listenForTransactions() -> Task<Void, Never> {
        Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                guard let transaction = self.unwrapVerified(result) else { continue }
                await transaction.finish()
                await self.updateAccessFromEntitlements()
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let safe):
            return safe
        }
    }

    private func unwrapVerified(_ result: VerificationResult<Transaction>) -> Transaction? {
        switch result {
        case .unverified:
            return nil
        case .verified(let transaction):
            return transaction
        }
    }
}
