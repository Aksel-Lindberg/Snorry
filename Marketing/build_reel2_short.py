#!/usr/bin/env python3
"""Build Reel 2 marketing short — progress & Insights angle."""

from __future__ import annotations

import subprocess
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
ASSETS = Path("/Users/aksellindberg/.cursor/projects/Users-aksellindberg-Developer-Snorry/assets")
OUT_DIR = ROOT / "Marketing" / "reel2-short"
FRAMES_DIR = OUT_DIR / "frames"

W, H = 1080, 1920
FPS = 30

BG = (10, 11, 30)
SURFACE = (23, 28, 56)
ACCENT = (124, 58, 237)
BLUE = (96, 165, 250)
CORAL = (255, 115, 89)
MINT = (77, 217, 153)
WARNING = (255, 204, 51)
WHITE = (255, 255, 255)
MUTED = (180, 184, 205)

SCENES: list[tuple[float, str, dict]] = [
    (2.0, "hook", {
        "headline": "Same snorer.",
        "sub": "Different nights.",
        "sub_color": BLUE,
    }),
    (2.0, "text", {
        "headline": "Are you getting",
        "sub": "better?",
        "sub_color": MINT,
    }),
    (2.5, "phone", {
        "image": ASSETS / "telegram-cloud-photo-size-4-5917785285838179974-y-78ebaf6f-9339-422f-9075-0070d10a137b.png",
        "headline": "Record while you sleep",
        "sub": "Tap START · plug in · rest",
    }),
    (2.5, "phone", {
        "image": ASSETS / "telegram-cloud-photo-size-4-5931631495896305106-y-e28c60ab-38e2-488f-aa41-9f69864ed46b.png",
        "headline": "Snorry listens all night",
        "sub": "Quiet · Detecting · Snoring",
    }),
    (2.0, "phone", {
        "image": ASSETS / "telegram-cloud-photo-size-4-5931631495896305231-y-a80dcbee-7bd5-444a-83f9-a3452a8646d0.png",
        "headline": "Gentle nudge",
        "sub": "Roll over · snoring stops",
        "highlight_notification": True,
    }),
    (2.0, "text", {
        "headline": "Alerts stop",
        "sub": "when you stop.",
        "sub_color": BLUE,
    }),
    (3.0, "phone", {
        "image": ASSETS / "simulator_screenshot_896BBF27-5B66-4E4E-92C1-C63B3D6C82AE-caa6dfae-f7a7-465a-97ce-1048d3980495.png",
        "headline": "Every morning: your numbers",
        "sub": "Sleep · Events · Snore time",
        "focus_last_session": True,
    }),
    (4.0, "chart", {
        "headline": "See the trend",
        "sub": "Not just one bad night",
    }),
    (2.5, "phone", {
        "image": ASSETS / "telegram-cloud-photo-size-4-5935820794111921748-y-7e421b99-cecf-48a4-9111-2df39dd5b950.png",
        "headline": "Change alerts. Compare.",
        "sub": "Settings markers on your chart",
        "focus_settings": True,
    }),
    (2.5, "phone", {
        "image": ASSETS / "telegram-cloud-photo-size-4-5935820794111922033-y-82a9d06a-4911-404b-9214-ba10e6552c58.png",
        "headline": "Quiet nights add up",
        "sub": "Timeline · clips · progress",
    }),
    (5.0, "end", {}),
]

# Declining demo data for synthetic Insights chart (minutes per day).
CHART_MINUTES = [23, 21, 19, 18, 16, 14, 13, 12, 11, 10, 9, 8, 11, 9, 7]


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
    lines = wrap_text(text, font, max_width)
    cy = y
    for line in lines:
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
    h_font = load_font(92)
    s_font = load_font(56, bold=False)

    y = H // 2 - 180
    if headline:
        y = draw_centered_text(draw, y, headline, h_font, WHITE)
        y += 24
    if sub:
        draw_centered_text(draw, y, sub, s_font, sub_color)
    return img.convert("RGB")


