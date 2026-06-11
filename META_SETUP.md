# Meta App Events Setup (Meta Ads)

This guide configures **Meta App Events** for Snorry so you can measure installs, launches, subscriptions, and key funnel events in [Meta Events Manager](https://www.facebook.com/events_manager) and optimize Meta Ads campaigns.

## App credentials

| Key | Value |
|-----|-------|
| Meta App ID | `998261486550509` |
| Display name | Snorry iOS App |
| Bundle ID | `app.Snorry.Snorry` |
| URL scheme | `fb998261486550509` |

The **Client Token** and **App ID** are configured in [`Snorry/Info.plist`](Snorry/Info.plist). Do not commit the App Secret to the repo.

---

## Prerequisites

1. [Meta Developer](https://developers.facebook.com/) account with access to the Snorry iOS App
2. A [Meta Business Portfolio](https://business.facebook.com/) linked to your ad account
3. Snorry built with the **FacebookCore** Swift package (see Xcode → Package Dependencies)

---

## Step 1 — Add iOS platform in Meta Developer Console

1. Open [App Settings → Basic](https://developers.facebook.com/apps/998261486550509/settings/basic/)
2. Scroll to **Add platform** (if iOS is not listed) → choose **iOS**
3. Set **Bundle ID** to `app.Snorry.Snorry`
4. Save changes

Optional but recommended for Ads Manager:

- **Privacy Policy URL:** `https://snorry.lintech.no/`
- **Terms of Service URL:** (Apple Standard EULA link used in App Store Connect)

---

## Step 2 — Link ad account

1. In the App Dashboard go to **Settings → Advanced**
2. Under **Authorized Ad Account IDs**, add your Meta ad account ID(s)
3. Connect the app to your Business Portfolio if prompted

---

## Step 3 — Events logged by the app

### Automatic (Meta SDK)

| Event | When |
|-------|------|
| App Install | First launch on a device |
| App Launch | Each time the app becomes active |
| Subscribe / Purchase | StoreKit 2 subscription completed (Basic monthly) |

Auto-logging is enabled in Info.plist but **delayed until App Tracking Transparency (ATT) is granted** in Release builds (same gate as Firebase Analytics).

### Manual standard events

| Meta event | Snorry trigger |
|------------|----------------|
| Complete Registration | Onboarding finished |
| View Content | Paywall shown |

Implementation: [`MetaAnalytics.swift`](Snorry/Services/MetaAnalytics.swift) via [`AppAnalytics.swift`](Snorry/Services/AppAnalytics.swift).

---

## Step 4 — Test events

### Debug build (Xcode)

1. Use the shared **Snorry** scheme (includes `-FIRAnalyticsDebugEnabled` for Firebase DebugView)
2. Run on a device or simulator
3. Grant **Allow Tracking** when the ATT dialog appears
4. Walk through onboarding and open the paywall

### App Ads Helper

1. Open [App Ads Helper](https://developers.facebook.com/tools/app-ads-helper/)
2. Select **Snorry iOS App** (`998261486550509`)
3. Click **Test Events**
4. Launch the app and perform actions — events should appear in real time

Expected event names in Events Manager include:

- `fb_mobile_activate_app`
- `fb_mobile_complete_registration`
- `fb_mobile_content_view`
- Subscription/purchase events after a sandbox StoreKit transaction

### StoreKit sandbox purchase

1. Configure a Sandbox Apple ID in **Settings → App Store** on a test device
2. Use [`Snorry.storekit`](Snorry/Snorry.storekit) in Xcode or TestFlight
3. Complete a Basic subscription purchase
4. Confirm a purchase/subscribe event in Events Manager

---

## Step 5 — ATT and privacy

- Analytics collection (Firebase + Meta) is **off in Release** until the user authorizes tracking via ATT.
- In-app copy is in [`LegalLinks.swift`](Snorry/Utilities/LegalLinks.swift) (`PrivacyCopy.usageAnalytics`).
- Before running paid Meta campaigns, update the public [Privacy Policy](PRIVACY_POLICY.md) on `snorry.lintech.no` to disclose Meta App Events.

---

## Code reference

| File | Role |
|------|------|
| [`AppDelegate.swift`](Snorry/AppDelegate.swift) | Meta SDK launch + URL handling |
| [`MetaAnalytics.swift`](Snorry/Services/MetaAnalytics.swift) | ATT-gated Meta settings and standard events |
| [`TrackingAuthorizationManager.swift`](Snorry/Services/TrackingAuthorizationManager.swift) | Syncs Meta settings when ATT resolves |
| [`Info.plist`](Snorry/Info.plist) | FacebookAppID, Client Token, URL scheme |

---

## Troubleshooting

| Issue | Check |
|-------|-------|
| No events in Events Manager | ATT granted? Release builds require tracking permission. |
| Events in Debug only | Run with Snorry scheme debug flag or test on device with ATT allowed. |
| Purchase events missing | Confirm StoreKit 2 sandbox purchase succeeded; auto-logging enabled after ATT. |
| Wrong app in dashboard | Bundle ID must match `app.Snorry.Snorry` exactly. |

For SKAdNetwork campaign optimization (conversion values), configure separately in Events Manager — not included in the initial SDK integration.
