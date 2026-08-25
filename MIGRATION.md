# Migration Plan: QML → Lua (Noctalia 5)

## Overview

Migrate the PrusaLink plugin from QML-based (Noctalia 4.x) to Lua-based (Noctalia 5).
The plugin currently provides a bar widget showing printer state, a popup panel with
status/job details and temperature graphs, and connection settings. All of these
features must be preserved.

## Architecture Change

| Current (QML)          | New (Lua)            | Role                                    |
|------------------------|----------------------|-----------------------------------------|
| `manifest.json`        | `plugin.toml`        | Manifest + typed settings schema        |
| `Main.qml`             | `service.luau`       | HTTP polling, state, temp history       |
| `BarWidget.qml`        | `widget.luau`        | Bar display, tooltip                    |
| `Panel.qml`            | `panel.luau`         | Popup panel: status + storage tabs      |
| `Settings.qml`         | _(declarative)_      | Host-rendered from `[[setting]]` schema |
| —                      | `translations/en.json`| Setting labels, UI strings             |

State flows: **service** polls API → `noctalia.state.set()` → **widget** and **panel**
watch via `noctalia.state.watch()` and render.

## References

- Plugin development docs: <https://docs.noctalia.dev/noctalia/plugins/development/>
- Manifest: <https://docs.noctalia.dev/noctalia/plugins/development/manifest/>
- Entries: <https://docs.noctalia.dev/noctalia/plugins/development/entries/>
- Declarative UI: <https://docs.noctalia.dev/noctalia/plugins/development/declarative-ui/>
- Runtime API: <https://docs.noctalia.dev/noctalia/plugins/development/runtime-api/>
- Plugin API versions: <https://docs.noctalia.dev/noctalia/plugins/development/plugin-api/>
- Workflow: <https://docs.noctalia.dev/noctalia/plugins/development/workflow/>
- PrusaLink OpenAPI spec: <https://github.com/prusa3d/prusa-link-web/raw/master/spec/openapi.yaml>
- Official plugins (examples): <https://github.com/noctalia-dev/official-plugins>
- Type definitions (ground truth for `barWidget.*`/`panel.*`/`HttpRequest`): <https://github.com/noctalia-dev/official-plugins/blob/main/noctalia.d.luau> — also copy this file into the plugin root for luau-lsp autocomplete

## Steps

### Step 1 — Manifest + settings schema

**Files**: create `plugin.toml`, `translations/en.json`

Port all 8 settings from `manifest.json.metadata.defaultSettings` to `[[setting]]`
entries in `plugin.toml`. Every setting gets a `label_key` and `description_key`
pointing to `translations/en.json`.

Settings to declare (plugin-level, `[[setting]]`):

| Key | Type | Default | Constraints |
|-----|------|---------|-------------|
| `protocol` | `select` | `"https"` | `options = [{value="https", label_key=...}, {value="http", label_key=...}]` |
| `host` | `string` | `""` | empty = unconfigured (printers almost never live on localhost) |
| `port` | `int` | `80` | `min = 1, max = 65535`; 80 = plain-HTTP default |
| `username` | `string` | `"maker"` | |
| `password` | `string` | `""` | |
| `offline_refresh_sec` | `int` | `10` | `min = 1, max = 120` |
| `idle_refresh_sec` | `int` | `2` | `min = 1, max = 120` |
| `printing_refresh_sec` | `int` | `1` | `min = 1, max = 120` |

Manifest `id` must become `<author>/prusa-link` — v5 requires the globally unique
`author/plugin` format and rejects the bare `"prusa-link"` from v4. Entries are
addressed as `<author>/prusa-link:<entry-id>` everywhere (`noctalia.togglePanel`,
`noctalia msg plugin ...`), so fix the entry ids now.

Declare three entry stubs: `[[service]]`, `[[widget]]`, `[[panel]]`.
Bump `version` (breaking rewrite; strict `MAJOR.MINOR.PATCH`). Set
`plugin_api = 22` — the lowest level covering everything this plugin uses
(`require` modules at 22, timezone-aware `formatTime` at 19, UI closures at 9).
Context menus are dropped entirely, so 28's `panel.openContextMenu` is not
needed and 22 keeps the plugin installable on older Noctalia v5 builds. 22 is
the target, not a hard constraint — bump deliberately if some future capability
earns it.

