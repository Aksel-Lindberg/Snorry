#!/usr/bin/env python3
"""Build Reel 1 marketing short from on-hand Snorry assets."""

from __future__ import annotations

import math
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
ASSETS = Path("/Users/aksellindberg/.cursor/projects/Users-aksellindberg-Developer-Snorry/assets")
OUT_DIR = ROOT / "Marketing" / "reel1-short"
FRAMES_DIR = OUT_DIR / "frames"

W, H = 1080, 1920
FPS = 30

# Brand colors
BG = (10, 11, 30)
ACCENT = (124, 58, 237)
BLUE = (96, 165, 250)
CORAL = (255, 115, 89)
WHITE = (255, 255, 255)
MUTED = (180, 184, 205)

SCENES: list[tuple[float, str, dict]] = [
    (2.0, "hook", {"headline": "They said you snore.", "sub": ""}),
    (2.0, "hook", {"headline": "You said…", "sub": "you don't.", "sub_color": CORAL}),
    (2.5, "phone", {
        "image": ASSETS / "simulator_screenshot_896BBF27-5B66-4E4E-92C1-C63B3D6C82AE-caa6dfae-f7a7-465a-97ce-1048d3980495.png",
        "headline": "Meet Snorry",
        "sub": "Tap to start recording",
    }),
    (2.5, "phone", {
        "image": ASSETS / "telegram-cloud-photo-size-4-5931631495896305231-y-a80dcbee-7bd5-444a-83f9-a3452a8646d0.png",
        "headline": "Knows when it's snoring",
        "sub": "Live detection all night",
    }),
    (2.5, "phone", {
        "image": ASSETS / "telegram-cloud-photo-size-4-5931631495896305231-y-a80dcbee-7bd5-444a-83f9-a3452a8646d0.png",
        "headline": "Gentle alert",
        "sub": "Push when snoring starts",
        "highlight_notification": True,
    }),
    (2.0, "text", {"headline": "Alerts stop", "sub": "when you stop.", "sub_color": BLUE}),
    (3.0, "phone", {
        "image": ASSETS / "simulator_screenshot_896BBF27-5B66-4E4E-92C1-C63B3D6C82AE-caa6dfae-f7a7-465a-97ce-1048d3980495.png",
        "headline": "Wake up to the truth",
        "sub": "Sleep · Events · Snore time",
        "focus_last_session": True,
    }),
    (3.0, "phone", {
        "image": ASSETS / "telegram-cloud-photo-size-4-5926895444048940616-y-3372e322-4a91-4173-b231-9d079002cfcd.png",
        "headline": "Every night, mapped",
        "sub": "Snore Clock & timeline",
    }),
    (2.5, "phone", {
        "image": ASSETS / "telegram-cloud-photo-size-4-5935820794111921748-y-7e421b99-cecf-48a4-9111-2df39dd5b950.png",
        "headline": "Share clips",
        "sub": "AirDrop · Messages · Save",
    }),
    (8.0, "end", {}),
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
    lines = wrap_text(text, font, max_width)
    bbox_h = sum(font.size + line_gap for _ in lines) - line_gap
    cy = y
    for line in lines:
        tw = draw.textlength(line, font=font)
        draw.text(((W - tw) / 2, cy), line, font=font, fill=fill)
        cy += font.size + line_gap
    return cy


def crop_phone_content(img: Image.Image) -> Image.Image:
    """Remove simulator chrome; keep phone screen content."""
    w, h = img.size
    if w > h * 0.55:
        # iPad / wide capture — center crop to phone-ish aspect
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
    thumb = ASSETS / "snorry-reel1-thumbnail-proof.png"
    if thumb.exists():
        bg = Image.open(thumb).convert("RGB").resize((W, H), Image.Resampling.LANCZOS)
        bg = bg.filter(ImageFilter.GaussianBlur(2))
        overlay = Image.new("RGBA", (W, H), (10, 11, 30, 140))
        bg = Image.alpha_composite(bg.convert("RGBA"), overlay).convert("RGB")
    else:
        bg = gradient_bg()

    draw = ImageDraw.Draw(bg)
    h_font = load_font(88)
    s_font = load_font(64)

    y = 220
    draw_centered_text(draw, y, headline, h_font, WHITE)
    if sub:
        draw_centered_text(draw, y + 200, sub, s_font, sub_color)
    return bg


def render_phone_scene(
    screenshot_path: Path,
    headline: str,
    sub: str,
    highlight_notification: bool = False,
    focus_last_session: bool = False,
) -> Image.Image:
    img = gradient_bg().convert("RGBA")
    draw = ImageDraw.Draw(img)

    h_font = load_font(68)
    s_font = load_font(40, bold=False)
    y = 150
    y = draw_centered_text(draw, y, headline, h_font, WHITE)
    draw_centered_text(draw, y + 10, sub, s_font, MUTED)

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
        bd.rounded_rectangle((bx, by, bx + bw, by + bh), radius=24, outline=ACCENT + (255,), width=4)
        img = Image.alpha_composite(img, badge)

    return img.convert("RGB")


def render_end_scene() -> Image.Image:
    img = gradient_bg().convert("RGBA")
    draw = ImageDraw.Draw(img)

    icon_path = ROOT / "Snorry" / "Assets.xcassets" / "HomeAppIcon.imageset" / "HomeAppIcon.png"
    icon = Image.open(icon_path).convert("RGBA")
    size = 180
    icon = icon.resize((size, size), Image.Resampling.LANCZOS)
    img.alpha_composite(icon, ((W - size) // 2, H // 2 - 260))

    draw_centered_text(draw, H // 2 - 40, "Snorry", load_font(96), WHITE)
    draw_centered_text(draw, H // 2 + 70, "Understand your Nights", load_font(44, bold=False), BLUE)
    draw_centered_text(draw, H // 2 + 150, "Free on the App Store", load_font(40, bold=False), MUTED)

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
        return render_hook_scene(opts.get("headline", ""), opts.get("sub", ""), opts.get("sub_color", ACCENT))
    if scene_type == "text":
        return render_text_scene(opts.get("headline", ""), opts.get("sub", ""), opts.get("sub_color", BLUE))
    if scene_type == "phone":
        return render_phone_scene(
            opts["image"],
            opts.get("headline", ""),
            opts.get("sub", ""),
            opts.get("highlight_notification", False),
            opts.get("focus_last_session", False),
        )
    if scene_type == "end":
        return render_end_scene()
    raise ValueError(scene_type)


def write_frames() -> list[tuple[Path, float]]:
    FRAMES_DIR.mkdir(parents=True, exist_ok=True)
    for old in FRAMES_DIR.glob("*.png"):
        old.unlink()

    clips: list[tuple[Path, float]] = []
    index = 0
    for duration, scene_type, opts in SCENES:
        frame = render_scene(scene_type, opts)
        path = FRAMES_DIR / f"scene_{index:02d}.png"
        frame.save(path, quality=95)
        clips.append((path, duration))
        index += 1
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
            f"[1:a]atrim=0:{total_duration:.3f},asetpts=PTS-STARTPTS,volume=0.35[a]",
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
    output = OUT_DIR / "snorry-reel1-proof-short.mp4"
    build_video(clips, audio, output)

    total = sum(d for _, d in clips)
    print(f"Wrote {len(clips)} scenes · {total:.1f}s")
    print(f"Video: {output}")


if __name__ == "__main__":
    main()
