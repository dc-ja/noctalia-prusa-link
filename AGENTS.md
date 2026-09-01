# PrusaLink — Noctalia Shell Plugin

Bar widget that shows your Prusa printer state and print progress, powered by the PrusaLink API.

## Current State (Phase 1 — Complete, Migrating to Lua)

- **Bar widget**: shows printer icon + progress % when printing, `IDLE` when idle, `—` when disconnected. Color-coded: primary (printing), variant (idle), error (offline/error/attention).
- **Tooltip on hover**: full status from the API — state, progress, time remaining, print time, nozzle/bed temps (actual/target), Z height, flow %, speed %, fan RPMs, storage info.
- **Left-click**: opens the attached panel.
- **Right-click**: unbound — Noctalia 5 bar widgets have no context-menu API, and `panel.openContextMenu()` only works inside an open panel. All printer actions live in the panel header.
- **Panel**: full UI with printer status, job details (filename, progress bar, time info), temperature graphs, and job control buttons (Pause/Resume/Stop).
- **Settings**: printer URL (one text field, e.g. `http://192.168.1.123` — scheme defaults to http, port to 80), username, password (digest auth), and three refresh intervals (marked advanced) — offline (default 10s), idle (default 2s), printing (default 1s) — dynamically switched based on printer state.

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
    http.luau      -- HTTP wrapper; everything rides a curl --digest bridge
    thumbs.luau    -- G-code thumbnail disk cache (pluginDataDir/thumbnails)
```

### Key Design Decisions

- **service.luau** is the single source of truth for printer state. Widget and panel read from `noctalia.state` keys.
- **HTTP Digest auth**: live-tested — Noctalia's `noctalia.http` does not answer digest challenges, and `HttpResponse` exposes no headers to do it ourselves, while the printer rejects Basic outright. `lib/http.luau` therefore falls back to a `curl --digest` bridge via the argv-table form of `noctalia.runAsync` (requires `plugin_api = 24`) whenever the native path returns 401, remembering the choice per printer. Callers keep a simple `http.request()` interface.
- **G-code thumbnails** (issue #4): storage-browser rows show printer-supplied art via `ui.image`, sourced from `lib/thumbs.luau`'s persistent cache under `noctalia.pluginDataDir()/thumbnails/`. Cache filenames are the url-encoded full URL truncated under one filesystem component plus two length-mixed edge checksums over its first/last 24 bytes — per-byte hashing of every URL measured hot enough to blow the host's CPU budget on big listings, so key construction is O(1)-ish per row and memoized. Image bytes stream through the curl bridge straight to disk (`destPath`, `-f -o`) and land atomically by temp-file rename after a 2xx; each file is fetched as a candidate chain (`refs.icon` small first, `refs.thumbnail` large as automatic fallback) and per-URL misses are negative-cached for ten minutes so re-renders can't retry-storm but stale gaps do recover; the store self-trims to 24 MiB oldest-mtime-first (throttled) and sweeps orphaned `*.part` temps. Fetch completions never rebuild the tree on the curl-callback stack — the panel arms a coalesced frame tick (`panel.setNeedsFrameTick` → `onFrameTick`) so expensive re-renders land in their own CPU slice instead of blowing the async-command budget.
- **Polling interval** has three user-configurable values — offline (10s), idle (2s), printing (1s) — dynamically switched based on printer state. The service calls `noctalia.setUpdateInterval(ms)` each `update()` tick.
- **Bar widget** uses the imperative API: `barWidget.setGlyph()`, `barWidget.setText()`, `barWidget.setTooltip()`.
- **Panel** uses declarative `ui.*` tree via `panel.render()`. Layout: `width = 600`, `height = 640`, `placement = "attached"` — fixed height because `"fill"` requires `placement = "floating"`; content wraps in `ui.scroll` so it survives smaller outputs.
- **No context menu**: Noctalia 5's `barWidget.*` namespace has no menu API (`panel.openContextMenu()` only works from inside an open panel), so the v4-style widget right-click menu is dropped; job controls (Pause/Resume/Stop) live in the panel header. Users can bind their own gestures per widget instance in Noctalia's widget settings.
- **Settings** are declared in `plugin.toml` as `[[setting]]` entries. The host renders the settings UI automatically. Labels/descriptions use translation keys in `translations/en.json`.
- **State keys** use snake_case; the full table lives under State keys below.

## State keys

All `noctalia.state` keys use snake_case and are published by the service
(`service.luau`); the widget and panel watch them. Full table:

| `connected` | bool | Whether the last HTTP call succeeded |
| `error` | string | Last transport/HTTP error description (empty when healthy) |
| `printer_state` | string | `"OFFLINE"` / `"IDLE"` / `"PRINTING"` / etc. |
| `temp_nozzle` | number | Current nozzle temperature (°C) |
| `target_nozzle` | number | Target nozzle temperature (°C) |
| `temp_bed` | number | Current bed temperature (°C) |
| `target_bed` | number | Target bed temperature (°C) |
| `axis_z` | number | Z-axis height (mm) |
| `flow` | int | Flow speed percentage |
| `speed` | int | Print speed percentage |
| `fan_hotend` | int | Hotend fan RPM |
| `fan_print` | int | Print fan RPM |
| `storage_name` | string | Active storage name from `/api/v1/status` (feeds tooltip row) |
| `storage_read_only` | bool | Drives the tooltip's "(read-only)" suffix |
| `job_id` | int | Current job ID (-1 if none) |
| `progress` | number | Print progress 0–100 |
| `time_remaining` | int | Seconds remaining |
| `time_printing` | int | Seconds of print time elapsed |
| `info` | table | Printer info (name, hostname, nozzle diameter, etc.) |
| `job` | table | `/api/v1/job` payload: `state`, `file.name`, `file.display_name`, `file.path`, `file.refs.icon`, `file.refs.thumbnail`, `file.m_timestamp`, `file.size` |
| `nozzle_temp_history` | number[] | Raw nozzle temp history (one sample per poll, capped ~240) |
| `nozzle_target_history` | number[] | Raw nozzle target history (same sampling) |
| `bed_temp_history` | number[] | Raw bed temp history (same sampling) |
| `bed_target_history` | number[] | Raw bed target history (same sampling) |
| `storage_list` | table[] | Available storage devices |
| `selected_storage` | string | Selected storage path |
| `storage_files` | table[] | Current directory listing |

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
- **Plugin API**: level 24 (require modules at 22, timezone-aware `formatTime` at 19, UI closures at 9, plus argv-table `runAsync` at 24 for the curl digest bridge; latest available is 28)
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