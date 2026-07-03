# Snorry — App Brand Guide (Developer Companion)

Companion to the marketing **Snorry Brand Guide v3.0** (PDF). The PDF covers Instagram, ads, and App Store creative. This document is the **implementation spec** for the iOS app UI, copy, and design tokens.

**Marketing PDF:** `docs/resources/` (see [docs/resources/README.md](docs/resources/README.md)). Filename may read `snorry-brand-guide-v12.pdf`; cover version is **v3.0**.

**Code tokens:** [`Snorry/Utilities/Theme.swift`](Snorry/Utilities/Theme.swift)

---

## 1. Vocabulary (hybrid model)

Use consistent user-facing language. Internal Swift names (`MonitorViewModel`, `MonitoringUsageTracker`, analytics keys) stay unchanged.

| Context | Term | Example |
|---------|------|---------|
| Tab label | **Tonight** | Bottom nav (formerly Monitor) |
| Session limits / counts | **recording** | "8 free recording sessions remaining" |
| Start / stop actions | **recording** | Nav title **Recording**; "Stop Recording"; VoiceOver "Start recording" |
| Live session reassurance | **listening** | Subline **We're listening for snores.** (not the nav title) |
| Marketing primary | **Understand your Nights** | Future header/onboarding pass |

**Do not say (user-facing):** "monitoring session", "Stop monitoring" (use recording), fear-driven or medical claims.

---

## 2. Color tokens

### Marketing palette (reference)

| Token | Hex | Role |
|-------|-----|------|
| Deep Space Navy | `#0A0B1E` | Primary background (dark) |
| Snorry Purple | `#7C3AED` | Accent, highlights |
| CTA Purple | `#381D92` | Primary action buttons (marketing) |
| Dream Blue | `#60A5FA` | Secondary accent |
| Soft Lavender | `#A78BFA` | Subtext, gradients |
| Morning Mist | `#EDE9FE` | Light lifestyle backgrounds (marketing only) |
| Pure White | `#FFFFFF` | Primary text |
| Muted Gray | `#8B8FAD` | Secondary text |

### App functional tokens (`Theme.swift`)

| Token | Role |
|-------|------|
| `background`, `surface`, `surfaceSecondary` | Screens and cards |
| `accent`, `accentGradient` | Links, tab tint, START button |
| `snoring`, `snoringGradient` | Confirmed snoring state |
| `good` | Quiet / success |
| `warning` | Detecting pattern |
| `stopGradient` | Stop Recording button |
| `labelPrimary`, `labelSecondary`, `labelTertiary`, `labelOnSurfaceSecondary` | Text hierarchy (secondary 75%, tertiary 52%, on-surface 68% white) |

**App policy:** Dark-only UI. Morning Mist is for marketing lifestyle posts, not in-app light mode.

---

## 3. Typography

### Marketing & web (see PDF)

Website and social use the **Snorry Brand Guide v3.0** (PDF) — not duplicated here. Typical split:

| Use | Font |
|-----|------|
| Display / hero headlines | Serif display (PDF names the family) |
| Body, nav, buttons, UI | Inter (400–900) |
| Lifestyle overlay lines | Inter Semibold/Bold or brand purple (e.g. *Understand your Nights*) |

**Do not use Noteworthy or app serif faces on the web** unless the PDF adds an explicit web script pairing.

### iOS app

| Use | Font |
|-----|------|
| UI default | SF Pro (system `.body`, `.caption`, etc.) |
| Wordmark “Snorry” on Tonight home | SF Rounded Bold |
| Handwritten accent | Noteworthy via `Theme.handwritten` + `Theme.handwrittenGradient` |
| Stats, timers, chart axes | Monospaced digits (`Theme.monoDigit`) |

**Noteworthy — approved placements only:** Tonight home subtitle (*Sleep Snore Alert & Tracking*), watch hint, onboarding tagline, START letter animation. Paywall may use Noteworthy for decorative wordmark only.

**Noteworthy rules:** Prefer **Noteworthy-Bold**; avoid Light below 17pt. Minimum **13pt** for readable accent lines (watch hint). Always pair with `handwrittenGradient` on dark backgrounds unless the PDF specifies otherwise. **Max one or two short lines per screen** — never for settings, cards, charts, or body copy.

**Text hierarchy on dark UI:** `labelPrimary` → `labelSecondary` (75%) → `labelTertiary` (52%). Card sublabels on `surface` use `labelOnSurfaceSecondary` (68%) — especially `.caption2` on cards.

**Minimum sizes:** Body 14pt; captions 11pt; headlines 22pt on mobile. Nav titles must fit inline without truncation on iPhone SE (~20 characters max).

**App policy:** No bundled Inter, no serif, no custom web fonts in-app.