Remove `manifest.json`.

Setting notes: there is no secret/password type — credentials are a plain
`string` setting (consider `advanced = true` for the password). The v5 settings
GUI is host-rendered per key; users re-enter values once after migrating.
Defaults intentionally deviate from v4: `host` ships **empty** and `port` at
**80** (v4 had `127.0.0.1:8080`) — a printer is almost always another machine on
the network, and an untouched install should sit clearly "unconfigured" instead
of silently probing localhost.

**Why first**: the manifest is the foundation — without it, no entry can load.

---

### Step 2 — Service: HTTP polling + printer state

**Files**: create `service.luau`

Implement the background polling loop that replaces `Main.qml`.

- Read settings via `noctalia.getConfig("host")`, etc.
- Build `baseUrl = protocol .. "://" .. host .. ":" .. port` (omit `:port` when
  it equals the protocol default — 80 for http, 443 for https — so "Open Web UI"
  gets a clean URL).
- Unconfigured guard: when `host` is empty (the default), skip all HTTP work,
  publish `connected = false` / `"printer_state" = "OFFLINE"`, and hold the
  offline refresh interval until the user configures a host.
- In `update()`:
  - Call `noctalia.setUpdateInterval(intervalMs)` using the dynamic interval logic.
    Preserve the mapping from `Main.qml:21-25`: OFFLINE → offline rate,
    PRINTING *and PAUSED* → printing rate, everything else → idle rate.
  - Poll `GET /api/v1/status` via `noctalia.http()`.
  - On first successful response, poll `GET /api/v1/info` and cache it — but
    reset that cache when the printer disconnects so it is refetched after a
    reconnect (matches `Main.qml:128-143`; printer identity can change across
    downtime).
  - Poll `GET /api/v1/storage` on each successful status tick and publish
    `"storage_list"` (+ default `"selected_storage"`), like `Main.qml:144` did —
    the service owns this so the widget tooltip shows storage without the panel
    ever having been opened.
  - Parse response, publish to `noctalia.state` keys:
    `"connected"`, `"printer_state"`, `"temp_nozzle"`, `"target_nozzle"`,
    `"temp_bed"`, `"target_bed"`, `"axis_z"`, `"flow"`, `"speed"`,
    `"fan_hotend"`, `"fan_print"`, `"job_id"`, `"progress"`,
    `"time_remaining"`, `"time_printing"`, `"info"` (table).
  - When `job_id >= 0`, poll `GET /api/v1/job` and publish `"job"` table.
    Handle the documented `204 No Content` (no active job) explicitly instead of
    treating it as an error.
- Handle errors: set `"connected" = false`, `"printer_state" = "OFFLINE"`.
  Careful: `res.ok` is *transport* success only — always branch on `res.status`
  too (non-2xx responses arrive with `ok == true`; documented host pitfall).
- Implement `onConfigChanged()` to detect config changes without restarting.
- Implement `onExit()` for cleanup.
- Add an `onIpc(event, payload)` debug surface (`dump`, `refresh`) — drivable via
  `noctalia msg plugin <author>/prusa-link:service all refresh` while developing.

**HTTP realities** (verified against the runtime API / `noctalia.d.luau`):

- Request fields: `{ url, method?, headers?, body?, basic_username?,
  basic_password?, follow_redirects?, allow_insecure_tls? }`.
- There is **no timeout option** (v4 used XHR timeouts of 2–5 s). Track an
  in-flight flag and skip the next poll until the callback fires, so one hung
  request cannot stack up requests (also keeps under the ≤ 8 concurrent HTTP
  requests per runtime cap).
- TLS: whether PrusaLink's HTTPS endpoint presents a self-signed certificate is
  UNVERIFIED — the OpenAPI spec is silent on transport, so settle this in the
  Step 2 spike against the real printer. Do not blanket-disable verification on
  an assumption: try strict TLS first; if a request fails with a transport-level
  certificate error, either retry once with `allow_insecure_tls = true` (option
  exists since API level 7) or expose it as an explicit user setting.

**Digest auth — de-risk FIRST (spike before writing lib/http.luau)**: the
PrusaLink OpenAPI spec declares `security: digestAuth` (`scheme: digest`) only.
The v5 request fields are named `basic_username` / `basic_password`, which smells
like Basic-only support — the QML version worked because Qt's network stack
answered digest challenges transparently, and v5 may not. Spike order:

1. Call a real printer with
   `noctalia.http({ url = ..., basic_username = ..., basic_password = ... })`.
   A 200 means the host solved digest — done, no wrapper needed.
2. On 401, implement the RFC 2617/7616 challenge-response inside `lib/http.luau`
   (a `require` module shared by service/widget/panel): send one unauthenticated
   GET, parse `WWW-Authenticate` (`realm`, `nonce`, `qop`, `algorithm`,
   `opaque`), compute `response = MD5(HA1:nonce:nc:cnonce:qop:HA2)`, retry with
   `Authorization: Digest ...`, cache HA1/nonce between calls.
   Luau ships **no crypto or base64 builtins**, so budget for a pure-Luau MD5
   implementation and derive `cnonce` from `math.random` + `noctalia.nowMs()`.

Keep the digest logic entirely inside the module — callers use something like
`http.get(baseUrl, path)` and receive `{ ok, status, body }`.

**Temp history — simplify on purpose**: do NOT port the 0.1 s interpolation from
`Main.qml:496-549` (1800-point arrays existed to keep the custom QML canvas smooth
between irregular polls). With ≥ 1 s polls, appending one raw sample per
successful poll is equivalent data at ~10× less cost — and `noctalia.state`
values are copied cross-entry on every publish, so array size directly drives
per-tick overhead. Append on success, cap at ~240 samples (~2–8 min of window
depending on interval), store as `"nozzle_temp_history"`,
`"nozzle_target_history"`, `"bed_temp_history"`, `"bed_target_history"`
(raw °C; the panel normalizes to 0–1 for `ui.graph`).

**Why second**: the service is the single source of truth. Widget and panel depend on it.

---

### Step 3 — Bar widget

**Files**: create `widget.luau`

Implement the bar widget replacing `BarWidget.qml`.

- Watch `"connected"` and `"printer_state"` via `noctalia.state.watch()` —
  register watches at top level (they persist across re-renders).
- In `update()`:
  - Set glyph: `barWidget.setGlyph("printer")` or `"printer-off"` (offline), and
    color-code with `barWidget.setColor(role)` / `setGlyphColor(role)`:
    `primary` for PRINTING/PAUSED/FINISHED, `error` for ERROR/ATTENTION,
    `on_surface_variant` otherwise (parity with `BarWidget.qml:57-67`).
  - Map **all nine states** to text — port `BarWidget.qml:33-53` verbatim:
    PRINTING → `<progress>%`, PAUSED → "Paused", IDLE → "Idle", READY → "Ready",
    BUSY → "Busy", FINISHED → "Finished", STOPPED → "Stopped", ERROR → "Error",
    ATTENTION → "Attention". Only show "Offline" when actually disconnected
    (the previous draft's catch-all would print "Offline" for a connected
    printer sitting in READY).
  - Tooltip: rebuild the row list from `BarWidget.qml:70-108` and pass it as an
    **array of `{ key, value }` rows** — `barWidget.setTooltip(rows)` accepts
    that natively (no manual `\n` joining needed). Include the Storage row,
    sourced from the new `"storage_name"` / `"storage_read_only"` state keys.
- `onClick()`: `noctalia.togglePanel("<author>/prusa-link:panel")` — v5 panel ids
  always include the author namespace.
- **No context menu (decided)**: `barWidget.*` has no context-menu API, and
  `panel.openContextMenu()` only works from inside an open panel — so the
  v4-style widget right-click menu is dropped, not emulated. All job controls
  (pause/resume/stop) stay in the panel header as in v4; `onRightClick()` is not
  implemented. Users who want quick actions can bind gestures to the widget
  instance in Noctalia's own widget settings — no plugin code involved.
- Job-control HTTP from the widget is fine (`noctalia.http` exists in every
  entry VM), but route it through the shared `lib/http.luau` module so base-URL,
  credentials and digest logic live in exactly one place.
- `onScroll(axis, steps, startsGesture)` exists if we later want scroll actions;
  leave unimplemented for now.

Use the imperative API (`setGlyph` / `setText` / `setTooltip`) rather than
`barWidget.render()` — it's simpler for this single-glyph + text pattern.

