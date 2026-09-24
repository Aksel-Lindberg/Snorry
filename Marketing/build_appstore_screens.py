#!/usr/bin/env python3
"""Rebuild Snorry App Store screenshots (1290×2796) at August headline scale."""

from __future__ import annotations

import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

SRC = Path(
    "/Users/aksellindberg/Library/CloudStorage/Dropbox/LinTech/Prosjekter/"
    "Snorry App/Appstore Screenshots/21 august 2026 1290x2796/App Store - ordered"
)
OUT = Path(
    "/Users/aksellindberg/Library/CloudStorage/Dropbox/LinTech/Prosjekter/"
    "Snorry App/Appstore Screenshots/24 september 2026 1290x2796/App Store - ordered"
)
CAPTURES = Path("/tmp/snorry-appstore-captures")
ROOT = Path(__file__).resolve().parents[1]
ASSETS = Path(__file__).resolve().parent / "assets"
APP_ICON = ROOT / "Snorry/Assets.xcassets/HomeAppIcon.imageset/HomeAppIcon.png"
NUDGE_CARDS_PAIR = ASSETS / "nudge_cards_pair.png"
NUDGE_CARDS_1100 = ASSETS / "nudge_cards_1100.png"
NUDGE_CARDS_1100_2 = ASSETS / "nudge_cards_1100_2.png"
NUDGE_CARD_WATCH = ASSETS / "nudge_card_watch.png"
NUDGE_CARD_PHONE = ASSETS / "nudge_card_phone.png"
MARKETING_OUT = Path(__file__).resolve().parent

W, H = 1290, 2796
HEAD = "/System/Library/Fonts/HelveticaNeue.ttc"
WHITE = (255, 255, 255)
BLUE = (59, 130, 246)
PURPLE = (167, 139, 250)
GRAD = (BLUE, PURPLE)
SURFACE = (18, 26, 52)
TEXT_SEC = (190, 196, 220)

# August originals use ~152 pt Helvetica Neue Condensed Bold (index 4 in HelveticaNeue.ttc).
HEAD_SIZE = 152
HEAD_INDEX = 4  # Condensed Bold — lighter than index 9 (Condensed Black)
HEAD_LINE_GAP = 56  # visible gap between the two headline lines (August spacing)
SUB_SIZE = 40
PHONE_SCREEN = (250, 730, 1040, 2280)
PHONE_INTERIOR = (11, 19, 41)
# Frame 01 layout — built on a clean canvas (no August phone UI).
NUDGE_BEZEL = (230, 968, 830, 1810)  # px0, py0, pw, ph
NUDGE_SCREEN_INSET = (20, 110, 810, 1700)  # inside bezel layer coords
NUDGE_RECORDING_BOTTOM = 0.675  # crop below dBFS / Events cards


def font(size: int, index: int = 0):
    return ImageFont.truetype(HEAD, size, index=index)


F_HEAD = font(HEAD_SIZE, HEAD_INDEX)
F_SUB = font(SUB_SIZE, 10)


def text_size(draw: ImageDraw.ImageDraw, text: str, fnt) -> tuple[int, int]:
    box = draw.textbbox((0, 0), text, font=fnt)
    return box[2] - box[0], box[3] - box[1]


def erase_with_profile(im: Image.Image, y0: int, y1: int, profile_y: int = 30) -> None:
    px = im.load()
    profile = [px[x, profile_y] for x in range(im.size[0])]
    for y in range(y0, y1):
        for x in range(im.size[0]):
            px[x, y] = profile[x]


