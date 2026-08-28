--!nonstrict
--[[
  PrusaLink panel — status tab (Step 4) + storage browser (Step 5).

  Attached panel, 600x640 (manifest): segmented Status/Storage tabs over a
  scroll-clipped body; header carries job controls that talk to the printer
  directly through lib/http.luau (inheriting the curl digest bridge).
  Temperature graphs normalise history against the v4 scale (300/120 degC)
  with a labelled tick rail beside each plot. Storage rows render G-code
  thumbnails from the disk cache in lib/thumbs.luau when available.
]]

local http = require("./lib/http.luau")
local thumbs = require("./lib/thumbs.luau")

-- ------------------------------------------------------------ live state

-- Mirrored service state, keyed exactly like noctalia.state (see WATCHED
-- below). The string indexer keeps the dynamic watch-writes legal for the
-- type solver while every read stays a plain table lookup.
local S: { [string]: any } = {}
local isOpen = false
local currentTab = 0 -- 0 = status, 1 = storage
local actionError = ""

-- Storage-browser state (ephemeral, panel-owned; the service only publishes
-- the storage list and a default selection — picker choices stay local).
local chosenStorage = nil
type PathSegment = { name: string, display_name: string }

local relPath: { PathSegment } = {}         -- folder names below the storage root
local pathHistory: { { PathSegment } } = {} -- stack of previous relPath copies
local dirEntries = {}  -- sorted children of the current directory
local dirLoading = ""
local dirError = ""
local lastLoadedKey = nil
local previewEntry = nil     -- listing item currently previewed (nil = list)
local previewConfirm = false -- "start now?" confirmation strip is open
local previewBusy = false    -- start-print POST in flight

local WATCHED = {
  "connected", "error", "printer_state", "progress",
  "time_remaining", "time_printing",
  "temp_nozzle", "target_nozzle", "temp_bed", "target_bed",
  "axis_z", "flow", "speed", "fan_hotend", "fan_print",
  "info", "job_id", "job",
  "nozzle_temp_history", "nozzle_target_history",
  "bed_temp_history", "bed_target_history",
  "storage_list", "selected_storage",
}

local STATE_LABELS = {
  IDLE = "Idle", READY = "Ready", BUSY = "Busy", PRINTING = "Printing",
  PAUSED = "Paused", FINISHED = "Finished", STOPPED = "Stopped",
  ERROR = "Error", ATTENTION = "Attention",
}

-- Nothing meaningful comes back while the printer is unreachable/offline.
local function printerOffline()
  local connected = S.connected == true
  local state = tostring(S.printer_state or "OFFLINE")
  return not (connected and state ~= "OFFLINE")
end

-- ------------------------------------------------------------ formatting

local function fmtTime(seconds)
  seconds = tonumber(seconds) or 0
  if seconds <= 0 then return "--:--" end
  local h = math.floor(seconds / 3600)
  local m = math.floor((seconds % 3600) / 60)
  local s = math.floor(seconds % 60)
  if h > 0 then return string.format("%dh %02dm", h, m) end
  return string.format("%dm %02ds", m, s)
end

local function fmtFan(rpm)
  rpm = tonumber(rpm) or 0
  if rpm <= 0 then return "0 RPM" end
  if rpm >= 1000 then return string.format("%.1fk RPM", rpm / 1000) end
  return string.format("%d RPM", rpm)
end

local function fmtSize(bytes)
  bytes = tonumber(bytes) or 0
  if bytes <= 0 then return "--" end
  if bytes >= 1048576 then return string.format("%.1f MiB", bytes / 1048576) end
  if bytes >= 1024 then return string.format("%.1f KiB", bytes / 1024) end
  return string.format("%d B", bytes)
end

local function fmtEndTime(secondsRemaining)
  secondsRemaining = tonumber(secondsRemaining) or 0
  if secondsRemaining <= 0 then return "--:--" end
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
  if ts <= 0 then return "--" end
  return os.date("%Y-%m-%d %H:%M", ts)
end

