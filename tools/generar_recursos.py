"""Genera los iconos y las imagenes de arranque de la aplicacion."""

import pathlib

from PIL import Image, ImageDraw

RESOURCES = pathlib.Path(__file__).resolve().parent.parent / "app" / "Resources"

BACKGROUND = (18, 28, 52, 255)
ACCENT = (232, 76, 60, 255)
TEXT = (245, 245, 245, 255)

ICON_SIZES = {
    "Icon-29.png": 29,
    "Icon-29@2x.png": 58,
    "Icon-40.png": 40,
    "Icon-40@2x.png": 80,
    "Icon-76.png": 76,
    "Icon-76@2x.png": 152,
    "Icon-83.5@2x.png": 167,
}

LAUNCH_SIZES = {
    "LaunchImage-700-Portrait.png": (768, 1024),
    "LaunchImage-700-Landscape.png": (1024, 768),
}


def draw_icon(size):
    image = Image.new("RGBA", (size, size), BACKGROUND)
    draw = ImageDraw.Draw(image)
    margin = max(1, size // 6)
    width = max(2, size // 12)
    draw.rounded_rectangle(
        [margin, margin, size - margin, size - margin],
        radius=max(1, size // 8),
        outline=ACCENT,
        width=width,
    )
    bar = max(2, size // 6)
    offset = size // 4
    draw.rectangle([offset, offset + bar, offset + bar, size - offset], fill=TEXT)
    draw.rectangle(
        [size - offset - bar, offset, size - offset, size - offset - bar], fill=TEXT
    )
    return image


def draw_launch(width, height):
    image = Image.new("RGBA", (width, height), BACKGROUND)
    draw = ImageDraw.Draw(image)
    side = min(width, height) // 6
    left = (width - side) // 2
    top = (height - side) // 2 - side // 4
    bar = side // 3
    draw.rectangle([left, top, left + bar, top + side], fill=TEXT)
    draw.rectangle(
        [width - left - bar, top, width - left, top + side - bar],
        fill=TEXT,
    )
    return image


def main():
    RESOURCES.mkdir(parents=True, exist_ok=True)
    for name, size in ICON_SIZES.items():
        draw_icon(size).save(RESOURCES / name)
        print("escrito", name)
    for name, (width, height) in LAUNCH_SIZES.items():
        draw_launch(width, height).save(RESOURCES / name)
        print("escrito", name)


if __name__ == "__main__":
    main()
