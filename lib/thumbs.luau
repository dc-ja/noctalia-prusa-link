--!nonstrict
--[[
  Thumbnail cache for G-code print files (panel storage browser).

  PrusaLink listings expose two bitmap variants per printable file via
  file.refs: icon (*.small.png, list-sized) and thumbnail (*.orig.png). Both
  are absolute paths served behind HTTP digest auth, so images are pulled
  through the shared curl bridge straight to disk (destPath) and never travel
  through Lua strings.

  Cache location: <pluginDataDir>/thumbnails/<name>.png. The cache key is the
  url-encoded URL body plus a pair of CHEAP edge checksums — the naive
  per-byte FNV over every URL was measured hot enough to blow Noctalia's
  per-callback CPU budget once a big USB listing renders hundreds of rows.
  Full URLs keep printers from colliding on identical printer-relative ref
  paths. Writes go to a *.part temp file renamed into place only after a 2xx,
  so partial content can never masquerade as cached art. Fetch misses are
  negative-cached for RETRY_AFTER_S so re-renders don't storm the printer but
  stale gaps do recover.

  One download runs at a time (printer web servers are modest), and the store
  self-trims to MAX_TOTAL_BYTES oldest-mtime-first whenever a completed fetch
  pushes it over budget; abandoned *.part temps older than ORPHAN_AGE are
  swept in the same pass.
]]

local http = require("./http.luau") -- lexical: relative to lib/, like this file

local M = {}

local SUFFIX       = ".png"
local PART         = ".part"
local MAX_BYTES    = 24 * 1024 * 1024 -- trim threshold for the whole cache dir
local TRIM_TARGET  = MAX_BYTES * 3 / 4
local MAX_QUEUE    = 128              -- drop excess; renders simply keep glyphs
local TIMEOUT_MS   = 8000
local ORPHAN_AGE_S = 3600             -- *.part older than this is garbage
local SWEEP_GAP_S  = 60               -- min seconds between full stat passes
local RETRY_AFTER_S = 600             -- negative-cache TTL for failed fetches

-- Filenames stay within the classic 255-byte component limit even for very
-- long ref paths: the encoded body is truncated to fit the checksum tail.
local NAME_MAX      = 200
local CHECKSUM_SEP  = "-"

-- ------------------------------------------------- cache-key construction

-- Edge checksums: always consume the FIRST/LAST EDGE_SPAN bytes verbatim
-- plus mix the length up front. Stride sampling alone proved insufficient
-- (two long URLs differing only between sample points collided in tests);
-- unconditional edge coverage makes any realistic tail/head difference flip
-- the signature. Multiply-free accumulation, O(EDGE_SPAN) iterations.
local EDGE_SPAN = 24

local function edgeChecksum(s, fromTail)
  local n = #s
  local h = (n * 2654435761) % 2147483647
  local first, last = 1, math.min(EDGE_SPAN, n)
  if fromTail then
    first = math.max(1, n - EDGE_SPAN + 1)
    last = n
  end
  for i = first, last do
    h = (h * 131 + s:byte(i)) % 2147483647
  end
  return h
end

local nameCache = {} -- url -> "<encoded>-<fwd>_<bwd>.png"; computed once/url

--- Deterministic filesystem-safe cache filename for a full thumbnail URL.
--- Exported for tests; callers go through pathFor().
function M.cacheName(url)
  local cached = nameCache[url]
  if cached ~= nil then
    return cached
  end
  local enc = noctalia.string.urlEncode(url) -- C-level pass, '/' → %2F is fine
  local sig = string.format("%x_%x",
    edgeChecksum(url, false), edgeChecksum(url, true))
  if #enc > NAME_MAX - #sig - 2 then
    enc = enc:sub(1, NAME_MAX - #sig - 2)
  end
  cached = enc .. CHECKSUM_SEP .. sig .. SUFFIX
  nameCache[url] = cached
  return cached
end

-- ------------------------------------------------------------ cache state

local cacheDir = nil     -- "<pluginDataDir>/thumbnails" once usable
local disableNote = nil  -- why thumbnails are off, for logs/describe()

local queued = {}        -- FIFO of jobs { candidates={url,...}, idx, ... }
local enqueued = {}      -- url -> true (membership across queued jobs)
local active = nil       -- job currently downloading (or nil)
local failed = {}        -- url -> unix ts until which the miss is honoured

local settle -- forward declarations (settle -> startAttempt/sweep/pump chain)
local startAttempt
local pump

local function resolveBase()
  if cacheDir ~= nil or disableNote ~= nil then
    return
  end
  local dataDir = noctalia.pluginDataDir()
  if type(dataDir) ~= "string" or dataDir == "" then
    disableNote = "pluginDataDir unavailable"
  else
    local want = dataDir .. "/thumbnails"
    local ok, err = noctalia.mkdirAll(want)
    if ok ~= true then
      disableNote = "mkdir(" .. want .. ") failed: " .. tostring(err)
    else
      cacheDir = want
    end
  end
  if disableNote ~= nil then
    noctalia.log("[prusa-link] thumbnails disabled: " .. disableNote)
  end
end

local function pathFor(url)
  return cacheDir .. "/" .. M.cacheName(url)
end

-- ------------------------------------------------------------- maintenance

-- Called after successful writes; throttled so a grown cache never costs a
-- full stat()-every-file pass more often than SWEEP_GAP_S.
local lastSweepAt = 0
local function sweepIfHeavy()
  local now = os.time()
  if now - lastSweepAt < SWEEP_GAP_S then
    return
  end
  lastSweepAt = now
  local names, err = noctalia.listDir(cacheDir)
  if type(names) ~= "table" then
    noctalia.log("[prusa-link] thumb sweep failed to list dir: " .. tostring(err))
    return
  end
  local now = os.time()
  local files = {}
  local total = 0
  for _, name in ipairs(names) do
    local info = noctalia.fileInfo(cacheDir .. "/" .. name)
    if type(info) == "table" and info.isDir ~= true then
      if name:sub(-#PART) == PART then
        if now - (info.mtime or 0) > ORPHAN_AGE_S then
          noctalia.removeFile(cacheDir .. "/" .. name) -- crashed-download litter
        end
      else
        total = total + (info.size or 0)
        files[#files + 1] = { name = name, size = info.size or 0,
                              mtime = info.mtime or 0 }
      end
    end
  end
  if total <= MAX_BYTES then
    return
  end
  table.sort(files, function(x, y) return x.mtime < y.mtime end)
  for _, f in ipairs(files) do
    if total <= TRIM_TARGET then
      break
    end
    if noctalia.removeFile(cacheDir .. "/" .. f.name) == true then
      total = total - f.size
    end
  end
  noctalia.log(string.format(
    "[prusa-link] thumbnail cache trimmed to %.1f MiB", total / 1048576))
end

local function deliver(job, notify)
  if type(notify) ~= "function" then
    return
  end
  local okNotify, err = pcall(notify)
  if not okNotify then
    noctalia.log("[prusa-link] thumbnail change-callback error: " .. tostring(err))
  end
end

-- Record a per-URL miss and move the job to its next candidate, if any.
-- Returns true when another variant will be attempted (caller must NOT
-- finish the job in that case).
local function recordMissAndAdvance(job, tmpPath, note)
  local url = job.candidates[job.idx]
  noctalia.removeFile(tmpPath) -- best effort; curl --fail usually leaves none
  failed[url] = os.time() + RETRY_AFTER_S
  if note ~= nil then
    noctalia.log("[prusa-link] " .. note .. ": " .. url)
  end
  job.idx = job.idx + 1
  return job.candidates[job.idx] ~= nil
end

settle = function(job, tmpPath, res)
  res = res or {}
  local url = job.candidates[job.idx]
  local finalPath = pathFor(url)
  local fetched = res.ok == true
    and type(res.status) == "number"
    and res.status >= 200
    and res.status < 300
  local promoted = false
  if fetched then
    promoted = noctalia.renameFile(tmpPath, finalPath) == true
    if promoted then
      sweepIfHeavy()
    end
  end

  local problem = nil
  if not fetched then
    problem = res.status == 0
      and tostring(res.body ~= nil and res.body or "")
      or ("HTTP " .. tostring(res.status))
  elseif not promoted then
    problem = "rename " .. finalPath .. " failed"
  end

  local jobDone = true
  if problem ~= nil then
    jobDone = not recordMissAndAdvance(job, tmpPath, string.format(
      "thumbnail miss (%s), %s", problem,
      job.candidates[job.idx] ~= nil and "falling back" or "giving up"))
  end

  if jobDone then
    active = nil
    deliver(job, job.notify)
    pump() -- keep draining whatever queued meanwhile
  else
    startAttempt(job) -- next rendition immediately; still serial overall
  end
end

startAttempt = function(job)
  local url = job.candidates[job.idx]
  local finalPath = pathFor(url)
  if noctalia.fileExists(finalPath) then
    -- Raced into existence during queue-wait/earlier attempts; surface it
    -- instead of redownloading.
    active = nil
    deliver(job, job.notify)
    pump()
    return
  end
  local tmpPath = finalPath .. PART
  noctalia.removeFile(tmpPath) -- clear stale partials from old crashes
  local answered = false       -- a response settles an attempt exactly once
  http.request({
    url = url,
    method = "GET",
    username = job.user,
    password = job.pass,
    timeoutMs = TIMEOUT_MS,
    destPath = tmpPath,
  }, function(res)
    if answered then
      return
    end
    answered = true
    settle(job, tmpPath, res)
  end)
end

pump = function()
  while active == nil and #queued > 0 do
    local job = table.remove(queued, 1)
    for _, u in ipairs(job.candidates) do
      enqueued[u] = nil
    end
    active = job
    startAttempt(job)
    return
  end
end

-- ------------------------------------------------------------- public API

local function normUrls(urls) -- string | array -> clean array of urls
  if type(urls) == "string" and urls ~= "" then
    return { urls }
  end
  local out = {}
  if type(urls) == "table" then
    for _, url in ipairs(urls) do
      if type(url) == "string" and url ~= "" then
        out[#out + 1] = url
      end
    end
  end
  return out
end

--- Full URL for a printer-relative refs path such as
--- "/api/thumbnails/local/dir/file.gcode.small.png". Segments are
--- percent-encoded individually, slashes preserved. "" when unusable.
function M.thumbUrl(base, refPath)
  if type(base) ~= "string" or base == ""
    or type(refPath) ~= "string" or refPath == "" then
    return ""
  end
  local segments = {}
  for segment in refPath:gmatch("[^/]+") do
    segments[#segments + 1] = noctalia.string.urlEncode(segment)
  end
  if #segments == 0 then
    return ""
  end
  return base .. "/" .. table.concat(segments, "/")
end

--- Absolute local path when url's image sits in the cache, else nil.
local function isActionable(url) -- not on disk, not fresh-failed, not in flight
  if failed[url] ~= nil and os.time() < failed[url] then
    return false
  end
  return true
end

--- First cached local path across url (string) or urls (array), else nil.
function M.lookup(urls)
  resolveBase()
  if cacheDir == nil then
    return nil
  end
  for _, url in ipairs(normUrls(urls)) do
    local path = pathFor(url)
    if noctalia.fileExists(path) then
      return path
    end
  end
  return nil
end

--- "cached" | "pending" | "failed" | "missing" | "off".
--- Drives placeholder choice without retrying anything. Pass knownAbsent =
--- true when the caller has already established nothing is on disk. A mixed
--- list (one variant fresh-failed, another still fetchable) reads "missing"
--- so the viable variant keeps its chance.
function M.stateFor(urls, knownAbsent)
  local list = normUrls(urls)
  if #list == 0 then
    return "missing"
  end
  if not knownAbsent and M.lookup(list) ~= nil then
    return "cached"
  end
  if disableNote ~= nil then
    return "off"
  end
  for _, url in ipairs(list) do
    if (type(active) == "table" and active.candidates[active.idx] == url)
      or enqueued[url] then
      return "pending"
    end
  end
  for _, url in ipairs(list) do
    if isActionable(url) then
      return "missing"
    end
  end
  return "failed"
end

--- Queue a background download, trying candidates left to right (pass a
--- string or an array; digest creds ride per request). No-op — and returns
--- false — while off/cached/failed-within-TTL/already queued, so repeated
--- renders can't retry-storm; expired misses become actionable again after
--- RETRY_AFTER_S. notify() fires once the chain settles, pcall-guarded.
function M.request(urls, auth, notify)
  resolveBase()
  if cacheDir == nil then
    return false
  end
  local want = {}
  for _, url in ipairs(normUrls(urls)) do
    if enqueued[url]
      or (type(active) == "table" and active.candidates[active.idx] == url) then
      return false -- one live chain per file is enough; don't double-start
    end
    if isActionable(url) and not noctalia.fileExists(pathFor(url)) then
      want[#want + 1] = url
    end
  end
  if #want == 0 then
    return false
  end
  if #queued >= MAX_QUEUE then
    noctalia.log("[prusa-link] thumbnail queue full; dropping " .. want[1])
    return false
  end
  auth = auth or {}
  for _, url in ipairs(want) do
    enqueued[url] = true
  end
  queued[#queued + 1] = {
    candidates = want,
    idx = 1,
    user = auth.user or "",
    pass = auth.pass or "",
    notify = notify,
  }
  pump()
  return true
end

--- Introspection for logs/tests.
function M.describe()
  local failedCount = 0
  for _ in pairs(failed) do
    failedCount = failedCount + 1
  end
  return {
    enabled = cacheDir ~= nil,
    note = disableNote,
    dir = cacheDir,
    queued = #queued,
    active = type(active) == "table" and active.candidates[active.idx] or nil,
    failed = failedCount,
  }
end

return M