def render_hook_scene(headline: str, sub: str = "", sub_color: tuple[int, int, int] = ACCENT) -> Image.Image:
    thumb = ASSETS / "snorry-reel2-thumbnail-progress.png"
    if thumb.exists():
        bg = Image.open(thumb).convert("RGB").resize((W, H), Image.Resampling.LANCZOS)
        bg = bg.filter(ImageFilter.GaussianBlur(1))
        overlay = Image.new("RGBA", (W, H), (10, 11, 30, 120))
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
    highlight_notification: bool = False,
    focus_last_session: bool = False,
    focus_settings: bool = False,
) -> Image.Image:
    img = gradient_bg().convert("RGBA")
    draw = ImageDraw.Draw(img)

    y = 150
    y = draw_centered_text(draw, y, headline, load_font(68), WHITE)
    draw_centered_text(draw, y + 10, sub, load_font(40, bold=False), MUTED)

    shot = Image.open(screenshot_path)
    mock = phone_mockup(shot, scale=0.82 if focus_last_session else 0.80)
    px = (W - mock.width) // 2
    py = 430 if focus_last_session else 460
    img.alpha_composite(mock, (px, py))

    if highlight_notification:
        badge = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        bd = ImageDraw.Draw(badge)
        bx, by, bw, bh = px + 40, py + 30, mock.width - 80, 130
        bd.rounded_rectangle((bx, by, bx + bw, by + bh), radius=22, fill=(255, 255, 255, 235))
        bd.text((bx + 24, by + 22), "Snoring Detected", font=load_font(34), fill=(20, 20, 30))
        bd.text((bx + 24, by + 68), "Snorry · now", font=load_font(24, bold=False), fill=(100, 100, 120))
        img = Image.alpha_composite(img, badge)

    if focus_last_session:
        badge = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        bd = ImageDraw.Draw(badge)
        bx = px + 30
        by = py + mock.height - 280
        bw = mock.width - 60
        bh = 220
        bd.rounded_rectangle((bx, by, bx + bw, by + bh), radius=24, outline=MINT + (255,), width=4)
        img = Image.alpha_composite(img, badge)

    if focus_settings:
        badge = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        bd = ImageDraw.Draw(badge)
        bx = px + 24
        by = py + 180
        bw = mock.width - 48
        bh = 420
        bd.rounded_rectangle((bx, by, bx + bw, by + bh), radius=24, outline=WARNING + (255,), width=4)
        img = Image.alpha_composite(img, badge)

    return img.convert("RGB")