local function roleFor(state)
  if state == "ERROR" or state == "ATTENTION" then return "error" end
  if state == "PRINTING" or state == "PAUSED" or state == "FINISHED" then return "primary" end
  return "on_surface_variant"
end

-- -------------------------------------------------------------- plumbing

local renderPanel -- forward declaration

local function targetBase()
  local t = http.parseTarget(noctalia.getConfig("url") or "")
  return t and t.base or ""
end

local function apiGet(path, cb)
  http.request({
    url = targetBase() .. path,
    method = "GET",
    username = noctalia.getConfig("username"),
    password = noctalia.getConfig("password"),
  }, cb)
end

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

-- Closing lives in the single onClose() defined near the lifecycle tail.

-- ------------------------------------------------------- deferred rendering

-- Thumbnail/poll completions must never rebuild the tree on the calling
-- (async command / curl) stack: a single callback slice can't afford full
-- re-renders, let alone a drain that settles several downloads. Arm one
-- coalesced frame tick instead — onFrameTick owns a fresh CPU slice.
local renderArmed = false

local function scheduleRender()
  if not renderArmed then
    renderArmed = true
    panel.setNeedsFrameTick(true)
  end
end

function onClose()
  isOpen = false
  renderArmed = false -- drop any pending deferred render with the surface
  panel.setNeedsFrameTick(false)
  panel.close()
end

-- ------------------------------------------------------- storage browser

local function storageSlug(path)
  -- Parentheses matter: bare gsub chains also return the match count, which
  -- would leak into single-value contexts as a phantom numeric segment.
  return (tostring(path or ""):gsub("^/+", ""):gsub("/+$", ""))
end

local function closePreview()
  previewEntry = nil
  previewConfirm = false
  previewBusy = false
end

local function resetRel()
  relPath = {}
  pathHistory = {}
  lastLoadedKey = nil
  closePreview()
end

local function pushHistory()
  local copy: { PathSegment } = {}
  for i, v in ipairs(relPath) do copy[i] = v end
  pathHistory[#pathHistory + 1] = copy
end

-- Human-readable breadcrumb: display names where available (v4 parity).
local function displayRelPath()
  local parts = {}
  for i, seg in ipairs(relPath) do parts[i] = seg.display_name or seg.name end
  return "/" .. table.concat(parts, "/")
end

local function syncStorage()
  local list = S.storage_list
  if type(list) ~= "table" then list = {}; S.storage_list = list end
  if chosenStorage ~= nil then
    local stillThere = false
    for _, entry in ipairs(list) do
      if entry.path == chosenStorage then stillThere = true; break end
    end
    if not stillThere then
      chosenStorage = nil; resetRel(); dirEntries = {}; dirError = ""
    end
  end
  if chosenStorage == nil then
    chosenStorage = S.selected_storage or (list[1] and list[1].path) or nil
    if chosenStorage ~= nil then resetRel() end
  end
end

local function ensureDirLoaded()
  if currentTab ~= 1 or chosenStorage == nil or dirLoading ~= "" then return end
  if printerOffline() then return end -- offline: nothing to fetch
  local shortNames = {}
  for i, seg in ipairs(relPath) do shortNames[i] = seg.name end
  local key = chosenStorage .. "#" .. table.concat(shortNames, "/")
  if lastLoadedKey == key then return end
  local segments = { storageSlug(chosenStorage) }
  for _, segment in ipairs(relPath) do
    segments[#segments + 1] = noctalia.string.urlEncode(segment.name)
  end
  local path = "/api/v1/files/" .. table.concat(segments, "/")
  noctalia.log("[prusa-link] files GET " .. targetBase() .. path)

  dirLoading = "Loading…"
  dirError = ""
  renderPanel()
  apiGet(path, function(res)
    -- Clear unconditionally first: nothing below may wedge us on Loading….
    dirLoading = ""
    noctalia.log(string.format(
      "[prusa-link] files done ok=%s status=%s len=%s",
      tostring(res.ok), tostring(res.status), tostring(#tostring(res.body))))

    local processed, perr = pcall(function()
      if not (res.ok and res.status == 200) then
        local detail = tostring(res.body or "")
        dirError = detail ~= "" and detail or ("HTTP " .. tostring(res.status))
        return
      end
      local data = noctalia.json.decode(res.body)
      local children = (type(data) == "table" and type(data.children) == "table")
        and data.children or {}
      local dirs, files = {}, {}
      for _, entryItem in ipairs(children) do
        if entryItem.type == "FOLDER" then dirs[#dirs + 1] = entryItem
        else files[#files + 1] = entryItem end
      end
      local function byDisplayName(x, y)
        local xn = (x.display_name or x.name or ""):lower()
        local yn = (y.display_name or y.name or ""):lower()
        return xn < yn
      end
      table.sort(dirs, byDisplayName)
      table.sort(files, byDisplayName)
      dirEntries = {}
      for _, d in ipairs(dirs) do dirEntries[#dirEntries + 1] = d end
      for _, f in ipairs(files) do dirEntries[#dirEntries + 1] = f end
      lastLoadedKey = key
      dirError = ""
    end)
    if not processed then
      dirError = "listing failed: " .. tostring(perr)
      noctalia.log("[prusa-link] files parse error: " .. tostring(perr))
    end
    renderPanel()
  end)
end

-- ------------------------------------------------------- file preview

local function apiFilePath(fileName)
  local segments = { storageSlug(chosenStorage) }
  for _, segment in ipairs(relPath) do
    segments[#segments + 1] = segment.name
  end
  segments[#segments + 1] = fileName
  for i, segment in ipairs(segments) do
    segments[i] = noctalia.string.urlEncode(segment)
  end
  return "/api/v1/files/" .. table.concat(segments, "/")
end

local function openPreview(entryItem)
  previewEntry = entryItem
  previewConfirm = false
  previewBusy = false
  renderPanel()
  -- The listing row carries basic fields only; the file's own endpoint adds
  -- parsed G-code metadata (meta) and the full refs. Merge when it arrives.
  apiGet(apiFilePath(entryItem.name), function(res)
    if previewEntry ~= entryItem then
      return -- navigated away or preview closed meanwhile
    end
    if res.ok and res.status == 200 then
      local data = noctalia.json.decode(res.body)
      if type(data) == "table" then
        for _, key in ipairs({ "display_name", "size", "m_timestamp",
                               "refs", "meta", "read_only" }) do
          if data[key] ~= nil then
            previewEntry[key] = data[key]
          end
        end
      end
    else
      noctalia.log("[prusa-link] file detail failed (HTTP "
        .. tostring(res.status) .. ")")
    end
    scheduleRender()
  end)
end

function onPreviewClose()
  closePreview()
  renderPanel()
end

function onPreviewStart()
  if previewEntry == nil then
    return
  end
  previewConfirm = true
  renderPanel()
end

function onPreviewCancel()
  previewConfirm = false
  renderPanel()
end

function onPreviewConfirm()
  if previewBusy or previewEntry == nil then
    return
  end
  local base = targetBase()
  if base == "" then
    actionError = "Printer URL is not configured"
    renderPanel()
    return
  end
  previewBusy = true
  renderPanel()
  -- POST /api/v1/files/{storage}/{path}: starts the print, body ignored.
  -- 204 accepted; 409 when a job is already running; 404 file gone.
  http.request({
    url = base .. apiFilePath(previewEntry.name),
    method = "POST",
    username = noctalia.getConfig("username"),
    password = noctalia.getConfig("password"),
  }, function(res)
    previewBusy = false
    if res.ok and res.status >= 200 and res.status < 300 then
      closePreview()
      currentTab = 0 -- per issue #5: show the status tab after starting
      actionError = ""
    elseif res.status == 409 then
      actionError = "Printer is busy (409)"
    elseif res.status == 404 then
      actionError = "File no longer exists (404)"
    else
      local detail = tostring(res.body or "")
      actionError = detail ~= "" and detail
        or ("Start failed (HTTP " .. tostring(res.status) .. ")")
    end
    scheduleRender()
  end)
end

function onDirBack()
  if #pathHistory > 0 then
    relPath = table.remove(pathHistory) or {}
    lastLoadedKey = nil
    closePreview()
    ensureDirLoaded()
  end
end

function onDirRoot()
  if #relPath > 0 then
    pushHistory()
    relPath = {}
    lastLoadedKey = nil
    closePreview()
    ensureDirLoaded()
  end
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

local function rowOf3(a, b, c)
  -- Missing cells become flexible spacers so present ones keep equal thirds.
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
        -- The graph's values2/primary series draws in the foreground; the
        -- values/outline series sits behind it.
        values = normalize(targetHist, maxValue),
        values2 = normalize(actualHist, maxValue),
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

-- Storage-row leading icon cell. Real art, placeholders and folder glyphs all
-- share this exact square so rows keep one rhythm regardless of cache state.
local THUMB_PX = 40

local function iconCell(node)
  return ui.row({ width = THUMB_PX, height = THUMB_PX, gap = 0,
                  align = "center", justify = "center" }, { node })
end

-- Preview art spans the full body width; the height is a fixed budget so
-- the pane keeps a predictable shape (art is letterboxed by fit="contain").
local PREVIEW_H = 320

-- Preview pane for one print file: large art, API-exposed details and the
-- idle-gated start-print flow. Returns the node list to append to the
-- storage tab body.
local function buildPreviewBody(entryItem, thumbBase, thumbAuth, startable)
  local children = {}

  children[#children + 1] = ui.row({ gap = 8, align = "center" }, {
    iconButton("chevron-left", "Back to files", onPreviewClose),
    ui.label({ text = tostring(entryItem.display_name or entryItem.name),
               fontWeight = "bold", fontSize = 14, flexGrow = 1 }),
  })

  -- Art: the large rendition first — the preview is where quality matters —
  -- falling back to the small icon exactly like the listing rows. A cached
  -- small variant is shown immediately while the large one downloads; the
  -- next frame tick swaps it in.
  local refs = type(entryItem.refs) == "table" and entryItem.refs or {}
  local urlList = {}
  local largeUrl = nil
  for _, refPath in ipairs({ refs.thumbnail, refs.icon }) do
    if type(refPath) == "string" and refPath ~= "" then
      local u = thumbs.thumbUrl(thumbBase, refPath)
      if u ~= "" then
        urlList[#urlList + 1] = u
        if largeUrl == nil then
          largeUrl = u -- first candidate is the thumbnail by design
        end
      end
    end
  end
  if #urlList > 1 and urlList[1] == urlList[2] then
    table.remove(urlList) -- degenerate payload: both refs identical
  end
  local imagePath = thumbs.lookup(urlList)
  if imagePath ~= nil then
    children[#children + 1] = ui.row({ gap = 0 }, {
      ui.image({ path = imagePath, flexGrow = 1, height = PREVIEW_H,
                 fit = "contain", radius = 8 }),
    })
    if largeUrl ~= nil and thumbs.lookup(largeUrl) == nil then
      thumbs.request(largeUrl, thumbAuth, scheduleRender) -- sharpness upgrade
    end
  elseif #urlList > 0 then
    thumbs.request(urlList, thumbAuth, scheduleRender)
    children[#children + 1] = ui.row({ gap = 0, height = PREVIEW_H,
        align = "center", justify = "center" }, {
      ui.glyph({ name = "photo", size = 96, color = "on_surface_variant" }),
    })
  else
    children[#children + 1] = ui.row({ gap = 0, height = PREVIEW_H,
        align = "center", justify = "center" }, {
      ui.glyph({ name = "file", size = 96, color = "on_surface_variant" }),
    })
  end

  -- Detail grid: listing fields plus parsed G-code metadata when the file
  -- detail exposed them. The raw filename is deliberately not shown; the
  -- display name in the toolbar is the human-readable one (issue #5).
  local meta = type(entryItem.meta) == "table" and entryItem.meta or {}
  local specs = {}
  local function addSpec(icon, label, text)
    if text ~= nil and text ~= "" then
      specs[#specs + 1] = { icon, label, text }
    end
  end
  if tonumber(entryItem.size) ~= nil then
    addSpec("file", "File size", fmtSize(entryItem.size))
  end
  if tonumber(entryItem.m_timestamp) ~= nil then
    addSpec("calendar", "Last modified", fmtModified(entryItem.m_timestamp))
  end
  addSpec("flask", "Material", meta.filament_type)
  if tonumber(meta.temperature) ~= nil then
    addSpec("thermometer", "Nozzle temp", string.format("%d °C", meta.temperature))
  end
  if tonumber(meta.bed_temperature) ~= nil then
    addSpec("thermometer", "Bed temp", string.format("%d °C", meta.bed_temperature))
  end
  if tonumber(meta.layer_height) ~= nil then
    addSpec("ruler-measure", "Layer height", string.format("%.2f mm", meta.layer_height))
  end
  if tonumber(meta.estimated_print_time) ~= nil then
    addSpec("clock", "Print time", fmtTime(meta.estimated_print_time))
  end
  addSpec("gauge", "Infill", meta.fill_density)
  if tonumber(meta.nozzle_diameter) ~= nil then
    addSpec("circle-dot", "Nozzle ⌀", string.format("%.2f mm", meta.nozzle_diameter))
  end
  addSpec("printer", "Printer model", meta.printer_model)
  local i = 1
  while i <= #specs do
    local trio = {}
    for j = 0, 2 do
      local spec = specs[i + j]
      trio[#trio + 1] = spec ~= nil and propRow(spec[1], spec[2], spec[3])
        or ui.spacer()
    end
    children[#children + 1] = ui.row({ gap = 10, align = "stretch" }, trio)
    i = i + 3
  end

  -- Start-print flow, gated to an idle printer (issue #5): press, confirm
  -- (bed-clean reminder), then POST; success lands back on the status tab.
  local startArea
  if not startable then
    startArea = ui.label({
      text = "Printer is busy — starting is available while it is idle.",
      fontSize = 12, color = "on_surface_variant",
    })
  elseif not previewConfirm then
    startArea = ui.column({ gap = 6 }, {
      ui.button({ text = "Start print", variant = "primary", flexGrow = 1,
                  onClick = function() onPreviewStart() end }),
      ui.label({ text = "Make sure the print bed is clean and cooled down.",
                 fontSize = 11, color = "on_surface_variant" }),
    })
  else
    startArea = ui.column({ gap = 8, align = "stretch" }, {
      ui.label({ text = "Start printing now?", fontWeight = "bold", fontSize = 13 }),
      ui.label({ text = "The print bed should be clean and free of leftovers.",
                 fontSize = 12, color = "on_surface_variant" }),
      ui.row({ gap = 8 }, {
        ui.button({ text = "Start now", variant = "primary", flexGrow = 1,
                    enabled = not previewBusy,
                    onClick = function() onPreviewConfirm() end }),
        ui.button({ text = "Cancel", variant = "ghost", flexGrow = 1,
                    enabled = not previewBusy,
                    onClick = function() onPreviewCancel() end }),
      }),
    })
  end
  children[#children + 1] = ui.column({ gap = 8, padding = 10,
      fill = "surface_variant/0.35", radius = 10, align = "stretch" },
    { startArea })

  return children
end

local function buildStorageBody()
  if printerOffline() then
    -- Offline: don't parade the failing fetch; relay it plainly, not as an
    -- error line.
    dirLoading = ""
    return ui.column({ gap = 8, align = "stretch" }, {
      ui.label({ text = "Printer is offline — files unavailable.", color = "on_surface_variant" }),
    })
  end
  local list = S.storage_list
  if type(list) ~= "table" or #list == 0 then
    return ui.column({ gap = 8, align = "stretch" }, {
      ui.label({ text = "No storage available.", color = "on_surface_variant" }),
    })
  end

  local options, selectedIndex = {}, 0
  for i, entry in ipairs(list) do
    options[i] = tostring(entry.display_name or entry.name or entry.path)
    if entry.path == chosenStorage then selectedIndex = i - 1 end
  end

  local children = {
    ui.select({
      options = options,
      selectedIndex = selectedIndex,
      onChange = function(indexText)
        local entry = list[(tonumber(indexText) or 0) + 1]
        if entry ~= nil and entry.path ~= chosenStorage then
          chosenStorage = entry.path
          resetRel()
          dirEntries = {}
          dirError = ""
          ensureDirLoaded()
        end
      end,
    }),
  }

  if #relPath > 0 then
    children[#children + 1] = ui.row({ gap = 6, align = "center" }, {
      iconButton("chevron-left", "Go back", onDirBack),
      iconButton("chevron-up", "Go to storage root", onDirRoot),
      ui.label({ text = displayRelPath(), fontSize = 11,
                 color = "on_surface_variant", flexGrow = 1 }),
    })
  end

  local thumbBase = targetBase()
  local thumbAuth = {
    user = noctalia.getConfig("username") or "",
    pass = noctalia.getConfig("password") or "",
  }
  local startable = not printerOffline()
    and (S.printer_state == "IDLE" or S.printer_state == "READY")

  if previewEntry ~= nil then
    for _, node in ipairs(buildPreviewBody(previewEntry, thumbBase, thumbAuth,
                                           startable)) do
      children[#children + 1] = node
    end
    return ui.column({ gap = 8, align = "stretch" }, children)
  end

  if dirLoading ~= "" then
    children[#children + 1] = ui.label({ text = dirLoading, color = "on_surface_variant" })
  elseif dirError ~= "" then
    children[#children + 1] = ui.label({ text = dirError, color = "error" })
  elseif #dirEntries == 0 then
    children[#children + 1] = ui.label({ text = "No files", color = "on_surface_variant" })
  else
    -- Stable row keys keep glyph→image swaps patching in place.
    for _, entryItem in ipairs(dirEntries) do
      local isFolder = entryItem.type == "FOLDER"
      local entryName = tostring(entryItem.name)
      local iconNode
      if isFolder then
        iconNode = ui.glyph({ name = "folder", size = 26, color = "primary" })
      else
        -- Candidate renditions: small icon first, large variant as fallback —
        -- some printers expose only one of the two per file.
        local refs = type(entryItem.refs) == "table" and entryItem.refs or {}
        local urlList = {}
        for _, refPath in ipairs({ refs.icon, refs.thumbnail }) do
          if type(refPath) == "string" and refPath ~= "" then
            local u = thumbs.thumbUrl(thumbBase, refPath)
            if u ~= "" then
              urlList[#urlList + 1] = u
            end
          end
        end
        if #urlList > 1 and urlList[1] == urlList[2] then
          table.remove(urlList) -- degenerate payload: both refs identical
        end
        local state = "absent"
        if #urlList > 0 then
          local imagePath = thumbs.lookup(urlList)
          if imagePath ~= nil then
            iconNode = ui.image({ path = imagePath, width = THUMB_PX,
                                  height = THUMB_PX, fit = "contain", radius = 4 })
          else
            -- Not on disk (caller-established): fetch once with fallback,
            -- hint while in flight. Completion re-enters via frame tick.
            state = thumbs.stateFor(urlList, true)
            if state == "missing" and thumbs.request(urlList, thumbAuth,
                                                     scheduleRender) then
              state = "pending"
            end
          end
        end
        if iconNode == nil then
          -- Placeholder/fallback: loading hint while fetching, plain file
          -- glyph when there's no image to be had.
          local pendingThumb = state == "pending"
          iconNode = ui.glyph({
            name = pendingThumb and "photo" or "file",
            size = 26,
            color = "on_surface_variant",
          })
        end
      end
      children[#children + 1] = ui.row({
        key = "store-" .. entryName,
        gap = 8, align = "center",
        onClick = function()
          if isFolder then
            pushHistory()
            relPath[#relPath + 1] = {
              name = entryName,
              display_name = tostring(entryItem.display_name or entryName),
            }
            lastLoadedKey = nil
            ensureDirLoaded()
          else
            openPreview(entryItem)
          end
        end,
      }, {
        iconCell(iconNode),
        ui.label({ text = tostring(entryItem.display_name or entryName), flexGrow = 1 }),
      })
    end
  end

  return ui.column({ gap = 8, align = "stretch" }, children)
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

  local headerItems = {
    ui.glyph({ name = (connected and state ~= "OFFLINE") and "printer" or "printer-off",
               size = 22, color = role }),
    ui.label({ text = "PrusaLink", fontWeight = "bold", fontSize = 14 }),
    ui.label({ text = tostring(printerName), color = "on_surface_variant", fontSize = 13, maxWidth = 180 }),
  }
  if state == "PRINTING" and jobId >= 0 then
    headerItems[#headerItems + 1] = iconButton("player-pause", "Pause print", onPause)
  end
  if state == "PAUSED" and jobId >= 0 then
    headerItems[#headerItems + 1] = iconButton("player-play", "Resume print", onResume)
  end
  if jobId >= 0 and (state == "PRINTING" or state == "PAUSED") then
    headerItems[#headerItems + 1] = iconButton("stop", "Stop print", onStop, "destructive")
  end
  headerItems[#headerItems + 1] = ui.spacer()
  headerItems[#headerItems + 1] = iconButton("refresh", "Redraw", onRefresh)
  headerItems[#headerItems + 1] = iconButton("external-link", "Open web interface", onOpenWebUI)
  headerItems[#headerItems + 1] = iconButton("close", "Close panel", onClose)

  local headerChildren = { ui.row({ gap = 8, align = "center" }, headerItems) }
  if not connected then
    local detail = (S.error ~= nil and S.error ~= "") and tostring(S.error) or "Printer unreachable"
    headerChildren[2] = ui.label({ text = detail, fontSize = 11, color = "error" })
  elseif actionError ~= "" then
    headerChildren[2] = ui.label({ text = actionError, fontSize = 11, color = "error" })
  end
  local header = ui.column({ gap = 6, padding = 10, fill = "surface_variant/0.35",
                             radius = 10, align = "stretch" }, headerChildren)

  -- Segmented-button stand-in for tabs: no native tab control yet (v5 beta).
  local tabBar = ui.row({ gap = 6, align = "stretch" }, {
    ui.button({ text = "Status", variant = "secondary", selected = currentTab == 0,
                controlSize = "sm", flexGrow = 1,
                onClick = function() currentTab = 0; renderPanel() end }),
    ui.button({ text = "Storage", variant = "secondary", selected = currentTab == 1,
                controlSize = "sm", flexGrow = 1,
                onClick = function() currentTab = 1; renderPanel(); ensureDirLoaded() end }),
  })

  local body
  if currentTab == 1 then
    body = buildStorageBody()
  else
    local progress = tonumber(S.progress) or 0
    local offline = printerOffline()
    local stateProp = propRow("printer-off", "State",
                              STATE_LABELS[state] or state, role)
    local statusRows
    if offline then
      -- Temps, flow/speed, Z and fans report stale values while the printer
      -- is unreachable, so the card collapses to the State property alone.
      statusRows = { rowOf3(stateProp) }
    else
      statusRows = {
        rowOf3(stateProp,
          propRow("thermometer", "Nozzle",
                  string.format("%.1f / %.0f °C",
                                tonumber(S.temp_nozzle) or 0,
                                tonumber(S.target_nozzle) or 0)),
          propRow("thermometer", "Bed",
                  string.format("%.1f / %.0f °C",
                                tonumber(S.temp_bed) or 0,
                                tonumber(S.target_bed) or 0))),
        rowOf3(
          propRow("gauge", "Flow", string.format("%d%%", tonumber(S.flow) or 100)),
          propRow("gauge", "Speed", string.format("%d%%", tonumber(S.speed) or 100)),
          propRow("ruler-measure", "Z-height", string.format("%.1f mm", tonumber(S.axis_z) or 0))),
        rowOf3(
          propRow("wind", "Hotend fan", fmtFan(S.fan_hotend)),
          propRow("wind", "Print fan", fmtFan(S.fan_print)),
          propRow("circle-dot", "Nozzle ⌀", string.format("%.2f mm", tonumber(info.nozzle_diameter) or 0))),
      }
    end
    local statusBox = ui.column({ gap = 10, padding = 10, fill = "surface_variant/0.35",
                                  radius = 10, align = "stretch" }, statusRows)
    local bodyParts = { statusBox }

    if jobId >= 0 and (file.name ~= nil or file.display_name ~= nil) then
      bodyParts[#bodyParts + 1] = ui.column({ gap = 8, padding = 10,
          fill = "surface_variant/0.35", radius = 10, align = "stretch" }, {
        ui.label({ text = tostring(file.display_name or file.name), fontWeight = "bold", fontSize = 13 }),
        ui.row({ gap = 8, align = "center" }, {
          ui.progress({ progress = math.max(0, math.min(1, progress / 100)),
                        fill = "primary", radius = 4, height = 8, flexGrow = 1 }),
          ui.label({ text = string.format("%d%%", math.floor(progress + 0.5)),
                     fontSize = 11, fontWeight = "bold" }),
        }),
        rowOf3(
          propRow("hourglass-high", "Remaining", fmtTime(S.time_remaining)),
          propRow("hourglass-low", "Printing time", fmtTime(S.time_printing)),
          propRow("clock", "Estimated end", fmtEndTime(S.time_remaining))),
        rowOf3(
          propRow("calendar", "Last modified", fmtModified(file.m_timestamp)),
          propRow("file", "File size", fmtSize(file.size))),
      })
    end

    if connected and state ~= "OFFLINE" then
      bodyParts[#bodyParts + 1] = ui.column({ gap = 10, padding = 10,
          fill = "surface_variant/0.35", radius = 10, align = "stretch" }, {
        graphBlock("Nozzle temperature (°C)", S.nozzle_temp_history, S.nozzle_target_history, 300),
        graphBlock("Bed temperature (°C)", S.bed_temp_history, S.bed_target_history, 120),
      })
    end

    body = ui.column({ gap = 10, align = "stretch" }, bodyParts)
  end

  return ui.column({ flexGrow = 1, gap = 10, align = "stretch" }, {
    header,
    tabBar,
    ui.scroll({ gap = 10, flexGrow = 1, align = "stretch", padding = 0 }, { body }),
  })
end

renderPanel = function()
  if isOpen then
    panel.render(buildTree())
  end
end

-- Consumes what scheduleRender() armed. Deliberately runs OUTSIDE the async
-- command stack: this rebuild may be heavy (long listings, many image swaps)
-- and deserves its own fresh CPU slice. Unarmed ticks are ignored — the host
-- may still deliver one coalesced frame after we disarm.
function onFrameTick(_deltaMs)
  if not renderArmed then
    return
  end
  renderArmed = false
  panel.setNeedsFrameTick(false)
  renderPanel()
end

-- ------------------------------------------------------------- watchers

for _, key in ipairs(WATCHED) do
  noctalia.state.watch(key, function(value)
    S[key] = value
    if key == "printer_state" or key == "job_id" then
      actionError = ""
    end
    if key == "storage_list" or key == "selected_storage" then
      syncStorage()
      if currentTab == 1 then
        ensureDirLoaded()
      end
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
  syncStorage()
  renderPanel()
end

-- Seed the mirror from whatever the service already published.
for _, key in ipairs(WATCHED) do
  S[key] = noctalia.state.get(key)
end
syncStorage()

-- The shell discovers panel lifecycle callbacks by name in this environment
-- (see [[panel]] in plugin.toml). Binding them here keeps that contract
-- visible to static analysis instead of relying on invisible string lookups.
_G.onOpen = onOpen
_G.onClose = onClose
_G.onFrameTick = onFrameTick
