# Remove the Onboarding Gate

## Context

ClashMiao currently routes `/` through an asynchronous onboarding gate. The
gate reads `onboarding_done`, displays a loading spinner, and either renders
`OnboardingPage` or `ShellPage`. The requested product direction removes this
screen completely so every launch opens the existing main application
immediately.

## Approved behavior

- `/` renders `ShellPage` directly.
- The application does not read or wait for `onboarding_done` during routing.
- There is no `/onboarding` route and no first-run loading/error gate.
- Fresh installs and existing installs follow the same startup path.
- The existing main-page navigation, profiles, settings, and deep links remain
  unchanged.

Removing onboarding does not silently opt users into analytics. The existing
analytics default remains `false`. Locale still follows a saved choice or the
device locale. Network region retains the existing `other` default and remains
editable on the configuration page.

## Implementation approaches considered

### 1. Direct root route and remove onboarding-only code — selected

Make the root route build `ShellPage`, delete the onboarding page and state,
and remove the first-run region-detection service that has no caller afterward.
This matches the requested behavior and leaves no hidden alternate startup
flow.

### 2. Automatically set `onboarding_done`

Writing the completion flag before routing would hide the page for most users,
but the gate, loading state, error fallback, route, and page would remain. It
also adds unnecessary preference I/O to every fresh install.

### 3. Keep onboarding as a debug route

The main flow could bypass the screen while retaining `/onboarding`. This
contradicts deleting the page and keeps production-only code that no longer
serves the product.

## Code removal

Remove:

- `OnboardingPage` and its widget tests;
- `onboardingDoneProvider` and `markOnboardingDone`;
- the `/onboarding` route and `_RootGate`;
- onboarding-only country/region detection and its tests;
- the `timezone_to_country` dependency used only by that detection service.

Keep shared components such as `BrandMark` and `AnalyticsToggleTile` because
they are used by the About, home, and settings interfaces. Keep the compile-time
terms URL declaration for release compatibility even though it no longer has an
onboarding consumer.

## Verification

- A router widget test starts with empty preferences and proves that
  `ShellPage` is rendered immediately.
- The test proves no onboarding completion flag is required.
- Existing `ShellPage`, home, settings, profile, deep-link, and desktop shortcut
  tests continue passing.
- Static analysis reports no imports or references to deleted onboarding code.
- The full unit suite passes.
- The macOS Debug application is rebuilt, the old process is stopped, and the
  real window is inspected to confirm that it opens on the main home page.

## Out of scope

- redesigning the main home page;
- changing language, region, DNS, or analytics defaults;
- changing existing users' saved preferences;
- merging the feature branch into `main` without explicit approval.
