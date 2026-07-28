# ClashMiao Logo Redesign

Date: 2026-07-27
Status: Approved visual direction; revised to include in-app brand marks

## Context

ClashMiao currently ships Flutter's default launcher mark on macOS, iOS, and
Android. The Windows icon follows the same legacy identity, while the tray icon
and Android notification icon use unrelated symbols. The redesign must replace
that fragmented set with one recognizable system for the Chinese product name
“喵速”.

## Goals

- Make “cat”, “speed”, and “network connection” recognizable without text.
- Remain legible from a 1024 px store asset down to a 16 px system icon.
- Use one visual family across macOS, iOS, Android, Windows, Linux, the macOS
  tray, Android notifications, and in-app branded surfaces.
- Produce platform-correct opaque, transparent, adaptive, and monochrome
  variants from one master mark.

## Non-goals

- No wordmark, letter monogram, slogan, shield, globe, or generic VPN symbol.
- No changes to in-app layout, theme, application name, or marketing copy
  beyond replacing generic paw placeholders with the approved brand mark.
- No photorealistic fur, facial features, or decorative details that disappear
  at small sizes.

## Selected direction

The selected concept is **疾速猫 / Speed Cat** in the **电光靛蓝 / Electric
Indigo** palette.

The full-color icon consists of:

1. An electric-indigo field transitioning from `#7667FF` at the upper-left to
   `#3155D8` at the lower-right.
2. A bold white cat-head silhouette with two clear ears and no facial features.
3. A warm yellow `#FFD75E` lightning bolt inside the cat silhouette.
4. Two short pale-indigo speed trails on the left, used only where the rendered
   size leaves enough room.

The mark must feel quick and friendly rather than cute. Shapes are flat,
vector-friendly, centered, and separated by generous negative space. There is
no text.

## Source artwork workflow

ImageGen will create the initial 1024 px, flat, vector-friendly Speed Cat mark.
The prompt will explicitly prohibit text, watermarks, shadows on the subject,
fur, facial features, extra symbols, and unnecessary detail.

The selected mark will be isolated as a transparent foreground and inspected
before platform export. Platform backgrounds, masks, padding, resizing, and
monochrome conversions will be produced deterministically so the icon does not
drift between platforms.

The source artwork and final platform assets will live in the repository, not
only in the ImageGen output directory.

### In-app brand mark

The onboarding hero shown before the user presses “开始” currently uses a
generic Fluent UI paw icon. The About page and the empty-profiles state repeat
the same paw symbol. All three are brand surfaces and must be updated together.

The implementation will add one shared `BrandMark` widget backed by the
transparent Speed Cat artwork. It will replace the three hard-coded
`FluentIcons.animal_paw_print_20_filled` instances while preserving the
surrounding page dimensions and responsive behavior:

- **Onboarding:** show the full-color Speed Cat tile in the existing 224 px
  hero area, replacing the paw-in-circle treatment from the supplied
  screenshot.
- **About:** show the same full-color tile at the existing 112 px size.
- **Empty profiles:** show the transparent cat-and-lightning mark over the
  existing soft radial glow so it remains visually integrated with the page.

The shared widget prevents these surfaces from drifting to different symbols
in later changes. It exposes only the presentation variants required above;
page-specific layout stays in each page.

## Platform variants

### Full-color launcher and desktop icons

- **iOS:** opaque square artwork; the OS applies its own icon mask. No
  pre-rounded transparent corners.
- **Android legacy:** density-specific `mipmap` PNGs at the existing required
  sizes.
- **Android adaptive:** add a background layer using the indigo field and a
  transparent foreground containing the cat-and-lightning mark. Keep the mark
  inside the adaptive safe zone.
- **macOS:** a rounded-square indigo tile with platform-appropriate margin and
  subtle tile depth on a transparent canvas. The cat mark itself remains flat.
- **Windows:** a multi-resolution ICO derived from the same master composition.
- **Linux:** continue deriving 32, 64, 128, 256, and 512 px package icons from
  the macOS AppIcon set, as `bin/package-linux.sh` already does.

Speed trails may be removed below 32 px if they merge into the silhouette.

### Monochrome system icons

The tray and Android notification variants remove the background, gradient,
color, and speed trails. They retain only:

- a solid cat-head silhouette; and
- a lightning-bolt knockout.

The macOS tray PNG is an alpha-only template image. `TrayController` will pass
`isTemplate: true` on macOS so AppKit automatically tints it for light and dark
menu bars. Windows and Linux will use a simplified full-color tray PNG from the
same mark because those platforms do not share AppKit's template-image
behavior. The Android vector notification icon uses a white alpha mask and lets
Android apply the notification color.

## Repository asset map

The implementation will update:

- `macos/Runner/Assets.xcassets/AppIcon.appiconset/*.png`
- `ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png`
- `android/app/src/main/res/mipmap-*/ic_launcher.png`
- Android adaptive-icon foreground/background resources under
  `android/app/src/main/res/`
- `windows/runner/resources/app_icon.ico`
- `assets/images/tray_icon.png`
- a macOS template tray asset under `assets/images/`
- the transparent and full-color in-app brand assets under `assets/images/`
- a shared BrandMark widget under `lib/shared/components/`
- `lib/features/onboarding/widget/onboarding_page.dart`
- `lib/features/about/widget/about_page.dart`
- `lib/features/home/widget/home_page.dart`
- `lib/app/tray/tray_controller.dart` to select the macOS template asset and
  enable template rendering
- `android/app/src/main/res/drawable/ic_stat_logo.xml`

The existing asset filenames and Xcode `Contents.json` mappings stay stable
unless Android adaptive-icon resources require new files.

## Quality and validation

The finished icon system must pass:

1. Visual inspection at 1024, 512, 256, 128, 64, 32, 24, and 16 px.
2. Transparent-corner and alpha-channel checks for macOS and tray assets.
3. Opaque-background checks for the iOS store icon.
4. Android adaptive safe-zone and notification-mask checks.
5. ICO inspection confirming multiple embedded resolutions.
6. macOS light/dark menu-bar checks with AppKit template tinting enabled.
7. Widget checks confirming onboarding, About, and empty-profiles surfaces use
   the shared brand mark and no longer render the generic paw icon.
8. A fresh macOS debug build and application launch, including visual
   inspection of the onboarding screen supplied by the user.
9. Repository status review to ensure only intended logo/config assets and
   documentation changed.

The implementation is accepted when the launcher icon is visibly replaced,
the running macOS app shows the new Dock icon, the tray/notification marks
match the same cat-and-lightning family, the onboarding/About/empty-profile
surfaces no longer show generic paw placeholders, and all required platform
assets have the expected dimensions and formats.
