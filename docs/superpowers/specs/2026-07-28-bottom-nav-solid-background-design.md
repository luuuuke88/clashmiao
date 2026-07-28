# Bottom navigation solid background design

## Goal

Improve the legibility of the floating bottom navigation bar. Page content
must no longer show through strongly enough to reduce the contrast of the four
navigation icons and labels.

## Approved visual direction

The user selected option C, the near-solid blue-gray treatment.

- Light mode background: `#EEF1F7`.
- Dark mode background: `#1B1D24`.
- Keep the existing 68 px capsule height, corner radius, outer spacing,
  border, shadow, icon geometry, labels, and brand-indigo selected state.
- Retain only a subtle edge highlight. The bar should read as a clear
  foreground surface rather than transparent glass.
- Do not add another selected-item capsule or change navigation behavior.

## Scope

The change is limited to `_GlassBottomNav` in `lib/app/shell_page.dart` and
focused widget-test coverage. Existing unrelated theme, page-layout, and
generated-file changes in the worktree must be preserved and excluded from the
implementation commit.

## Theme behavior

- In light mode, the bar uses the approved solid blue-gray surface so text and
  icons remain readable over bright or colorful page content.
- In dark mode, the bar uses the corresponding deep blue-black surface.
- Existing selected and unselected foreground colors stay unchanged unless a
  contrast test proves a minimal adjustment is required.

## Verification

- A focused widget test locates `bottom_nav_bar` and verifies the approved
  light-mode background.
- A focused widget test verifies the dark-mode background.
- Existing navigation tap behavior remains covered and unchanged.
- Run focused tests, static analysis, a macOS debug build, and inspect the
  relaunched app window.

## Success criteria

The bottom navigation is immediately distinguishable from the page behind it,
all four icons and labels remain clear, light and dark modes are coherent, and
no unrelated UI or navigation behavior changes.
