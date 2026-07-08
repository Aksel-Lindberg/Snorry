#!/usr/bin/env python3
"""Build Reel 3 marketing short — partner / push & Watch angle."""

from __future__ import annotations

import subprocess
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
ASSETS = Path("/Users/aksellindberg/.cursor/projects/Users-aksellindberg-Developer-Snorry/assets")
OUT_DIR = ROOT / "Marketing" / "reel3-short"
FRAMES_DIR = OUT_DIR / "frames"

W, H = 1080, 1920
FPS = 30

BG = (10, 11, 30)
SURFACE = (23, 28, 56)
ACCENT = (124, 58, 237)
BLUE = (96, 165, 250)
CORAL = (255, 115, 89)
MINT = (77, 217, 153)
WHITE = (255, 255, 255)
MUTED = (180, 184, 205)

SCENES: list[tuple[float, str, dict]] = [
    (2.0, "hook", {
        "headline": "You're awake.",
        "sub": "They're not.",
        "sub_color": CORAL,
    }),
    (2.0, "text", {
        "headline": "Again.",
        "sub": "There's a better way.",
        "sub_color": BLUE,
    }),
    (2.5, "phone", {
        "image": ASSETS / "telegram-cloud-photo-size-4-5926895444048940695-y-17148e2a-a4bc-4c6b-b8f9-2d7b69800496.png",
        "headline": "Push only. Sound off.",
        "sub": "Nudge you — not the room",
        "focus_alert_setup": True,
    }),
    (2.5, "phone", {
        "image": ASSETS / "telegram-cloud-photo-size-4-5917785285838179974-y-78ebaf6f-9339-422f-9075-0070d10a137b.png",
        "headline": "Snorry listens while you sleep",
        "sub": "Tap START · lock your phone",
    }),
    (3.0, "watch", {
        "headline": "A tap on your wrist",
        "sub": "Not a speaker blast",
    }),
    (2.0, "phone", {
        "image": ASSETS / "telegram-cloud-photo-size-4-5931631495896305106-y-e28c60ab-38e2-488f-aa41-9f69864ed46b.png",
        "headline": "Roll over · snoring stops",
        "sub": "Status back to Quiet",
        "focus_quiet_badge": True,
    }),
    (2.0, "text", {
        "headline": "Alerts stop",
        "sub": "when you stop.",
        "sub_color": MINT,
    }),
    (2.5, "phone", {
        "image": ASSETS / "telegram-cloud-photo-size-4-5935820794111921748-y-7e421b99-cecf-48a4-9111-2df39dd5b950.png",
        "headline": "Your alert setup",
        "sub": "Push · Watch · your rules",
        "focus_push_channels": True,
    }),
    (2.5, "phone", {
        "image": ASSETS / "telegram-cloud-photo-size-4-5926895444048940695-y-17148e2a-a4bc-4c6b-b8f9-2d7b69800496.png",
        "headline": "Works with Apple Watch",
        "sub": "Alerts on your wrist",
        "focus_watch_hint": True,
    }),
    (2.5, "text", {
        "headline": "They slept.",
        "sub": "You got the nudge.",
        "sub_color": BLUE,
    }),
    (6.5, "end", {}),
]


def load_font(size: int, bold: bool = True) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    paths = [
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf" if bold else "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/Library/Fonts/Arial Bold.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
    ]
    for path in paths:
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            continue
    return ImageFont.load_default()


def gradient_bg() -> Image.Image:
    img = Image.new("RGB", (W, H), BG)
    draw = ImageDraw.Draw(img)
    for y in range(H):
        t = y / H
        r = int(BG[0] + (18 - BG[0]) * (1 - t) * 0.35)
        g = int(BG[1] + (12 - BG[1]) * (1 - t) * 0.35)
        b = int(BG[2] + (40 - BG[2]) * (1 - t) * 0.35)
        draw.line([(0, y), (W, y)], fill=(r, g, b))
    return img


def wrap_text(text: str, font: ImageFont.FreeTypeFont, max_width: int) -> list[str]:
    words = text.split()
    lines: list[str] = []
    current = ""
    draw = ImageDraw.Draw(Image.new("RGB", (1, 1)))
    for word in words:
        trial = f"{current} {word}".strip()
        if draw.textlength(trial, font=font) <= max_width:
            current = trial
        else:
            if current:
                lines.append(current)
            current = word
    if current:
        lines.append(current)
    return lines or [text]


