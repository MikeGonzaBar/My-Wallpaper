# My Wallpaper

![My Wallpaper icon](assets/MyWallpaperIcon.png)

My Wallpaper is a native macOS app for assigning your own videos to each display. Each display can use one video or an ordered playlist, with a chosen starting video and continuous looping.

## Prototype status

This repository contains a working prototype. GitHub Actions produces an ad-hoc-signed app by default, so macOS may require **Control-click → Open** the first time. For public distribution, configure the optional Developer ID and notarization secrets documented below; without them, the app is not notarized by Apple.

## What it does

- Assigns a different video or playlist to every connected display.
- Lets each playlist start at a selected item and continue in order forever.
- Imports MOV, MP4, and M4V files into `~/Library/Application Support/My Wallpaper/Videos`.
- Keeps video files and settings on this Mac; nothing is uploaded.
- Provides a menu-bar icon for starting the configured full-screen playback or locking the Mac.
- Includes a universal `arm64`/`x86_64` `.saver` module for macOS's automatic screen-saver system.

## Install the app

1. Open the release folder and locate **My Wallpaper.app**.
2. Drag **My Wallpaper.app** into Finder's **Applications** folder.
3. Open it from **Applications**. If macOS shows a security warning for this local prototype, Control-click the app, choose **Open**, and confirm.

The packaged app is created at `dist/My Wallpaper.app` when you build it locally. The installed copy should be `/Applications/My Wallpaper.app`.

For a drag-to-Applications installer, download **My-Wallpaper.dmg** from the GitHub Actions artifact or a tagged GitHub Release. Open the DMG, then drag **My Wallpaper.app** onto the **Applications** shortcut shown beside it.

## Configure displays

1. Open **My Wallpaper** and select a display card.
2. Choose **Single video** and add one video, or choose **Playlist** and add multiple videos.
3. Use **Start here** to choose which playlist item plays first.
4. Reorder videos with **Go Up** and **Go Down**. The playlist loops continuously.
5. Use **Preview all displays** to verify the videos and scaling before leaving the app.

![Displays and playlist configuration](assets/readme-displays.png)

## Menu-bar screen saver and lock

My Wallpaper adds a small screen/play icon to the macOS menu bar while the app is running. Its actions are:

- **Start Screen Saver**: starts the videos configured in My Wallpaper directly on every display. It does not depend on whichever Apple screen saver is currently selected. Allow a few seconds for the first video frame to load; the first four seconds intentionally ignore the launch click so the screen saver does not immediately dismiss itself.
- **Lock Mac Now**: uses macOS display sleep and the Mac's Lock Screen policy. It does not require Accessibility permission.
- **Open My Wallpaper**: brings the configuration window back after it is closed.
- **Screen Saver Settings…**: opens the relevant macOS settings pane.

After the menu-bar screen saver is running, mouse or keyboard input dismisses playback and locks the Mac. Set **System Settings → Lock Screen → Require password** to **Immediately** for the strongest lock behavior.

The menu-bar icon is available while My Wallpaper is running, even if its main window is closed. Quit the app to remove the icon.

## Connect to macOS automatic screen saver

The menu-bar action above uses My Wallpaper's configured videos directly. To let macOS start the bundled `.saver` automatically after an idle period:

1. Open **Preferences** in My Wallpaper.
2. Click **Install Screen Saver** (or **Reinstall**).
3. Click **Open System Settings**.
4. In the Screen Saver pane, select **My Wallpaper** and choose the idle activation time.
5. In **System Settings → Lock Screen**, configure the password delay.

The app's per-display configuration is shared with the `.saver` module. macOS must have **My Wallpaper** selected for the idle-triggered path; configuring videos in the app alone does not change Apple's selected screen saver.

![Preferences and macOS integration](assets/readme-preferences.png)

## Build locally

Requires macOS 14 or newer and Apple's command-line developer tools.

```sh
./scripts/package-app.sh release
open "dist/My Wallpaper.app"
```

For a debug build:

```sh
./scripts/package-app.sh debug
open "dist/My Wallpaper.app"
```

The packaging script selects an installed macOS SDK automatically. Set `MY_WALLPAPER_SDK` to override the SDK path.

To build only the screen-saver bundle:

```sh
./scripts/build-saver.sh
```

The bundle is written under `.build/screensaver/release/My Wallpaper.saver`.

To create the installer DMG locally after building:

```sh
./scripts/create-dmg.sh
```

The result is `dist/My-Wallpaper.dmg`.

GitHub Actions runs tests and the release build on `macos-14` for pushes, pull requests, and manual runs. Push a version tag such as `v0.2.1` to publish both `My-Wallpaper.dmg` and `My-Wallpaper.app.zip` to a GitHub Release:

```sh
git tag v0.2.1
git push origin v0.2.1
```

For signed distribution, add these repository secrets before pushing the tag:

- `MACOS_CERTIFICATE_BASE64`: base64-encoded Developer ID Application `.p12` certificate.
- `MACOS_CERTIFICATE_PASSWORD`: password for that certificate.
- `MACOS_KEYCHAIN_PASSWORD`: temporary CI keychain password.
- `MACOS_SIGNING_IDENTITY`: optional certificate name; defaults to `Developer ID Application`.
- `APPLE_ID`, `APPLE_TEAM_ID`, and `APPLE_APP_PASSWORD`: Apple notarization credentials.

When these secrets are present, the workflow signs the app and notarizes/staples the DMG. Keep these values only in GitHub Actions secrets, never in the repository.

## Data and privacy

Imported videos are copied into the app's Application Support directory. Settings are stored in `~/Library/Application Support/My Wallpaper/settings.json` and in the app's local preferences. The app does not require an account or network connection.
