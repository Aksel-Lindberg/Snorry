import SwiftUI
import StoreKit

// MARK: - Premium subscription paywall (Calm-inspired, Snorry-styled)
struct SubscriptionView: View {

    var paywallSource: String? = nil

    @Environment(AppEnvironment.self) private var appEnv
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var selectedPlan: PremiumPlan = .yearly
    @State private var didLogPaywallView = false

    private var subscription: SubscriptionManager { appEnv.subscription }

    private var isBusy: Bool {
        subscription.purchaseState == .purchasing || subscription.purchaseState == .restoring
    }

    var body: some View {
        ZStack {
            Theme.nightGradient.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    heroCard
                    trialBadge
                    headlineSection
                    planPicker
                    subscribeButton
                    restoreButton
                    legalFooter
                }
                .padding(.horizontal, horizontalSizeClass == .regular ? 32 : 20)
                .padding(.top, 56)
                .padding(.bottom, 32)
                .frame(maxWidth: horizontalSizeClass == .regular ? 480 : .infinity)
                .frame(maxWidth: .infinity)
            }
        }
        .overlay(alignment: .topLeading) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.labelSecondary)
                    .frame(width: 44, height: 44)
            }
            .padding(.leading, 8)
            .padding(.top, 8)
            .accessibilityLabel("Close")
        }
        .onAppear {
            guard !didLogPaywallView else { return }
            didLogPaywallView = true
            AppAnalytics.logPaywallViewed(source: paywallSource)
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
        .preferredColorScheme(.dark)
    }

    // MARK: - Sections

    private var heroCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.35, green: 0.55, blue: 1.0),
                            Color(red: 1.0, green: 0.45, blue: 0.35),
                            Color(red: 0.55, green: 0.35, blue: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 160)
                .rotationEffect(.degrees(-6))
                .shadow(color: Theme.accent.opacity(0.25), radius: 20, y: 8)

            VStack(spacing: 8) {
                Image(systemName: "gift.fill")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.9))

                Text("7 Days Free")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Snorry")
                    .font(Theme.handwritten(size: 22))
                    .foregroundStyle(.white.opacity(0.95))
            }
            .rotationEffect(.degrees(-6))
        }
        .frame(height: 180)
        .padding(.bottom, 4)
    }

    private var trialBadge: some View {
        Text("7-Day Free Trial on Yearly")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Theme.warning, in: Capsule())
    }

    private var headlineSection: some View {
        VStack(spacing: 10) {
            Text(headlineText)
                .font(.title2.bold())
                .foregroundStyle(Theme.labelPrimary)
                .multilineTextAlignment(.center)

            Text(
                "Unlock unlimited recording, full Sleep History, and snore trends in Insights — all processed on your iPhone."
            )
            .font(.subheadline)
            .foregroundStyle(Theme.labelSecondary)
            .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 4)
    }

    private var planPicker: some View {
        VStack(spacing: 0) {
            planRow(plan: .yearly, showTrialBadge: true)
            Divider().background(Theme.labelTertiary.opacity(0.3))
            planRow(plan: .monthly, showTrialBadge: false)
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.radiusCard)
                .stroke(Theme.labelTertiary.opacity(0.2), lineWidth: 1)
        }
    }

    private func planRow(plan: PremiumPlan, showTrialBadge: Bool) -> some View {
        let isSelected = selectedPlan == plan

        return Button {
            selectedPlan = plan
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(plan == .yearly ? "Yearly" : "Monthly")
                        .font(.headline)
                        .foregroundStyle(Theme.labelPrimary)

                    // Calculated monthly equivalent — subordinate to billed amount (App Store 3.1.2)
                    if plan == .yearly {
                        Text(yearlyMonthlyEquivalentText)
                            .font(.caption)
                            .foregroundStyle(Theme.labelSecondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    if showTrialBadge {
                        Text("7-Day Free Trial")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Theme.warning, in: Capsule())
                    }

                    // Billed amount is the most prominent pricing element
                    Text(plan == .yearly ? yearlyBilledPriceText : monthlyBilledPriceText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.labelPrimary)
                }
            }
            .padding(16)
            .background(isSelected ? Theme.surfaceSecondary : Color.clear)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Theme.labelPrimary.opacity(0.65), lineWidth: 2)
                        .padding(6)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var subscribeButton: some View {
        Group {
            if subscription.hasPremiumAccess {
                Link(destination: LegalLinks.manageSubscriptions) {
                    Text("Manage Subscription")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(PremiumPrimaryButtonStyle())
            } else {
                Button {
                    Task { await subscription.purchase(plan: selectedPlan) }
                } label: {
                    HStack(spacing: 8) {
                        if subscription.purchaseState == .purchasing {
                            ProgressView().tint(.black)
                        }
                        Text(ctaTitle)
                            .font(.headline.weight(.bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
                .buttonStyle(PremiumPrimaryButtonStyle(isWhite: true))
                .disabled(isBusy || subscription.product(for: selectedPlan) == nil)
            }
        }
        .padding(.top, 4)
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
        }
        .foregroundStyle(Theme.accent)
        .disabled(isBusy)
    }

    private var legalFooter: some View {
        VStack(spacing: 10) {
            Text(finePrint)
                .font(.caption2)
                .foregroundStyle(Theme.labelSecondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Link("Terms of Use (EULA)", destination: LegalLinks.termsOfUse)
                Link("Privacy Policy", destination: LegalLinks.privacyPolicy)
            }
            .font(.caption)
            .foregroundStyle(Theme.accent)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    // MARK: - Copy helpers

    private var headlineText: String {
        if subscription.hasPremiumAccess {
            return "You have Snorry Premium"
        }
        switch selectedPlan {
        case .yearly:
            return "Get Snorry Premium for $0 if you start your trial today"
        case .monthly:
            return "Get unlimited recording, full Sleep History, and Insights"
        }
    }

    private var ctaTitle: String {
        switch selectedPlan {
        case .yearly:
            if subscription.product(for: .yearly)?.subscription?.introductoryOffer?.paymentMode == .freeTrial {
                return "Try For $0"
            }
            return "Start Free Trial"
        case .monthly:
            return "Subscribe"
        }
    }

    private var yearlyBilledPriceText: String {
        if let product = subscription.yearlyProduct {
            return "\(product.displayPrice)/year"
        }
        return "$29.99/year"
    }

    private var yearlyMonthlyEquivalentText: String {
        if let product = subscription.yearlyProduct {
            let monthly = product.price / 12
            let formatted = monthly.formatted(product.priceFormatStyle)
            return "(≈ \(formatted)/month)"
        }
        return "(≈ $2.50/month)"
    }

    private var monthlyBilledPriceText: String {
        if let product = subscription.monthlyProduct {
            return "\(product.displayPrice)/month"
        }
        return "$4.99/month"
    }

    private var finePrint: String {
        if subscription.hasPremiumAccess {
            return "Manage or cancel in Apple ID Subscriptions. Payment is handled by Apple."
        }
        switch selectedPlan {
        case .yearly:
            return "7 days free, then \(yearlyBilledPriceText). Cancel anytime."
        case .monthly:
            return "\(monthlyBilledPriceText.replacingOccurrences(of: "/month", with: " per month")). Cancel anytime."
        }
    }
}

// MARK: - Button styles

private struct PremiumPrimaryButtonStyle: ButtonStyle {
    var isWhite: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isWhite ? .black : .white)
            .background(
                isWhite ? AnyShapeStyle(Color.white) : AnyShapeStyle(Theme.accentGradient),
                in: RoundedRectangle(cornerRadius: Theme.radiusButton)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
