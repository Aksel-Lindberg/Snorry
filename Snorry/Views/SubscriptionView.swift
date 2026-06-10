import SwiftUI
import StoreKit

// MARK: - Subscription paywall for Snorry Basic
struct SubscriptionView: View {

    @Environment(AppEnvironment.self) private var appEnv
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var didLogPaywallView = false

    private var subscription: SubscriptionManager { appEnv.subscription }

    private var isBusy: Bool {
        subscription.purchaseState == .purchasing || subscription.purchaseState == .restoring
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.nightGradient.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header
                        planComparison
                        pricingCard
                        subscribeButton
                        restoreButton
                        legalFooter
                    }
                    .padding(.horizontal, horizontalSizeClass == .regular ? 32 : 20)
                    .padding(.vertical, 24)
                    .frame(maxWidth: horizontalSizeClass == .regular ? 560 : .infinity)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Subscription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.labelSecondary)
                }
            }
            .onAppear {
                guard !didLogPaywallView else { return }
                didLogPaywallView = true
                AppAnalytics.logPaywallViewed()
                Task { await subscription.refreshEntitlements() }
            }
            .alert(
                "Subscription",
                isPresented: Binding(
                    get: { subscription.errorMessage != nil },
                    set: { if !$0 { subscription.clearError() } }
                )
            ) {
                Button("OK", role: .cancel) { subscription.clearError() }
            } message: {
                Text(subscription.errorMessage ?? "")
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Snorry Basic")
                .font(.title.bold())
                .foregroundStyle(Theme.labelPrimary)
            Text("Unlock your full sleep history and trend analytics.")
                .font(.subheadline)
                .foregroundStyle(Theme.labelSecondary)
        }
    }

    private var planComparison: some View {
        VStack(spacing: 12) {
            PlanCard(
                title: "Free",
                subtitle: "Included",
                features: [
                    PlanFeature("Monitor snoring", included: true),
                    PlanFeature("Latest sleep session in History", included: true),
                    PlanFeature("Full Sleep History", included: false),
                    PlanFeature("Analytics trends", included: false)
                ],
                isHighlighted: false
            )

            PlanCard(
                title: "Basic",
                subtitle: subscription.hasBasicAccess ? "Active" : "Recommended",
                features: [
                    PlanFeature("Monitor snoring", included: true),
                    PlanFeature("Full Sleep History", included: true),
                    PlanFeature("Analytics trends", included: true),
                    PlanFeature("All alarm & alert settings", included: true)
                ],
                isHighlighted: true
            )
        }
    }

    private var pricingCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if subscription.hasBasicAccess {
                Label("You have full access with Basic.", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.good)
            } else {
                Text(priceLine)
                    .font(.headline)
                    .foregroundStyle(Theme.labelPrimary)
                Text(trialLine)
                    .font(.caption)
                    .foregroundStyle(Theme.labelSecondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
    }

    private var subscribeButton: some View {
        Group {
            if subscription.hasBasicAccess {
                Link(destination: LegalLinks.manageSubscriptions) {
                    Text("Manage Subscription")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(SubscriptionPrimaryButtonStyle())
            } else {
                Button {
                    Task { await subscription.purchaseBasic() }
                } label: {
                    HStack(spacing: 8) {
                        if subscription.purchaseState == .purchasing {
                            ProgressView().tint(.white)
                        }
                        Text(subscribeButtonTitle)
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(SubscriptionPrimaryButtonStyle())
                .disabled(isBusy || subscription.basicProduct == nil)
            }
        }
    }

    private var restoreButton: some View {
        Button {
            Task { await subscription.restorePurchases() }
        } label: {
            HStack(spacing: 8) {
                if subscription.purchaseState == .restoring {
                    ProgressView().tint(Theme.accent)
                }
                Text("Restore Purchases")
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(Theme.accent)
        .disabled(isBusy)
    }

    private var legalFooter: some View {
        VStack(spacing: 8) {
            Text(
                "Payment is charged to your Apple ID. Subscription renews monthly unless cancelled at least 24 hours before the period ends. Manage or cancel in Apple ID Subscriptions."
            )
            .font(.caption2)
            .foregroundStyle(Theme.labelTertiary)
            .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Link("Terms of Use", destination: LegalLinks.termsOfUse)
                Link("Privacy Policy", destination: LegalLinks.privacyPolicy)
            }
            .font(.caption)
            .foregroundStyle(Theme.accent)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    // MARK: - Copy helpers

    private var priceLine: String {
        if let product = subscription.basicProduct {
            return "\(product.displayPrice) per month"
        }
        return "$4.99 per month"
    }

    private var trialLine: String {
        if let offer = subscription.basicProduct?.subscription?.introductoryOffer,
           offer.paymentMode == .freeTrial {
            let unit = offer.period.unit
            let value = offer.period.value
            let unitName: String
            switch unit {
            case .day: unitName = value == 1 ? "day" : "days"
            case .week: unitName = value == 1 ? "week" : "weeks"
            case .month: unitName = value == 1 ? "month" : "months"
            case .year: unitName = value == 1 ? "year" : "years"
            @unknown default: unitName = "period"
            }
            return "\(value)-\(unitName) free trial, then billed monthly. Cancel anytime."
        }
        return "7-day free trial, then billed monthly. Cancel anytime."
    }

    private var subscribeButtonTitle: String {
        if subscription.basicProduct?.subscription?.introductoryOffer?.paymentMode == .freeTrial {
            return "Start Free Trial"
        }
        return "Subscribe to Basic"
    }
}

// MARK: - Plan comparison card

private struct PlanFeature {
    let title: String
    let included: Bool

    init(_ title: String, included: Bool) {
        self.title = title
        self.included = included
    }
}

private struct PlanCard: View {
    let title: String
    let subtitle: String
    let features: [PlanFeature]
    let isHighlighted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Theme.labelPrimary)
                Spacer()
                Text(subtitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isHighlighted ? Theme.accent : Theme.labelSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        (isHighlighted ? Theme.accent : Theme.labelSecondary).opacity(0.15),
                        in: Capsule()
                    )
            }

            ForEach(features.indices, id: \.self) { index in
                let feature = features[index]
                HStack(spacing: 10) {
                    Image(systemName: feature.included ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundStyle(feature.included ? Theme.good : Theme.labelTertiary)
                    Text(feature.title)
                        .font(.subheadline)
                        .foregroundStyle(feature.included ? Theme.labelPrimary : Theme.labelTertiary)
                }
            }
        }
        .padding(16)
        .background(
            isHighlighted ? Theme.surface : Theme.surface.opacity(0.7),
            in: RoundedRectangle(cornerRadius: Theme.radiusCard)
        )
        .overlay {
            if isHighlighted {
                RoundedRectangle(cornerRadius: Theme.radiusCard)
                    .stroke(Theme.accent.opacity(0.45), lineWidth: 1)
            }
        }
    }
}

private struct SubscriptionPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(Theme.accentGradient, in: RoundedRectangle(cornerRadius: Theme.radiusButton))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
