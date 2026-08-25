--!nonstrict
--[[
  PrusaLink panel — status tab (MIGRATION.md Step 4).

  Attached panel, 600x640 (manifest): header with job controls, status
  property grid, active-job card and dual temperature graphs normalised to
  the v4 scale (nozzle 300 °C, bed 120 °C). Job control talks to the
  printer directly through lib/http.luau (which transparently bridges
  digest auth). Storage tab lands in Step 5.
]]

local http = require("./lib/http.luau")

-- ------------------------------------------------------------ live state

local S = {}
local isOpen = false
local currentTab = 0 -- 0 = status, 1 = storage
local actionError = ""

local WATCHED = {
  "connected", "error", "printer_state", "progress",
  "time_remaining", "time_printing",
  "temp_nozzle", "target_nozzle", "temp_bed", "target_bed",
  "axis_z", "flow", "speed", "fan_hotend", "fan_print",
  "info", "job_id", "job",
  "nozzle_temp_history", "nozzle_target_history",
  "bed_temp_history", "bed_target_history",
}

local STATE_LABELS = {
  IDLE = "Idle", READY = "Ready", BUSY = "Busy", PRINTING = "Printing",
  PAUSED = "Paused", FINISHED = "Finished", STOPPED = "Stopped",
  ERROR = "Error", ATTENTION = "Attention",
}

local function roleFor(state)
  if state == "ERROR" or state == "ATTENTION" then
    return "error"
  end
  if state == "PRINTING" or state == "PAUSED" or state == "FINISHED" then
    return "primary"
  end
  return "on_surface_variant"
end

-- ------------------------------------------------------------ formatting

local function fmtTime(seconds)
  seconds = tonumber(seconds) or 0
  if seconds <= 0 then
    return "--:--"
  end
  local h = math.floor(seconds / 3600)
  local m = math.floor((seconds % 3600) / 60)
  local s = math.floor(seconds % 60)
  if h > 0 then
    return string.format("%dh %02dm", h, m)
  end
  return string.format("%dm %02ds", m, s)
end

local function fmtFan(rpm)
  rpm = tonumber(rpm) or 0
  if rpm <= 0 then
    return "0 RPM"
  end
  if rpm >= 1000 then
    return string.format("%.1fk RPM", rpm / 1000)
  end
  return string.format("%d RPM", rpm)
end

local function fmtSize(bytes)
  bytes = tonumber(bytes) or 0
  if bytes <= 0 then
    return "--"
  end
  if bytes >= 1048576 then
    return string.format("%.1f MiB", bytes / 1048576)
  end
  if bytes >= 1024 then
    return string.format("%.1f KiB", bytes / 1024)
  end
  return string.format("%d B", bytes)
end

local function fmtEndTime(secondsRemaining)
  secondsRemaining = tonumber(secondsRemaining) or 0
  if secondsRemaining <= 0 then
    return "--:--"
  end
  local endT = os.date("*t", os.time() + math.floor(secondsRemaining))
  local nowT = os.date("*t")
  local hhmm = string.format("%02d:%02d", endT.hour, endT.min)
  if endT.day == nowT.day and endT.month == nowT.month and endT.year == nowT.year then
    return "Today " .. hhmm
  end
  local tomT = os.date("*t", os.time() + 86400)
  if endT.day == tomT.day and endT.month == tomT.month then
    return "Tomorrow " .. hhmm
  end
  return string.format("%02d.%02d. ", endT.day, endT.month) .. hhmm
end

local function fmtModified(ts)
  ts = tonumber(ts) or 0
  if ts <= 0 then
    return "--"
  end
  return os.date("%Y-%m-%d %H:%M", ts)
end

-- -------------------------------------------------------------- plumbing

local function targetBase()
  local t = http.parseTarget(noctalia.getConfig("url") or "")
  return t and t.base or ""
end

local renderPanel -- forward declaration