def render_insights_chart_scene(headline: str, sub: str) -> Image.Image:
    """Synthetic Insights tab matching in-app layout."""
    img = gradient_bg().convert("RGBA")
    draw = ImageDraw.Draw(img)

    y = 130
    y = draw_centered_text(draw, y, headline, load_font(68), WHITE)
    draw_centered_text(draw, y + 8, sub, load_font(38, bold=False), MUTED)

    card_w, card_h = 920, 980
    cx, cy = (W - card_w) // 2, 400
    draw.rounded_rectangle((cx, cy, cx + card_w, cy + card_h), radius=28, fill=SURFACE)

    draw.text((cx + 28, cy + 24), "Insights", font=load_font(42), fill=WHITE)

    # Segmented control — Month selected
    seg_y = cy + 88
    seg_labels = ["Week", "Month", "3 Months"]
    seg_w = (card_w - 56) // 3
    for i, label in enumerate(seg_labels):
        sx = cx + 28 + i * seg_w
        fill = ACCENT if label == "Month" else (35, 42, 74)
        text_fill = WHITE if label == "Month" else MUTED
        draw.rounded_rectangle((sx, seg_y, sx + seg_w - 8, seg_y + 52), radius=12, fill=fill)
        tw = draw.textlength(label, font=load_font(24))
        draw.text((sx + (seg_w - 8 - tw) / 2, seg_y + 14), label, font=load_font(24), fill=text_fill)

    # Summary pills
    pill_y = seg_y + 72
    pills = [("11m", "Avg min/day", CORAL), ("14", "Sessions", BLUE), ("12", "Days", MINT)]
    pill_w = (card_w - 56 - 24) // 3
    for i, (value, title, color) in enumerate(pills):
        px = cx + 28 + i * (pill_w + 12)
        draw.rounded_rectangle((px, pill_y, px + pill_w, pill_y + 96), radius=18, fill=(18, 22, 44))
        tw = draw.textlength(value, font=load_font(34))
        draw.text((px + (pill_w - tw) / 2, pill_y + 16), value, font=load_font(34), fill=color)
        tw = draw.textlength(title, font=load_font(18, bold=False))
        draw.text((px + (pill_w - tw) / 2, pill_y + 58), title, font=load_font(18, bold=False), fill=MUTED)

    # Chart card
    chart_top = pill_y + 120
    draw.text((cx + 28, chart_top), "Snore duration", font=load_font(30), fill=WHITE)
    draw.text((cx + 28, chart_top + 36), "Daily totals · month", font=load_font(20, bold=False), fill=MUTED)

    legend_x = cx + card_w - 250
    draw.ellipse((legend_x, chart_top + 8, legend_x + 12, chart_top + 20), fill=WARNING)
    draw.text((legend_x + 20, chart_top + 2), "Settings changes", font=load_font(18, bold=False), fill=MUTED)

    plot_x = cx + 48
    plot_y = chart_top + 78
    plot_w = card_w - 96
    plot_h = 420
    draw.rounded_rectangle((plot_x, plot_y, plot_x + plot_w, plot_y + plot_h), radius=16, fill=(14, 17, 36))

    values = CHART_MINUTES
    max_val = max(values)
    bar_gap = 8
    bar_w = (plot_w - bar_gap * (len(values) + 1)) // len(values)
    marker_index = 7

    for i, val in enumerate(values):
        bh = max(4, int((val / max_val) * (plot_h - 40)))
        bx = plot_x + bar_gap + i * (bar_w + bar_gap)
        by = plot_y + plot_h - 20 - bh
        bar_color = CORAL if i >= marker_index else (200, 90, 72)
        draw.rounded_rectangle((bx, by, bx + bar_w, plot_y + plot_h - 20), radius=6, fill=bar_color)

        if i == marker_index:
            mx = bx + bar_w // 2
            draw.ellipse((mx - 14, by - 36, mx + 14, by - 8), fill=WARNING)
            draw.text((mx - 5, by - 32), "1", font=load_font(18), fill=BG)

    # Trend line overlay (declining)
    points: list[tuple[int, int]] = []
    for i, val in enumerate(values):
        bx = plot_x + bar_gap + i * (bar_w + bar_gap) + bar_w // 2
        by = plot_y + plot_h - 20 - int((val / max_val) * (plot_h - 40))
        points.append((bx, by))
    draw.line(points, fill=MINT, width=4)

    # Before / after pill
    comp_y = plot_y + plot_h + 28
    draw.rounded_rectangle((cx + 28, comp_y, cx + card_w - 28, comp_y + 72), radius=18, fill=(18, 22, 44))
    comp_text = "23 min  →  11 min"
    tw = draw.textlength(comp_text, font=load_font(32))
    draw.text((cx + (card_w - tw) / 2, comp_y + 18), comp_text, font=load_font(32), fill=WHITE)
    arrow_x = cx + (card_w + tw) / 2 - 40
    draw.text((arrow_x, comp_y + 14), "↓", font=load_font(36), fill=MINT)

    # Premium badge
    draw.rounded_rectangle((cx + card_w - 230, cy + 24, cx + card_w - 28, cy + 68), radius=14, fill=ACCENT)
    draw.text((cx + card_w - 210, cy + 34), "Premium", font=load_font(22), fill=WHITE)

    return img.convert("RGB")


def render_end_scene() -> Image.Image:
    img = gradient_bg().convert("RGBA")
    draw = ImageDraw.Draw(img)

    icon_path = ROOT / "Snorry" / "Assets.xcassets" / "HomeAppIcon.imageset" / "HomeAppIcon.png"
    icon = Image.open(icon_path).convert("RGBA").resize((180, 180), Image.Resampling.LANCZOS)
    img.alpha_composite(icon, ((W - 180) // 2, H // 2 - 280))

    draw_centered_text(draw, H // 2 - 60, "Snorry", load_font(96), WHITE)
    draw_centered_text(draw, H // 2 + 50, "Understand your Nights", load_font(44, bold=False), BLUE)
    draw_centered_text(draw, H // 2 + 120, "Free to start · Premium for Insights", load_font(36, bold=False), MUTED)

    pill_w, pill_h = 560, 72
    px = (W - pill_w) // 2
    py = H // 2 + 210
    draw.rounded_rectangle((px, py, px + pill_w, py + pill_h), radius=36, fill=ACCENT)
    label = "Track your progress"
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
            opts.get("highlight_notification", False),
            opts.get("focus_last_session", False),
            opts.get("focus_settings", False),
        )
    if scene_type == "chart":
        return render_insights_chart_scene(opts.get("headline", ""), opts.get("sub", ""))
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
        audio = ROOT / "Snorry" / "Resources" / "Marimba intrumental.mp3"

    clips = write_frames()
    output = OUT_DIR / "snorry-reel2-progress-short.mp4"
    build_video(clips, audio, output)

    total = sum(d for _, d in clips)
    print(f"Wrote {len(clips)} scenes · {total:.1f}s")
    print(f"Video: {output}")


if __name__ == "__main__":
    main()
