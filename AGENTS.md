# PrusaLink — Noctalia Shell Plugin

Bar widget that shows your Prusa printer state and print progress, powered by the PrusaLink API.

## Current State (Phase 1 — Complete)

- **Bar widget**: shows printer icon + progress % when printing, `IDLE` when idle, `—` when disconnected. Color-coded: primary (printing), variant (idle), error (offline/error/attention).
- **Tooltip on hover**: full status from the API — state, progress, time remaining, print time, nozzle/bed temps (actual/target), Z height, flow %, speed %, fan RPMs, storage info.
- **Left-click**: opens the attached panel.
- **Right-click**: context menu with Pause/Resume/Stop print, Refresh, Open Web UI, and Widget Settings actions.
- **Panel**: full QML-based UI with printer status, job details (thumbnail, filename, progress bar, time info), temperature graphs with Y-axis scale, and job control buttons (Pause/Resume/Stop).
- **Settings**: host, port, username, password (digest auth), and three refresh intervals — offline (default 10s), idle (default 2s), printing (default 1s) — dynamically switched based on printer state.

## Architecture

```
prusa-link/
  manifest.json    -- plugin metadata, entry points, default settings
  Main.qml         -- invisible root; polls GET /api/v1/status, exposes all fields as QML properties
  BarWidget.qml    -- bar capsule widget with state icon, progress text, hover tooltip
  Panel.qml        -- full QML panel with status, job info, temperature graphs, job controls
  Settings.qml     -- connection settings UI
```

### Key Design Decisions

- **Main.qml** is the single source of truth for printer state. All other components read from `pluginApi.mainInstance` properties.
- **HTTP Digest auth** is handled by passing `username`/`password` as the 4th/5th arguments to `XMLHttpRequest.open(method, url, async, user, pass)` — the Qt network stack handles the challenge-response automatically.
 - **Polling interval** has three user-configurable values — offline (10s), idle (2s), printing (1s) — dynamically switched based on printer state. A single `Timer` in `Main.qml` drives all updates.
- **Tooltip** uses `TooltipService.show(root, arrayOfArrays, direction)` per the Noctalia pattern. Each sub-array is `[label, value]`.

## PrusaLink API

- **Base**: `http://host:port`
- **Status**: `GET /api/v1/status` (digest auth)
- **Auth scheme**: HTTP Digest (`scheme: digest`)
- **Response shape**:
  ```json
  {
    "printer": { "state": "PRINTING", "temp_nozzle": 220.2, "target_nozzle": 220.0, "temp_bed": 59.9, "target_bed": 60.0, "axis_z": 42.2, "flow": 95, "speed": 100, "fan_hotend": 4833, "fan_print": 5953 },
    "job": { "id": 133, "progress": 59.0, "time_remaining": 3120, "time_printing": 4744 },
    "storage": { "path": "/usb/", "name": "usb", "read_only": false }
  }
  ```
- **Printer states**: `IDLE`, `BUSY`, `PRINTING`, `PAUSED`, `FINISHED`, `STOPPED`, `ERROR`, `ATTENTION`, `READY`
- **Full OpenAPI spec**: see https://github.com/prusa3d/prusa-link-web/raw/a67f306bc878009be0e27864a01a1837e5c4cf06/spec/openapi.yaml

## Noctalia Shell Conventions

- **Framework**: QML (QtQuick), running under Quickshell/Noctalia Shell 4.7.7+
- **Imports**: `QtQuick`, `QtQuick.Layouts`, `Quickshell`, `qs.Commons`, `qs.Services.UI`, `qs.Widgets`
- **Style/Color**: always use `Style.*` and `Color.*` from `qs.Commons` — never hardcode values
- **Bar widgets**: must support horizontal and vertical bar positions. Use `Settings.getBarPositionForScreen()` to detect orientation, then conditionally use `RowLayout` vs `ColumnLayout`
- **Capsule**: `Rectangle` with `Style.capsuleColor`, `Style.radiusL`, `Style.capsuleBorder*`
- **Tooltip**: `TooltipService.show()`, `.hide()`, `.updateText()` from `qs.Services.UI`
- **Context menu**: `NPopupContextMenu` + `PanelService.showContextMenu()` / `.closeContextMenu()`
- **Panel toggle**: `pluginApi.togglePanel(screen, widget)`
- **Settings**: use `pluginApi.pluginSettings` (read/write) and `pluginApi.saveSettings()`. Default settings live in `manifest.json.metadata.defaultSettings`
- **NTextInput password**: use `inputItem.echoMode: TextInput.Password` (the internal TextField is aliased as `inputItem`)
- **Logging**: `Logger.e(tag, message)`, `Logger.w(...)`, `Logger.i(...)` — requires `import Quickshell`
- **Exec**: `Quickshell.execDetached(["xdg-open", url])` for launching external processes

## What's Next (Phase 2 — In Progress)

1. **~Printer control (done)~**: pause/resume/stop via `PUT/DELETE /api/v1/job/{id}/*` — implemented in panel header and context menu.
2. **Print file browser**: QML-based file browser using `GET /api/v1/files/{storage}/{path}` to list, preview, and start prints.
3. **Notifications**: optional desktop notification when a print finishes or errors.
