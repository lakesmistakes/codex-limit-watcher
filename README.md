# Codex Limit Watcher

Windows-first local watcher for Codex usage limits. It talks to the official local Codex app-server over `stdio://`; it does not scrape ChatGPT, automate a browser, OCR screenshots, or read auth/token files.

## Easy Setup for Non-Technical Users

If you do not like command prompts, start here. These files are meant to be double-clicked from the Codex Limit Watcher folder:

- `Setup.bat` prepares the app, creates `config.json` if needed, installs Node packages if needed, and runs a notification test.
- `Test Notification.bat` checks the sound, toast, and billboard without reading Codex limits.
- `Start Watcher.bat` starts the watcher in visible/debug mode. Leave the window open while you want it running.
- `Start Watcher Hidden.bat` starts the watcher in background mode without leaving a command prompt window open.
- `Stop Watcher.bat` stops the background watcher.
- `Watcher Status.bat` checks whether the background watcher is running and shows the PID and log locations.
- `Open Config.bat` opens your local settings file. If `config.json` does not exist yet, it opens the example settings.
- `Open Logs.bat` opens the log file if one has been created.

Recommended first run:

1. Double-click `Setup.bat`.
2. Double-click `Test Notification.bat`.
3. Double-click `Start Watcher Hidden.bat` for background mode.
4. Double-click `Watcher Status.bat` any time you want to check it.
5. Double-click `Stop Watcher.bat` when you want to stop background mode.

If `Open Logs.bat` says no log exists yet, that is normal before the watcher or tests have run.

There are two start modes:

- Use `Start Watcher.bat` when you want visible/debug mode. It shows the live command window, and closing that window stops the watcher.
- Use `Start Watcher Hidden.bat` for normal/background mode. It starts the watcher without leaving a command prompt open.
- Use `Watcher Status.bat` if you are unsure whether background mode is running. It shows the saved PID, whether the process still looks like Codex Limit Watcher, recent log lines, and where the logs live.
- Use `Stop Watcher.bat` to stop background mode.
- Logs are stored in `logs\`. Background output goes to `logs\watcher-background.out.log`, background errors go to `logs\watcher-background.err.log`, and app/quota logs go to `logs\codex-limit-watcher.log`.
- If background mode fails or exits right away, try `Start Watcher.bat` so you can see live errors in the visible window.

## Setup

1. Install Codex Desktop / Codex CLI and make sure `codex --version` works.
2. Open PowerShell:

```powershell
cd A:\Programs\codex-limit-watcher
copy config.example.json config.json
```

3. Edit `config.json` if you want different sounds, images, titles, messages, or polling.

## Commands

Start the watcher:

```powershell
npm start
```

Run one quota read and print the redacted safe response shape:

```powershell
npm run probe
```

Run notification diagnostics without querying Codex limits:

```powershell
npm run diagnose:notifications
```

Run app-server startup diagnostics without leaving the watcher running:

```powershell
npm run diagnose:app-server
```

Test individual notification channels:

```powershell
npm run test:sound
npm run test:toast
npm run test:billboard
```

Send test notifications without querying Codex limits:

```powershell
node src/watcher.js --test-notification primary
node src/watcher.js --test-notification weekly
node src/watcher.js --test-notification early-weekly
```

Shortcut scripts are also available:

```powershell
npm run diagnose:notifications
npm run test:sound
npm run test:toast
npm run test:billboard
npm run test:primary
npm run test:weekly
npm run test:early-weekly
```

Manual fallback reminder if the app-server quota API stops working:

```powershell
npm run manual-reminder -- --in 5h --message "Check Codex limits"
```

Or schedule by time:

```powershell
npm run manual-reminder -- --at "2026-05-17 09:00" --message "Check Codex weekly reset"
```

## Config

`config.example.json` is the shareable template. `config.json` is local and ignored by git.

Important notification settings:

```json
{
  "notifications": {
    "toastEnabled": true,
    "billboardEnabled": true,
    "soundEnabled": true,
    "soundFile": "assets/sounds/gem-alarm.wav",
    "billboardImage": "assets/billboards/usage-reset-lock-in.png",
    "primary5hTitle": "5H USAGE RESET",
    "primary5hMessage": "5-hour Codex limit is back. Lock in.",
    "weeklyTitle": "USAGE RESET LOCK TF IN!!",
    "weeklyMessage": "Weekly Codex limit is back. Stop wasting the reset.",
    "earlyWeeklyTitle": "EARLY WEEKLY RESET DETECTED",
    "earlyWeeklyMessage": "Codex weekly usage dropped early. Open Codex now."
  },
  "billboard": {
    "durationSeconds": 30,
    "alwaysOnTop": true,
    "borderless": true,
    "showTaskbarIcon": false,
    "position": "bottomRight",
    "screenMargin": 24,
    "mode": "imageWithSmallBadge",
    "fit": "contain",
    "autoSizeToImage": true,
    "maxWidth": 460,
    "maxHeight": 345,
    "backgroundColor": "#000000",
    "badgeFontSize": 11,
    "badgePadding": 8,
    "badgeOpacity": 0.72,
    "showCustomDismissButton": false,
    "clickToDismiss": true
  },
  "display": {
    "timeZone": "local",
    "resetTimeFormat": "weekdayTime",
    "triggeredTimeFormat": "dateTime"
  }
}
```

Asset paths are resolved relative to the project root. If the sound file is missing, the watcher logs a warning and still shows the toast and billboard. If the billboard image is missing, the watcher logs a warning and shows a generated text fallback instead.

For billboard layout:

- `mode: "imageOnly"` shows the image without text overlay.
- `mode: "imageWithSmallBadge"` shows the image plus a small scheduled/triggered badge.
- `fit: "contain"` keeps tall images fully visible without cropping.
- `autoSizeToImage: true` scales the window to the source image while respecting `maxWidth` and `maxHeight`.
- `position` supports `center`, `bottomRight`, `bottomLeft`, `topRight`, and `topLeft`.
- `screenMargin` offsets the notification from the chosen screen edge using the primary screen working area.
- `badgeFontSize`, `badgePadding`, and `badgeOpacity` tune the small metadata badge without changing the underlying art.

Examples:

```json
{
  "billboard": {
    "position": "bottomRight"
  }
}
```

```json
{
  "billboard": {
    "position": "bottomLeft"
  }
}
```

## Changing the alarm sound or billboard image

1. Put your `.wav` file in `assets/user/`.
2. Put your image in `assets/user/`.
3. Update `config.json` paths.
4. Restart the watcher.

Example:

```json
{
  "notifications": {
    "soundFile": "assets/user/my-alert.wav",
    "billboardImage": "assets/user/my-billboard.png"
  }
}
```

Use `.wav` sounds first because Windows can play them reliably.

## Asset Folders

Default assets:

```text
assets/
  billboards/
    usage-reset-lock-in.png
  sounds/
    gem-alarm.wav
  user/
    README.md
