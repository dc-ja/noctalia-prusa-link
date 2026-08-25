--!nonstrict
--[[
  Shared HTTP helper for the PrusaLink entries (service, widget, panel).

  Auth reality (spiked against server 2.1.2, live-confirmed in Noctalia):
    - The printer speaks HTTP Digest only; Basic is rejected outright.
    - noctalia.http does NOT answer digest challenges.
    - HttpResponse exposes no headers, so we cannot do the RFC handshake.
  Therefore requests go native first; on a 401 the origin switches to a
  `curl --digest` bridge executed via the argv-table form of noctalia.runAsync
  (plugin_api >= 24) and stays there for the session. The bridge also restores
  real timeouts (-m) that HttpRequest lacks.

  HTTPS: native tries certificate verification first and retries once with
  allow_insecure_tls; the bridge mirrors this with -k. Decisions are cached
  per origin. Every callback fires EXACTLY ONCE.
]]

local M = {}

local insecureOrigins = {} -- origin -> true: skip strict-TLS attempts
local curlOrigins = {}     -- origin -> true: native 401'd once, use the bridge
local curlAvailable = nil  -- tri-state cache for commandExists("curl")

-- ------------------------------------------------------------ URL helpers

--- Parse a user-supplied address into { scheme, host, port, base }.
--- Accepts "[https://]host[:port][/...]"; trims whitespace, strips trailing
--- slashes, defaults scheme to http and port to 80/443. nil if unusable.
function M.parseTarget(raw)
  if type(raw) ~= "string" then
    return nil
  end
  local s = raw:match("^%s*(.-)%s*$")
  s = s:gsub("/+$", "")
  if s == "" then
    return nil
  end
  if not s:match("^%a[%w+.-]*://") then
    s = "http://" .. s
  end
  local scheme, rest = s:match("^(https?)://([^/]+)$")
  if not scheme then
    return nil
  end
  local host, portText = rest:match("^([^:/]+):(%d+)$")
  if not host then
    if rest:find(":", 1, true) then
      return nil -- colon present but port is not numeric
    end
    host = rest
  end
  if host == "" then
    return nil
  end
  local port = tonumber(portText)
  if port ~= nil and (port < 1 or port > 65535) then
    return nil
  end
  if port == nil then
    port = (scheme == "https") and 443 or 80
  end
  local base = scheme .. "://" .. host
  if not ((scheme == "http" and port == 80) or (scheme == "https" and port == 443)) then
    base = base .. ":" .. tostring(port)
  end
  return { scheme = scheme, host = host, port = port, base = base }
end

--- scheme://host[:port] with default ports elided (kept for callers/tests).
function M.buildBase(scheme, host, port)
  local t = M.parseTarget(scheme .. "://" .. host .. ":" .. tostring(port))
  if t then
    return t.base
  end
  return scheme .. "://" .. host
end

-- ----------------------------------------------------------- delivery guard

local function finishOnce(cb)
  local done = false
  return function(res)
    if done then
      return
    end
    done = true
    cb(res or { ok = false, status = 0, body = "nil response" })
  end
end

-- ------------------------------------------------------------- native path

local runBridge -- forward declaration; assigned below

local function nativeAttempt(finish, opts, insecure)
  local req = {
    url = opts.url,
    method = opts.method or "GET",
    headers = opts.headers,
    body = opts.body,
  }
  if opts.username and opts.username ~= "" then
    req.basic_username = opts.username
  end
  if opts.password and opts.password ~= "" then
    req.basic_password = opts.password
  end
  if insecure then
    req.allow_insecure_tls = true
  end
  local started = noctalia.http(req, function(res)
    local transportFailed = res == nil or res.ok == false
    local origin = string.match(opts.url or "", "^(https://[^/]+)")
    if transportFailed and origin ~= nil and insecure ~= true and opts.insecureFallback ~= false then
      insecureOrigins[origin] = true
      nativeAttempt(finish, opts, true)
      return
    end
    finish(res)
  end)
  if not started then
    finish({ ok = false, status = 0, body = "request rejected by host" })
  end
end

-- ------------------------------------------------------------- curl bridge