def erase_headline_zone(im: Image.Image, y0: int = 70, y1: int = 700, blend_from_y: int = 680) -> None:
    """Replace the old headline block with a smooth vertical blend (no flat seam)."""
    px = im.load()
    top = px[im.size[0] // 2, y0 + 8]
    bottom = px[im.size[0] // 2, blend_from_y]
    for y in range(y0, y1):
        t = (y - y0) / max(1, y1 - y0 - 1)
        col = tuple(int(top[i] * (1 - t) + bottom[i] * t) for i in range(3))
        for x in range(im.size[0]):
            px[x, y] = col


def draw_gradient_line(base: Image.Image, text: str, y: int, fnt, c0, c1) -> int:
    probe = ImageDraw.Draw(Image.new("RGB", (8, 8)))
    left, top, right, bottom = probe.textbbox((0, 0), text, font=fnt)
    tw, th = right - left, bottom - top
    pad = 28
    mw, mh = tw + pad * 2, th + pad * 2
    mask = Image.new("L", (mw, mh), 0)
    ImageDraw.Draw(mask).text((pad - left, pad - top), text, font=fnt, fill=255)
    x = (W - tw) // 2 - pad
    if c0 == c1:
        solid = Image.new("RGB", (mw, mh), c0)
        base.paste(solid, (x, y), mask)
        return th
    grad = Image.new("RGB", (mw, mh))
    gp = grad.load()
    for gx in range(mw):
        t = gx / max(1, mw - 1)
        col = tuple(int(c0[i] * (1 - t) + c1[i] * t) for i in range(3))
        for gy in range(mh):
            gp[gx, gy] = col
    base.paste(grad, (x, y), mask)
    return th


def glow(base: Image.Image, y: int) -> None:
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    cx = W // 2
    d.rounded_rectangle((cx - 150, y, cx + 150, y + 3), radius=2, fill=(140, 120, 255, 230))
    layer = layer.filter(ImageFilter.GaussianBlur(8))
    d2 = ImageDraw.Draw(layer)
    d2.rounded_rectangle((cx - 90, y, cx + 90, y + 2), radius=1, fill=(220, 220, 255, 255))
    base.paste(Image.alpha_composite(base.convert("RGBA"), layer).convert("RGB"))


def headline(
    base: Image.Image,
    lines: list[tuple[str, tuple]],
    sub: str | None = None,
    top: int = 130,
) -> None:
    y = top
    for text, color in lines:
        if isinstance(color[0], tuple):
            th = draw_gradient_line(base, text, y, F_HEAD, color[0], color[1])
        else:
            th = draw_gradient_line(base, text, y, F_HEAD, color, color)
        y += th + HEAD_LINE_GAP
    if sub is None:
        return
    y += 30
    draw = ImageDraw.Draw(base)
    tw, th = text_size(draw, sub, F_SUB)
    draw.text(((W - tw) // 2, y), sub, font=F_SUB, fill=(230, 232, 245))
    glow(base, y + th + 24)


def gradient_background() -> Image.Image:
    im = Image.new("RGB", (W, H), (6, 8, 22))
    glow_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow_layer)
    gd.ellipse((700, 200, 1500, 1100), fill=(70, 40, 160, 70))
    gd.ellipse((-200, 1400, 500, 2200), fill=(30, 50, 140, 50))
    return Image.alpha_composite(im.convert("RGBA"), glow_layer.filter(ImageFilter.GaussianBlur(40))).convert("RGB")


def erase_callout_column(im: Image.Image, x0: int = 938, x1: int = W, y0: int = 760, y1: int = 2480) -> None:
    """Remove August side callouts using the clean left background gradient."""
    px = im.load()
    sample_x = 120
    for y in range(y0, min(y1, im.size[1])):
        col = px[sample_x, y]
        for x in range(x0, x1):
            px[x, y] = col


def crop_recording_capture(shot: Image.Image) -> Image.Image:
    """Trim status bar and stop button — keep greeting through metrics for the marketing frame."""
    w, h = shot.size
    top = int(h * 0.08)
    bottom = int(h * 0.62)
    return shot.crop((0, top, w, bottom))


def crop_recording_bottom_only(shot: Image.Image) -> Image.Image:
    """Keep the full live screen — trim only the stop button at the bottom."""
    w, h = shot.size
    bottom = int(h * 0.885)
    return shot.crop((0, 0, w, bottom))


def crop_recording_through_metrics(shot: Image.Image) -> Image.Image:
    """Keep the real recording UI through the loudness / events cards — cut below that."""
    w, h = shot.size
    bottom = int(h * NUDGE_RECORDING_BOTTOM)
    return shot.crop((0, 0, w, bottom))


def erase_phone_screen_zone(
    im: Image.Image,
    screen_rect: tuple[int, int, int, int],
    fill: tuple[int, int, int] = PHONE_INTERIOR,
) -> None:
    """Paint over the entire phone screen so August UI cannot bleed through."""
    x0, y0, x1, y1 = screen_rect
    draw = ImageDraw.Draw(im)
    draw.rectangle((x0, y0, x1, y1), fill=fill)


def trim_content_bounds(im: Image.Image, threshold: int = 18) -> Image.Image:
    """Crop away empty/black margins from a reference asset."""
    px = im.load()
    w, h = im.size
    min_x, min_y, max_x, max_y = w, h, 0, 0
    for y in range(h):
        for x in range(w):
            if sum(px[x, y][:3]) > threshold * 3:
                min_x = min(min_x, x)
                min_y = min(min_y, y)
                max_x = max(max_x, x)
                max_y = max(max_y, y)
    if max_x <= min_x or max_y <= min_y:
        return im
    pad = 4
    return im.crop((
        max(0, min_x - pad),
        max(0, min_y - pad),
        min(w, max_x + pad + 1),
        min(h, max_y + pad + 1),
    ))


def key_black_to_alpha(im: Image.Image, threshold: int = 24) -> Image.Image:
    """Make black backdrops transparent so cards sit cleanly on the gradient."""
    rgba = im.convert("RGBA")
    px = rgba.load()
    for y in range(rgba.height):
        for x in range(rgba.width):
            r, g, b, _a = px[x, y]
            if r <= threshold and g <= threshold and b <= threshold:
                px[x, y] = (0, 0, 0, 0)
    return rgba


def nudge_background() -> Image.Image:
    """Dark starfield + glow — matches the attached concept mockup."""
    im = Image.new("RGB", (W, H), (4, 6, 18))
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse((360, 820, 1180, 2300), fill=(55, 35, 110, 70))
    gd.ellipse((80, 1200, 620, 2300), fill=(25, 45, 95, 50))
    gd.ellipse((820, 300, 1280, 900), fill=(40, 25, 80, 35))
    im = Image.alpha_composite(im.convert("RGBA"), glow.filter(ImageFilter.GaussianBlur(55))).convert("RGB")

    rng = random.Random(42)
    stars = ImageDraw.Draw(im)
    for _ in range(140):
        x, y = rng.randint(0, W - 1), rng.randint(0, H - 1)
        b = rng.randint(70, 190)
        stars.point((x, y), fill=(b, b, min(255, b + 25)))

    wave = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    wd = ImageDraw.Draw(wave)
    for x in range(0, W, 5):
        y = 1120 + int(16 * math.sin(x / 28.0))
        wd.ellipse((x, y, x + 4, y + 4), fill=(255, 255, 255, 55))
    im.paste(Image.alpha_composite(im.convert("RGBA"), wave.filter(ImageFilter.GaussianBlur(2))).convert("RGB"))
    return im


def prepare_nudge_cards_1100() -> Image.Image:
    """Load the latest 1100-style card pair (Smartwatch + iPhone)."""
    path = NUDGE_CARDS_1100_2 if NUDGE_CARDS_1100_2.exists() else NUDGE_CARDS_1100
    if not path.exists():
        raise FileNotFoundError(f"Missing nudge card asset in {ASSETS}")

    cards = Image.open(path).convert("RGB")
    if path == NUDGE_CARDS_1100:
        # Legacy asset — rename label and drop redundant lock-screen icon.
        d = ImageDraw.Draw(cards)
        label_bg = cards.getpixel((80, 284))
        d.rectangle((52, 272, 236, 294), fill=label_bg)
        d.text((58, 275), "Smart watch", font=font(16, 1), fill=(167, 139, 250))
        d.rounded_rectangle((532, 114, 598, 178), radius=12, fill=(245, 245, 247))
    else:
        # v2 asset — remove redundant notification icon on the iPhone banner.
        d = ImageDraw.Draw(cards)
        d.rounded_rectangle((532, 114, 598, 178), radius=12, fill=(245, 245, 247))

    cards = trim_content_bounds(cards)
    return key_black_to_alpha(cards)


def apply_slight_tilt(im: Image.Image, shear: float = 0.068) -> Image.Image:
    """Gentle perspective skew so the phone feels dimensional, not flat."""
    w, h = im.size
    pad = int(h * abs(shear)) + 20
    out_w, out_h = w + pad * 2, h + 24
    return im.transform(
        (out_w, out_h),
        Image.AFFINE,
        (1, -shear, pad + int(h * shear * 0.35), 0, 1, 8),
        resample=Image.Resampling.BICUBIC,
        fillcolor=(0, 0, 0, 0),
    )


def crop_session_detail_capture(shot: Image.Image) -> Image.Image:
    """Trim tab bar; keep nav + Snore Clock + Sound Events for the marketing frame."""
    w, h = shot.size
    top = int(h * 0.0)
    bottom = int(h * 0.905)
    return shot.crop((0, top, w, bottom))


def compose_straight_phone(
    capture_path: Path,
    crop_fn,
) -> Image.Image:
    """Bezel + cropped simulator screen — no tilt (matches Frame 1 delivery)."""
    _px0, _py0, pw, ph = NUDGE_BEZEL
    sx0, sy0, sx1, sy1 = NUDGE_SCREEN_INSET
    layer = Image.new("RGBA", (pw + 40, ph + 40), (0, 0, 0, 0))
    draw_phone_bezel(layer, px0=20, py0=20, pw=pw, ph=ph)

    if capture_path.exists():
        sw, sh = sx1 - sx0, sy1 - sy0
        shot = crop_fn(Image.open(capture_path).convert("RGB"))
        shot = shot.resize((sw, sh), Image.Resampling.LANCZOS)
        mask = Image.new("L", (sw, sh), 0)
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, sw - 1, sh - 1), radius=54, fill=255)
        layer.paste(shot, (20 + sx0, 20 + sy0), mask)
    else:
        print("warning: capture missing for straight phone:", capture_path)

    return layer


def compose_tilted_phone(capture_path: Path) -> Image.Image:
    """Build bezel + real recording screen, then tilt as one unit."""
    px0, py0, pw, ph = NUDGE_BEZEL
    sx0, sy0, sx1, sy1 = NUDGE_SCREEN_INSET
    layer = Image.new("RGBA", (pw + 40, ph + 40), (0, 0, 0, 0))
    draw_phone_bezel(layer, px0=20, py0=20, pw=pw, ph=ph)

    if capture_path.exists():
        sw, sh = sx1 - sx0, sy1 - sy0
        shot = crop_recording_through_metrics(Image.open(capture_path).convert("RGB"))
        shot = shot.resize((sw, sh), Image.Resampling.LANCZOS)
        mask = Image.new("L", (sw, sh), 0)
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, sw - 1, sh - 1), radius=54, fill=255)
        layer.paste(shot, (20 + sx0, 20 + sy0), mask)

    return apply_slight_tilt(layer)


