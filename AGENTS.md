# PrusaLink — Noctalia Shell Plugin

Bar widget that shows your Prusa printer state and print progress, powered by the PrusaLink API.

## Current State (Phase 1 — Complete, Migrating to Lua)

- **Bar widget**: shows printer icon + progress % when printing, `IDLE` when idle, `—` when disconnected. Color-coded: primary (printing), variant (idle), error (offline/error/attention).
- **Tooltip on hover**: full status from the API — state, progress, time remaining, print time, nozzle/bed temps (actual/target), Z height, flow %, speed %, fan RPMs, storage info.
- **Left-click**: opens the attached panel.
- **Right-click**: unbound — Noctalia 5 bar widgets have no context-menu API, and `panel.openContextMenu()` only works inside an open panel. All printer actions live in the panel header.
- **Panel**: full UI with printer status, job details (filename, progress bar, time info), temperature graphs, and job control buttons (Pause/Resume/Stop).
- **Settings**: host, port, username, password (digest auth), and three refresh intervals — offline (default 10s), idle (default 2s), printing (default 1s) — dynamically switched based on printer state.

## Architecture (Noctalia 5 — Lua)

```
prusa-link/
  plugin.toml      -- manifest: identity, entries, typed settings schema
  service.luau     -- background polling loop; polls API, publishes to noctalia.state
  widget.luau      -- bar widget: glyph, text, tooltip
  panel.luau       -- popup panel: status tab, storage browser, temp graphs, controls
  translations/
    en.json        -- setting labels, UI strings
  lib/
    http.luau      -- HTTP wrapper with optional digest auth fallback
```

### Key Design Decisions

- **service.luau** is the single source of truth for printer state. Widget and panel read from `noctalia.state` keys.
- **HTTP Digest auth**: pass `basic_username`/`basic_password` to `noctalia.http()`. If the Qt stack handles digest automatically, no extra work needed. Otherwise, `lib/http.luau` wraps the digest challenge-response (401 nonce → compute response → retry) so the rest of the code calls a simple `http.get(baseUrl, path)`.
- **Polling interval** has three user-configurable values — offline (10s), idle (2s), printing (1s) — dynamically switched based on printer state. The service calls `noctalia.setUpdateInterval(ms)` each `update()` tick.
- **Bar widget** uses the imperative API: `barWidget.setGlyph()`, `barWidget.setText()`, `barWidget.setTooltip()`.
- **Panel** uses declarative `ui.*` tree via `panel.render()`. Layout: `width = 600`, `height = 640`, `placement = "attached"` — fixed height because `"fill"` requires `placement = "floating"`; content wraps in `ui.scroll` so it survives smaller outputs.
- **No context menu**: Noctalia 5's `barWidget.*` namespace has no menu API (`panel.openContextMenu()` only works from inside an open panel), so the v4-style widget right-click menu is dropped; job controls (Pause/Resume/Stop) live in the panel header. Users can bind their own gestures per widget instance in Noctalia's widget settings.
- **Settings** are declared in `plugin.toml` as `[[setting]]` entries. The host renders the settings UI automatically. Labels/descriptions use translation keys in `translations/en.json`.
- **State keys** use snake_case. See `MIGRATION.md` for the full key convention.

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
- **Full OpenAPI spec**: <https://github.com/prusa3d/prusa-link-web/raw/master/spec/openapi.yaml>

## Noctalia 5 Plugin Conventions

- **Framework**: Luau (Lua with types), running under Noctalia Shell 5
- **Plugin API**: level 22 (target — lowest level covering our features: `require` modules at 22, timezone-aware `formatTime` at 19, UI closures at 9; latest available is 28)
- **Manifest**: `plugin.toml` — TOML format, declares entries and settings schema
- **Settings**: `[[setting]]` at manifest root. Types: `string`, `int`, `double`, `bool`, `select`, `file`, `folder`, `string_map`. Labels via `label_key` pointing to `translations/<lang>.json`.
- **State sharing**: `noctalia.state.set(key, value)`, `noctalia.state.get(key)`, `noctalia.state.watch(key, fn)` — in-memory only, process-lifetime
- **Declarative UI**: `ui.*` constructors (`ui.column`, `ui.row`, `ui.label`, `ui.glyph`, `ui.button`, `ui.progress`, `ui.graph`, `ui.input`, `ui.select`, `ui.scroll`, `ui.toggle`, `ui.slider`, etc.)
- **Bar widget**: `barWidget.setGlyph()`, `.setText()`, `.setImage()`, `.setTooltip()`, `.render()`, `.isVertical()`
- **Panel**: `panel.render(tree)`, `panel.close()`, `panel.setNeedsFrameTick(bool)`
- **HTTP**: `noctalia.http(request, cb)` — async, returns `{ ok, status, body }`. Supports `basic_username`/`basic_password`, `headers`, `method`, `body`.
- **Subprocess**: `noctalia.runAsync(cmdOrArgv, cb)` — for `curl`, `xdg-open`, etc.
- **Notifications**: `noctalia.notify(title, body)`, `noctalia.notifyError(title, body)`
- **Panel toggle**: `noctalia.togglePanel("author/plugin:panel")`
- **Filesystem**: `noctalia.readFile()`, `noctalia.writeFile()`, `noctalia.pluginDataDir()`, etc.
- **Colors**: palette tokens (`primary`, `on_surface`, `error`, `on_surface_variant`, etc.) or hex (`#rrggbb`)

## What's Next (Phase 2)

1. **Printer control (done)**: pause/resume/stop via `PUT/DELETE /api/v1/job/{id}/*` — implemented in the panel header.
2. **Print file browser**: file browser in panel storage tab with folder navigation. Clicking a G-code file opens a preview panel with a "Start print" button.
3. **Notifications**: optional desktop notification when a print finishes or errors.
