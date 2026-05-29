# Snorry — Feature Description & Use Cases

**Snorry** is an iPhone app for overnight snore monitoring, gentle alerts, and personal sleep-noise insights. Audio is analysed **on your device**; sleep sessions, clips, and charts are stored **locally**. Anonymous **usage analytics** (Firebase) may be collected to improve the app — not sleep recordings.

**Platform:** iPhone (iOS). No watchOS app; alerts may mirror to Apple Watch via standard iOS notifications.  
**Category:** Sleep / wellness tool — **not** a medical device or HealthKit clinical app.

---

## Table of contents

1. [App structure](#1-app-structure)
2. [First launch & onboarding](#2-first-launch--onboarding)
3. [Monitor — start & home](#3-monitor--start--home)
4. [Live monitoring](#4-live-monitoring)
5. [Alerts & escalation](#5-alerts--escalation)
6. [History (Sleep History)](#6-history-sleep-history)
7. [Session detail & playback](#7-session-detail--playback)
8. [Analytics (trends)](#8-analytics-trends)
9. [Settings](#9-settings)
10. [Help & support](#10-help--support)
11. [Privacy & data](#11-privacy--data)
12. [Use case scenarios](#12-use-case-scenarios)
13. [Limitations & good practices](#13-limitations--good-practices)

---

## 1. App structure

After onboarding, Snorry uses a **four-tab** layout:

| Tab | Purpose |
|-----|---------|
| **Monitor** | Start/stop overnight monitoring; alert summary; last session snapshot |
| **History** | List of past nights (“Sleep History”); open any session for detail |
| **Analytics** | Charts and trends over time; settings-change markers; alert-profile comparison |
| **Settings** | Alert channels, timings, alarm tone, support, reset/delete data, legal links |

A contextual **Help** sheet is available from the Monitor tab (toolbar).

---

## 2. First launch & onboarding

### Features

- **Two-page flow:** Welcome → Before You Start  
- **Welcome** explains core value: adaptive snore detection, wrist-friendly notifications, automatic alert stop, progress tracking  
- **Before You Start** explains:
  - **Microphone** — on-device listening; audio not uploaded  
  - **Notifications** — local snore alerts; may appear on a paired Apple Watch  
  - **Usage analytics** — anonymous app usage via Firebase (no sleep audio)  
  - **Legal** — Terms of Use and Privacy Policy links  
  - **Charger tip** — recommends plugging in the iPhone overnight  
- **Allow & Continue** requests microphone, then notification permission, then opens the main app

### Typical use

| Scenario | How to use |
|----------|------------|
| New install | Complete onboarding once; permissions can be changed later in iOS Settings |
| Re-install / new phone | Onboarding runs again; prior local data is not restored unless you use device backup |
| Privacy-conscious user | Read analytics disclosure on page 2 and Privacy Policy before continuing |

---

## 3. Monitor — start & home

### Features

- **Large start control** (sleep animation) — tap to begin monitoring  
- **Alert setup summary card** — mirrors saved Settings: push on/off, sound alarm on/off, push delay (fixed 2 s), sound-alarm delay, repeat-push interval  
- **Last Session card** — when available: sleep duration, snore event count, total snore time for the most recent **completed** night  
- **Help** (toolbar) — opens Help Center  
- **Permissions handling** — if mic access is missing, a sheet or system Settings prompt appears when you tap Start  

### Typical use

| Scenario | How to use |
|----------|------------|
| Every night | Open Monitor → tap Start → lock phone (optional) → sleep |
| Check tonight’s alert plan | Read Alert setup summary before starting; change in Settings if needed |
| Quick recap of last night | Glance at Last Session without opening History |
| Mic denied earlier | Tap Start → follow prompt to open iOS Settings and enable Microphone |

---

## 4. Live monitoring

### Features

Opened automatically when monitoring starts. Stays active until you tap **Stop Monitoring** or monitoring ends.

- **Status badge** — progresses through quiet / detecting / **snoring detected** (confirmation reduces false alarms)  
- **Live power spectrum** — frequency-band view; breath-tempo harmonic highlighted when a bout is confirmed  
- **Metrics** — input level (dBFS), breath rate (BRPM) when available, **event count** (completed snore bouts)  
- **Alert phase card** — shows push sent, alarm active, alert cleared, etc., when alerts are enabled  
- **Live timeline** — ~last 10 minutes of loudness with snoring periods emphasised  
- **Stop Monitoring** — ends session, saves to History; may show brief “finishing audio” / “classifying sounds” for background nights  

### Background & locked iPhone

- **Background audio** keeps the mic pipeline running when the screen is locked  
- While locked, a **lighter detection path** may be used; after stop, saved clips can be **re-classified** (snoring vs sleep talking vs environment) for accurate History labels  
- **Sound alarm on locked phone** auto-stops after about five seconds so tones do not run indefinitely  

### Typical use

| Scenario | How to use |
|----------|------------|
| Standard overnight | Start → lock phone → leave on nightstand → stop in the morning |
| Check if snoring now | Unlock briefly; read status badge and timeline (avoid long screen-on time) |
| Partner in same room | Lower sound-alarm volume is fixed full level in app; prefer **push-only** or watch nudges if sound disturbs partner |
| False alarm worry | Rely on confirmation step; adjust alert channels in Settings between nights |

---

## 5. Alerts & escalation

Configured in **Settings**; applied on the next monitoring session (and shown on Monitor home summary).

### Channels

| Channel | Behavior |
|---------|----------|
| **Push notifications** | Local iOS notifications after **2 seconds** of continuous confirmed snoring; can **repeat** at 1–10 s interval while snoring continues |
| **Sound alarm** | In-app tone after your chosen delay (1–10 s slider); stepped/ramped playback; multiple **alarm styles** (gentle, classic, alert, bundled tones) with preview |

You can enable **push only**, **sound only**, or **both**. With both, push fires first, then sound after the sound delay.

### Alert lifecycle

- Alerts arm only after snoring is **confirmed** (not on every noise spike)  
- Alerts **clear** when snoring stays off for a few seconds (timing adapts slightly when the phone was locked)  
- Notifications may **mirror to Apple Watch** like any iOS alert (not guaranteed; no Snorry watch app)

### Typical use

| Scenario | How to use |
|----------|------------|
| Subtle nudge | Push on, sound off; optional Watch mirroring |
| Harder to ignore | Sound alarm on with shorter sound delay; pick a noticeable alarm style |
| Avoid waking partner | Push-only; longer repeat interval |
| Test what works | Change Settings → Save → run several nights → compare in **Analytics** (alert profile vs snore duration) |

---

## 6. History (Sleep History)

### Features

- Chronological list of monitoring sessions (newest first)  
- Each row: start time, sleep duration, snore event count, total snore time, bar vs longest night in list  
- **Swipe to delete** a single night  
- Tap a row → **Session detail**  
- Empty state when no sessions yet  

### Typical use

| Scenario | How to use |
|----------|------------|
| Morning review | History → open last night → see stats and events |
| Compare rough nights | Scan row bars and snore minutes without opening detail |
| Remove one bad night | Swipe left on that session |
| Privacy cleanup | Delete individual sessions or use Settings bulk delete |

---

## 7. Session detail & playback

### Features

- **Summary stats** — sleep duration, snore events, snore duration, average BRPM when available  
- **Snore Clock** — visual timeline of snoring bouts only  
- **Session timeline chart** — loudness/waveform from saved samples  
- **Sound events list** — each snore bout as a row  
- **Clip playback** — tap events with audio to hear the saved **AAC clip** (when recorded)  
- **Sound labels** (after background/locked nights) — events may show **Snoring**, **Sleep talking**, or **Environment**  
- **Alert setup snapshot** — shows current Settings preferences for context  

### Typical use

| Scenario | How to use |
|----------|------------|
| “Was that really snoring?” | Play back clips; read sound kind label |
| Understand timing | Use Snore Clock and timeline to see when bouts clustered |
| Share with clinician (informal) | Review stats locally; Snorry does not export medical reports |
| Distinguish talk vs snore | Rely on post-session classification on nights that used background detection |

---

## 8. Analytics (trends)

**Note:** This tab is **on-device sleep analytics** (charts from your sessions), not the Firebase usage dashboard.

### Features

- **Time range** — Week / Month / 3 Months  
- **Summary pills** — average snore minutes per day, session count, days with data  
- **Snore duration trend** — daily snore minutes and event counts; optional **numbered markers** when you saved Settings changes  
- **Settings change legend** — expand to read what changed; delete individual markers without changing current Settings  
- **Alert type vs snore duration** — average snore minutes per alert configuration profile (correlation only, not medical advice)  

### Typical use

| Scenario | How to use |
|----------|------------|
| “Am I improving?” | Month view → trend line of daily snore minutes |
| Test a settings experiment | Save new push/sound setup → marker appears on chart → compare weeks before/after |
| See which alert profile correlates with less snoring | Review Alert Type vs Snore duration card (interpret cautiously) |
| Clean chart markers | Remove obsolete settings-change markers from legend |

---

## 9. Settings

### Alert configuration

- Toggle **push notifications** and **sound alarm**  
- **Sound alarm delay** and **push repeat interval** (1–10 s)  
- **Alarm style** picker with **Play / Stop** preview  
- Push delay for first notification is **fixed at 2 s** in current builds  

### Data & maintenance

- **Reset to Defaults** — restores alert preferences to app defaults  
- **Delete All Sleep & Settings Logs** — removes all sessions, clips, waveforms, and analytics markers (must **stop monitoring** first)  

### Other

- **Support** — contact email, troubleshooting, privacy summary  
- **Legal** — Terms of Use, Privacy Policy (web)  
- **Cancel / Save** — discards or persists changes (active monitoring picks up saved alert settings via notification)  

### Typical use

| Scenario | How to use |
|----------|------------|
| First-time tuning | Enable push → test one night → add sound if needed |
| Notifications blocked | Settings shows alert; open iOS Settings for Snorry notifications |
| Fresh start | Stop monitoring → Delete All Logs → optionally Reset to Defaults |
| Preview alarm tone | Alarm style → Play before saving |

---

## 10. Help & support

### Features

- **Help Center** (Monitor toolbar) — accordion sections: getting started, tabs, Monitor home, live monitoring, History, Analytics, Settings  
- **Support** (Settings) — email link, common topics (mic, notifications, delete logs, clips), troubleshooting steps, privacy text  

### Typical use

| Scenario | How to use |
|----------|------------|
| Learn overnight workflow | Help → Monitor tab → Overnight & locked iPhone |
| Understand alert phases | Help → Live monitoring → Alert phases |
| Contact developer | Support → email with device/iOS/app version |

---

## 11. Privacy & data

| Data type | Where it lives |
|-----------|----------------|
| Sleep audio analysis, sessions, clips, waveforms | **On iPhone only** (until you delete or uninstall) |
| Alert preferences | Local (SwiftData) |
| Anonymous usage events (screens, monitoring start/stop buckets, settings categories changed) | **Google Firebase Analytics** |

- Full policy: [https://snorry.lintech.no](https://snorry.lintech.no)  
- In-app disclosure: onboarding, Support, Help  

---

## 12. Use case scenarios

### A. Nightly self-monitoring

**Goal:** Build awareness of snoring without a separate device.

1. Plug in iPhone.  
2. Monitor → Start → lock phone.  
3. Morning → Stop (if still running) or review Last Session / History.  
4. Weekly → Analytics tab for trends.

---

### B. Gentle position-change nudges (Watch)

**Goal:** Subtle prompts via wrist without loud bedroom audio.

1. Settings → enable **Push**, disable **Sound** (optional).  
2. Ensure iPhone notifications for Snorry are allowed; Watch mirrors iPhone alerts if configured.  
3. Start monitoring and sleep.  
4. When snoring is confirmed, receive repeated pushes at your interval until snoring stops.

---

### C. Escalating alert (push then sound)

**Goal:** Notification first, louder in-app alarm if snoring continues.

1. Settings → enable both push and sound.  
2. Set sound delay longer than push (e.g. push at 2 s, sound at 10 s).  
3. Choose alarm style with preview.  
4. Run several sessions; review alert phases on live screen if awake.

---

### D. Experimenting with alert settings

**Goal:** Find what reduces snore duration for you.

1. Note current Analytics trend (week view).  
2. Change one setting (e.g. enable repeat push) → **Save**.  
3. Use app for 7–14 nights.  
4. Analytics → check new **settings marker** on chart and **Alert type vs snore duration** card.  
5. Interpret as personal correlation, not proven causation.

---

### E. Reviewing a disturbing night

**Goal:** Understand when and what happened.

1. History → select the night.  
2. Read duration and event count.  
3. Snore Clock + timeline for timing.  
4. Play individual **Sound events** clips.  
5. Check labels (snoring vs sleep talking vs environment) if classification ran.

---

### F. Travel or guest bedroom

**Goal:** Monitor without leaving cloud sleep recordings.

1. Confirm mic permission.  
2. Prefer push-only alerts to reduce room noise.  
3. Start session; keep phone on bedside with power.  
4. Delete session afterward from History if desired (swipe) for privacy on shared devices.

---

### G. Privacy reset

**Goal:** Remove all local sleep history.

1. Stop monitoring if active.  
2. Settings → **Delete All Sleep & Settings Logs**.  
3. Optionally uninstall app for full removal of local container.

---

### H. Troubleshooting “Start does nothing”

**Goal:** Restore monitoring.

1. Help or Support → Microphone / Notifications topics.  
2. iOS Settings → Snorry → enable Microphone and Notifications.  
3. Return to Monitor → Start again.  
4. If denied permanently, reinstall may be needed to re-trigger permission dialogs.

---

### I. iPad layout

**Goal:** Use Snorry on iPad.

- Monitor home adapts: side-by-side layout in **landscape**; stacked in **portrait** with compressed spacing.  
- Same four tabs and features; monitoring still uses device microphone.

---

## 13. Limitations & good practices

### Limitations

- **Not medical advice** — do not use for diagnosis or treatment decisions.  
- **iPhone-only app** — no native watchOS companion.  
- **Partner / room noise** — may affect detection; classification helps but is not perfect.  
- **Battery** — overnight mic use; charger recommended.  
- **Analytics tab ≠ Firebase** — in-app charts are local; Firebase is product analytics only.  
- **No cloud backup of sessions** — device loss or delete removes history unless you use full device backup.

### Good practices

- Keep iPhone **plugged in** overnight.  
- Place phone **near the bed** with clear mic exposure (not buried under pillows).  
- **Stop monitoring** in the morning so sessions finalize and classify completely.  
- Review **Help → Overnight & locked iPhone** before first locked-phone night.  
- Update **Privacy Policy** and App Store privacy labels if you change analytics or data practices.

---

## Document info

| Field | Value |
|-------|--------|
| App name | Snorry |
| Bundle ID | `app.Snorry.Snorry` |
| Support | aksel.lindberg@lintech.no |
| Privacy | https://snorry.lintech.no |

*This document describes app behavior as implemented in the Snorry codebase. Features may change between releases.*
