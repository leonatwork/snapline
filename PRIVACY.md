# Privacy

*🇩🇪 [Deutsche Version](PRIVACY.de.md)*

Snapline manages windows locally on your Mac. It does not transmit window data,
layouts, workspaces or diagnostics over the network. There is no telemetry,
analytics or automatic upload of debug logs. Links such as **More apps you might
like** open in your browser; visiting those websites is subject to their own
privacy policies.

## Data processed and stored locally

- **Window management:** Snapline reads running apps, window titles, positions,
  sizes and display information to find, arrange and restore windows. It observes
  mouse events and keyboard/modifier events for snapping gestures and shortcuts;
  it does not save a history of typed text.
- **Layouts:** custom layout names and zone geometry are stored in
  `~/Library/Application Support/Snapline/layouts.json`.
- **Workspaces:** saved arrangement names, app names and bundle identifiers,
  **window titles**, display identifiers/indices and relative window geometry
  are stored in `~/Library/Application Support/Snapline/workspaces.json`.
  Titles help match saved windows to open windows when restoring a workspace.
  These JSON files are not encrypted by Snapline; titles may contain document
  names or other personal information.
- **Preferences:** feature toggles, spacing, shortcuts, excluded app bundle IDs
  and the active layout for each display are saved through macOS UserDefaults.
  The installed app's domain is `io.github.leonatwork.snapline`, normally backed
  by `~/Library/Preferences/io.github.leonatwork.snapline.plist`. macOS also
  manages the launch-at-login registration and permission grants.
- **Live previews:** optional Snap Assist window thumbnails are captured with
  ScreenCaptureKit and cached in memory. Snapline does not save these images to
  disk; quitting the app clears the in-memory cache.
- **Optional debug log:** disabled by default and enabled only with
  `defaults write io.github.leonatwork.snapline debugLog -bool true`, followed by
  an app restart. It records timestamps and snapping diagnostics, such as window
  geometry/IDs, mouse/drag state, modifier state, layout names and display names.
  It does **not** record window titles, title hashes or window contents. Files:
  `~/Library/Logs/Snapline/debug.log` and the single backup `debug.log.1` in the
  same directory. On a log write, new and existing log files get owner-only
  read/write permissions (`0600`), including an existing backup. If the current
  log exceeds **1 MB (1,000,000 bytes)**, it is moved to `debug.log.1` before the
  next write, replacing the previous backup. Exactly at the limit, an entry is
  still appended: a log may exceed the limit by one entry. There is no timed
  deletion. Older versions' logs may still contain titles; updating does not
  remove their contents or retroactively shrink an oversized backup.

## Permissions and their purpose

- **Accessibility** is required to read window information, move and resize
  other apps' windows and use the event tap for Snapline's gestures and the
  green-button flyout/native-menu suppression.
- **Screen Recording** is optional and used only for live window previews in
  Snap Assist. Without it (or with live previews disabled), Snap Assist can
  show app icons and window titles instead.

You can revoke these grants in **System Settings → Privacy & Security →
Accessibility / Screen Recording**. Revoking a permission does not delete saved
layouts, workspaces or logs.

## Deleting your data

Quit Snapline before deleting files or resetting preferences, so it cannot write
them back while running.

- Delete individual layouts or workspaces through Snapline's menu/editor, or
  delete `layouts.json` and/or `workspaces.json` at the paths above to remove all
  saved entries. Remove `~/Library/Application Support/Snapline/` to delete both.
- Remove `~/Library/Logs/Snapline/` to delete the current log and its backup,
  including any titles retained from older versions. Disable future logging with
  `defaults write io.github.leonatwork.snapline debugLog -bool false` before
  restarting Snapline. Disabling logging alone does not delete existing logs.
- Reset all Snapline preferences with
  `defaults delete io.github.leonatwork.snapline` while the app is closed. This
  also resets the debug-log opt-in, but does not delete layouts or workspaces.
- Turn off **Launch at login** in Snapline or remove it under **System Settings →
  General → Login Items**. Revoke permissions separately as described above.
  If you used **Turn off macOS tiling now…**, restore those system options in
  **Desktop & Dock** if desired; resetting Snapline's preferences does not undo
  changes to macOS's `com.apple.WindowManager` settings.

Removing `Snapline.app` alone does not delete these local data files. Empty the
Trash if you moved files there. Copies you exported, shared or included in system
backups must be deleted separately.
