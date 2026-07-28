#!/usr/bin/env python3

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[2]
SOURCE_MARK_PATH = ROOT / "assets/branding/speed_cat_mark_source.png"
MARK_PATH = ROOT / "assets/branding/speed_cat_mark.png"

INDIGO_A = (118, 103, 255, 255)
INDIGO_B = (49, 85, 216, 255)
WHITE = (255, 255, 255)
YELLOW = (255, 215, 94)
TRAIL = (198, 205, 255)
PALETTE = (WHITE, YELLOW, TRAIL)
MAC_MARK_RATIO = 1.04
SQUARE_MARK_RATIO = 1.12
CAT_HORIZONTAL_OFFSET = -35
RESAMPLE = Image.Resampling.LANCZOS

MAC_SIZES = [16, 32, 64, 128, 256, 512, 1024]
ANDROID = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}
IOS = {
    "Icon-App-20x20@1x.png": 20,
    "Icon-App-20x20@2x.png": 40,
    "Icon-App-20x20@3x.png": 60,
    "Icon-App-29x29@1x.png": 29,
    "Icon-App-29x29@2x.png": 58,
    "Icon-App-29x29@3x.png": 87,
    "Icon-App-40x40@1x.png": 40,
    "Icon-App-40x40@2x.png": 80,
    "Icon-App-40x40@3x.png": 120,
    "Icon-App-60x60@2x.png": 120,
    "Icon-App-60x60@3x.png": 180,
    "Icon-App-76x76@1x.png": 76,
    "Icon-App-76x76@2x.png": 152,
    "Icon-App-83.5x83.5@2x.png": 167,
    "Icon-App-1024x1024@1x.png": 1024,
}


def gradient(size: int) -> Image.Image:
    horizontal = Image.linear_gradient("L").rotate(90, expand=False)
    vertical = Image.linear_gradient("L")
    diagonal = ImageChops.add(horizontal, vertical, scale=2.0)
    diagonal = diagonal.resize((size, size), RESAMPLE)
    start = Image.new("RGBA", (size, size), INDIGO_A)
    end = Image.new("RGBA", (size, size), INDIGO_B)
    return Image.composite(end, start, diagonal)


def fitted_mark(
    mark: Image.Image,
    canvas_size: int,
    ratio: float,
) -> Image.Image:
    side = round(canvas_size * ratio)
    resized = mark.resize((side, side), RESAMPLE)
    layer = Image.new("RGBA", (canvas_size, canvas_size))
    offset = (canvas_size - side) // 2
    layer.alpha_composite(resized, (offset, offset))
    return layer


def square_icon(mark: Image.Image, size: int) -> Image.Image:
    image = gradient(size)
    image.alpha_composite(fitted_mark(mark, size, ratio=SQUARE_MARK_RATIO))
    return image.convert("RGB")


def mac_icon(mark: Image.Image, size: int) -> Image.Image:
    scale = 4
    work = size * scale
    canvas = Image.new("RGBA", (work, work))
    tile_side = round(work * 0.84)
    tile_xy = (work - tile_side) // 2
    tile_box = (tile_xy, tile_xy, tile_xy + tile_side, tile_xy + tile_side)

    mask = Image.new("L", (work, work))
    ImageDraw.Draw(mask).rounded_rectangle(
        tile_box,
        radius=round(tile_side * 0.24),
        fill=255,
    )

    shadow_alpha = mask.filter(ImageFilter.GaussianBlur(radius=round(work * 0.025)))
    shadow = Image.new("RGBA", (work, work), (23, 31, 89, 0))
    shadow.putalpha(shadow_alpha.point(lambda value: round(value * 0.28)))
    canvas.alpha_composite(shadow, (0, round(work * 0.012)))

    tile = gradient(work)
    tile.putalpha(mask)
    canvas.alpha_composite(tile)
    canvas.alpha_composite(fitted_mark(mark, work, ratio=MAC_MARK_RATIO))
    return canvas.resize((size, size), RESAMPLE)


def save_png(image: Image.Image, relative: str) -> None:
    path = ROOT / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, optimize=True)


def color_distance(
    left: tuple[int, int, int],
    right: tuple[int, int, int],
) -> int:
    return sum((a - b) ** 2 for a, b in zip(left, right))


def nearest_brand_color(rgb: tuple[int, int, int]) -> tuple[int, int, int]:
    return min(PALETTE, key=lambda target: color_distance(rgb, target))


def color_class_mask(
    image: Image.Image,
    target: tuple[int, int, int],
) -> Image.Image:
    source = image.convert("RGBA")
    mask = Image.new("L", source.size)
    source_pixels = source.load()
    mask_pixels = mask.load()
    for y in range(source.height):
        for x in range(source.width):
            red, green, blue, alpha = source_pixels[x, y]
            if (
                alpha >= 32
                and nearest_brand_color((red, green, blue)) == target
            ):
                mask_pixels[x, y] = alpha
    return mask


