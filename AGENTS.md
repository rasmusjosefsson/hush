# Hush agent notes

- Build: `swift build`; tests: `swift test --parallel` (~680 XCTests). Requires the Xcode toolchain with its license accepted; the Command Line Tools toolchain fails on the macOS 27 SDK (`SwiftUIMacros` plugin missing for `@State`).
- Some sources are CRLF (`git ls-files --eol`). Preserve line endings when editing, or the diff explodes.
- Visual check without launching a second Hush: add a temporary executable target depending on `HushUI`, host views in offscreen `NSWindow`s, and capture with `bitmapImageRepForCachingDisplay`/`cacheDisplay` (renders Form/switches correctly, unlike `ImageRenderer`). Remove the target afterwards.
- Accent color is user-selectable (`AccentChoice`, key `appearance.accentChoice`); `DesignSystem.Colors.accent` reads it. `MainWindowView` re-ids the detail pane on change.
- `scripts/dist/build_app_bundle.sh` stamps the real SDK version into the binary with `vtool` (the linker writes `sdk 14.0`, which runs Hush in compatibility mode without the current macOS design) and signs with the first `Apple Development` identity, falling back to ad-hoc. Check with `vtool -show-build`.
- Accessibility (TCC) is tied to the code requirement recorded at grant time. After changing signing identity, `tccutil reset Accessibility com.hush.Hush` and re-grant; toggling the old entry keeps the stale requirement.