local function apiCall(method, path)
  local base = targetBase()
  if base == "" then
    actionError = "Printer URL is not configured"
    renderPanel()
    return
  end
  http.request({
    url = base .. path,
    method = method,
    username = noctalia.getConfig("username"),
    password = noctalia.getConfig("password"),
  }, function(res)
    if res.ok and res.status >= 200 and res.status < 300 then
      actionError = "" -- service picks up the new state within a poll
    elseif res.status == 409 then
      actionError = "Printer reports a conflict (409)"
    elseif res.status == 404 then
      actionError = "Job not found (404)"
    elseif res.status == 401 then
      actionError = "Authentication failed (401)"
    else
      local detail = tostring(res.body or "")
      actionError = detail ~= "" and detail
        or (method .. " failed (HTTP " .. tostring(res.status) .. ")")
    end
    renderPanel()
  end)
end

function onPause()
  if (tonumber(S.job_id) or -1) >= 0 then
    apiCall("PUT", "/api/v1/job/" .. tostring(S.job_id) .. "/pause")
  end
end

function onResume()
  if (tonumber(S.job_id) or -1) >= 0 then
    apiCall("PUT", "/api/v1/job/" .. tostring(S.job_id) .. "/resume")
  end
end

function onStop()
  if (tonumber(S.job_id) or -1) >= 0 then
    apiCall("DELETE", "/api/v1/job/" .. tostring(S.job_id))
  end
end

function onRefresh()
  renderPanel()
end

function onOpenWebUI()
  local base = targetBase()
  if base ~= "" then
    noctalia.runAsync({ "xdg-open", base })
  end
end

function onClose()
  panel.close()
end

-- ------------------------------------------------------------------- ui

local function propRow(icon, label, value, valueColor)
  return ui.row({ gap = 8, align = "center", flexGrow = 1 }, {
    ui.glyph({ name = icon, size = 16, color = "on_surface_variant" }),
    ui.column({ gap = 0, flexGrow = 1 }, {
      ui.label({ text = label, fontSize = 11, color = "on_surface_variant" }),
      ui.label({ text = value, fontSize = 13, fontWeight = "bold", color = valueColor }),
    }),
  })
end

-- Lay out up to three property cells; missing cells become flexible spacers
-- so the present ones keep equal thirds instead of splitting the free width.
local function rowOf3(a, b, c)
  local given = { a, b, c }
  local items = {}
  for i = 1, 3 do
    items[i] = given[i] or ui.spacer()
  end
  return ui.row({ gap = 10, align = "stretch" }, items)
end

local function normalize(values, maxValue)
  local out = {}
  for _, v in ipairs(values or {}) do
    local n = (tonumber(v) or 0) / maxValue
    if n < 0 then n = 0 elseif n > 1 then n = 1 end
    out[#out + 1] = n
  end
  return out
end

local function graphBlock(title, actualHist, targetHist, maxValue)
  -- Scale labels ride in a rail beside the plot (justify spreads them over
  -- the exact 0..max span). True interior gridlines need upstream support —
  -- see the deferred list in AGENTS.md.
  local ticks = {}
  for i = 0, 4 do -- top -> bottom: max, 3/4, 1/2, 1/4, 0
    ticks[#ticks + 1] = ui.label({
      text = string.format("%.0f", maxValue * (1 - i / 4)),
      fontSize = 9,
      color = "on_surface_variant",
    })
  end
  return ui.column({ gap = 4, align = "stretch" }, {
    ui.label({ text = title, fontSize = 11, color = "on_surface_variant" }),
    ui.row({ gap = 6, align = "stretch" }, {
      ui.graph({
        values = normalize(actualHist, maxValue),
        values2 = normalize(targetHist, maxValue),
        color = "outline",
        color2 = "primary",
        height = 90,
        fillOpacity = 0.15,
        flexGrow = 1,
      }),
      ui.column({ width = 20, height = 90, justify = "space_between", align = "start" }, ticks),
    }),
  })
end

