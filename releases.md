# Releases

## 0.4.4 (build 10)

- Publishes a clearly labeled ad-hoc-signed prerelease when Apple distribution credentials are unavailable.
- Preserves Developer ID signing and notarization automatically when the complete credential set is configured.
- Rejects partially configured signing credentials with an actionable list of missing secrets.

## 0.4.3 (build 9)

- Fixes Swift 5.10 strict-concurrency failures in the appearance transition and launch-at-login integration so release builds complete on the macOS 14 runner.
- Aligns the checked-in app and screen-saver bundle metadata with the release version source.

## 0.4.2 (build 8)

- Fixes Swift actor isolation in the video preview bridge so release CI builds successfully with strict concurrency checking.

## 0.4.1 (build 7)

- Adds the redesigned Displays, Video Library, and Preferences workflow.
- Improves import cancellation, duplicate detection, settings recovery, private file handling, accessibility, and playback reliability.
- Fixes stale screen-saver display claims so external displays receive their assigned wallpapers.
- Strengthens universal release packaging, diagnostics, signing checks, and regression coverage.