def draw_centered_text(
    draw: ImageDraw.ImageDraw,
    y: int,
    text: str,
    font: ImageFont.FreeTypeFont,
    fill: tuple[int, int, int],
    max_width: int = 920,
    line_gap: int = 12,
) -> int:
    cy = y
    for line in wrap_text(text, font, max_width):
        tw = draw.textlength(line, font=font)
        draw.text(((W - tw) / 2, cy), line, font=font, fill=fill)
        cy += font.size + line_gap
    return cy


def crop_phone_content(img: Image.Image) -> Image.Image:
    w, h = img.size
    if w > h * 0.55:
        target_ratio = 9 / 19.5
        crop_w = int(h * target_ratio)
        left = (w - crop_w) // 2
        return img.crop((left, 0, left + crop_w, h))
    return img


def phone_mockup(screenshot: Image.Image, scale: float = 0.78) -> Image.Image:
    shot = crop_phone_content(screenshot.convert("RGBA"))
    target_w = int(W * scale)
    target_h = int(target_w * (shot.height / shot.width))
    shot = shot.resize((target_w, target_h), Image.Resampling.LANCZOS)

    frame = Image.new("RGBA", (target_w + 48, target_h + 48), (0, 0, 0, 0))
    shadow = Image.new("RGBA", frame.size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.rounded_rectangle((16, 16, frame.width - 16, frame.height - 16), radius=42, fill=(0, 0, 0, 160))
    shadow = shadow.filter(ImageFilter.GaussianBlur(18))
    frame.alpha_composite(shadow)

    mask = Image.new("L", (target_w, target_h), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, target_w, target_h), radius=36, fill=255)
    rounded = Image.new("RGBA", (target_w, target_h), (0, 0, 0, 0))
    rounded.paste(shot, (0, 0), mask)

    ox, oy = 24, 24
    frame.alpha_composite(rounded, (ox, oy))

    border = ImageDraw.Draw(frame)
    border.rounded_rectangle(
        (ox, oy, ox + target_w, oy + target_h),
        radius=36,
        outline=(124, 58, 237, 120),
        width=3,
    )
    return frame


def render_text_scene(headline: str, sub: str = "", sub_color: tuple[int, int, int] = BLUE) -> Image.Image:
    img = gradient_bg().convert("RGBA")
    draw = ImageDraw.Draw(img)
    y = H // 2 - 180
    if headline:
        y = draw_centered_text(draw, y, headline, load_font(92), WHITE)
        y += 24
    if sub:
        draw_centered_text(draw, y, sub, load_font(56, bold=False), sub_color)
    return img.convert("RGB")


def render_hook_scene(headline: str, sub: str = "", sub_color: tuple[int, int, int] = ACCENT) -> Image.Image:
    thumb = ASSETS / "snorry-reel3-thumbnail-partner.png"
    if thumb.exists():
        bg = Image.open(thumb).convert("RGB").resize((W, H), Image.Resampling.LANCZOS)
        bg = bg.filter(ImageFilter.GaussianBlur(1))
        overlay = Image.new("RGBA", (W, H), (10, 11, 30, 130))
        bg = Image.alpha_composite(bg.convert("RGBA"), overlay).convert("RGB")
    else:
        bg = gradient_bg()

    draw = ImageDraw.Draw(bg)
    draw_centered_text(draw, 220, headline, load_font(88), WHITE)
    if sub:
        draw_centered_text(draw, 420, sub, load_font(64), sub_color)
    return bg


def render_phone_scene(
    screenshot_path: Path,
    headline: str,
    sub: str,
    focus_alert_setup: bool = False,
    focus_quiet_badge: bool = False,
    focus_push_channels: bool = False,
    focus_watch_hint: bool = False,
) -> Image.Image:
    img = gradient_bg().convert("RGBA")
    draw = ImageDraw.Draw(img)

    y = 150
    y = draw_centered_text(draw, y, headline, load_font(68), WHITE)
    draw_centered_text(draw, y + 10, sub, load_font(40, bold=False), MUTED)

    shot = Image.open(screenshot_path)
    mock = phone_mockup(shot, scale=0.80)
    px = (W - mock.width) // 2
    py = 460
    img.alpha_composite(mock, (px, py))

    badge = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    bd = ImageDraw.Draw(badge)

    if focus_alert_setup:
        bx, by, bw, bh = px + 24, py + mock.height - 340, mock.width - 48, 200
        bd.rounded_rectangle((bx, by, bx + bw, by + bh), radius=22, outline=MINT + (255,), width=4)

    if focus_quiet_badge:
        bx, by, bw, bh = px + 40, py + 200, mock.width - 80, 72
        bd.rounded_rectangle((bx, by, bx + bw, by + bh), radius=20, outline=MINT + (255,), width=4)

    if focus_push_channels:
        bx, by, bw, bh = px + 24, py + 200, mock.width - 48, 340
        bd.rounded_rectangle((bx, by, bx + bw, by + bh), radius=22, outline=ACCENT + (255,), width=4)

    if focus_watch_hint:
        bx, by, bw, bh = px + 40, py + 520, mock.width - 80, 52
        bd.rounded_rectangle((bx, by, bx + bw, by + bh), radius=14, outline=BLUE + (255,), width=4)

    if focus_alert_setup or focus_quiet_badge or focus_push_channels or focus_watch_hint:
        img = Image.alpha_composite(img, badge)

    return img.convert("RGB")