local function bridgeRun(finish, opts, insecure, timeoutSec)
  local origin = string.match(opts.url or "", "^(https?://[^/]+)") or ""
  local argv = { "curl", "-sS", "-m", tostring(timeoutSec), "--digest" }
  if (opts.username and opts.username ~= "") or (opts.password and opts.password ~= "") then
    argv[#argv + 1] = "-u"
    argv[#argv + 1] = (opts.username or "") .. ":" .. (opts.password or "")
  end
  if (opts.method or "GET") ~= "GET" then
    argv[#argv + 1] = "-X"
    argv[#argv + 1] = opts.method
  end
  if opts.body then
    argv[#argv + 1] = "--data-binary"
    argv[#argv + 1] = opts.body
  end
  for _, header in ipairs(opts.headers or {}) do
    argv[#argv + 1] = "-H"
    argv[#argv + 1] = header
  end
  local wantsInsecure = insecure == true or insecureOrigins[origin] == true
  if wantsInsecure and origin:sub(1, 6) == "https:" then
    argv[#argv + 1] = "-k"
  end
  argv[#argv + 1] = "-w"
  argv[#argv + 1] = "\n@@HTTP:%{http_code}"
  argv[#argv + 1] = opts.url

  local accepted = noctalia.runAsync(argv, function(result)
    result = result or {}
    if result.exitCode == 60 and not wantsInsecure and origin:sub(1, 6) == "https:" then
      insecureOrigins[origin] = true -- SSL certificate problem: retry once with -k
      bridgeRun(finish, opts, true, timeoutSec)
      return
    end
    if result.exitCode ~= 0 then
      local err = (result.stderr or ""):gsub("^%s+", ""):gsub("%s+$", "")
      local msg = "curl exit " .. tostring(result.exitCode)
      if err ~= "" then
        msg = msg .. ": " .. err
      end
      finish({ ok = false, status = 0, body = msg })
      return
    end
    local body, statusText = (result.stdout or ""):match("^(.*)\n@@HTTP:(%d+)$")
    if not statusText then
      local note = result.stdoutTruncated and " (output truncated)" or ""
      finish({ ok = false, status = 0, body = "curl output missing status marker" .. note })
      return
    end
    finish({ ok = true, status = tonumber(statusText) or 0, body = body })
  end)
  if not accepted then
    finish({ ok = false, status = 0, body = "curl could not be started" })
  end
end

runBridge = function(finish, opts)
  if curlAvailable == nil then
    curlAvailable = type(noctalia.commandExists) == "function"
      and noctalia.commandExists("curl")
      or false
    if not curlAvailable then
      noctalia.log("prusa-link: curl not found on PATH; digest auth cannot be bridged")
    end
  end
  if not curlAvailable then
    finish({ ok = false, status = 0, body = "curl not available on PATH" })
    return
  end
  local timeoutSec = math.floor((opts.timeoutMs or 5000) / 1000)
  if timeoutSec < 1 then
    timeoutSec = 1
  elseif timeoutSec > 60 then
    timeoutSec = 60
  end
  bridgeRun(finish, opts, false, timeoutSec)
end

-- -------------------------------------------------------------- public API

--- Issue one HTTP request. opts:
---   url (required), method ("GET"), headers ({ "H: v", ... }), body,
---   username / password, timeoutMs (bridge only; default 5000, clamp 1–60 s),
---   insecureFallback (default true).
--- cb receives { ok, status, body } exactly once. Origins whose native attempt
--- returns 401 switch to the curl --digest bridge for the rest of the session.
function M.request(opts, cb)
  local finish = finishOnce(cb)
  local origin = string.match(opts.url or "", "^(https?://[^/]+)") or ""

  if curlOrigins[origin] then
    runBridge(finish, opts)
    return
  end

  nativeAttempt(function(res)
    local hasCreds = (opts.username ~= nil and opts.username ~= "")
      or (opts.password ~= nil and opts.password ~= "")
    if res ~= nil and res.status == 401 and origin ~= "" and hasCreds then
      curlOrigins[origin] = true
      runBridge(finish, opts)
      return
    end
    finish(res)
  end, opts, insecureOrigins[origin] == true)
end

return M