def build_brand_layer(
    mark: Image.Image,
    color: tuple[int, int, int],
) -> Image.Image:
    mask = color_class_mask(mark, color)
    layer = Image.new("RGBA", mark.size, (*color, 255))
    layer.putalpha(mask)
    return layer


def connected_component_count(
    mask: Image.Image,
    threshold: int = 32,
) -> int:
    grayscale = mask.convert("L")
    pixels = grayscale.load()
    width, height = grayscale.size
    visited = bytearray(width * height)
    count = 0

    for y in range(height):
        for x in range(width):
            start_index = y * width + x
            if visited[start_index] or pixels[x, y] < threshold:
                continue
            count += 1
            pending = [(x, y)]
            visited[start_index] = 1
            while pending:
                current_x, current_y = pending.pop()
                for neighbor_x, neighbor_y in (
                    (current_x - 1, current_y),
                    (current_x + 1, current_y),
                    (current_x, current_y - 1),
                    (current_x, current_y + 1),
                ):
                    if not (
                        0 <= neighbor_x < width and 0 <= neighbor_y < height
                    ):
                        continue
                    neighbor_index = neighbor_y * width + neighbor_x
                    if (
                        visited[neighbor_index]
                        or pixels[neighbor_x, neighbor_y] < threshold
                    ):
                        continue
                    visited[neighbor_index] = 1
                    pending.append((neighbor_x, neighbor_y))
    return count


def build_refined_mark(source: Image.Image) -> Image.Image:
    source = source.convert("RGBA")
    refined = Image.new("RGBA", source.size)
    source_pixels = source.load()
    refined_pixels = refined.load()
    for y in range(source.height):
        for x in range(source.width):
            red, green, blue, alpha = source_pixels[x, y]
            if alpha == 0:
                continue
            if nearest_brand_color((red, green, blue)) == TRAIL:
                continue
            destination_x = x + CAT_HORIZONTAL_OFFSET
            if 0 <= destination_x < source.width:
                refined_pixels[destination_x, y] = (
                    red,
                    green,
                    blue,
                    alpha,
                )
    return refined


def macos_template(mark: Image.Image) -> Image.Image:
    template_source = mark.resize((128, 128), RESAMPLE)

    alpha = Image.new("L", (128, 128))
    source_pixels = template_source.load()
    alpha_pixels = alpha.load()
    for y in range(128):
        for x in range(128):
            red, green, blue, source_alpha = source_pixels[x, y]
            if source_alpha < 32:
                continue
            rgb = (red, green, blue)
            nearest = min(
                PALETTE,
                key=lambda target: color_distance(rgb, target),
            )
            if nearest == WHITE:
                alpha_pixels[x, y] = source_alpha

    template = Image.new("RGBA", (128, 128), (255, 255, 255, 0))
    template.putalpha(alpha)
    return template


def main() -> None:
    source = Image.open(SOURCE_MARK_PATH).convert("RGBA")
    mark = build_refined_mark(source)

    save_png(mark, "assets/branding/speed_cat_mark.png")
    save_png(mark, "assets/images/brand_mark.png")
    save_png(
        build_brand_layer(mark, WHITE),
        "assets/images/brand_cat.png",
    )
    save_png(
        build_brand_layer(mark, YELLOW),
        "assets/images/brand_bolt.png",
    )
    save_png(mac_icon(mark, 1024), "assets/images/brand_logo.png")
    save_png(mac_icon(mark, 128), "assets/images/tray_icon.png")
    save_png(macos_template(mark), "assets/images/tray_icon_macos.png")

    for size in MAC_SIZES:
        save_png(
            mac_icon(mark, size),
            "macos/Runner/Assets.xcassets/AppIcon.appiconset/"
            f"app_icon_{size}.png",
        )

    for filename, size in IOS.items():
        save_png(
            square_icon(mark, size),
            f"ios/Runner/Assets.xcassets/AppIcon.appiconset/{filename}",
        )

    for density, size in ANDROID.items():
        save_png(
            square_icon(mark, size),
            f"android/app/src/main/res/mipmap-{density}/ic_launcher.png",
        )

    ico_base = square_icon(mark, 1024)
    ico_base.save(
        ROOT / "windows/runner/resources/app_icon.ico",
        sizes=[
            (16, 16),
            (24, 24),
            (32, 32),
            (48, 48),
            (64, 64),
            (128, 128),
            (256, 256),
        ],
    )


if __name__ == "__main__":
    main()
