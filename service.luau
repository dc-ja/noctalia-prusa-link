--!nonstrict
--[[
  PrusaLink service — polls the printer API on a state-dependent cadence and
  publishes results via noctalia.state for the bar widget and the panel.
  See MIGRATION.md Step 2.

  Published keys (snake_case):
    connected, error, printer_state,
    temp_nozzle, target_nozzle, temp_bed, target_bed,
    axis_z, flow, speed, fan_hotend, fan_print,
    storage_name, storage_read_only,
    job_id, progress, time_remaining, time_printing,
    info, job, storage_list, selected_storage,
    nozzle_temp_history, nozzle_target_history,
    bed_temp_history, bed_target_history
]]

local http = require("./lib/http.luau")

-- --------------------------------------------------------------- settings

local cfg = {
  url = "",
  username = "maker",
  password = "",
  offlineSec = 10,
  idleSec = 2,
  printingSec = 1,
}
local baseUrl = ""
local configured = false

local function readSettings()
  cfg.url = noctalia.getConfig("url") or ""
  cfg.username = noctalia.getConfig("username") or ""
  cfg.password = noctalia.getConfig("password") or ""
  cfg.offlineSec = noctalia.getConfig("offline_refresh_sec") or 10
  cfg.idleSec = noctalia.getConfig("idle_refresh_sec") or 2
  cfg.printingSec = noctalia.getConfig("printing_refresh_sec") or 1
  local target = http.parseTarget(cfg.url)
  configured = target ~= nil
  baseUrl = target and target.base or ""
end

-- ------------------------------------------------------------- live state

local live = {
  connected = false,
  printerState = "OFFLINE",
  error = "",
  infoFetched = false,
  inFlight = false,
  jobId = -1,
}
local selectedStorage = ""

-- One raw temperature sample per successful poll, capped (~2–8 min window).
local HISTORY_MAX = 240
local history = {
  nozzleTemp = {},
  nozzleTarget = {},
  bedTemp = {},
  bedTarget = {},
}

local function resetHistory()
  history.nozzleTemp = {}
  history.nozzleTarget = {}
  history.bedTemp = {}
  history.bedTarget = {}
end

local function pushSample(value, samples)
  samples[#samples + 1] = value
  if #samples > HISTORY_MAX then
    table.remove(samples, 1)
  end
end

-- Update cadence follows the printer state (v4 Main.qml mapping):
-- OFFLINE -> offline rate, PRINTING/PAUSED -> printing rate, else idle rate.
local function intervalMs()
  if not configured or live.printerState == "OFFLINE" then
    return cfg.offlineSec * 1000
  end
  if live.printerState == "PRINTING" or live.printerState == "PAUSED" then
    return cfg.printingSec * 1000
  end
  return cfg.idleSec * 1000
end

-- Apply the cadence only when it changes; also invoked on state transitions so
-- a flip (e.g. PRINTING -> OFFLINE) takes effect immediately, not next tick.
local activeIntervalMs = nil
local function applyInterval()
  local ms = intervalMs()
  if ms ~= activeIntervalMs then
    activeIntervalMs = ms
    noctalia.setUpdateInterval(ms)
  end
end

-- ------------------------------------------------------------- publishing

local published = {} -- serialized last value per key; skips redundant sets

local function publish(key, value)
  local encoded = noctalia.json.encode(value)
  if published[key] ~= encoded then
    published[key] = encoded
    noctalia.state.set(key, value)
  end
end

local function publishHistories()
  publish("nozzle_temp_history", history.nozzleTemp)
  publish("nozzle_target_history", history.nozzleTarget)
  publish("bed_temp_history", history.bedTemp)
  publish("bed_target_history", history.bedTarget)
end

local function publishOffline(message)
  live.connected = false
  live.printerState = "OFFLINE"
  live.error = message or ""
  live.infoFetched = false -- refetch identity after reconnect
  live.jobId = -1
  publish("connected", false)
  publish("error", live.error)
  publish("printer_state", "OFFLINE")
  publish("job_id", -1)
  applyInterval()
end

-- ---------------------------------------------------------------- polling

local function apiGet(path, cb)
  http.request({
    url = baseUrl .. path,
    method = "GET",
    username = cfg.username,
    password = cfg.password,
  }, cb)
end

local function fetchInfo()
  apiGet("/api/v1/info", function(res)
    if not (res.ok and res.status == 200) then
      return
    end
    local data = noctalia.json.decode(res.body)
    if not data then
      return
    end
    live.infoFetched = true
    publish("info", data)
  end)
end

local function fetchJob()
  apiGet("/api/v1/job", function(res)
    if not res.ok then
      return
    end
    if res.status == 204 then -- documented "No Content": job just ended
      publish("job", {})
      return
    end
    if res.status ~= 200 then
      return
    end
    local data = noctalia.json.decode(res.body)
    if data then
      publish("job", data)
    end
  end)
end

local function fetchStorageList()
  apiGet("/api/v1/storage", function(res)
    if not (res.ok and res.status == 200) then
      return
    end
    local data = noctalia.json.decode(res.body)
    if not data then
      return
    end
    local list = data.storage_list or {}
    publish("storage_list", list)
    local stillValid = false
    for _, entry in ipairs(list) do
      if entry.path == selectedStorage then
        stillValid = true
        break
      end
    end
    if not stillValid then
      selectedStorage = (list[1] and list[1].path) or ""
    end
    publish("selected_storage", selectedStorage)
  end)
end

local function applyStatus(data)
  local printer = data.printer or {}
  local job = data.job or {}
  local storage = data.storage or {}

  live.connected = true
  live.error = ""
  live.printerState = printer.state or "OFFLINE"

  publish("connected", true)
  publish("error", "")
  publish("printer_state", live.printerState)

  local nozzleTemp = printer.temp_nozzle or 0
  local nozzleTarget = printer.target_nozzle or 0
  local bedTemp = printer.temp_bed or 0
  local bedTarget = printer.target_bed or 0
  pushSample(nozzleTemp, history.nozzleTemp)
  pushSample(nozzleTarget, history.nozzleTarget)
  pushSample(bedTemp, history.bedTemp)
  pushSample(bedTarget, history.bedTarget)

  publish("temp_nozzle", nozzleTemp)
  publish("target_nozzle", nozzleTarget)
  publish("temp_bed", bedTemp)
  publish("target_bed", bedTarget)
  publish("axis_z", printer.axis_z or 0)
  publish("flow", printer.flow or 100)
  publish("speed", printer.speed or 100)
  publish("fan_hotend", printer.fan_hotend or 0)
  publish("fan_print", printer.fan_print or 0)
  publish("storage_name", storage.name or "")
  publish("storage_read_only", storage.read_only or false)

  local id = job.id
  if id == nil then
    id = -1
  end
  live.jobId = id
  publish("job_id", id)
  publish("progress", job.progress or 0)
  publish("time_remaining", job.time_remaining or 0)
  publish("time_printing", job.time_printing or 0)
  publishHistories()

  if not live.infoFetched then
    fetchInfo()
  end
  fetchStorageList()
  if id >= 0 then
    fetchJob()
  else
    publish("job", {})
  end
  applyInterval()
end

local function pollStatus()
  if not configured or live.inFlight then
    return
  end
  live.inFlight = true
  apiGet("/api/v1/status", function(res)
    live.inFlight = false
    if not res.ok then
      -- Bridge/native failures carry useful detail in body ("curl exit N: …").
      local detail = tostring(res.body or "")
      if detail == "" then
        detail = "transport error"
      end
      publishOffline(detail)
      return
    end
    if res.status ~= 200 then
      publishOffline("HTTP " .. tostring(res.status))
      return
    end
    local data = noctalia.json.decode(res.body)
    if not data or type(data.printer) ~= "table" then
      publishOffline("unexpected status payload")
      return
    end
    applyStatus(data)
  end)
end

-- -------------------------------------------------------------- lifecycle

function update()
  applyInterval()
  pollStatus()
end

function onConfigChanged()
  local previousBase = baseUrl
  readSettings()
  if baseUrl ~= previousBase then
    -- Target printer changed: drop identity, selection and history.
    live.infoFetched = false
    selectedStorage = ""
    resetHistory()
    publishHistories()
    publishOffline("")
  end
end

function onExit(_signal, _reason)
  -- Nothing to clean up: no subprocesses, streams or timers of our own.
end

function onIpc(event, _payload)
  if event == "refresh" then
    pollStatus()
  elseif event == "dump" then
    noctalia.log(string.format(
      "prusa-link service: base=%s configured=%s connected=%s state=%s job=%d inFlight=%s error='%s'",
      baseUrl,
      tostring(configured),
      tostring(live.connected),
      live.printerState,
      live.jobId,
      tostring(live.inFlight),
      live.error))
  end
end

-- Startup: seed offline state (which also applies the initial cadence), then
-- kick a first poll without waiting for the first tick.
readSettings()
publishOffline("")
pollStatus()

-- The shell discovers the service's lifecycle callbacks by name in this
-- environment (update cadence, config changes, exit, IPC); binding them
-- explicitly keeps that contract visible to static analysis.
_G.update = update
_G.onConfigChanged = onConfigChanged
_G.onExit = onExit
_G.onIpc = onIpc