---

## 4. Spacing scale

Marketing grid: 4, 8, 16, 24, 32, 48, 80 px. Prefer these in new layout work; existing screens may use legacy values until refactored.

---

## 5. Motion

| Duration | Use |
|----------|-----|
| 200 ms | Micro-interactions, press (0.97× scale) |
| 350 ms | Screen transitions |
| 500 ms | Modals / sheets |

Default easing: ease-in-out. Spring damping ≥ 0.7 for sheets only. Respect `prefers-reduced-motion`. Infinite pulse allowed only on live snoring status badge during an active session.

---

## 6. Screen specs

### Tonight (home tab)

- **Nav:** Toolbar app icon + Help (?)
- **Header:** Snorry wordmark; handwritten subtitle (brand alignment TBD)
- **Hero:** Large START circle — moon, waveform, mic + **START**; caption **Tap to start recording** directly below the circle
- **Free tier hint:** `N free recording session(s) remaining`
- **Alert Setup card:** Collapsed by default; caption "Used for the next recording session"
- **Last Session card:** Always visible. Three columns: Sleep duration / Snore events / Snore duration. Empty state: all **—** + footer *No recordings yet.*

**Marketing screenshots:** Prefer real app UI; crop tab bar labels if phone appears small in posts.

### Live session (recording screen)

- **Nav title:** Recording
- **Tab bar:** Hidden for the duration of the session
- **Greeting (scroll content):** `Good night, {firstName}.` or `Good night.` when no name in Settings → Profile
- **Subline:** We're listening for snores.
- **Status badge (dynamic):** Quiet · Detecting Pattern… · Snoring Detected
- **Live Power Spectrum:** Short subtext *Frequency view of tonight’s audio*; technical detail via **info** sheet (ⓘ)
- **Stop button:** Sticky at bottom — always visible without scrolling; **Stop Recording** / **Stopping…**
- **Overlay on stop:** Saving session…

Do not replace status badge copy with listening language — badge shows live detection state.

### Recording in progress (app-wide)

When the user leaves Recording while a session is still active:

- **Banner (all tabs):** Recording in progress · Return — with elapsed timer; tap opens Recording
- **Tonight tab badge:** Numeric indicator while session is active off-screen
- **Tonight hero:** Caption **Return to recording** (replaces *Tap to start recording*); hide free-tier and watch hints until session ends

---

## 7. Approved copy library

### Tonight (home)

| Element | Copy |
|---------|------|
| START caption (below circle) | Tap to start recording |
| Return caption (session active, off Recording screen) | Return to recording |
| In-progress banner (all tabs) | Recording in progress · Return |
| Watch hint (below free-tier line) | Connect your watch · get Snore alerts on your wrist |
| Free sessions | `{N} free recording session(s) remaining` |
| Free limit | Free recording limit reached. Upgrade to Premium to continue. |
| Last Session empty footer | No recordings yet. |
| Alert Setup caption | Used for the next recording session |
| Mic permission | Microphone access required to record snoring |
| VoiceOver START | Label: Start recording · Hint: Begins an overnight snore recording session |

### Live session

| Element | Copy |
|---------|------|
| Nav title | Recording |
| Greeting (name set) | Good night, {firstName}. |
| Greeting (no name) | Good night. |
| Subline | We're listening for snores. |
| Spectrum card subtext | Frequency view of tonight’s audio |
| Stop button | Stop Recording |
| Stopping | Stopping… |

### Settings — Profile

| Element | Copy |
|---------|------|
| Section | Profile |
| Field placeholder | Your name |
| Footer | Optional. Used for a personal “Good night” greeting when you start recording. |

### Tab bar

| Tab | Label | Icon |
|-----|-------|------|
| Home | Tonight | Moon + star (`moon.stars.fill` or `TabTonightIcon` asset) |
| History | History | clock.arrow.circlepath |
| Insights | Insights | chart.line.uptrend.xyaxis |
| Settings | Settings | gearshape |

---

## 8. Accessibility

- WCAG AA contrast on dark backgrounds
- Never use color alone for chart meaning — add labels
- VoiceOver labels must match visible action vocabulary (recording / listening as above)
- Nav titles: short; full sentences go in body/subline

---

## 9. Out of scope (future passes)

- Header rewrite to "Understand your Nights" / demote watch subtitle
- Theme.swift alignment to marketing hex values
- Spectrum card technical copy simplification
- Bundled Inter font

---

## 10. Related docs

- [FEATURES.md](FEATURES.md) — product behavior
- [SUBSCRIPTION_SETUP.md](SUBSCRIPTION_SETUP.md) — App Store copy
- [docs/resources/README.md](docs/resources/README.md) — marketing assets index