```

`assets/user/` is for personal files and is ignored by git except for its README.

## Detection Rules

The watcher notifies only after consecutive successful reads. It detects a reset when usage drops sharply, remaining percentage reaches the configured threshold, `resetsAt` advances, or a previously blocked bucket becomes usable. It only treats primary as 5-hour when app-server confirms a 300-minute window, and only treats secondary as weekly when it confirms a 10080-minute window.

Quota detection lives separately from notification rendering, so reset detection continues even if the configured image or sound is missing.

## Logs

Logs are compact JSON lines in `logs/codex-limit-watcher.log`. Logs are ignored by git.

Example:

```json
{"timestamp":"2026-05-17T01:34:44.433Z","source":"codex-app-server","limitId":"codex","planType":"plus","primary":"used=31% remaining=69% reset=2026-05-17T03:35:01.000Z","primaryMappingConfirmed":true,"secondary":"used=5% remaining=95% reset=2026-05-23T22:35:01.000Z","secondaryMappingConfirmed":true,"rateLimitReachedType":null,"notificationFired":[]}
```

Warnings for missing assets are logged like this:

```json
{"timestamp":"2026-05-17T01:34:44.433Z","source":"notifications","level":"warn","warning":"sound file missing: assets/user/my-alert.wav"}
```

## GitHub Sharing

- Commit `config.example.json`, not your local `config.json`.
- Commit default public assets under `assets/billboards/` and `assets/sounds/` only if you have rights to share them.
- Do not commit `logs/`.
- Do not commit auth files, cookies, API keys, browser data, or Codex token files.

## Troubleshooting

- If `codex` is not found, set `codexCommand` in `config.json` to the full path of `codex.ps1`, `codex.cmd`, or `codex.exe`.
- If the app-server schema changes, run `npm run probe` and inspect the redacted shape. Update `src/rateLimits.js` so bucket mapping is confirmed by field names or durations before notifications are trusted.
- If the watcher says `codex app-server exited with code=1 signal=null`, run these exact checks first:

```powershell
npm run diagnose:app-server
```

- `diagnose:app-server` starts Codex the same way as the watcher, reports whether `initialize` succeeded, whether the child stayed alive briefly, recent redacted stdout/stderr, the resolved Codex command, checked command candidates, cwd, USERPROFILE, HOME, and whether PATH was present plus its length. Its `cleanup` block now shows whether an exit was actually observed, whether descendant verification was performed, whether any descendant still appears to be running, and whether cleanup is confirmed or uncertain before the diagnostic exits.
- If hidden/background mode fails, run `Watcher Status.bat` and check these log files:
  - `logs\watcher-background.out.log`
  - `logs\watcher-background.err.log`
  - `logs\codex-limit-watcher.log`
- If foreground works but hidden mode fails, compare the `diagnose:app-server` output with the background logs. The most useful fields are the resolved Codex command, checked candidates, cwd, USERPROFILE, HOME, PATH present/length, and recent redacted stdout/stderr.
- If background mode keeps exiting right away, try `Start Watcher.bat` so you can see the live startup error in the visible window before it falls back to the manual reminder message.
- If notifications do not appear, run these exact checks first:

```powershell
npm run diagnose:notifications
npm run test:sound
npm run test:toast
npm run test:billboard
```

- The diagnostics JSON prints the loaded config path plus per-channel `attempted`, `success`, and `error` fields.
- `assets.soundFile` and `assets.billboardImage` show the configured path, resolved path, whether the file exists on disk, and billboard image dimensions when available.
- `billboardConfig`, `billboardPlacement`, `display`, and `timing` show the active layout mode, position, auto-sizing limits, working area, final window size and left/top, badge settings, formatted reset text, timezone used, spawn timestamps, and billboard-ready timing.
- If `test:sound` fails with `sound file missing`, fix `notifications.soundFile` in `config.json` or place the `.wav` file at that path.
- If `test:toast` fails, check Windows notification settings and confirm PowerShell can load `System.Windows.Forms`.
- If `test:billboard` fails, confirm PowerShell can open WPF windows and that the session is allowed to show desktop UI.
- Every test and diagnose run is logged to `logs/codex-limit-watcher.log`, including stdout/stderr from the PowerShell child process.
- If the billboard appears behind other windows, leave `billboard.alwaysOnTop` set to `true`.
