# Manual smoke tests

Run these checks against the packaged app after changes to window lifecycle, preview input, imports, or accessibility. Record the macOS version, app version, hardware, display arrangement, and result for each section.

## Launch at login and main-window lifecycle

1. Open **My Wallpaper**, enable launch at login, and quit the app.
2. Log out and back in, or restart the Mac.
3. Confirm the app launches without showing its main window and remains available from its menu-bar item.
4. Choose **Open My Wallpaper** from the menu-bar item. Confirm one main window appears and becomes key.
5. Close the main window, then choose **Open My Wallpaper** again. Confirm the same logical main window reopens; no duplicate window is created.
6. Hide and unhide the app, then repeat the menu-bar reopen action.
7. Disable launch at login and confirm the status shown in Preferences matches System Settings.

Expected: background login launch stays hidden, every explicit reopen presents one main window, and behavior does not depend on the localized window title.

## Main preview flow

1. Import a short local movie from the Displays page.
2. Confirm the analyzing and importing states appear, then disappear when work completes.
3. Assign the movie to a display and confirm the inline preview starts only while the app is active, the main window is visible, and the Displays page is selected.
4. Switch between Fill Screen and Fit to Screen and confirm the inline preview updates.
5. Choose **Preview All Displays** and wait at least four seconds without input.
6. Press a key or click while My Wallpaper is active. Confirm the full-screen preview exits.
7. Start the preview again, switch to another app, and confirm the preview exits when My Wallpaper resigns active.
8. Start the preview once more and provide no input. Confirm the timeout exits the preview.

Expected: local input exits an armed preview while the app is active. App deactivation is the explicit fallback; the app does not require macOS Accessibility permission for a global event monitor.

## Video library and persistence

1. Import two differently named copies of the same movie in one selection. Confirm the review identifies duplicate content.
2. Add a video to Single Video mode, switch to Playlist, add another video, reorder it, and mark a starting video.
3. Quit and reopen the app. Confirm assignments, order, start video, mute, scaling, quality, and optimization profile persist.
4. Remove an unused library item and confirm the managed file is removed.
5. Enable Performance Mode, allow optimization to finish, then delete optimized copies. Confirm original videos remain playable.

## Playlist editing and undo

1. Assign at least four videos in Playlist mode. Drag a row to the beginning and end; confirm starting-video identity stays the same.
2. Command-click two nonadjacent rows and Shift-click a range. Confirm each selected row has a visible outline.
3. Choose **Remove Selected**, then **Undo** and **Redo**. Confirm only display assignments change; the shared library stays intact.
4. Use the row's move buttons with keyboard focus. Confirm order, starting video, and playback type can be undone from the Edit menu.
5. Undo an assignment change after importing a new library item. Confirm the new item remains in the library.

## Recovery, optimization status, and storage

Use a disposable test library for file-removal steps.

1. Quit the app and move one disposable managed original out of Application Support. Reopen and select **Video Library → Missing**.
2. Select the missing item and choose **Replace Video…**. Choose a readable supported movie. Confirm the name, every display assignment, playlist order, and starting-video identity survive, including after relaunch.
3. Cancel the replacement picker, then retry with an unreadable or invalid movie. Confirm the original library record stays intact and a meaningful error appears for a failed replacement.
4. Enable Performance Mode. Confirm each pending video's status changes from Queued to Optimizing to Ready. Select an item to inspect its status.
5. Start Preview All Displays while conversion is active. Confirm the queue shows Paused, then resumes when preview ends. Repeat with the native screen saver.
6. Cancel a paused queue, end playback, and confirm optimization stays cancelled until requested again.
7. For a failed conversion, confirm its details show the failure reason and **Retry Performance Copy** retries that item.
8. Confirm original and performance-copy storage totals are separate. Open and cancel each cleanup confirmation; verify its estimated reclaimed space is shown.
9. Delete performance copies. Confirm totals update, originals remain readable, and assigned videos still play.

## Screen saver integration

1. Install or update the bundled screen saver from Preferences.
2. Complete the System Settings selection and Automation permission flow when prompted.
3. Verify the app reports Ready and starts the native screen saver.
4. Test with two displays when available. Confirm each display follows its assignment and a disconnected-display configuration does not break fallback playback.

## Accessibility and keyboard behavior

1. Enable VoiceOver and navigate the sidebar, display selector, playback type, appearance, video sizing, quality, optimization profile, and mute control.
2. Confirm every retro choice bar is announced as one labeled radio group with the selected option.
3. Confirm Mute Audio is announced as a toggle with its current state.
4. Confirm decorative arrows, squares, and playback glyphs are not announced as unexplained content.
5. Navigate using only Tab, Shift-Tab, arrow keys, Space, Return, and Escape. Confirm focus remains visible and every reachable control can be operated.
6. Enable Reduce Motion and repeat page and display switching. Confirm content remains understandable without directional animations.

## Result template

- macOS:
- App version/build:
- Mac/display setup:
- Launch-at-login lifecycle: Pass / Fail
- Main preview flow: Pass / Fail
- Library and persistence: Pass / Fail
- Screen saver integration: Pass / Fail
- VoiceOver and keyboard: Pass / Fail
- Notes or follow-up issue:
