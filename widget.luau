--!nonstrict
--[[
  PrusaLink bar widget — glyph, text, colours and tooltip driven entirely by
  the service's noctalia.state publications. See MIGRATION.md Step 3.

  Left-click toggles the panel. Right-click is intentionally unbound (users
  can attach their own gestures to this widget in Noctalia's settings).
]]

local PANEL_ID = "dc-ja/prusa-link:panel"

-- Local mirror of the service's publications; watchers keep it fresh.
-- Mirrored service state, keyed exactly like noctalia.state (see WATCHED
-- below). The string indexer keeps the dynamic watch-writes legal for the
-- type solver while every read stays a plain table lookup.
local S: { [string]: any } = {}

local WATCHED = {
  "connected", "error", "printer_state", "progress", "time_remaining",
  "temp_nozzle", "target_nozzle", "temp_bed", "target_bed",
  "axis_z", "flow", "speed", "fan_hotend", "fan_print",
  "storage_name", "storage_read_only", "info",
}

-- ------------------------------------------------------------- formatting

local function formatTime(seconds)
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

local function formatFan(rpm)
  rpm = tonumber(rpm) or 0
  if rpm <= 0 then
    return "0 RPM"
  end
  if rpm >= 1000 then
    return string.format("%.1fk RPM", rpm / 1000)
  end
  return string.format("%d RPM", rpm)
end

local STATE_LABELS = {
  IDLE = "idle",
  READY = "ready",
  BUSY = "busy",
  PRINTING = "printing",
  PAUSED = "paused",
  FINISHED = "finished",
  STOPPED = "stopped",
  ERROR = "error",
  ATTENTION = "attention",
}

-- Per-state label visibility (advanced settings). Defaults to visible except
-- for idle and offline; returns false only when the user has explicitly
-- hidden the label for the current state.
local function labelVisible(state)
  local key = "label_visible_" .. state:lower()
  return noctalia.getConfig(key) ~= false
end

-- ----------------------------------------------------------------- render

local function render()
  local connected = S.connected == true
  local state = tostring(S.printer_state or "OFFLINE")
  local offline = (not connected) or state == "OFFLINE"

  -- Glyph + colours (BarWidget.qml:55-67 parity)
  barWidget.setGlyph(offline and "printer-off" or "printer")
  local role
  if state == "ERROR" or state == "ATTENTION" then
    role = "error"
  elseif state == "PRINTING" or state == "PAUSED" or state == "FINISHED" then
    role = "primary"
  else
    role = "on_surface_variant"
  end
  barWidget.setColor(role)
  barWidget.setGlyphColor(role)

  -- Text (BarWidget.qml:33-53 parity — all nine states)
  local text
  if offline then
    text = "Offline"
  elseif state == "PRINTING" then
    text = string.format("%d%%", math.floor((tonumber(S.progress) or 0) + 0.5))
  elseif state == "PAUSED" then
    text = "Paused"
  elseif state == "IDLE" then
    text = "Idle"
  elseif state == "READY" then
    text = "Ready"
  elseif state == "BUSY" then
    text = "Busy"
  elseif state == "FINISHED" then
    text = "Finished"
  elseif state == "STOPPED" then
    text = "Stopped"
  elseif state == "ERROR" then
    text = "Error"
  elseif state == "ATTENTION" then
    text = "Attention"
  else
    text = state
  end
  -- Hide the label when its per-state visibility setting is off (offline uses
  -- the dedicated offline key; every other state maps to its own key).
  local visible = offline and labelVisible("offline") or labelVisible(state)
  barWidget.setText(visible and text or "")

  -- Tooltip as native { key, value } rows (BarWidget.qml:70-108 parity)
  local rows
  if not connected then
    rows = { { key = "PrusaLink", value = "Disconnected" } }
    if S.error ~= nil and S.error ~= "" then
      rows[2] = { key = "Error", value = tostring(S.error) }
    end
  else
    rows = {}
    local info = S.info
    local name = (type(info) == "table") and (info.name or info.hostname) or nil
    if name ~= nil and name ~= "" then
      rows[#rows + 1] = { key = "Printer", value = tostring(name) }
    end
    rows[#rows + 1] = { key = "State", value = STATE_LABELS[state] or "offline" }
    if state == "PRINTING" or state == "PAUSED" then
      rows[#rows + 1] = {
        key = "Progress",
        value = string.format("%d%%", math.floor((tonumber(S.progress) or 0) + 0.5)),
      }
      rows[#rows + 1] = { key = "Time remaining", value = formatTime(S.time_remaining) }
    end
    rows[#rows + 1] = {
      key = "Nozzle",
      value = string.format("%.1f / %.0f °C", tonumber(S.temp_nozzle) or 0, tonumber(S.target_nozzle) or 0),
    }
    rows[#rows + 1] = {
      key = "Bed",
      value = string.format("%.1f / %.0f °C", tonumber(S.temp_bed) or 0, tonumber(S.target_bed) or 0),
    }
    rows[#rows + 1] = { key = "Z-height", value = string.format("%.1f mm", tonumber(S.axis_z) or 0) }
    rows[#rows + 1] = { key = "Flow", value = string.format("%d%%", tonumber(S.flow) or 100) }
    rows[#rows + 1] = { key = "Speed", value = string.format("%d%%", tonumber(S.speed) or 100) }
    rows[#rows + 1] = { key = "Hotend fan", value = formatFan(S.fan_hotend) }
    rows[#rows + 1] = { key = "Print fan", value = formatFan(S.fan_print) }
    if S.storage_name ~= nil and S.storage_name ~= "" then
      local label = tostring(S.storage_name)
      if S.storage_read_only == true then
        label = label .. " (read-only)"
      end
      rows[#rows + 1] = { key = "Storage", value = label }
    end
  end
  barWidget.setTooltip(rows)
end

-- ------------------------------------------------------- wiring & actions

for _, key in ipairs(WATCHED) do
  noctalia.state.watch(key, function(value)
    S[key] = value
    render()
  end)
end

function onClick()
  noctalia.togglePanel(PANEL_ID)
end

-- Seed the mirror from whatever the service already published, then draw.
for _, key in ipairs(WATCHED) do
  S[key] = noctalia.state.get(key)
end
render()
