# Snorry Subscription Setup (App Store Connect)

This guide configures the **Free** and **Premium** plans for Snorry. See also [BRAND_GUIDE_APP.md](BRAND_GUIDE_APP.md) for user-facing copy standards.

The app uses StoreKit 2 with product IDs:

- `app.Snorry.Snorry.premium.yearly` — $29.99/year (7-day free trial)
- `app.Snorry.Snorry.premium.monthly` — $4.99/month (no trial)

## Plan summary

| Plan | Price | Features |
|------|-------|----------|
| **Free** | Included | Unlimited recording, full Sleep History, Habits, Insights for first 7 recorded nights |
| **Premium Yearly** | $29.99/year (~$2.49/mo) | Insights after first 7 recorded nights |
| **Premium Monthly** | $4.99/month | Insights after first 7 recorded nights |
| **Trial** | 7 days free | Applies to **Premium Yearly** only (first-time eligible subscribers) |

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
   - **Reference name:** `Snorry Premium`
   - **Group name** (customer-facing): `Snorry Premium`
5. Save

---

## Step 3 — Create Premium Yearly subscription

Inside the **Snorry Premium** group:

1. Click **+** → **Create Subscription**
2. Configure:

| Field | Value |
|-------|-------|
| Reference name | `Premium Yearly` |
| Product ID | `app.Snorry.Snorry.premium.yearly` |
| Subscription duration | 1 year |

3. **Subscription prices**
   - Base territory: **United States**
   - Price: **$29.99**
   - Use **Apply to all territories** or adjust per country

4. **Localization** (English U.S. minimum):
   - **Display name:** `Premium Yearly`
   - **Description:** `Keep Insights after your first 7 recorded nights.`

5. Save the subscription

---

## Step 4 — Add 1-week free trial (Yearly only)

1. Open the **Premium Yearly** subscription
2. Go to **Introductory Offers** → **+**
3. Configure:
   - **Type:** Free
   - **Duration:** 1 week
   - **Territories:** All (or your target storefronts)
4. Save

Apple shows trial terms automatically on the purchase sheet.

---

## Step 5 — Create Premium Monthly subscription

Inside the **Snorry Premium** group:

1. Click **+** → **Create Subscription**
2. Configure:

| Field | Value |
|-------|-------|
| Reference name | `Premium Monthly` |
| Product ID | `app.Snorry.Snorry.premium.monthly` |
| Subscription duration | 1 month |

3. **Subscription prices**
   - Base territory: **United States**
   - Price: **$4.99**

4. **Localization** (English U.S. minimum):
   - **Display name:** `Premium Monthly`
   - **Description:** `Keep Insights after your first 7 recorded nights.`

5. **Do not** add an introductory offer on the monthly plan.

> **Important:** Product IDs must match [`SubscriptionProductID.swift`](Snorry/Models/SubscriptionProductID.swift) exactly.

---

## Step 6 — Subscription review information

On the subscription group page, provide:

| Field | Value |
|-------|-------|
| Subscription Privacy Policy URL | `https://snorry.lintech.no/privacy-policy/` |
| Terms of Use | Apple Standard EULA (or your custom URL) |

Before App Store submission, update your privacy policy to mention:
- Auto-renewable subscriptions are billed through Apple
- Payment and subscription management are handled by Apple (not stored by Snorry)
- Free vs Premium feature differences (Insights after 7 recorded nights on Free)

---

## Step 7 — Attach subscriptions to app version

1. App Store Connect → Snorry → your app version
2. Scroll to **In-App Purchases and Subscriptions**
3. Click **+** and select **Premium Yearly** and **Premium Monthly**
4. Ensure both subscriptions are **Ready to Submit** before submitting the version

---

## Step 8 — Local testing (Xcode StoreKit)

1. The repo includes [`Snorry/Configuration/Snorry.storekit`](Snorry/Configuration/Snorry.storekit)
2. In Xcode: **Product → Scheme → Edit Scheme → Run → Options**
3. Set **StoreKit Configuration** to `Snorry.storekit`
4. Run on Simulator or device — purchases use the local config (no sandbox account needed)
5. Use **Debug → StoreKit → Manage Transactions** to simulate renewals, expiry, and refunds

---

## Step 9 — Sandbox testing (App Store Connect)

1. App Store Connect → **Users and Access** → **Sandbox** → **Testers**
2. Create a Sandbox Apple ID
3. On test device: **Settings → App Store → Sandbox Account** → sign in
4. Remove the StoreKit configuration from the Xcode scheme (set to **None**) to hit real sandbox APIs
5. Verify:
   - Free user: full access to recording, History, and Habits; Insights free for first 7 recorded nights, then paywall on Insights tab
   - Subscribe (yearly): 1-week trial starts; full access unlocks immediately
   - Subscribe (monthly): charged immediately; full access unlocks
   - **Restore Purchases** in Settings works on a second device
   - Cancel subscription: access ends after the current period

---

## Step 10 — App Review checklist

- [ ] Product IDs match code (`premium.yearly`, `premium.monthly`)
- [ ] Subscription group + products status: **Ready to Submit**
- [ ] Privacy policy mentions subscriptions and Apple billing
- [ ] App includes **Restore Purchases** (Settings → Subscription)
- [ ] App includes **Manage Subscription** link for Premium users
- [ ] App description explains Free vs Premium tiers
- [ ] Screenshots show paywall if requested by review

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Product not loading in app | Confirm Product IDs, Paid Apps agreement active, wait ~15 min after creating products |
| "Subscription not available" | Check network; verify IAP capability enabled; test with `.storekit` file first |
| Restore finds nothing | Ensure same Sandbox Apple ID; subscription not expired |
| Trial not shown on yearly | Confirm introductory offer is saved and user is eligible (new subscriber) |
| Monthly shows trial | Remove introductory offer from Premium Monthly in App Store Connect |

---

## Code reference

| File | Role |
|------|------|
| `SubscriptionProductID.swift` | Product ID constants and `PremiumPlan` enum |
| `SubscriptionManager.swift` | StoreKit 2 purchase, restore, entitlements |
| `InsightsTrialTracker.swift` | Free Insights for first 7 completed recording nights |
| `HabitKind.swift` / `HabitLog.swift` | Habit definitions and SwiftData logging |
| `HabitsView.swift` | Habits tab UI |
| `SubscriptionView.swift` | Paywall UI (yearly default, plan picker) |
| `AnalyticsViewModel.swift` | Habit correlation stats |
| `AnalyticsView.swift` | Insights tab gating and habit correlation card |
| `SettingsView.swift` | Plan status, upgrade, restore, manage |