def paste_nudge_cards_row(base: Image.Image, cards: Image.Image, top_y: int, target_width: int) -> None:
    """Paste the full-width nudge card strip centred above the phone."""
    scale = target_width / cards.width
    tw, th = target_width, max(1, int(cards.height * scale))
    scaled = cards.resize((tw, th), Image.Resampling.LANCZOS)
    x = (W - tw) // 2

    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.rounded_rectangle((x + 4, top_y + 8, x + tw + 4, top_y + th + 8), radius=24, fill=(0, 0, 0, 90))
    base.paste(Image.alpha_composite(base.convert("RGBA"), shadow.filter(ImageFilter.GaussianBlur(10))).convert("RGB"))
    base.paste(scaled, (x, top_y), scaled)


def load_card_top_visual(path: Path, top_fraction: float = 0.56) -> Image.Image:
    """Top portion of a reference card — device visual without the caption block."""
    if not path.exists():
        raise FileNotFoundError(f"Missing nudge asset: {path}")
    im = trim_content_bounds(Image.open(path).convert("RGB"))
    cut = max(1, int(im.height * top_fraction))
    return key_black_to_alpha(im.crop((0, 0, im.width, cut)))


def paste_rgba_asset(
    base: Image.Image,
    asset: Image.Image,
    center_x: int,
    top_y: int,
    target_width: int,
) -> None:
    scale = target_width / asset.width
    tw, th = target_width, max(1, int(asset.height * scale))
    scaled = asset.resize((tw, th), Image.Resampling.LANCZOS)
    x = center_x - tw // 2

    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.rounded_rectangle((x + 5, top_y + 8, x + tw + 5, top_y + th + 8), radius=20, fill=(0, 0, 0, 85))
    base.paste(Image.alpha_composite(base.convert("RGBA"), shadow.filter(ImageFilter.GaussianBlur(8))).convert("RGB"))
    base.paste(scaled, (x, top_y), scaled)