def render_watch_scene(headline: str, sub: str) -> Image.Image:
    """Synthetic Apple Watch alert moment (notifications mirror from iPhone)."""
    img = gradient_bg().convert("RGBA")
    draw = ImageDraw.Draw(img)

    y = 140
    y = draw_centered_text(draw, y, headline, load_font(68), WHITE)
    draw_centered_text(draw, y + 10, sub, load_font(40, bold=False), MUTED)

    # Soft bedroom vignette
    vignette = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    vd = ImageDraw.Draw(vignette)
    vd.ellipse((120, 720, 960, 1700), fill=(20, 24, 50, 80))
    img = Image.alpha_composite(img, vignette)

    # Wrist + watch body
    cx, cy = W // 2, 1050
    watch_w, watch_h = 340, 420
    wx, wy = cx - watch_w // 2, cy - watch_h // 2

    strap = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sd = ImageDraw.Draw(strap)
    sd.rounded_rectangle((wx - 36, wy - 120, wx + watch_w + 36, wy + watch_h + 120), radius=28, fill=(28, 32, 48, 220))
    sd.rounded_rectangle((wx - 8, wy - 80, wx + watch_w + 8, wy + watch_h + 80), radius=18, fill=(18, 20, 34, 255))
    img = Image.alpha_composite(img, strap)

    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.rounded_rectangle((wx - 20, wy - 20, wx + watch_w + 20, wy + watch_h + 20), radius=52, fill=ACCENT + (60,))
    glow = glow.filter(ImageFilter.GaussianBlur(24))
    img = Image.alpha_composite(img, glow)

    draw.rounded_rectangle((wx, wy, wx + watch_w, wy + watch_h), radius=44, fill=(8, 8, 12))
    draw.rounded_rectangle((wx, wy, wx + watch_w, wy + watch_h), radius=44, outline=ACCENT, width=4)

    # Watch face content
    draw.text((wx + 28, wy + 24), "9:41", font=load_font(28), fill=MUTED)
    draw.text((wx + 28, wy + 72), "Snoring Detected", font=load_font(34), fill=WHITE)
    draw.text((wx + 28, wy + 118), "Snorry", font=load_font(26, bold=False), fill=BLUE)
    draw.text((wx + 28, wy + 158), "Tap to roll over", font=load_font(22, bold=False), fill=MUTED)

    # App icon on watch
    icon_path = ROOT / "Snorry" / "Assets.xcassets" / "HomeAppIcon.imageset" / "HomeAppIcon.png"
    if icon_path.exists():
        icon = Image.open(icon_path).convert("RGBA").resize((72, 72), Image.Resampling.LANCZOS)
        img.alpha_composite(icon, (wx + watch_w - 96, wy + watch_h - 96))

    # Haptic ripple rings
    for radius, alpha in [(200, 40), (260, 25), (320, 12)]:
        ring = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        rd = ImageDraw.Draw(ring)
        rd.ellipse(
            (cx - radius, cy + 40 - radius, cx + radius, cy + 40 + radius),
            outline=ACCENT + (alpha,),
            width=3,
        )
        img = Image.alpha_composite(img, ring)

    draw_centered_text(draw, 1580, "Alerts on your wrist", load_font(36, bold=False), BLUE)
    draw_centered_text(draw, 1640, "Not a dedicated Watch app — iPhone notifications", load_font(22, bold=False), MUTED)

    return img.convert("RGB")


