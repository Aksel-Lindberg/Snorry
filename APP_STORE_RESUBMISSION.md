# App Store resubmission — privacy review fixes

Use these notes when resubmitting after Guideline 5.1.1 and 5.1.2 fixes.

## App Store Connect (manual)

1. Open **App Privacy** for Snorry and confirm analytics/tracking disclosures match Firebase usage.
2. If the app tracks users (per Apple’s definition), ensure **Tracking** is declared and linked data types are accurate.

## Review Notes (paste into App Store Connect)

Guideline 5.1.1: Pre-permission buttons now use “Continue”. Informational copy remains on the onboarding screen.

Guideline 5.1.2: Removed custom analytics consent UI. App Tracking Transparency is requested via `ATTrackingManager.requestTrackingAuthorization()` when the user taps Continue on the “Before You Start” onboarding screen (first launch), before microphone permission. For existing users updating the app, ATT is requested on first entry to the main tab bar if not yet determined. Firebase Analytics collection is disabled until ATT status is determined.

## Where to verify in the app

| Flow | ATT location |
|------|----------------|
| New install | Onboarding page 2 → **Continue** → system ATT dialog → mic → notifications |
| App update (onboarding already done) | First open of main tab bar → system ATT dialog if not yet determined |

## Microphone pre-prompt

- Onboarding and Permissions sheet use **Continue**, not “Allow” or “Grant”.
- Denied microphone: Monitor tab shows Settings guidance (no custom Allow button).