def paste_nudge_recording(base: Image.Image, capture_path: Path, screen_rect: tuple[int, int, int, int]) -> None:
    """Paste the live recording capture into the phone screen area."""
    if not capture_path.exists():
        print("skip paste, missing", capture_path)
        return
    x0, y0, x1, y1 = screen_rect
    tw, th = x1 - x0, y1 - y0
    shot = crop_recording_capture(Image.open(capture_path).convert("RGB"))
    shot = shot.resize((tw, th), Image.Resampling.LANCZOS)
    mask = Image.new("L", (tw, th), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, tw - 1, th - 1), radius=54, fill=255)
    base.paste(shot, (x0, y0), mask)


def retitle(
    src_name: str,
    out_name: str,
    cover_bottom: int,
    lines,
    sub: str,
    top: int = 130,
    extra_erase: tuple[int, int] | None = None,
) -> Image.Image:
    im = Image.open(SRC / src_name).convert("RGB")
    erase_with_profile(im, 70, cover_bottom)
    if extra_erase:
        erase_with_profile(im, extra_erase[0], extra_erase[1])
    headline(im, lines, sub, top=top)
    OUT.mkdir(parents=True, exist_ok=True)
    im.save(OUT / out_name, "PNG")
    print("wrote", out_name)
    return im


