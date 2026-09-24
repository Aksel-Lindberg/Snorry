#!/bin/bash
# Capture Snorry tab screenshots from the booted iOS Simulator.
set -euo pipefail

OUT="${1:-/tmp/snorry-appstore-captures}"
mkdir -p "$OUT"

scroll_device() {
  python3 "$(dirname "$0")/simulator_swipe.py" "$1" "$2" "$3"
}

tap_device() {
  local dx=$1 dy=$2
  osascript <<APPLESCRIPT
tell application "Simulator" to activate
delay 0.35
tell application "System Events"
  tell process "Simulator"
    set frontmost to true
    set winPos to position of window 1
    set winSize to size of window 1
    set insetLeft to 18
    set insetTop to 78
    set insetRight to 18
    set insetBottom to 18
    set contentW to (item 1 of winSize) - insetLeft - insetRight
    set contentH to (item 2 of winSize) - insetTop - insetBottom
    set scaleX to contentW / 1206.0
    set scaleY to contentH / 2622.0
    set clickX to (item 1 of winPos) + insetLeft + ($dx * scaleX)
    set clickY to (item 2 of winPos) + insetTop + ($dy * scaleY)
    click at {clickX, clickY}
  end tell
end tell
APPLESCRIPT
}

shot() {
  local name=$1
  sleep 1.5
  xcrun simctl io booted screenshot "$OUT/$name.png"
  echo "captured $name"
}

status_bar_override() {
  xcrun simctl status_bar booted override \
    --cellularBars 4 \
    --cellularMode active \
    --wifiBars 3 \
    --batteryLevel 85 \
    --batteryState charged \
    --time "02:14" >/dev/null 2>&1 || true
}

status_bar_clear() {
  xcrun simctl status_bar booted clear >/dev/null 2>&1 || true
}

APP="/Users/aksellindberg/Library/Developer/Xcode/DerivedData/Snorry-dnlpkcfvixbulubukuemevakmmes/Build/Products/Debug-iphonesimulator/Snorry.app"

app_plist() {
  xcrun simctl get_app_container booted app.Snorry.Snorry data 2>/dev/null
}

ensure_plist() {
  local plist="$1"
  if [[ ! -f "$plist" ]]; then
    mkdir -p "$(dirname "$plist")"
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' \
      '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
      '<plist version="1.0"><dict></dict></plist>' > "$plist"
  fi
}

set_plist_bool() {
  local key=$1
  local value=$2
  local plist
  plist="$(app_plist)/Library/Preferences/app.Snorry.Snorry.plist"
  ensure_plist "$plist"
  if /usr/libexec/PlistBuddy -c "Print :$key" "$plist" >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c "Set :$key $value" "$plist" >/dev/null
  else
    /usr/libexec/PlistBuddy -c "Add :$key bool $value" "$plist" >/dev/null
  fi
}

set_plist_string() {
  local key=$1
  local value=$2
  local plist
  plist="$(app_plist)/Library/Preferences/app.Snorry.Snorry.plist"
  ensure_plist "$plist"
  if /usr/libexec/PlistBuddy -c "Print :$key" "$plist" >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c "Set :$key $value" "$plist" >/dev/null
  else
    /usr/libexec/PlistBuddy -c "Add :$key string $value" "$plist" >/dev/null
  fi
}

xcrun simctl terminate booted app.Snorry.Snorry >/dev/null 2>&1 || true
sleep 0.5
xcrun simctl install booted "$APP" >/dev/null 2>&1 || true
set_plist_bool hasCompletedOnboarding true
set_plist_string userDisplayName Anna

# Frame 01 — recording screen with demo monitoring state.
set_plist_bool seedAppStoreDemo true
set_plist_bool appStoreDemoRecordingScreen true
xcrun simctl launch booted app.Snorry.Snorry >/dev/null
sleep 4
shot recording

# Tab captures — relaunch without the recording-screen flag.
xcrun simctl terminate booted app.Snorry.Snorry >/dev/null 2>&1 || true
sleep 0.5
set_plist_bool seedAppStoreDemo true
set_plist_bool appStoreDemoRecordingScreen false
xcrun simctl launch booted app.Snorry.Snorry >/dev/null
sleep 4
status_bar_override

# Tab bar centers (device pixels, 1206×2622 capture).
tap_device 184 2570
shot tonight
tap_device 393 2570
shot history
tap_device 602 2570
shot habits
tap_device 811 2570
shot insights_week
# Demo seeder opens Insights on Month; scroll to habit correlation cards.
sleep 1
scroll_device 603 1900 900
sleep 0.5
scroll_device 603 1900 900
sleep 1
shot insights
tap_device 1020 2570
shot exercises

# Session detail — hero night (first History row): Snore Clock + Sound Events.
tap_device 393 2570
sleep 1
tap_device 603 520
sleep 2.5
# Scroll ~450 device px — keep clock at top, bring play rows into view.
scroll_device 603 1700 1250
sleep 1
shot session_detail

status_bar_clear
