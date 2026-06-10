# Snorry Subscription Setup (App Store Connect)

This guide configures the **Free** and **Basic** plans for Snorry. The app uses StoreKit 2 with product ID `app.Snorry.Snorry.basic.monthly`.

## Plan summary

| Plan | Price | Features |
|------|-------|----------|
| **Free** | Included | Monitor, latest Sleep History session only |
| **Basic** | $4.99/month | Full Sleep History, Analytics, all settings |
| **Trial** | 7 days free | Applies when subscribing to Basic for the first time |

---

## Prerequisites

1. **Paid Apple Developer Program** membership
2. App record for Snorry with bundle ID `app.Snorry.Snorry`
3. At least one build uploaded to App Store Connect (recommended before creating subscriptions)
4. **Agreements, Tax, and Banking** completed:
   - App Store Connect → **Business** → **Agreements, Tax, and Banking**
   - **Paid Applications** agreement must be **Active**

---

## Step 1 — Enable In-App Purchase in Xcode

1. Open `Snorry.xcodeproj` in Xcode
2. Select the **Snorry** target → **Signing & Capabilities**
3. Click **+ Capability** → add **In-App Purchase**
4. Ensure your Team (`L675KNV756`) is selected and signing succeeds

---

## Step 2 — Create subscription group

1. [App Store Connect](https://appstoreconnect.apple.com) → **Apps** → **Snorry**
2. Sidebar → **Subscriptions**
3. Click **+** (Create Subscription Group)
4. Fill in:
   - **Reference name:** `Snorry Basic`
   - **Group name** (customer-facing): `Snorry Basic`
5. Save

---

## Step 3 — Create Basic monthly subscription

Inside the **Snorry Basic** group:

1. Click **+** → **Create Subscription**
2. Configure:

| Field | Value |
|-------|-------|
| Reference name | `Basic Monthly` |
| Product ID | `app.Snorry.Snorry.basic.monthly` |
| Subscription duration | 1 month |

3. **Subscription prices**
   - Base territory: **United States**
   - Price: **$4.99**
   - Use **Apply to all territories** or adjust per country

4. **Localization** (English U.S. minimum):
   - **Display name:** `Basic`
   - **Description:** `Full access to Sleep History and Analytics.`

5. Save the subscription

> **Important:** The Product ID must match [`SubscriptionProductID.swift`](Snorry/Models/SubscriptionProductID.swift) exactly.

---

## Step 4 — Add 1-week free trial

1. Open the **Basic Monthly** subscription
2. Go to **Introductory Offers** → **+**
3. Configure:
   - **Type:** Free
   - **Duration:** 1 week
   - **Territories:** All (or your target storefronts)
4. Save

Apple shows trial terms automatically on the purchase sheet.

---

## Step 5 — Subscription review information

On the subscription group page, provide:

| Field | Value |
|-------|-------|
| Subscription Privacy Policy URL | `https://snorry.lintech.no` |
| Terms of Use | Apple Standard EULA (or your custom URL) |

Before App Store submission, update your privacy policy to mention:
- Auto-renewable subscriptions are billed through Apple
- Payment and subscription management are handled by Apple (not stored by Snorry)
- Free vs Basic feature differences

---

## Step 6 — Attach subscription to app version

1. App Store Connect → Snorry → your app version (e.g. 1.1)
2. Scroll to **In-App Purchases and Subscriptions**
3. Click **+** and select **Basic Monthly**
4. Ensure subscription status is **Ready to Submit** before submitting the version

---

## Step 7 — Local testing (Xcode StoreKit)

1. The repo includes [`Snorry/Configuration/Snorry.storekit`](Snorry/Configuration/Snorry.storekit)
2. In Xcode: **Product → Scheme → Edit Scheme → Run → Options**
3. Set **StoreKit Configuration** to `Snorry.storekit`
4. Run on Simulator or device — purchases use the local config (no sandbox account needed)
5. Use **Debug → StoreKit → Manage Transactions** to simulate renewals, expiry, and refunds

---

## Step 8 — Sandbox testing (App Store Connect)

1. App Store Connect → **Users and Access** → **Sandbox** → **Testers**
2. Create a Sandbox Apple ID
3. On test device: **Settings → App Store → Sandbox Account** → sign in
4. Remove the StoreKit configuration from the Xcode scheme (set to **None**) to hit real sandbox APIs
5. Verify:
   - Free user: older History rows are locked; Analytics shows upgrade screen
   - Subscribe: 1-week trial starts; full access unlocks immediately
   - **Restore Purchases** in Settings works on a second device
   - Cancel subscription: access ends after the current period (check via StoreKit Transaction Manager or sandbox expiry)

---

## Step 9 — App Review checklist

- [ ] Product ID `app.Snorry.Snorry.basic.monthly` matches code
- [ ] Subscription group + product status: **Ready to Submit**
- [ ] Privacy policy mentions subscriptions and Apple billing
- [ ] App includes **Restore Purchases** (Settings → Subscription)
- [ ] App includes **Manage Subscription** link for Basic users
- [ ] App description explains Free vs Basic tiers
- [ ] Screenshots show paywall if requested by review

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Product not loading in app | Confirm Product ID, Paid Apps agreement active, wait ~15 min after creating product |
| "Subscription not available" | Check network; verify IAP capability enabled; test with `.storekit` file first |
| Restore finds nothing | Ensure same Sandbox Apple ID; subscription not expired |
| Trial not shown | Confirm introductory offer is saved and user is eligible (new subscriber) |

---

## Code reference

| File | Role |
|------|------|
| `SubscriptionProductID.swift` | Product ID constant |
| `SubscriptionManager.swift` | StoreKit 2 purchase, restore, entitlements |
| `SubscriptionView.swift` | Paywall UI |
| `SessionsListView.swift` | History gating (latest session only on Free) |
| `AnalyticsView.swift` | Analytics gating |
| `SettingsView.swift` | Plan status, upgrade, restore, manage |