**Why third**: the bar widget is the most visible feature and the quickest to verify.

---

### Step 4 — Panel: status tab

**Files**: modify `panel.luau` (add status tab content)

Implement the popup panel with the status tab only (no storage yet).

- Manifest: `[[panel]]` entry with `width = 600`, `height = 640`,
  `placement = "attached"` (anchored to the bar edge, like the v4 panel).
  A fixed px height is required here — `"fill"` is only valid with
  `placement = "floating"`. Oversized values clamp to the output instead of
  breaking; tune 640 during verification. The host also injects per-panel user
  settings (`<id>_placement`, `<id>_position`, `<id>_open_near_click`), so the
  manifest value is just the default — users can switch an instance to floating
  without code changes.
- Because the height is fixed, make `ui.scroll` the root of each tab's content:
  the two graphs alone are ~250 px, so shorter viewports would otherwise clip.
- In `onOpen(context)`: render the UI tree via `panel.render()`.
- Watch state keys and re-render on changes.
- Tab switching: there is no `ui.tabs` control in the declarative vocabulary —
  use a local `currentTab` plus per-section `visible` flags (every node accepts
  `visible`). The Step 5 approach is right; just note it here too.
- Time formatting: prefer `noctalia.formatTime(pattern, unixSeconds)` plus
  `dateFormat()` / `timeFormat()` (API ≥ 19) over porting the QML `Qt.locale()`
  helpers from `Main.qml:551-588`.
- Status tab UI:
  - Header row: printer icon + printer name + control buttons (pause/resume/stop)
    + refresh + open web UI + close buttons.
  - Status properties: printer state, nozzle temp, bed temp, flow %, fan RPMs,
    speed %, Z height, nozzle diameter.
  - Job section (visible when `job_id >= 0`; v4 actually keyed visibility on
    `jobFileName ~= ""`): file name, thumbnail, progress bar (`ui.progress`),
    time remaining, print time, estimated end time, last modified, file size.
  - Thumbnail caveat: `ui.image` accepts **local paths only** — no URLs, no base64
    data URIs. To keep the v4 job image: fetch `refs.icon`/`refs.thumbnail` with
    the authenticated `http()` wrapper, write the bytes under
    `noctalia.pluginDataDir()/`, and hand that path to `ui.image.path`. If that
    complexity isn't worth it for phase 1, dropping thumbnails is an acceptable,
    documented regression (decision needed).
  - Progress bar: `ui.progress` takes `progress` in **0–1**, so divide by 100.
  - Temperature graphs: two `ui.graph` controls — one for nozzle, one for bed.
    Confirmed against the control reference: `values` / `values2` take arrays of
    **0–1 floats**, with `color` / `color2` for dual-line (actual + target). No
    Y-axis labels in the new API — simplified from the custom `GraphWithAxis`
    component (accepted regression). Normalize using the v4 maxima so both
    series share a scale: nozzle ÷ 300 °C, bed ÷ 120 °C.
- Implement callbacks: `onPause()`, `onResume()`, `onStop()`, `onRefresh()`,
  `onOpenWebUI()`, `onClose()`.
- Job control: call the PrusaLink API directly from the panel through the shared
  `lib/http.luau` module — single place for base URL + credentials + digest.
  Endpoints verified against the OpenAPI spec: `PUT /api/v1/job/{id}/pause`,
  `PUT /api/v1/job/{id}/resume`, `DELETE /api/v1/job/{id}` (204 on success,
  409 conflict possible). Direct calls are simpler and more responsive than
  routing commands through the service.

**Why fourth**: the panel is the most complex UI. Implement status first (the
primary use case), then storage as a follow-up.

---

### Step 5 — Panel: storage tab

**Files**: modify `panel.luau` (add storage tab + file browser)

Add the storage browser tab to the panel.

