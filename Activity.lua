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
--   * logging in, a copy says which of the last 90 days' hours it has. The
--     copy that can fill the most of the gaps sends those hours and the
--     others stand down; then it asks again, so a gap the first couldn't
--     fill (or a message that went missing) is filled by someone else
--   * asking again later: when a copy that has hours we're missing says
--     which it has (it just logged in), or on Sync now. So a copy that came
--     online after our ask still fills us in
--
-- Hours merge without double counting: the peak is the highest anyone saw,
-- the people on are joined together, and the average comes from whichever
-- copy took the most samples. Anyone running the addon can contribute; it's
-- an observation, not an edit.
--
-- WIRE (see Sync.lua for the rest):
--   W hour peak avg10 samples id,id,...   one hour (several W's for a busy hour)
--   y from count bits                     the hours from..from+count-1 I have,
--                                         6 to a character (see DIGITS)
--   z target from                         "I'll fill target's gaps from there"
--   w base id:run.run,...                 who was on, by person; a run is
--                                         "start" or "start+more", hours after
--                                         base, in base 36
--   h base gap.peak.avg10.samples,...     each hour's numbers, in base 36; gap
--                                         is hours after the one before (the
--                                         first is base). These follow their
--                                         w's and complete those hours.
--   Y lastHour / Z target                 the older catch-up (a week after the
--                                         newest hour), for copies that
--                                         haven't updated
-- An id is a GUID without its "Player-" prefix.

local _, NS = ...
local PGM = NS.PGM
local P = PGM.Plain

local SAMPLE_EVERY = 5 * 60
local KEEP_HOURS = 92 * 24      -- the longest page shows 90 days
local CATCHUP_HOURS = 7 * 24    -- how far the older catch-up reaches
local GAP_HOURS = 90 * 24       -- how far back a copy asks about gaps
local PIECE_HOURS = 1200        -- hours per "y" (200 characters)
local HAVE_SAMPLES = 6          -- half an hour watched: we have that hour
local GAP_ROUNDS = 3            -- asks per session, while someone answers
local REASK_GAP = 120           -- seconds between asks prompted by someone else
local GIVEN_FOR = 600           -- seconds an answer counts as on its way

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

-- Base 36 for numbers, and 6 bits per character for the "y" bits.
local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-_"
local function b36(n)
    n = math.floor(n)
    if n <= 0 then return "0" end
    local s = ""
    while n > 0 do
        local d = n % 36
        s = DIGITS:sub(d + 1, d + 1) .. s
        n = math.floor(n / 36)
    end
    return s
end
local POW = { 1, 2, 4, 8, 16, 32 }
local function bitAt(bits, i)
    local c = bits:sub(math.floor(i / 6) + 1, math.floor(i / 6) + 1)
    local v = c ~= "" and DIGITS:find(c, 1, true)
    if not v then return false end
    return math.floor((v - 1) / POW[i % 6 + 1]) % 2 == 1
end

local function hasHour(a, key)
    local h = a.hours[key]
    return h ~= nil and (h.n or 0) >= HAVE_SAMPLES
end

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

-- Merge a shared hour into ours. True if it changed anything; `quiet`
-- leaves telling the page to the caller (a catch-up merges many at once).
local function mergeHour(key, peak, avg10, samples, ids, quiet)
    local g, a = store()
    if not (g and key and peak) then return false end
    local now = hourOf(PGM.Now())
    if key > now or key < now - KEEP_HOURS then return false end
    local h = a.hours[key] or { p = 0, n = 0, s = 0, m = "" }
    local set = toSet(h.m)
    local changed = false
    for id in (ids or ""):gmatch("[^,]+") do
        local guid = fullGuid(id)
        if not set[id] and (g.members[guid] or g.former[guid]) then
            set[id] = true
            changed = true
        end
    end
    h.m = fromSet(set)
    -- No more online at once than were seen on in the hour at all (an hour
    -- comes in batches, so this rises as the rest of its list arrives).
    local seen = 0
    for _ in pairs(set) do seen = seen + 1 end
    local before = h.p or 0
    h.p = math.max(before, math.min(peak, seen))
    if h.p ~= before then changed = true end
    -- The average from whoever watched the hour most closely.
    if (samples or 0) > (h.n or 0) and avg10 then
        h.n = samples
        h.s = avg10 / 10 * samples
        changed = true
    end
    a.hours[key] = h
    heard[key] = math.max(heard[key] or 0, samples or 0)
    if changed and not quiet then PGM:Fire("ACTIVITY") end
    return changed
end

local handlers = PGM.SyncHandlers or {}

-- Anyone may send these, so keep the numbers possible: no more samples than
-- an hour holds, no more online than the guild has (or than the hour's list
-- of who was on, see mergeHour), and an average no higher than the peak.
local MAX_SAMPLES = math.floor(3600 / SAMPLE_EVERY) + 1
local function saneHour(key, peak, avg10, samples)
    if not (key and peak and peak >= 0) then return nil end
    local members = PGM.CountMembers and PGM:CountMembers() or 0
    if members > 0 and peak > members then return nil end
    if key > hourOf(PGM.Now()) then return nil end
    samples = samples and math.max(0, math.min(math.floor(samples), MAX_SAMPLES)) or nil
    avg10 = avg10 and math.max(0, math.min(avg10, peak * 10)) or nil
    return peak, avg10, samples
end

function handlers.W(f)
    local key = tonumber(f[2])
    local peak, avg10, samples = saneHour(key, tonumber(f[3]), tonumber(f[4]), tonumber(f[5]))
    if peak then mergeHour(key, peak, avg10, samples, f[6]) end
end

-- ---------- the older catch-up, for copies that haven't updated ----------

-- Someone has nothing after `lastHour`. If we have newer hours, volunteer
-- after a random wait, unless someone else volunteers first.
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

function handlers.Z(f)
    -- Someone else is already catching that player up: stand down.
    if volunteer and volunteerFor and PGM.SyncNorm(f[2]) == PGM.SyncNorm(volunteerFor) then
        volunteer:Cancel()
        volunteer, volunteerFor = nil, nil
    end
end

-- ---------- filling gaps ----------

-- The hours we were asked for and have, sent by person: each person once,
-- with the stretches they were on, then each hour's numbers.
local LIMIT = 248
local function packer(kind, base)
    local head = #kind + 1 + #tostring(base) + 1
    local items, size = {}, head
    local p = {}
    function p.flush()
        if #items > 0 then PGM.SyncSend(true, kind, base, table.concat(items, ",")) end
        items, size = {}, head
    end
    function p.add(item)
        if size + #item + 1 > LIMIT and #items > 0 then p.flush() end
        items[#items + 1] = item
        size = size + #item + 1
    end
    return p
end

local function sendGaps(keys)
    local _, a = store()
    if not (a and keys[1]) then return end
    local base = keys[1]
    local per, order = {}, {}
    for _, key in ipairs(keys) do
        for id in (a.hours[key].m or ""):gmatch("[^,]+") do
            local l = per[id]
            if not l then
                l = {}
                per[id] = l
                order[#order + 1] = id
            end
            l[#l + 1] = key - base
        end
    end
    table.sort(order)

    local people = packer("1w", base)
    for _, id in ipairs(order) do
        local offs, runs = per[id], {}
        local start, prev = offs[1], offs[1]
        for i = 2, #offs + 1 do
            local o = offs[i]
            if o and o == prev + 1 then
                prev = o
            else
                runs[#runs + 1] = prev == start and b36(start) or (b36(start) .. "+" .. b36(prev - start))
                if o then start, prev = o, o end
            end
        end
        -- Someone on for many separate stretches goes in more than one item.
        local item, empty = id .. ":", true
        for _, r in ipairs(runs) do
            if not empty and #item + #r + 1 > 200 then
                people.add(item)
                item, empty = id .. ":", true
            end
            item = item .. (empty and "" or ".") .. r
            empty = false
        end
        people.add(item)
    end
    people.flush()

    -- Each message of numbers starts at its own first hour; the hours after
    -- it are gaps from the one before.
    local items, size, first, last = {}, 0, nil, nil
    local function flush()
        if first then PGM.SyncSend(true, "1h", first, table.concat(items, ",")) end
        items, first = {}, nil
    end
    for _, key in ipairs(keys) do
        local h = a.hours[key]
        local avg10 = h.n > 0 and math.floor(h.s / h.n * 10 + 0.5) or (h.p * 10)
        local tail = "." .. b36(h.p) .. "." .. b36(avg10) .. "." .. b36(h.n)
        local item = first and (b36(key - last) .. tail) or tail
        if first and size + #item + 1 > LIMIT then
            flush()
            item = tail
        end
        if not first then
            first = key
            size = 2 + 1 + #tostring(key) + 1
        end
        items[#items + 1] = item
        size = size + #item + 1
        last = key
    end
    flush()
end

-- Someone said which hours they have. If we have some they don't, offer to
-- send them: whoever can fill the most waits least (by how many, not by
-- share: most gaps are hours nobody saw); the rest hear "z" and stand down.
local offers = {}   -- [who .. ":" .. from] = timer
local function offerId(who, from) return PGM.SyncNorm(who or "") .. ":" .. tostring(from) end

-- Hours already queued for someone: [who] = { [hour] = when }. Asked again
-- while they're still going out (behind a records catch-up, say), they
-- aren't queued twice; once the queue is empty, asking again means some
-- went missing, so they're sent again.
local given = {}
local function alreadyGiven(who, key)
    local t = given[who] and given[who][key]
    if not t or GetTime() - t > GIVEN_FOR then return false end
    return (PGM.SyncQueued and PGM:SyncQueued() or 0) > 0
end

local askSoon   -- below: ask again because someone has hours we don't

function handlers.y(f, sender)
    local from, count, bits = tonumber(f[2]), tonumber(f[3]), f[4] or ""
    if not (from and count and count >= 1 and count <= PIECE_HOURS) then return end
    from, count = math.floor(from), math.floor(count)
    local _, a = store()
    if not a then return end
    local now = hourOf(PGM.Now())
    local who = PGM.SyncNorm(sender or "")
    local keys, theyHaveMore = {}, false
    for i = 0, count - 1 do
        local key = from + i
        if key >= now then break end   -- the hour in progress isn't over yet
        local theirs = bitAt(bits, i)
        if not theirs and hasHour(a, key) and not alreadyGiven(who, key) then keys[#keys + 1] = key end
        if theirs and not hasHour(a, key) then theyHaveMore = true end
    end
    -- They run this version and have hours we're missing.
    if theyHaveMore then askSoon() end
    if #keys == 0 then return end
    local id = offerId(sender, from)
    if offers[id] then offers[id]:Cancel() end
    offers[id] = C_Timer.NewTimer(1 + 6 / (1 + #keys) + math.random() * 2, function()
        offers[id] = nil
        PGM.SyncSend(false, "1z", sender, from)
        given[who] = given[who] or {}
        local at = GetTime()
        for _, key in ipairs(keys) do given[who][key] = at end
        sendGaps(keys)
    end)
end

-- Our own ask: how many rounds this session, and whether anyone answered.
local asked = { rounds = 0, answered = false }
local quiet
local askForGaps

-- Once someone answers, ask again after their hours stop coming: whatever
-- they couldn't fill (or whatever went missing) someone else may have.
local function askAgainWhenQuiet()
    if quiet then quiet:Cancel() end
    quiet = C_Timer.NewTimer(30, function()
        quiet = nil
        if asked.rounds < GAP_ROUNDS then askForGaps() end
    end)
end

function handlers.z(f)
    local id = offerId(f[2], tonumber(f[3]))
    if offers[id] then
        offers[id]:Cancel()
        offers[id] = nil
    end
    if PGM.SyncIsMe and PGM.SyncIsMe(f[2]) then
        asked.answered = true
        askAgainWhenQuiet()
    end
end

-- People heard before their hours' numbers; the numbers ("h") complete them.
-- Kept apart till then, so an hour half-heard (a reload mid catch-up) is
-- still a gap next time rather than an hour with nobody's numbers.
local pending = {}   -- [hour] = { [id] = true }

function handlers.w(f)
    local g = PGM.GuildDB()
    local base = tonumber(f[2])
    if not (g and base) then return end
    local now = hourOf(PGM.Now())
    for item in (f[3] or ""):gmatch("[^,]+") do
        local id, runs = item:match("^([^:]+):(.+)$")
        local guid = id and fullGuid(id)
        if guid and (g.members[guid] or g.former[guid]) then
            for run in runs:gmatch("[^.]+") do
                local s, more = run:match("^(%w+)%+?(%w*)$")
                s = s and tonumber(s, 36)
                if more == nil or more == "" then more = 0 else more = tonumber(more, 36) end
                if s and more and s <= GAP_HOURS and more <= PIECE_HOURS then
                    for key = base + s, base + s + more do
                        if key < now and key >= now - KEEP_HOURS then
                            local set = pending[key] or {}
                            set[id] = true
                            pending[key] = set
                        end
                    end
                end
            end
        end
    end
    if quiet then askAgainWhenQuiet() end
end

function handlers.h(f)
    local key = tonumber(f[2])
    if not key then return end
    local changed = false
    for item in (f[3] or ""):gmatch("[^,]+") do
        local d, p, a10, n = item:match("^(%w*)%.(%w+)%.(%w+)%.(%w+)$")
        if not p then break end
        d = d == "" and 0 or tonumber(d, 36)
        if not (d and d <= PIECE_HOURS) then break end
        key = key + d
        local peak, avg10, samples = saneHour(key, tonumber(p, 36), tonumber(a10, 36), tonumber(n, 36))
        if peak then
            local set = pending[key]
            pending[key] = nil
            if mergeHour(key, peak, avg10, samples, set and fromSet(set) or "", true) then changed = true end
        end
    end
    if changed then PGM:Fire("ACTIVITY") end
    if quiet then askAgainWhenQuiet() end
end

-- Tell the guild which of the last 90 days' hours we have, in pieces.
-- False if we have them all (nothing to ask).
askForGaps = function()
    local _, a = store()
    if not (a and PGM.SyncSend) then return false end
    local now = hourOf(PGM.Now())
    local first, last = now - GAP_HOURS, now - 1
    local sent = false
    for from = first, last, PIECE_HOURS do
        local count = math.min(PIECE_HOURS, last - from + 1)
        local chars, missing = {}, 0
        for i = 0, count - 1, 6 do
            local v = 0
            for b = 0, 5 do
                if i + b < count then
                    if hasHour(a, from + i + b) then v = v + POW[b + 1] else missing = missing + 1 end
                end
            end
            chars[#chars + 1] = DIGITS:sub(v + 1, v + 1)
        end
        if missing > 0 then
            PGM.SyncSend(false, "1y", from, count, table.concat(chars))
            sent = true
        end
    end
    if sent then
        asked.rounds = asked.rounds + 1
        asked.answered = false
    end
    return sent
end

-- Ask again, soon: someone who has hours we're missing just said so (or
-- Sync now was pressed). Not while an answer is still arriving, and not
-- more than every couple of minutes.
local reask, lastReask = nil, -1000
askSoon = function(now)
    if reask or quiet or GetTime() - lastReask < REASK_GAP then return end
    local g = PGM.GuildDB()
    if not (g and g.seeded) then return end
    reask = C_Timer.NewTimer(now and 1 or (5 + math.random() * 10), function()
        reask = nil
        if quiet then return end
        lastReask = GetTime()
        askForGaps()
    end)
end

if PGM.SyncNow then
    local hello = PGM.SyncNow
    PGM.SyncNow = function(...)
        hello(...)
        askSoon(true)
    end
end

-- The older ask, for when nobody running this version answers.
local function askTheOldWay()
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
end

-- After logging in: ask for what we're missing, then share each hour as it ends.
local started = false
PGM:On("ROSTER", function()
    if started then return end
    local g = PGM.GuildDB()
    if not (g and g.seeded) then return end
    started = true
    prune()
    C_Timer.After(30, function()
        if not askForGaps() then return end
        C_Timer.After(20, function()
            if asked.rounds == 1 and not asked.answered then askTheOldWay() end
        end)
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
-- Remembered per hour: the answer never changes within a session.
local localParts = {}
local function local_(key)
    local t = localParts[key]
    if not t then
        local d = date("*t", key * 3600)
        t = { d.hour, d.wday }
        localParts[key] = t
    end
    return t[1], t[2]
end

-- Each hour's "who was on" list, parsed once and again only if it changes.
local parsed = {}
local function membersOf(key, h)
    local m = h.m or ""
    local c = parsed[key]
    if not c or c.m ~= m then
        c = { m = m, list = {} }
        for id in m:gmatch("[^,]+") do c.list[#c.list + 1] = fullGuid(id) end
        parsed[key] = c
    end
    return c.list
end

-- Results by period. They only go stale when the hours change (ACTIVITY),
-- when someone joins, leaves or is relinked (the guild's versions below),
-- or when the hour turns; not on every roster read.
local caches, cacheFor = {}, nil
PGM:On("ACTIVITY", function() wipe(caches) end)
PGM:On("ROSTER", function()
    local v = (PGM.membersVersion or 0) .. ":" .. (PGM.altsVersion or 0)
    if v ~= cacheFor then
        cacheFor = v
        wipe(caches)
    end
end)

-- Everything the Activity page shows, for the last `days` days.
-- mainsOnly folds each alt's hours into its main.
function PGM:ComputeActivity(days, mainsOnly)
    local key = days .. (mainsOnly and "m" or "a") .. hourOf(PGM.Now())
    if caches[key] then return caches[key] end
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
            for _, guid in ipairs(membersOf(hkey, h)) do
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
        return PGM.NameLess(x.rec.short, y.rec.short)
    end)
    caches[key] = o
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