def round_rect(draw, box, radius, fill, outline=None, width=1):
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def fill_phone_band(im: Image.Image, x0: int, y0: int, x1: int, y1: int, sample: tuple[int, int]) -> None:
    px = im.load()
    sx, sy = sample
    col = px[sx, sy]
    draw = ImageDraw.Draw(im)
    draw.rectangle((x0, y0, x1, y1), fill=col)


def paste_sim_screen(
    base: Image.Image,
    capture_path: Path,
    screen_rect: tuple[int, int, int, int] = PHONE_SCREEN,
    radius: int = 58,
) -> None:
    if not capture_path.exists():
        print("skip paste, missing", capture_path)
        return
    shot = Image.open(capture_path).convert("RGB")
    x0, y0, x1, y1 = screen_rect
    tw, th = x1 - x0, y1 - y0
    shot = shot.resize((tw, th), Image.Resampling.LANCZOS)
    mask = Image.new("L", (tw, th), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, tw - 1, th - 1), radius=radius, fill=255)
    base.paste(shot, (x0, y0), mask)


def replace_phone_screen(base: Image.Image, capture_path: Path, sample: tuple[int, int] = (400, 900)) -> None:
    x0, y0, x1, y1 = PHONE_SCREEN
    fill_phone_band(base, x0, y0, x1, y1, sample)
    paste_sim_screen(base, capture_path)


def draw_phone_bezel(im: Image.Image, px0: int = 230, py0: int = 620, pw: int = 830, ph: int = 1680) -> None:
    d = ImageDraw.Draw(im)
    round_rect(d, (px0 - 14, py0 - 14, px0 + pw + 14, py0 + ph + 14), 78, (28, 28, 32))
    round_rect(d, (px0, py0, px0 + pw, py0 + ph), 64, (10, 12, 28))


def nudge_frame() -> None:
    """Frame 01 — 1100 card style, real recording screen (bottom crop), slight phone tilt."""
    im = nudge_background()

    headline(
        im,
        [("GET A NUDGE", WHITE), ("WHEN YOU SNORE", GRAD)],
        sub=None,
        top=130,
    )

    capture = CAPTURES / "recording.png"
    if not capture.exists():
        print("warning: recording.png missing, falling back to tonight.png")
        capture = CAPTURES / "tonight.png"

    cards = prepare_nudge_cards_1100()
    paste_nudge_cards_row(im, cards, top_y=508, target_width=1100)

    phone = compose_tilted_phone(capture)
    phone_x = (W - phone.width) // 2 - 10
    phone_y = 968
    im.paste(phone, (phone_x, phone_y), phone)

    OUT.mkdir(parents=True, exist_ok=True)
    out_name = "01_a-nudge-when-you-snore.png"
    im.save(OUT / out_name, "PNG")
    im.save(MARKETING_OUT / out_name, "PNG")
    print("wrote", out_name)