- Storage list comes from the **service** (see Step 2 — polled on every status
  tick), not from the panel. This keeps the stated architecture ("service is the
  single source of truth") true and matches v4 behavior; it also means the
  picker is populated even on first open. The panel owns only ephemeral UI
  state locally: path stack, back-history, loading flag.
- Tab switching: local `currentTab` variable (0 = status, 1 = storage).
- Storage tab UI:
  - `ui.select` for storage picker — its `options` is an array of **plain
    strings** (not key/value pairs like QML's NComboBox), `selectedIndex` drives
    the selection, and `onChange` delivers the **index as a string**; map indices
    to `storage_list` entries yourself.
  - Navigation row: back button (visible when not at root), root button,
    current path label.
  - File list: `ui.scroll` containing folder items as clickable `ui.row` elements.
  - Loading state: show `"Loading..."` label while fetching.
  - Empty state: show `"No files"` when directory is empty.
- Folder navigation: clicking a folder row pushes to path stack, triggers
  `GET /api/v1/files/{storage}/{path}` (percent-encode segments with
  `noctalia.string.urlEncode()`). Preserve v4 listing behavior from
  `Main.qml:393-418`: split `children` into FOLDER/FILE, sort each
  case-insensitively by display name, folders first.
- Path history: maintain a Lua table for back navigation.
- File entries: render as `ui.row` with `ui.glyph({ name = "folder" })` + `ui.label`.
  Clickable via `onClick = function() openFolder(name) end`.

**Why fifth**: storage browsing is a secondary feature. Can be completed independently
of the status tab.

---

### Step 6 — Cleanup + verification

**Files**: remove old files, verify everything works

- Remove: `manifest.json`, `Main.qml`, `BarWidget.qml`, `Panel.qml`, `Settings.qml`.
  The pre-migration tree is preserved on the `legacy-noctalia-v4` branch —
  confirm that branch is pushed before deleting anything.
- Keep: `AGENTS.md` — updated alongside this plan (context-menu claims removed,
  `plugin_api` set to 22).
- **Delete `settings.json`** rather than migrating it. v5 stores settings
  host-side per declared key, so renaming keys in that file accomplishes nothing;
  users re-enter host/password once in Settings → Plugins. Note the defaults
  deliberately differ from v4 (`host` empty instead of `127.0.0.1`, `port` 80
  instead of 8080), so an untouched install stays cleanly offline instead of
  probing localhost. The file is gitignored but contains a real password — don't
  leave it on disk.
- Publishing: raising `plugin_api` drops the plugin on older Noctalia v5 builds
  unless the catalog pins older revisions via `[[plugin.release]]` rows (see
  Workflow docs). Only relevant if this ships through a source repo/catalog.
- Verify:
  - Plugin loads and shows in the plugin list.
  - Bar widget displays correct state and color coding.
  - Tooltip shows on hover with all expected fields.
  - Job control works from the panel header (pause/resume/stop); right-click on
    the widget is intentionally inert.
  - Panel opens on click, shows status tab correctly.
  - Temperature graphs render and update.
  - Storage tab lists folders, navigation works.
  - Settings are editable and applied correctly (edit → service keeps running,
    new values take effect via `onConfigChanged` without a reload).
  - Dynamic refresh interval switches based on printer state — including PAUSED
    counting as the printing rate.
  - After a disconnect/reconnect: `/api/v1/info` is refetched and stale temp
    history doesn't leak across sessions.
  - Digest auth verified against the real printer (Step 2 spike outcome);
    HTTPS mode tested — if the printer's certificate fails validation, the
    `allow_insecure_tls` fallback handles it (and the chosen strategy — retry
    or setting — is recorded here).
  - Widget text is correct for READY / BUSY / FINISHED / STOPPED printers —
    not "Offline".
  - Vertical bars: layout branches on `barWidget.isVertical()` where needed.
  - `/api/v1/job` returning 204 clears the job card instead of erroring.

---

## State Key Convention

All `noctalia.state` keys use snake_case. The service publishes these keys:

| Key | Type | Description |
|-----|------|-------------|
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
| `job` | table | `/api/v1/job` payload: `state`, `file.name`, `file.display_name`, `file.refs.icon`, `file.refs.thumbnail`, `file.m_timestamp`, `file.size` |
| `nozzle_temp_history` | number[] | Raw nozzle temp history (one sample per poll, capped ~240) |
| `nozzle_target_history` | number[] | Raw nozzle target history (same sampling) |
| `bed_temp_history` | number[] | Raw bed temp history (same sampling) |
| `bed_target_history` | number[] | Raw bed target history (same sampling) |
| `storage_list` | table[] | Available storage devices |
| `selected_storage` | string | Selected storage path |
| `storage_files` | table[] | Current directory listing |
