# PrusaLink — Noctalia Shell Plugin

Bar widget that shows your Prusa printer state and print progress, powered by the PrusaLink API.

## Current State (Phase 1 — Complete)

- **Bar widget**: shows printer icon + progress % when printing, `IDLE` when idle, `—` when disconnected. Color-coded: primary (printing), variant (idle), error (offline/error/attention).
- **Tooltip on hover**: full status from the API — state, progress, time remaining, print time, nozzle/bed temps (actual/target), Z height, flow %, speed %, fan RPMs, storage info.
- **Left-click**: opens the attached panel.
- **Right-click**: context menu with Refresh action.
- **Panel**: placeholder with "Open Web UI" button that launches the browser to `http://host:port`.
- **Settings**: host, port, username, password (digest auth), refresh interval.

## Architecture

```
prusa-link/
  manifest.json    -- plugin metadata, entry points, default settings
  Main.qml         -- invisible root; polls GET /api/v1/status, exposes all fields as QML properties
  BarWidget.qml    -- bar capsule widget with state icon, progress text, hover tooltip
  Panel.qml        -- attached panel (currently just opens browser)
  Settings.qml     -- connection settings UI
```

### Key Design Decisions

- **Main.qml** is the single source of truth for printer state. All other components read from `pluginApi.mainInstance` properties.
- **HTTP Digest auth** is handled by passing `username`/`password` as the 4th/5th arguments to `XMLHttpRequest.open(method, url, async, user, pass)` — the Qt network stack handles the challenge-response automatically.
- **Polling interval** is user-configurable (default 10s). A single `Timer` in `Main.qml` drives all updates.
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

## What's Next (Phase 2)

1. **Embedded web UI in Panel**: replace the "Open Web UI" button with a `WebView` or `WebEngineView` that loads `http://host:port` directly in the attached panel, implementing the full PrusaLink web interface.
2. **Printer control**: add context menu or panel actions for Stop/Pause/Resume job via the API (`DELETE /api/v1/job/{id}`, `PUT /api/v1/job/{id}/pause`, etc.)
3. **Transfer status**: show upload progress when a file transfer is active (from the `transfer` object in the status response)
4. **Camera**: integrate the camera snapshot endpoint (`GET /api/v1/cameras/snap`) into the panel
5. **Error state handling**: show error details from the API when printer state is `ERROR` or `ATTENTION`
6. **Notifications**: optional desktop notification when a print finishes or errors
