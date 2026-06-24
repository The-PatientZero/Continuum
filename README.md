# Continuum

Continuum is a minimal macOS menu bar utility for hiding menu bar items into a quiet overlay tray and revealing them only when needed.

The project is intentionally being trimmed around a small stable surface:

- Hide and reveal menu bar items without observing screen contents.
- Require Accessibility permission only.
- Keep settings sparse and predictable.
- Omit multi-layout switching, scripted actions, screen observation, and appearance decoration.
- Preserve a compact, premium interface that belongs in the menu bar.

## Requirements

- macOS 26 or newer
- Accessibility permission

## Build

```sh
xcodebuild build \
  -project Continuum.xcodeproj \
  -scheme Continuum \
  -destination 'platform=macOS,arch=arm64' \
  -disableAutomaticPackageResolution \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO
```

## URL Scheme

Continuum registers `continuum://` for two small actions:

- `continuum://toggle-hidden`
- `continuum://open-settings`

Settings mutation through URLs is intentionally disabled.

## License

Continuum is available under the GPL-3.0 license. Copyright and license attribution for upstream work is preserved in the source headers and license files.