def habits_frame() -> None:
    im = gradient_background()

    headline(
        im,
        [("WHAT CHANGES", WHITE), ("YOUR SNORING?", GRAD)],
        "Log a habit. Compare the nights.",
        top=130,
    )

    draw_phone_bezel(im)
    replace_phone_screen(im, CAPTURES / "habits.png", sample=(400, 900))

    OUT.mkdir(parents=True, exist_ok=True)
    im.save(OUT / "03_what-changes-your-snoring.png", "PNG")
    print("wrote 03_what-changes-your-snoring.png")


def replay_frame() -> None:
    """Frame 02 — session replay on the same clean canvas as Frame 01."""
    im = nudge_background()
    headline(
        im,
        [("SEE WHEN", WHITE), ("YOU SNORED", GRAD)],
        sub=None,
        top=130,
    )

    capture = CAPTURES / "session_detail.png"
    phone = compose_straight_phone(capture, crop_session_detail_capture)
    phone_x = (W - phone.width) // 2 - 10
    phone_y = 968
    im.paste(phone, (phone_x, phone_y), phone)

    OUT.mkdir(parents=True, exist_ok=True)
    out_name = "02_see-when-you-snored.png"
    im.save(OUT / out_name, "PNG")
    im.save(MARKETING_OUT / out_name, "PNG")
    print("wrote", out_name)


def insights_frame() -> None:
    im = Image.open(SRC / "05_Track-Habits-Find_Triggers.png").convert("RGB")
    erase_with_profile(im, 70, 700)
    headline(im, [("WHICH HABITS", WHITE), ("TRACK", GRAD)], "One month. Habits next to your nights.")

    capture = CAPTURES / "insights.png"
    if capture.exists():
        replace_phone_screen(im, capture)
    else:
        d = ImageDraw.Draw(im)
        fill_phone_band(im, 470, 1160, 820, 1545, (645, 1120))
        card = (470, 1168, 820, 1510)
        cx0, cy0, cx1, cy1 = card
        round_rect(d, card, 22, (16, 22, 48), outline=(70, 90, 150), width=1)
        d.text((cx0 + 18, cy0 + 16), "Had caffeine late", font=font(28, 1), fill=WHITE)
        d.text((cx0 + 18, cy0 + 52), "Average snore minutes when logged", font=font(16, 0), fill=TEXT_SEC)

        bar_top = cy0 + 92
        d.text((cx0 + 36, bar_top), "Logged", font=font(20, 1), fill=(255, 180, 80))
        d.text((cx0 + 250, bar_top), "Not logged", font=font(20, 1), fill=BLUE)
        d.rounded_rectangle((cx0 + 36, bar_top + 34, cx0 + 120, bar_top + 170), radius=12, fill=(255, 150, 70))
        d.rounded_rectangle((cx0 + 250, bar_top + 84, cx0 + 334, bar_top + 170), radius=12, fill=(70, 130, 255))
        d.text((cx0 + 52, bar_top + 182), "22m", font=font(24, 1), fill=WHITE)
        d.text((cx0 + 262, bar_top + 182), "9m", font=font(24, 1), fill=WHITE)

    im.save(OUT / "04_which-habits-track.png", "PNG")
    print("wrote 04_which-habits-track.png")


def exercises_frame() -> None:
    im = Image.open(SRC / "07_train-your-tongue.png").convert("RGB")
    erase_with_profile(im, 70, 880)
    headline(
        im,
        [("TRAIN YOUR", WHITE), ("AIRWAY", GRAD)],
        "Tongue and throat exercises you can log.",
        top=170,
    )
    erase_with_profile(im, 640, 760)
    exercises_screen = (252, 960, 1038, 2790)
    x0, y0, x1, y1 = exercises_screen
    fill_phone_band(im, x0, y0, x1, y1, (645, 1090))
    paste_sim_screen(im, CAPTURES / "exercises.png", exercises_screen)

    im.save(OUT / "06_train-your-airway.png", "PNG")
    print("wrote 06_train-your-airway.png")


def main() -> None:
    nudge_frame()
    replay_frame()
    habits_frame()
    insights_frame()
    retitle(
        "03_gentle-alerts.png",
        "05_on-your-wrist-or-as-a-tone.png",
        880,
        [("ON YOUR WRIST,", WHITE), ("OR AS A TONE", GRAD)],
        "Push, Apple Watch, or sound.",
        top=150,
        extra_erase=(640, 760),
    )
    exercises_frame()


if __name__ == "__main__":
    main()
