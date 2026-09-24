#!/usr/bin/env python3
"""Swipe on the booted iOS Simulator content area (device coordinates)."""

from __future__ import annotations

import ctypes
import ctypes.util
import subprocess
import sys
import time

cg = ctypes.CDLL(ctypes.util.find_library("CoreGraphics"))

# CGEvent types
kCGEventLeftMouseDown = 1
kCGEventLeftMouseUp = 2
kCGEventLeftMouseDragged = 6
kCGHIDEventTap = 0
kCGMouseButtonLeft = 0

CGEventCreateMouseEvent = cg.CGEventCreateMouseEvent
CGEventCreateMouseEvent.restype = ctypes.c_void_p
CGEventCreateMouseEvent.argtypes = [
    ctypes.c_void_p,
    ctypes.c_uint32,
    ctypes.c_double * 2,
    ctypes.c_uint32,
]

CGEventPost = cg.CGEventPost
CGEventPost.restype = None
CGEventPost.argtypes = [ctypes.c_uint32, ctypes.c_void_p]


def window_geometry() -> tuple[float, float, float, float]:
    script = """
tell application "System Events"
  tell process "Simulator"
    set winPos to position of window 1
    set winSize to size of window 1
    return winPos & winSize
  end tell
end tell
"""
    raw = subprocess.check_output(["osascript", "-e", script], text=True).strip()
    parts = [float(v) for v in raw.replace(",", " ").split() if v]
    if len(parts) != 4:
        raise RuntimeError(f"unexpected Simulator window geometry: {raw!r}")
    return parts[0], parts[1], parts[2], parts[3]


def device_to_screen(dx: float, dy: float) -> tuple[float, float]:
    px, py, w, h = window_geometry()
    inset_left, inset_top, inset_right, inset_bottom = 18, 78, 18, 18
    content_w = w - inset_left - inset_right
    content_h = h - inset_top - inset_bottom
    x = px + inset_left + (dx / 1206.0) * content_w
    y = py + inset_top + (dy / 2622.0) * content_h
    return x, y


def post_mouse(event_type: int, x: float, y: float) -> None:
    point = (ctypes.c_double * 2)(x, y)
    event = CGEventCreateMouseEvent(None, event_type, point, kCGMouseButtonLeft)
    CGEventPost(kCGHIDEventTap, event)


def swipe(dx: float, dy_start: float, dy_end: float) -> None:
    subprocess.run(["osascript", "-e", 'tell application "Simulator" to activate'], check=False)
    time.sleep(0.2)
    x1, y1 = device_to_screen(dx, dy_start)
    x2, y2 = device_to_screen(dx, dy_end)
    post_mouse(kCGEventLeftMouseDown, x1, y1)
    time.sleep(0.05)
    steps = 12
    for step in range(1, steps + 1):
        t = step / steps
        x = x1 + (x2 - x1) * t
        y = y1 + (y2 - y1) * t
        post_mouse(kCGEventLeftMouseDragged, x, y)
        time.sleep(0.02)
    post_mouse(kCGEventLeftMouseUp, x2, y2)


if __name__ == "__main__":
    if len(sys.argv) != 4:
        raise SystemExit("usage: simulator_swipe.py <deviceX> <deviceYStart> <deviceYEnd>")
    swipe(float(sys.argv[1]), float(sys.argv[2]), float(sys.argv[3]))
