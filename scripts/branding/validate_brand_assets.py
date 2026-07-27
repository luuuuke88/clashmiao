#!/usr/bin/env python3

from __future__ import annotations

from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]

EXPECTED = {
    "assets/branding/speed_cat_mark.png": (1024, 1024),
    "assets/images/brand_logo.png": (1024, 1024),
    "assets/images/brand_mark.png": (1024, 1024),
    "assets/images/tray_icon.png": (128, 128),
    "assets/images/tray_icon_macos.png": (128, 128),
    "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_16.png": (16, 16),
    "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_32.png": (32, 32),
    "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_64.png": (64, 64),
    "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_128.png": (128, 128),
    "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_256.png": (256, 256),
    "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_512.png": (512, 512),
    "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png": (
        1024,
        1024,
    ),
    "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png": (
        1024,
        1024,
    ),
    "android/app/src/main/res/mipmap-mdpi/ic_launcher.png": (48, 48),
    "android/app/src/main/res/mipmap-hdpi/ic_launcher.png": (72, 72),
    "android/app/src/main/res/mipmap-xhdpi/ic_launcher.png": (96, 96),
    "android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png": (144, 144),
    "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png": (192, 192),
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
}

EXPECTED.update(
    {
        f"ios/Runner/Assets.xcassets/AppIcon.appiconset/{filename}": (
            size,
            size,
        )
        for filename, size in IOS.items()
    }
)


def image_at(relative: str) -> Image.Image | None:
    path = ROOT / relative
    if not path.exists():
        return None
    return Image.open(path)


errors: list[str] = []

for relative, expected_size in EXPECTED.items():
    path = ROOT / relative
    if not path.exists():
        errors.append(f"missing: {relative}")
        continue
    with Image.open(path) as image:
        if image.size != expected_size:
            errors.append(
                f"{relative}: expected {expected_size}, got {image.size}"
            )

brand_mark = image_at("assets/images/brand_mark.png")
if brand_mark is not None:
    with brand_mark:
        if brand_mark.mode != "RGBA" or brand_mark.getpixel((0, 0))[3] != 0:
            errors.append("brand_mark.png must have transparent RGBA corners")

macos_icon = image_at(
    "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png"
)
if macos_icon is not None:
    with macos_icon:
        if macos_icon.mode != "RGBA" or macos_icon.getpixel((0, 0))[3] != 0:
            errors.append("macOS 1024 icon must have transparent outer corners")

ios_icon = image_at(
    "ios/Runner/Assets.xcassets/AppIcon.appiconset/"
    "Icon-App-1024x1024@1x.png"
)
if ios_icon is not None:
    with ios_icon:
        if ios_icon.convert("RGBA").getpixel((0, 0))[3] != 255:
            errors.append("iOS marketing icon must be opaque")

ico = image_at("windows/runner/resources/app_icon.ico")
if ico is not None:
    with ico:
        sizes = set(ico.info.get("sizes", set()))
        required = {(16, 16), (32, 32), (48, 48), (128, 128), (256, 256)}
        if not required.issubset(sizes):
            errors.append(f"Windows ICO missing sizes: {sorted(required - sizes)}")

if errors:
    raise SystemExit("\n".join(errors))

print(f"validated {len(EXPECTED)} raster assets and Windows ICO")
