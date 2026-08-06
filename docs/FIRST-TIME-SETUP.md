# First-time setup

This guide takes a new macOS user from a fresh clone to a running copy of My Wallpaper. It does not require an Apple Developer account, signing certificate, or GitHub Actions secrets.

## What you need

- A Mac running macOS 14 (Sonoma) or newer.
- Enough disk space for Xcode and the videos you plan to import.
- Internet access to download Xcode and clone the repository.
- Full Xcode from the Mac App Store. The Command Line Tools alone can build the app, but the project's XCTest suite needs Xcode.

## 1. Install and select Xcode

1. Install the current version of **Xcode** from the Mac App Store.
2. Open Xcode once and accept its license or install any components it requests.
3. Open **Terminal** and run the following command. Enter your Mac password if prompted; Terminal does not show password characters while you type.

   ```sh
   sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
   ```

4. Confirm that macOS can find the tools:

   ```sh
   xcodebuild -version
   swift --version
   ```

   Both commands should print version information. If `xcodebuild` says that the active developer directory is the Command Line Tools, repeat step 3.

## 2. Clone the repository

In Terminal, choose a folder where you keep projects, then run:

```sh
git clone https://github.com/MikeGonzaBar/My-Wallpaper.git
cd My-Wallpaper
```

If you downloaded the project as a ZIP instead, open Terminal and use `cd` to move into the extracted `My-Wallpaper` folder before continuing.

## 3. Run the checks

The project has Swift unit tests and native screen-saver manifest tests. Run both before building:

```sh
swift test
./scripts/test-saver-manifest.sh
```

Each command should finish successfully. The first run may take a little longer while Xcode creates build caches.

If macOS reports that a script is not executable, run this once and retry the affected command:

```sh
chmod +x scripts/*.sh
```

## 4. Build and open the app

Build the release app and open it in Finder:

```sh
./scripts/package-app.sh release
open "dist/My Wallpaper.app"
```

The finished application is at `dist/My Wallpaper.app`. This local build is ad-hoc signed, so macOS may warn the first time you open it. In Finder, Control-click **My Wallpaper.app**, choose **Open**, then choose **Open** again in the confirmation dialog.

For development, use a debug build instead:

```sh
./scripts/package-app.sh debug
open "dist/My Wallpaper.app"
```

## 5. Configure your first wallpaper

1. In My Wallpaper, select a display card.
2. Choose **Single video** to use one movie, or **Playlist** to loop several movies.
3. Add MOV, MP4, or M4V video files.
4. Click **Preview all displays** to make sure the playback and sizing look right. Preview ends automatically after 45 seconds and does not lock your Mac.

In **Preferences**, choose **Automatic** (the default) to follow your Mac's Light or Dark appearance, or select a fixed **Light** or **Dark** mode. The app transitions between modes diagonally from the upper-left to the lower-right.

If high-resolution or high-frame-rate videos stutter, enable **Performance Mode** in Preferences. The recommended **1440p / 60 FPS** option creates local HEVC playback copies while preserving the imported originals. Conversion progress and storage use appear in the same panel; originals remain active until each copy is ready.

Imported videos are copied to `~/Library/Application Support/My Wallpaper/Videos`, so do not delete that folder while using the app.

## Optional: enable the native screen saver

After at least one video is configured:

1. Open **Preferences** in My Wallpaper.
2. Click **Install** (or **Update**) for the bundled screen saver.
3. Click **Verify System Setup** and allow the one-time Automation request. It only checks which saver macOS has selected.
4. Click **Open System Settings**, then select **Wallpaper → Screen Saver → Other → My Wallpaper**.
5. Return to the app and confirm the status says **My Wallpaper Selected**.

See [README.md](../README.md#native-screen-saver-setup) for how the screen saver, menu-bar actions, and lock-screen password policy work.

## Common problems

### `xcodebuild` cannot run

Install and open full Xcode, then run the `sudo xcode-select --switch ...` command from step 1. `xcode-select -p` should print `/Applications/Xcode.app/Contents/Developer`.

### The build cannot find a macOS SDK

Make sure Xcode is selected as above. If you intentionally use a nonstandard SDK, set `MY_WALLPAPER_SDK` to its path for that Terminal session:

```sh
export MY_WALLPAPER_SDK="/path/to/MacOSX.sdk"
./scripts/package-app.sh release
```

### macOS refuses to open the local build

Use Finder to Control-click `dist/My Wallpaper.app`, choose **Open**, and confirm. This is expected for the locally ad-hoc-signed prototype. Do not disable Gatekeeper system-wide.

### The screen saver is unavailable or the app says setup is incomplete

Return to **Preferences**, install or update the module, verify system setup, and select **My Wallpaper** under **Wallpaper → Screen Saver → Other**. If verification was denied, allow My Wallpaper in **System Settings → Privacy & Security → Automation**, then verify again.

## Next steps

- Build a distributable installer with `./scripts/create-dmg.sh`; it writes `dist/My-Wallpaper.dmg`.
- Read [README.md](../README.md) for product behavior, release tagging, signing, notarization, and privacy details.
