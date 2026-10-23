-- Activity.lua: when the guild plays, and who plays when.
--
-- The guild roster shows everyone's online status, addon or not, so one copy
-- of the addon sees the whole guild while its player is logged in. Every five
-- minutes it notes who's online (in the game; the mobile app doesn't count).
-- Those notes are kept per hour: the most online at once, the average, and
-- who was on at some point. A copy only sees the hours its player is on;
-- sharing fills in the rest:
--
--   * after each hour, one copy (chosen at random among those online) sends
--     that hour to the guild; the others hear it and don't repeat it
--   * logging in after time away, a copy asks for the hours it missed (up to
--     a week back) and one copy that has them sends them
--
-- Hours merge without double counting: the peak is the highest anyone saw,
-- the people on are joined together, and the average comes from whichever
-- copy took the most samples. Anyone running the addon can contribute; it's
-- an observation, not an edit.
--
-- WIRE (see Sync.lua for the rest):
--   W hour peak avg10 samples id,id,...   one hour (several W's for a busy hour)
--   Y lastHour                            "I've nothing after this hour"
--   Z target                              "I'll catch target up"
-- An id is a GUID without its "Player-" prefix.

local _, NS = ...
local PGM = NS.PGM
local P = PGM.Plain

local SAMPLE_EVERY = 5 * 60
local KEEP_HOURS = 120 * 24
local CATCHUP_HOURS = 7 * 24

local lastSample = 0

local function store()
    local g = PGM.GuildDB(true)
    if not g then return nil end
    g.activity = g.activity or {}
    g.activity.hours = g.activity.hours or {}
    return g, g.activity
end

local function hourOf(t) return math.floor(t / 3600) end

local function shortId(guid) return (guid:gsub("^Player%-", "")) end
local function fullGuid(id) return "Player-" .. id end

-- "id,id,id" <-> set
local function toSet(text)
    local set = {}
    for id in (text or ""):gmatch("[^,]+") do set[id] = true end
    return set
end
local function fromSet(set)
    local ids = {}
    for id in pairs(set) do ids[#ids + 1] = id end
    table.sort(ids)
    return table.concat(ids, ",")
end

-- ============================================================
-- SAMPLING
-- ============================================================

local function sample()
    local g, a = store()
    if not (g and g.seeded and g.lastComplete) then return end
    local now = PGM.Now()
    -- Only from a fresh, complete roster read.
    if now - g.lastComplete > 180 then return end
    local key = hourOf(now)
    local h = a.hours[key] or { p = 0, n = 0, s = 0, m = "" }
    local set = toSet(h.m)
    local online = 0
    for guid, rec in pairs(g.members) do
        if rec.online and not rec.mobile then
            online = online + 1
            set[shortId(guid)] = true
        end
    end
    h.p = math.max(h.p or 0, online)
    h.n = (h.n or 0) + 1
    h.s = (h.s or 0) + online
    h.m = fromSet(set)
    a.hours[key] = h
    lastSample = now
    PGM:Fire("ACTIVITY")
end

PGM:On("ROSTER", function()
    if PGM.Now() - lastSample >= SAMPLE_EVERY then sample() end
end)

-- Old hours go, so saved data stays small.
local function prune()
    local _, a = store()
    if not a then return end
    local oldest = hourOf(PGM.Now()) - KEEP_HOURS
    for key in pairs(a.hours) do
        if key < oldest then a.hours[key] = nil end
    end
end

-- ============================================================
-- SHARING
-- ============================================================

local heard = {}   -- [hour] = samples someone else already shared for it

-- One hour, split across as many messages as its list of people needs.
local function sendHour(key, bulk)
    local _, a = store()
    local h = a and a.hours[key]
    if not (h and PGM.SyncSend) then return end
    local avg10 = h.n > 0 and math.floor(h.s / h.n * 10 + 0.5) or (h.p * 10)
    local head = table.concat({ "1W", key, h.p, avg10, h.n }, "\031")
    local batch, size = {}, #head + 1
    local function flush()
        PGM.SyncSend(bulk, "1W", key, h.p, avg10, h.n, table.concat(batch, ","))
        batch, size = {}, #head + 1
    end
    for id in (h.m or ""):gmatch("[^,]+") do
        if size + #id + 1 > 248 then flush() end
        batch[#batch + 1] = id
        size = size + #id + 1
    end
    if #batch > 0 or h.m == "" then flush() end
end

-- After each hour: wait a random bit, then share it unless someone already did.
local function shareFinishedHour()
    local key = hourOf(PGM.Now()) - 1
    local _, a = store()
    local h = a and a.hours[key]
    if not h or (h.n or 0) < 2 then return end
    C_Timer.After(5 + math.random() * 90, function()
        if (heard[key] or 0) >= h.n * 0.8 then return end
        sendHour(key, true)
        heard[key] = h.n
    end)
end

-- Merge a shared hour into ours.
local function mergeHour(key, peak, avg10, samples, ids)
    local g, a = store()
    if not (g and key and peak) then return end
    local now = hourOf(PGM.Now())
    if key > now or key < now - KEEP_HOURS then return end
    local h = a.hours[key] or { p = 0, n = 0, s = 0, m = "" }
    local set = toSet(h.m)
    local added = false
    for id in (ids or ""):gmatch("[^,]+") do
        local guid = fullGuid(id)
        if not set[id] and (g.members[guid] or g.former[guid]) then
            set[id] = true
            added = true
        end
    end
    h.m = fromSet(set)
    h.p = math.max(h.p or 0, peak)
    -- The average from whoever watched the hour most closely.
    if (samples or 0) > (h.n or 0) and avg10 then
        h.n = samples
        h.s = avg10 / 10 * samples
    end
    a.hours[key] = h
    heard[key] = math.max(heard[key] or 0, samples or 0)
    if added then PGM:Fire("ACTIVITY") end
end

local handlers = PGM.SyncHandlers or {}

function handlers.W(f)
    local key, peak, avg10, samples = tonumber(f[2]), tonumber(f[3]), tonumber(f[4]), tonumber(f[5])
    if not (key and peak and peak >= 0 and peak < 5000) then return end
    mergeHour(key, peak, avg10, samples, f[6])
end

-- Catch-up: someone has nothing after `lastHour`. If we have newer hours,
-- volunteer after a random wait, unless someone else volunteers first.
local volunteer, volunteerFor
function handlers.Y(f, sender)
    local since = tonumber(f[2]) or 0
    local _, a = store()
    if not a then return end
    local newest = 0
    for key in pairs(a.hours) do if key > newest then newest = key end end
    if newest <= since + 1 then return end
    if volunteer then volunteer:Cancel() end
    volunteerFor = sender
    volunteer = C_Timer.NewTimer(1 + math.random() * 5, function()
        volunteer, volunteerFor = nil, nil
        PGM.SyncSend(false, "1Z", sender)
        local from = math.max(since + 1, hourOf(PGM.Now()) - CATCHUP_HOURS)
        local keys = {}
        for key in pairs(a.hours) do if key >= from then keys[#keys + 1] = key end end
        table.sort(keys)
        for _, key in ipairs(keys) do sendHour(key, true) end
    end)
end

function handlers.Z(f, sender)
    -- Someone else is already catching that player up: stand down.
    if volunteer and volunteerFor and PGM.SyncNorm(f[2]) == PGM.SyncNorm(volunteerFor) then
        volunteer:Cancel()
        volunteer, volunteerFor = nil, nil
    end
end

-- After logging in: ask for what we missed, then share each hour as it ends.
local started = false
PGM:On("ROSTER", function()
    if started then return end
    local g = PGM.GuildDB()
    if not (g and g.seeded) then return end
    started = true
    prune()
    C_Timer.After(30, function()
        local _, a = store()
        if not (a and PGM.SyncSend) then return end
        local newest = 0
        for key in pairs(a.hours) do
            -- The hours of this session don't count as "what we have".
            if key > newest and key < hourOf(PGM.Now()) - 1 then newest = key end
        end
        if newest < hourOf(PGM.Now()) - 2 then
            PGM.SyncSend(false, "1Y", math.max(newest, hourOf(PGM.Now()) - CATCHUP_HOURS))
        end
    end)
    -- Check at each new hour whether to share the one that just ended.
    local lastHour = hourOf(PGM.Now())
    C_Timer.NewTicker(60, function()
        local h = hourOf(PGM.Now())
        if h ~= lastHour then
            lastHour = h
            shareFinishedHour()
        end
    end)
end)

-- ============================================================
-- READING
-- ============================================================

-- Local clock parts for an hour key: hour of day (0-23), weekday (1 = Sunday).
local function local_(key)
    local t = date("*t", key * 3600)
    return t.hour, t.wday
end
PGM.ActivityLocalTime = local_

local cache, cacheKey = nil, nil
PGM:On("ACTIVITY", function() cache = nil end)
PGM:On("ROSTER", function() cache = nil end)

-- Everything the Activity page shows, for the last `days` days.
-- mainsOnly folds each alt's hours into its main.
function PGM:ComputeActivity(days, mainsOnly)
    local key = days .. (mainsOnly and "m" or "a")
    if cache and cacheKey == key then return cache end
    local g, a = store()
    local o = {
        days = days, observed = 0, possible = days * 24, sumAvg = 0, avg = 0,
        peak = 0, peakAt = nil, byHour = {}, byCell = {}, people = {},
    }
    for hr = 0, 23 do o.byHour[hr] = { sum = 0, n = 0, peak = 0 } end
    for wd = 1, 7 do
        o.byCell[wd] = {}
        for hr = 0, 23 do o.byCell[wd][hr] = { sum = 0, n = 0 } end
    end
    if not a then return o end

    local now = hourOf(PGM.Now())
    local from = now - days * 24
    local per = {}
    for hkey, h in pairs(a.hours) do
        if hkey >= from and hkey <= now then
            o.observed = o.observed + 1
            local avg = (h.n or 0) > 0 and h.s / h.n or h.p
            o.sumAvg = o.sumAvg + avg
            if (h.p or 0) > o.peak then o.peak, o.peakAt = h.p, hkey * 3600 end
            local hr, wd = local_(hkey)
            local b = o.byHour[hr]
            b.sum, b.n, b.peak = b.sum + avg, b.n + 1, math.max(b.peak, h.p or 0)
            local c = o.byCell[wd][hr]
            c.sum, c.n = c.sum + avg, c.n + 1
            -- Who played: one hour per person per hour slot, alts folded in.
            local seenThisHour = {}
            for id in (h.m or ""):gmatch("[^,]+") do
                local guid = fullGuid(id)
                if g.members[guid] then
                    local who = mainsOnly and PGM:MainOf(guid) or guid
                    if not seenThisHour[who] then
                        seenThisHour[who] = true
                        local p = per[who]
                        if not p then
                            p = { guid = who, hours = 0, byHour = {}, byDay = {}, last = 0 }
                            per[who] = p
                        end
                        p.hours = p.hours + 1
                        p.byHour[hr] = (p.byHour[hr] or 0) + 1
                        p.byDay[wd] = (p.byDay[wd] or 0) + 1
                        if hkey > p.last then p.last = hkey end
                    end
                end
            end
        end
    end
    o.avg = o.observed > 0 and o.sumAvg / o.observed or 0

    -- The busiest hour of the week, by average online.
    local best
    for wd = 1, 7 do
        for hr = 0, 23 do
            local c = o.byCell[wd][hr]
            if c.n > 0 and (not best or c.sum / c.n > best.avg) then
                best = { wd = wd, hr = hr, avg = c.sum / c.n }
            end
        end
    end
    o.busiest = best

    for _, p in pairs(per) do
        p.rec = g.members[p.guid]
        o.people[#o.people + 1] = p
    end
    table.sort(o.people, function(x, y)
        if x.hours ~= y.hours then return x.hours > y.hours end
        return (x.rec.short or "") < (y.rec.short or "")
    end)
    cache, cacheKey = o, key
    return o
end

local DAYS = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }
PGM.WEEKDAYS = DAYS

function PGM.HourLabel(hr)
    local h12 = hr % 12 == 0 and 12 or hr % 12
    return h12 .. (hr < 12 and "am" or "pm")
end

-- "8pm-11pm": the three-hour stretch someone is most often on.
function PGM.UsualTime(p)
    local bestStart, bestSum = nil, 0
    for start = 0, 23 do
        local sum = 0
        for i = 0, 2 do sum = sum + (p.byHour[(start + i) % 24] or 0) end
        if sum > bestSum then bestStart, bestSum = start, sum end
    end
    if not bestStart then return "-" end
    return PGM.HourLabel(bestStart) .. "-" .. PGM.HourLabel((bestStart + 3) % 24)
end

function PGM.TopDay(p)
    local bestDay, bestN = nil, 0
    for wd = 1, 7 do
        if (p.byDay[wd] or 0) > bestN then bestDay, bestN = wd, p.byDay[wd] end
    end
    return bestDay and DAYS[bestDay] or "-"
end

-- One member's last 30 days, for their profile (alts folded into the main).
function PGM:ActivityFor(guid)
    local o = PGM:ComputeActivity(30, true)
    local main = PGM:MainOf(guid)
    for _, p in ipairs(o.people) do
        if p.guid == main then return p, o end
    end
    return nil, o
end
