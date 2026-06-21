# Release

`Release` workflow is triggered by tags that match `v*`.

```bash
git tag v0.1.0
git push origin v0.1.0
```

It can also be run manually from GitHub Actions with the same tag value.

## Artifacts

The tag workflow builds and publishes these release assets:

- Windows: `ClashMiao-Windows-x64-Setup.exe`
- Windows: `ClashMiao-Windows-x64-<version>.zip`
- Android: `app-release.apk`
- Android: `app-release.aab`
- macOS: `ClashMiao-macOS-arm64.dmg`
- macOS: `ClashMiao-macOS-arm64.zip` as a fallback/package archive

Before publishing, the workflow runs formatting, analysis, and unit/widget
tests, then verifies that each platform produced the expected package files.
Windows and macOS also verify that `libcore` is bundled into the app output.

## Android Signing

For store-ready Android artifacts, configure these repository secrets:

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`
- `ANDROID_STORE_PASSWORD`

`ANDROID_KEYSTORE_BASE64` should be the base64 content of the JKS file. Without
these secrets, the workflow still builds installable APK/AAB artifacts using the
debug signing config and emits a warning.