def render_end_scene() -> Image.Image:
    img = gradient_bg().convert("RGBA")
    draw = ImageDraw.Draw(img)

    icon_path = ROOT / "Snorry" / "Assets.xcassets" / "HomeAppIcon.imageset" / "HomeAppIcon.png"
    icon = Image.open(icon_path).convert("RGBA").resize((180, 180), Image.Resampling.LANCZOS)
    img.alpha_composite(icon, ((W - 180) // 2, H // 2 - 300))

    draw_centered_text(draw, H // 2 - 80, "Snorry", load_font(96), WHITE)
    draw_centered_text(draw, H // 2 + 30, "Nudge you. Not them.", load_font(48, bold=False), BLUE)
    draw_centered_text(draw, H // 2 + 100, "Understand your Nights", load_font(40, bold=False), MUTED)
    draw_centered_text(draw, H // 2 + 160, "Free on the App Store", load_font(36, bold=False), MUTED)

    pill_w, pill_h = 520, 72
    px = (W - pill_w) // 2
    py = H // 2 + 240
    draw.rounded_rectangle((px, py, px + pill_w, py + pill_h), radius=36, fill=ACCENT)
    label = "Try Snorry tonight"
    tw = draw.textlength(label, font=load_font(34))
    draw.text(((W - tw) / 2, py + 16), label, font=load_font(34), fill=WHITE)

    return img.convert("RGB")


def render_scene(scene_type: str, opts: dict) -> Image.Image:
    if scene_type == "hook":
        return render_hook_scene(
            opts.get("headline", ""),
            opts.get("sub", ""),
            opts.get("sub_color", ACCENT),
        )
    if scene_type == "text":
        return render_text_scene(
            opts.get("headline", ""),
            opts.get("sub", ""),
            opts.get("sub_color", BLUE),
        )
    if scene_type == "phone":
        return render_phone_scene(
            opts["image"],
            opts.get("headline", ""),
            opts.get("sub", ""),
            opts.get("focus_alert_setup", False),
            opts.get("focus_quiet_badge", False),
            opts.get("focus_push_channels", False),
            opts.get("focus_watch_hint", False),
        )
    if scene_type == "watch":
        return render_watch_scene(opts.get("headline", ""), opts.get("sub", ""))
    if scene_type == "end":
        return render_end_scene()
    raise ValueError(scene_type)


def write_frames() -> list[tuple[Path, float]]:
    FRAMES_DIR.mkdir(parents=True, exist_ok=True)
    for old in FRAMES_DIR.glob("*.png"):
        old.unlink()

    clips: list[tuple[Path, float]] = []
    for index, (duration, scene_type, opts) in enumerate(SCENES):
        frame = render_scene(scene_type, opts)
        path = FRAMES_DIR / f"scene_{index:02d}.png"
        frame.save(path, quality=95)
        clips.append((path, duration))
    return clips


def build_video(clips: list[tuple[Path, float]], audio_path: Path, output_path: Path) -> None:
    concat_path = OUT_DIR / "concat.txt"
    lines: list[str] = []
    for path, duration in clips:
        lines.append(f"file '{path}'")
        lines.append(f"duration {duration:.3f}")
    lines.append(f"file '{clips[-1][0]}'")
    concat_path.write_text("\n".join(lines) + "\n")

    silent_video = OUT_DIR / "silent.mp4"
    subprocess.run(
        [
            "ffmpeg", "-y",
            "-f", "concat", "-safe", "0", "-i", str(concat_path),
            "-vf", f"scale={W}:{H}:force_original_aspect_ratio=decrease,pad={W}:{H}:(ow-iw)/2:(oh-ih)/2,format=yuv420p",
            "-r", str(FPS),
            "-c:v", "libx264", "-pix_fmt", "yuv420p",
            str(silent_video),
        ],
        check=True,
        capture_output=True,
    )

    total_duration = sum(d for _, d in clips)
    subprocess.run(
        [
            "ffmpeg", "-y",
            "-i", str(silent_video),
            "-i", str(audio_path),
            "-filter_complex",
            f"[1:a]atrim=0:{total_duration:.3f},asetpts=PTS-STARTPTS,volume=0.32[a]",
            "-map", "0:v:0", "-map", "[a]",
            "-c:v", "copy", "-c:a", "aac", "-b:a", "192k",
            "-shortest",
            str(output_path),
        ],
        check=True,
        capture_output=True,
    )


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    audio = ROOT / "Snorry" / "Resources" / "Quiet_Found_Us.mp3"
    if not audio.exists():
        audio = ROOT / "Snorry" / "Resources" / "Raindrop.mp3"

    clips = write_frames()
    output = OUT_DIR / "snorry-reel3-partner-short.mp4"
    build_video(clips, audio, output)

    total = sum(d for _, d in clips)
    print(f"Wrote {len(clips)} scenes · {total:.1f}s")
    print(f"Video: {output}")


if __name__ == "__main__":
    main()
