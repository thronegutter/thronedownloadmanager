"""Build the desktop and browser extension icon sizes from their artwork in art/.

Run from the repository root: python -I tools/icon/build_icon.py
"""

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
APP_SRC = ROOT / "art" / "Throne Download Manager.png"
EXT_SRC = ROOT / "art" / "Mister Download Manager.png"
APP = ROOT / "crates" / "app" / "assets" / "icons" / "app"
EXT = ROOT / "extension" / "icons"
SIZES = [16, 20, 24, 32, 48, 64, 128, 256]
# The original artwork's globe, hat and moustache, in source pixels.
TIGHT = (330, 60, 1160, 1110)


def opaque(im: Image.Image) -> Image.Image:
    r, g, b, a = im.split()
    return Image.merge("RGBA", (r, g, b, a.point(lambda v: 255 if v >= 240 else v)))


def square(im: Image.Image, box, pad: float) -> Image.Image:
    c = im.crop(box)
    w, h = c.size
    s = int(max(w, h) * (1 + 2 * pad))
    out = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    out.paste(c, ((s - w) // 2, (s - h) // 2), c)
    return out


def build_app() -> None:
    with Image.open(APP_SRC) as source:
        app = source.convert("RGBA")
    icons = {}
    for size in SIZES:
        icons[size] = app.resize((size, size), Image.LANCZOS)
        icons[size].save(APP / f"mdm-{size}.png")
    icons[256].save(
        APP / "mdm.ico",
        sizes=[(s, s) for s in SIZES],
        append_images=[icons[s] for s in SIZES if s != 256],
    )


def build_extension() -> None:
    # Make the original artwork's nearly opaque fills solid.
    with Image.open(EXT_SRC) as source:
        src = opaque(source.convert("RGBA"))
    bbox = src.getchannel("A").point(lambda v: 255 if v > 16 else 0).getbbox()
    full = square(src, bbox, 0.02)
    tight = square(src, TIGHT, 0.0)
    for size in (16, 32, 48, 128):
        base = tight if size <= 32 else full
        base.resize((size, size), Image.LANCZOS).save(EXT / f"icon-{size}.png")


if __name__ == "__main__":
    build_app()
    build_extension()
    print("wrote", ", ".join(str(s) for s in SIZES), "+ mdm.ico + extension icons")