local function iconButton(glyph, tooltip, handler, variant)
  return ui.button({
    glyph = glyph,
    glyphSize = 14,
    variant = variant or "ghost",
    tooltip = tooltip,
    controlSize = "sm",
    onClick = handler,
  })
end

local function buildTree()
  local connected = S.connected == true
  local state = tostring(S.printer_state or "OFFLINE")
  local role = roleFor(state)
  local jobId = tonumber(S.job_id) or -1
  local job = (type(S.job) == "table") and S.job or {}
  local file = (type(job.file) == "table") and job.file or {}
  local info = (type(S.info) == "table") and S.info or {}
  local printerName = info.name or info.hostname or (connected and "Unknown" or "Not connected")

  -- header -------------------------------------------------------------
  local headerItems = {
    ui.glyph({ name = (connected and state ~= "OFFLINE") and "printer" or "printer-off", size = 22, color = role }),
    ui.label({ text = "PrusaLink", fontWeight = "bold", fontSize = 14 }),
    ui.label({ text = tostring(printerName), color = "on_surface_variant", fontSize = 13, maxWidth = 180 }),
  }
  if state == "PRINTING" and jobId >= 0 then
    headerItems[#headerItems + 1] = iconButton("player-pause", "Pause print", "onPause")
  end
  if state == "PAUSED" and jobId >= 0 then
    headerItems[#headerItems + 1] = iconButton("player-play", "Resume print", "onResume")
  end
  if jobId >= 0 and (state == "PRINTING" or state == "PAUSED") then
    headerItems[#headerItems + 1] = iconButton("stop", "Stop print", "onStop", "destructive")
  end
  headerItems[#headerItems + 1] = ui.spacer()
  headerItems[#headerItems + 1] = iconButton("refresh", "Redraw", "onRefresh")
  headerItems[#headerItems + 1] = iconButton("external-link", "Open web interface", "onOpenWebUI")
  headerItems[#headerItems + 1] = iconButton("close", "Close panel", "onClose")

  local headerChildren = {
    ui.row({ gap = 8, align = "center" }, headerItems),
  }
  if not connected then
    local detail = (S.error ~= nil and S.error ~= "") and tostring(S.error) or "Printer unreachable"
    headerChildren[2] = ui.label({ text = detail, fontSize = 11, color = "error" })
  elseif actionError ~= "" then
    headerChildren[2] = ui.label({ text = actionError, fontSize = 11, color = "error" })
  end
  local header = ui.column({ gap = 6, padding = 10, fill = "surface_variant/0.35", radius = 10, align = "stretch" }, headerChildren)

  -- tabs ---------------------------------------------------------------
  -- Segmented-button stand-in for tabs: the plugin API has no native tab
  -- control yet (v5 is beta). When the shell grows one (e.g. ui.tabs),
  -- replace this row with it — see MIGRATION.md Step 4.
  local tabBar = ui.row({ gap = 6, align = "stretch" }, {
    ui.button({ text = "Status", variant = "secondary", selected = currentTab == 0, controlSize = "sm", flexGrow = 1,
      onClick = function() currentTab = 0; renderPanel() end }),
    ui.button({ text = "Storage", variant = "secondary", selected = currentTab == 1, controlSize = "sm", flexGrow = 1,
      onClick = function() currentTab = 1; renderPanel() end }),
  })

  -- body ---------------------------------------------------------------
  local body
  if currentTab == 1 then
    body = ui.column({ gap = 8, align = "stretch" }, {
      ui.label({ text = "Storage browser arrives in the next update.", color = "on_surface_variant" }),
    })
  else
    local statusChildren = {
      rowOf3(
        propRow(connected and state ~= "OFFLINE" and "printer" or "printer-off", "State", STATE_LABELS[state] or state, role),
        propRow("thermometer", "Nozzle", string.format("%.1f / %.0f °C", tonumber(S.temp_nozzle) or 0, tonumber(S.target_nozzle) or 0)),
        propRow("thermometer", "Bed", string.format("%.1f / %.0f °C", tonumber(S.temp_bed) or 0, tonumber(S.target_bed) or 0))
      ),
      rowOf3(
        propRow("gauge", "Flow", string.format("%d%%", tonumber(S.flow) or 100)),
        propRow("gauge", "Speed", string.format("%d%%", tonumber(S.speed) or 100)),
        propRow("ruler-measure", "Z-height", string.format("%.1f mm", tonumber(S.axis_z) or 0))
      ),
      rowOf3(
        propRow("wind", "Hotend fan", fmtFan(S.fan_hotend)),
        propRow("wind", "Print fan", fmtFan(S.fan_print)),
        propRow("circle-dot", "Nozzle ⌀", string.format("%.2f mm", tonumber(info.nozzle_diameter) or 0))
      ),
    }
    local statusBox = ui.column({ gap = 10, padding = 10, fill = "surface_variant/0.35", radius = 10, align = "stretch" }, statusChildren)

    local bodyParts = { statusBox }

    local progress = tonumber(S.progress) or 0
    if jobId >= 0 and (file.name ~= nil or file.display_name ~= nil) then
      local jobChildren = {
        ui.label({ text = tostring(file.display_name or file.name), fontWeight = "bold", fontSize = 13 }),
        ui.row({ gap = 8, align = "center" }, {
          ui.progress({ progress = math.max(0, math.min(1, progress / 100)), fill = "primary", radius = 4, height = 8, flexGrow = 1 }),
          ui.label({ text = string.format("%d%%", math.floor(progress + 0.5)), fontSize = 11, fontWeight = "bold" }),
        }),
        rowOf3(
          propRow("hourglass-high", "Remaining", fmtTime(S.time_remaining)),
          propRow("hourglass-low", "Printing time", fmtTime(S.time_printing)),
          propRow("clock", "Estimated end", fmtEndTime(S.time_remaining))
        ),
        rowOf3(
          propRow("calendar", "Last modified", fmtModified(file.m_timestamp)),
          propRow("file", "File size", fmtSize(file.size))
        ),
      }
      bodyParts[#bodyParts + 1] = ui.column({ gap = 8, padding = 10, fill = "surface_variant/0.35", radius = 10, align = "stretch" }, jobChildren)
    end

    if connected and state ~= "OFFLINE" then
      bodyParts[#bodyParts + 1] = ui.column({ gap = 10, padding = 10, fill = "surface_variant/0.35", radius = 10, align = "stretch" }, {
        graphBlock("Nozzle temperature (°C)", S.nozzle_temp_history, S.nozzle_target_history, 300),
        graphBlock("Bed temperature (°C)", S.bed_temp_history, S.bed_target_history, 120),
      })
    end

    body = ui.column({ gap = 10, align = "stretch" }, bodyParts)
  end

  return ui.column({ flexGrow = 1, gap = 10, align = "stretch" }, {
    header,
    tabBar,
    -- padding pinned to 0: keep the scrolling viewport flush with the header
    -- and tab row above it (some scroll surfaces carry a default inset).
    ui.scroll({ gap = 10, flexGrow = 1, align = "stretch", padding = 0 }, { body }),
  })
end

renderPanel = function()
  if isOpen then
    panel.render(buildTree())
  end
end

-- ------------------------------------------------------------- lifecycle

for _, key in ipairs(WATCHED) do
  noctalia.state.watch(key, function(value)
    S[key] = value
    if key == "printer_state" or key == "job_id" then
      actionError = "" -- stale action feedback dies with the state it came from
    end
    renderPanel()
  end)
end

function onOpen(_context)
  isOpen = true
  actionError = ""
  currentTab = 0
  for _, key in ipairs(WATCHED) do
    S[key] = noctalia.state.get(key)
  end
  renderPanel()
end

function onClose()
  isOpen = false
end

-- seed mirror so the first open reflects current state even pre-watch-fire
for _, key in ipairs(WATCHED) do
  S[key] = noctalia.state.get(key)
end
