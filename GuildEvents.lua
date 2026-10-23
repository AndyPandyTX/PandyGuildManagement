-- GuildEvents.lua: who made each change.
--
-- The roster shows that someone was promoted, demoted or is gone, but not
-- who did it. Two things say:
--   * the game's system messages ("X has demoted Y to Member.", "Y has been
--     kicked out of the guild by X."), which arrive at once but only while
--     you're online;
--   * the guild event log, the game's own record of the last hundred or so
--     invites, joins, promotions, demotions, kicks and leaves, with who did
--     each and roughly when.
-- A History entry is credited from a system message when there was one,
-- and otherwise from the event log, so changes made while you were offline
-- get credited too.

local _, NS = ...
local PGM = NS.PGM
local P = PGM.Plain

local MESSAGE_KEEP = 600        -- a system message counts for ten minutes
local LOOKBACK = 14 * 86400     -- History entries this recent can still be credited
local QUERY_GAP = 60

local function shortName(name)
    name = P(name)
    if type(name) ~= "string" or name == "" then return nil end
    return name:match("^([^%-]+)") or name
end

local function nameKey(name)
    local s = shortName(name)
    return s and s:lower()
end

-- ============================================================
-- SYSTEM MESSAGES
-- ============================================================

-- "%s has promoted %s to %s." -> "^(.+) has promoted (.+) to (.+)%.$"
local function toPattern(fmt)
    if type(fmt) ~= "string" then return nil end
    local parts = {}
    for piece in (fmt .. "%s"):gmatch("(.-)%%%d*%$?s") do
        parts[#parts + 1] = (piece:gsub("[%(%)%.%+%-%*%?%[%]%^%$%%]", "%%%0"))
    end
    return "^" .. table.concat(parts, "(.+)") .. "$"
end

-- Which capture is the doer and which the member, per message.
local MESSAGES = {
    { name = "ERR_GUILD_PROMOTE_SSS", kind = "promote", by = 1, who = 2 },
    { name = "ERR_GUILD_DEMOTE_SSS",  kind = "demote",  by = 1, who = 2 },
    { name = "ERR_GUILD_REMOVE_SS",   kind = "remove",  who = 1, by = 2 },
    { name = "ERR_GUILD_LEAVE_S",     kind = "quit",    who = 1 },
}

local recent = {}   -- ["kind:member"] = { by = name, t = when }

PGM:RegisterEvent("CHAT_MSG_SYSTEM", function(_, text)
    text = P(text)
    if type(text) ~= "string" then return end
    for _, m in ipairs(MESSAGES) do
        if m.pattern == nil then m.pattern = toPattern(_G[m.name]) or false end
        if m.pattern then
            local caps = { text:match(m.pattern) }
            if #caps > 0 then
                local who = nameKey(caps[m.who])
                if who then
                    recent[m.kind .. ":" .. who] = { by = m.by and shortName(caps[m.by]), t = PGM.Now() }
                end
                return
            end
        end
    end
end)

local function take(kind, who)
    local k = kind .. ":" .. (who or "")
    local r = recent[k]
    if r and PGM.Now() - r.t <= MESSAGE_KEEP then
        recent[k] = nil
        return r
    end
end

-- Called for every new History entry (Roster.lua): credit it from a system
-- message if one just came in.
function PGM:CreditLog(e)
    if e.credited then return end
    local who = e.name and e.name:lower()
    if e.kind == "promote" or e.kind == "demote" then
        local r = take(e.kind, who)
        if r and r.by then e.by, e.credited = r.by, true end
    elseif e.kind == "leave" then
        local r = take("remove", who)
        if r then
            e.removed, e.by, e.credited = true, r.by or e.by, true
        elseif take("quit", who) then
            e.removed, e.credited = nil, true
        end
    end
end

-- ============================================================
-- THE GUILD EVENT LOG
-- ============================================================

local CREDIT = { promote = true, demote = true, leave = true, join = true, rejoin = true }

local function uncredited(g, now)
    for i = #g.log, 1, -1 do
        local e = g.log[i]
        if not e.t or now - e.t > LOOKBACK then return false end
        if CREDIT[e.kind] and not e.credited then return true end
    end
    return false
end

-- Newest first. "join" and "quit" name only the member; the others name the
-- doer first and the member second.
local function readEvents(now)
    local events = {}
    if type(GetNumGuildEvents) ~= "function" or type(GetGuildEventInfo) ~= "function" then return events end
    local ok, n = pcall(GetNumGuildEvents)
    n = ok and P(n) or 0
    for i = n, 1, -1 do
        local okI, typ, p1, p2, _, year, month, day, hour = pcall(GetGuildEventInfo, i)
        typ = okI and P(typ)
        if type(typ) == "string" then
            local solo = typ == "join" or typ == "quit"
            local ago = ((((P(year) or 0) * 365 + (P(month) or 0) * 30 + (P(day) or 0)) * 24) + (P(hour) or 0)) * 3600
            events[#events + 1] = {
                typ = typ,
                by = not solo and shortName(p1) or nil,
                who = nameKey(solo and p1 or p2),
                at = now - ago,
            }
        end
    end
    return events
end

-- Match uncredited entries to events, newest to newest, each event used
-- once. An event can't be after the entry it explains (give or take the
-- log's one-hour rounding), nor more than a week before it.
function PGM:CreditFromEventLog(events)
    local g = PGM.GuildDB()
    if not g then return 0 end
    local now = PGM.Now()
    events = events or readEvents(now)
    local used, n = {}, 0
    for i = #g.log, 1, -1 do
        local e = g.log[i]
        if not e.t or now - e.t > LOOKBACK then break end
        if CREDIT[e.kind] and not e.credited then
            local who = e.name and e.name:lower()
            local function fits(j, ev, typ)
                return not used[j] and ev.who == who and ev.typ == typ
                    and ev.at <= e.t + 3600 and ev.at >= e.t - 7 * 86400
            end
            -- The event types that explain this entry, in order of
            -- preference: a join was an invite if there was one (it names
            -- who invited), else a Guild Finder join with nobody to credit.
            local order = (e.kind == "join" or e.kind == "rejoin") and { "invite", "join" }
                or (e.kind == "leave" and { "remove", "quit" }) or { e.kind }
            local found
            for _, typ in ipairs(order) do
                for j, ev in ipairs(events) do
                    if fits(j, ev, typ) then found = j break end
                end
                if found then break end
            end
            if found then
                local ev = events[found]
                used[found] = true
                if ev.typ == "remove" then
                    e.removed, e.by = true, ev.by
                elseif ev.typ == "quit" then
                    e.removed = nil
                elseif ev.typ ~= "join" then
                    e.by = ev.by
                end
                e.credited = true
                n = n + 1
            end
        end
    end
    if n > 0 then PGM:Fire("LOG") end
    return n
end

PGM:RegisterEvent("GUILD_EVENT_LOG_UPDATE", function() PGM:CreditFromEventLog() end)

-- After a roster read turns up changes nobody has been credited for, ask
-- the game for its event log (at most once a minute).
local lastQuery = -QUERY_GAP
PGM:On("ROSTER", function()
    local g = PGM.GuildDB()
    if not (g and g.log) or type(QueryGuildEventLog) ~= "function" then return end
    if GetTime() - lastQuery < QUERY_GAP or not uncredited(g, PGM.Now()) then return end
    lastQuery = GetTime()
    pcall(QueryGuildEventLog)
end)
