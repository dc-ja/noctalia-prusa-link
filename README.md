# PrusaLink for Noctalia

A [Noctalia Shell](https://docs.noctalia.dev) 5 plugin that puts your Prusa 3D printer on the desktop bar: live printer state, print progress, temperature graphs, a storage browser with G-code thumbnails, and job controls — powered by your printer's [PrusaLink](https://github.com/prusa3d/Prusa-Link-Web) HTTP API.

## Features

**Bar widget**

- Printer glyph with the live print progress (`42%`) while printing; state name (`Idle`, `Paused`, `Finished`, …) otherwise; `Offline` when the printer is unreachable
- Color-coded by state: accent while printing/paused/finished, red on errors and attention, muted otherwise
- Hover tooltip with the full picture: state, progress, time remaining / elapsed, nozzle and bed temperatures (actual / target), Z height, flow and speed, fan speeds, active storage
- Per-state label visibility — choose on which printer states the bar shows text at all

**Panel** (left-click the widget)

- **Status tab** — printer state, nozzle/bed temperatures with history graphs, Z height, flow/speed, fans, and current job details (file name, progress bar, elapsed / remaining time). Pause, resume and stop the job right from the header, and jump to the printer's own web interface.
- **Storage tab** — browse the printer's storages and folders. Files with embedded previews show their G-code thumbnail; the file being printed is tagged with a live `Printing · 42%` badge (and its parent folders with `Printing inside`). Click a file for a large preview with size, last-modified and parsed G-code metadata (material, temperatures, layer height, print time, …), and start it from there — with a confirmation step — while the printer is idle.

## Requirements

- Noctalia Shell 5 (plugin API level 24 or newer)
- A Prusa printer with PrusaLink enabled and reachable over the network (e.g. MK4, MK3S+, MINI+, XL — anything exposing the PrusaLink API at `http://printer/`)
- `curl` on your `PATH` — the plugin authenticates with HTTP digest, which Noctalia's built-in HTTP client cannot do yet, so all requests run through a `curl --digest` subprocess bridge

## Installation

1. In Noctalia, open **Settings → Plugins** and add this repository as a plugin source (git):

   ```
   https://github.com/dc-ja/noctalia-prusa-link
   ```

2. Install **PrusaLink** from the source list.
3. Add the *PrusaLink* widget to your bar, then configure it under the widget's plugin settings (see below).

## Configuration

All settings live under **Settings → Plugins → PrusaLink**.

| Setting | Default | Description |
| --- | --- | --- |
| Printer URL | — | Address of the printer, e.g. `http://192.168.1.123`. The scheme defaults to `http` (port 80; `https` uses 443). |
| Username | `maker` | PrusaLink account username. |
| Password | — | PrusaLink password (HTTP digest authentication). |
| Interval — offline *(advanced)* | 10 s | Poll interval while the printer is unreachable (1–120 s). |
| Interval — idle *(advanced)* | 2 s | Poll interval while the printer is on but not printing (1–120 s). |
| Interval — printing *(advanced)* | 1 s | Poll interval during a print job (1–120 s). |
| Label — \<state\> *(advanced)* | off for *idle* / *offline*, on otherwise | One toggle per printer state (`offline`, `idle`, `ready`, `busy`, `printing`, `paused`, `finished`, `stopped`, `error`, `attention`) controlling whether the bar widget shows its text label in that state. |

## How it works

- A background **service** polls `/api/v1/status` at the interval matching the printer's state and publishes the result to Noctalia's shared state; the bar widget and panel react to it. Nothing is stored outside the plugin's own data directory.
- Every request — status polling, file listings, thumbnail downloads — goes through the **`curl --digest` bridge**, restoring real request timeouts and full HTTP digest authentication. `https://` URLs work with certificate verification.
- **G-code thumbnails** are fetched once from the printer, streamed to disk, and cached in the plugin data directory (`thumbnails/`). The cache holds up to 24 MiB and trims itself oldest-first; failed fetches are retried after ten minutes. Deleting the cache folder is safe — thumbnails are simply re-downloaded.

## Troubleshooting

- **Widget says `Offline`** — confirm the printer's web interface opens at the configured URL in a browser, and that username/password are correct (these are the PrusaLink credentials set on the printer, not Prusa Connect credentials).
- **Everything else loads, but no thumbnails / no file listings** — make sure `curl` is installed and on your `PATH`.
- **Wrong or stale state** — toggle the plugin off and on in Noctalia's plugin settings to restart its service.

## Development

Developer documentation — architecture, state keys, the PrusaLink API surface and Noctalia plugin conventions — lives in [AGENTS.md](AGENTS.md). The plugin is plain Luau; there is no build step.
