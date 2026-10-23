-- Bulk.lua: kick, promote or demote many members at once, by rules.
--
-- Blizzard only runs /gremove, /gpromote and /gdemote from a real click or
-- key press, so no addon can work through a list on its own. Instead, rules
-- build a queue, and each press of the Bulk Actions button (or its hotkey)
-- runs the next batch: as many commands as fit in one macro's 255
-- characters, so several people per press. After each press the roster is
-- read again. Anyone whose change shows up is done; anyone it didn't take
-- for is tried once more, then counted as failed.
--
-- Nothing here is shared with the guild: the rules and the ignore list are
-- this player's own, kept per guild.

local _, NS = ...
local PGM = NS.PGM

PGM.BULK_ACTIONS = { "kick", "promote", "demote" }
PGM.BULK_VERB = { kick = "/gremove", promote = "/gpromote", demote = "/gdemote" }

local MACRO_MAX = 255
local CONFIRM_WAIT = 20   -- seconds for a change to show in the roster
local MAX_TRIES = 2

-- The run in progress (one at a time), and who this session's runs removed,
-- so History can say "was removed" rather than "left".
local Bulk = { kicked = {} }
PGM.Bulk = Bulk

local function store()
    local g = PGM.GuildDB(true)
    if not g then return nil end
    g.bulk = g.bulk or {}
    local b = g.bulk
    b.rules = b.rules or {}
    b.ignore = b.ignore or {}
    for _, a in ipairs(PGM.BULK_ACTIONS) do
        b.rules[a] = b.rules[a] or {}
        b.ignore[a] = b.ignore[a] or {}
    end
    return g, b
end

function PGM:MyRankIndex()
    local g = PGM.GuildDB()
    local me = g and g.members[PGM:MyGuid() or ""]
    return me and me.rankIndex
end

-- What this character may do here: officers only (the same people who can
-- edit raid teams), and then only what the game lets their rank do.
function PGM:BulkAllowed()
    local officer = PGM.CanEdit ~= nil and PGM:CanEdit()
    local function can(fn)
        if not officer or type(_G[fn]) ~= "function" then return false end
        local ok, res = pcall(_G[fn])
        return ok and PGM.Plain(res) and true or false
    end
    return { officer = officer, kick = can("CanGuildRemove"), promote = can("CanGuildPromote"),
             demote = can("CanGuildDemote") }
end

-- ============================================================
-- RULES
-- ============================================================
-- A rule is a set of conditions; a member matches when they meet all of
-- them. Fields (any may be missing):
--   name, on              label, and whether it's in use
--   ranks                 { [rankIndex] = true }; none = any rank below yours
--   awayDays              away at least this long (kick, demote)
--   seenDays              online within this long (promote)
--   minLevel, maxLevel
--   joinedDays            in the guild at least this long
--   note                  text the public or officer note contains
--   skipTeams             leave raid team members alone
--   keepIfGroupActive     leave them alone if an alt or main was on within awayDays
--   toRank                the rank to move them to (promote, demote)

function PGM:BulkRules(action)
    local _, b = store()
    return b and b.rules[action] or {}
end

function PGM:BulkNewRule(action)
    local _, b = store()
    if not b or not (PGM.CanEdit and PGM:CanEdit()) then return nil end
    local r = { id = ("%d-%d"):format(PGM.Now(), math.random(1000, 9999)), on = true, skipTeams = true }
    if action == "kick" then
        r.name, r.awayDays, r.keepIfGroupActive = "Away 60+ days", 60, true
    elseif action == "promote" then
        r.name, r.seenDays = "New promotion rule", 14
    else
        r.name, r.awayDays, r.keepIfGroupActive = "New demotion rule", 30, true
    end
    table.insert(b.rules[action], r)
    PGM:Fire("BULK")
    return r
end

function PGM:BulkDeleteRule(action, id)
    local _, b = store()
    if not b then return end
    for i, r in ipairs(b.rules[action]) do
        if r.id == id then table.remove(b.rules[action], i) break end
    end
    PGM:Fire("BULK")
end

function PGM:BulkIgnored(action, guid)
    local _, b = store()
    return b and b.ignore[action][guid] and true or false
end

function PGM:BulkSetIgnored(action, guid, ignored)
    local _, b = store()
    if not b then return end
    b.ignore[action][guid] = ignored and true or nil
    PGM:Fire("BULK")
end

function PGM:BulkClearIgnored(action)
    local _, b = store()
    if b then wipe(b.ignore[action]) end
    PGM:Fire("BULK")
end

function PGM:BulkIgnoredCount(action)
    local _, b = store()
    local n = 0
    for _ in pairs(b and b.ignore[action] or {}) do n = n + 1 end
    return n
end

local function daysAway(rec)
    if rec.online then return 0 end
    return PGM.DaysSince(rec.lastOnline)
end

-- How many /gpromote or /gdemote lines it takes to get them there.
local function stepsTo(action, rec, toRank)
    if action == "kick" then return 1 end
    if not (toRank and rec.rankIndex) then return 0 end
    local d = action == "promote" and (rec.rankIndex - toRank) or (toRank - rec.rankIndex)
    return math.max(0, d)
end

-- What every rule check needs, worked out once per pass over the guild
-- rather than per member per rule: who has a raid team spot, and each
-- member's alt group as it's asked for.
local function context(g)
    local ctx = { g = g, onTeam = {}, groups = {} }
    for _, t in ipairs(PGM:Teams()) do
        for guid in pairs(t.members or {}) do ctx.onTeam[guid] = true end
    end
    return ctx
end

local function groupOf(ctx, guid)
    local group = ctx.groups[guid]
    if not group then
        group = PGM:GroupOf(guid)
        ctx.groups[guid] = group
    end
    return group
end

local function matches(r, action, guid, rec, myRank, ctx)
    if r.ranks and next(r.ranks) and not r.ranks[rec.rankIndex] then return false end
    local away = daysAway(rec)
    -- An unknown last-online never counts as away: better to skip someone.
    if r.awayDays and (not away or away < r.awayDays) then return false end
    if r.seenDays and (not away or away > r.seenDays) then return false end
    local lvl = rec.level or 0
    if r.minLevel and lvl < r.minLevel then return false end
    if r.maxLevel and lvl > r.maxLevel then return false end
    if r.joinedDays then
        local d = PGM.DaysSince(rec.joined)
        if not d or d < r.joinedDays then return false end
    end
    if r.note and r.note ~= "" then
        local q = r.note:lower()
        if not ((rec.note or ""):lower():find(q, 1, true) or (rec.onote or ""):lower():find(q, 1, true)) then
            return false
        end
    end
    -- A team spot held by any of their characters counts (as TeamsOf does).
    if r.skipTeams then
        for _, other in ipairs(groupOf(ctx, guid)) do
            if ctx.onTeam[other] then return false end
        end
    end
    if r.keepIfGroupActive and r.awayDays then
        for _, other in ipairs(groupOf(ctx, guid)) do
            local orec = other ~= guid and ctx.g.members[other]
            local oa = orec and daysAway(orec)
            if oa and oa < r.awayDays then return false end
        end
    end
    if action ~= "kick" then
        -- Nobody can be moved to your own rank or above it.
        if not r.toRank or r.toRank <= myRank then return false end
        if stepsTo(action, rec, r.toRank) == 0 then return false end
    end
    return true
end

-- Everyone the enabled rules pick for this action, by name. Never you, the
-- guild master, or anyone at your rank or above (the game wouldn't let you).
-- Ignored people are included, marked, so the page can show them unticked.
-- Also returns how many people each enabled rule picks, from the same pass.
function PGM:BulkMatches(action)
    local g, b = store()
    local out, counts = {}, {}
    local myRank = PGM:MyRankIndex()
    if not (g and myRank) then return out, counts end
    local rules = {}
    for _, r in ipairs(b.rules[action]) do
        if r.on then rules[#rules + 1] = r counts[r.id] = 0 end
    end
    if #rules == 0 then return out, counts end
    local ctx = context(g)
    local me = PGM:MyGuid()
    for guid, rec in pairs(g.members) do
        if guid ~= me and rec.rankIndex and rec.rankIndex > myRank and rec.rankIndex ~= 0 then
            local first
            for _, r in ipairs(rules) do
                if matches(r, action, guid, rec, myRank, ctx) then
                    counts[r.id] = counts[r.id] + 1
                    first = first or r
                end
            end
            if first then
                out[#out + 1] = { guid = guid, rec = rec, rule = first, toRank = first.toRank, action = action,
                                  ignored = b.ignore[action][guid] and true or nil }
            end
        end
    end
    table.sort(out, function(a, c) return PGM.NameLess(a.rec.short, c.rec.short) end)
    return out, counts
end

-- How many people one rule picks.
function PGM:BulkRuleCount(action, rule)
    local g = PGM.GuildDB()
    local myRank = PGM:MyRankIndex()
    if not (g and myRank) then return 0 end
    local ctx = context(g)
    local me, n = PGM:MyGuid(), 0
    for guid, rec in pairs(g.members) do
        if guid ~= me and rec.rankIndex and rec.rankIndex > myRank and rec.rankIndex ~= 0
            and matches(rule, action, guid, rec, myRank, ctx) then
            n = n + 1
        end
    end
    return n
end

-- ============================================================
-- RUNNING
-- ============================================================
-- Each queued person has a state: nil (waiting), "pending" (sent, waiting
-- to see it in the roster), "done", "failed" or "gone" (left on their own
-- before a promote or demote).

local ticker

local function resolve()
    if not Bulk.action then return end
    local g = PGM.GuildDB()
    if not g then return end
    local now = GetTime()
    local changed = false
    for _, item in ipairs(Bulk.queue) do
        local st = Bulk.state[item.guid]
        if st and st.s == "pending" then
            local rec = g.members[item.guid]
            if Bulk.action == "kick" then
                if not rec then st.s = "done" end
            elseif not rec then
                st.s = "gone"
            elseif rec.rankIndex == item.toRank then
                st.s = "done"
            elseif rec.rankIndex ~= st.rank then
                -- Moved part of the way: the rest goes in a later batch.
                st.s, st.tries = nil, 0
            end
            if st.s == "pending" and now - st.t > CONFIRM_WAIT then
                st.s = st.tries >= MAX_TRIES and "failed" or nil
            end
            if st.s ~= "pending" then changed = true end
        end
    end
    if changed then PGM:Fire("BULK") end
end
PGM:On("ROSTER", resolve)

-- Start a run over everyone the rules pick, minus the ignored. Returns how
-- many are queued.
function PGM:BulkStart(action)
    if not (PGM.CanEdit and PGM:CanEdit()) then return 0 end
    local queue = {}
    for _, it in ipairs(PGM:BulkMatches(action)) do
        if not it.ignored then queue[#queue + 1] = it end
    end
    Bulk.action, Bulk.queue, Bulk.state = action, queue, {}
    if ticker then ticker:Cancel() end
    -- The roster doesn't always report back by itself: keep asking while
    -- anything is waiting to be confirmed.
    ticker = C_Timer.NewTicker(5, function()
        for _, st in pairs(Bulk.state) do
            if st.s == "pending" then
                PGM:RequestRoster(true)
                break
            end
        end
        resolve()
    end)
    PGM:Fire("BULK")
    return #queue
end

function PGM:BulkStop()
    Bulk.action, Bulk.queue, Bulk.state = nil, nil, nil
    if ticker then ticker:Cancel() ticker = nil end
    PGM:Fire("BULK")
end

function PGM:BulkRunning()
    return Bulk.action
end

function PGM:BulkState(guid)
    local st = Bulk.state and Bulk.state[guid]
    return st and st.s
end

-- The next batch: the macro text and the people in it, or nil when nobody
-- is waiting. Someone needing more steps than fit is started anyway; the
-- rest of their steps come in a later batch.
function PGM:BulkBatch()
    if not Bulk.action then return nil end
    local g = PGM.GuildDB()
    if not g then return nil end
    local verb = PGM.BULK_VERB[Bulk.action]
    local lines, size, items = {}, 0, {}
    for _, item in ipairs(Bulk.queue) do
        local st = Bulk.state[item.guid]
        if not (st and st.s) then
            local rec = g.members[item.guid]
            local n = rec and stepsTo(Bulk.action, rec, item.toRank) or 0
            if not rec then
                Bulk.state[item.guid] = { s = Bulk.action == "kick" and "done" or "gone", tries = 0 }
            elseif n == 0 then
                Bulk.state[item.guid] = { s = "done", tries = 0 }
            elseif rec.name then
                local line = verb .. " " .. rec.name
                local added = 0
                for _ = 1, n do
                    local extra = #line + (size > 0 and 1 or 0)
                    if size + extra > MACRO_MAX then break end
                    lines[#lines + 1] = line
                    size = size + extra
                    added = added + 1
                end
                if added > 0 then items[#items + 1] = item end
                if added < n then break end   -- the macro is full
            end
        end
    end
    if #lines == 0 then return nil end
    return table.concat(lines, "\n"), items
end

-- The button or hotkey just ran a batch.
function PGM:BulkSent(items)
    if not Bulk.action then return end
    local g = PGM.GuildDB()
    local now = GetTime()
    for _, item in ipairs(items or {}) do
        local st = Bulk.state[item.guid] or { tries = 0 }
        local rec = g and g.members[item.guid]
        st.s, st.t, st.tries, st.rank = "pending", now, (st.tries or 0) + 1, rec and rec.rankIndex
        Bulk.state[item.guid] = st
        if Bulk.action == "kick" then Bulk.kicked[item.guid] = true end
    end
    C_Timer.After(1, function() PGM:RequestRoster(true) end)
    PGM:Fire("BULK")
end

-- { waiting, pending, done, failed, gone, total }
function PGM:BulkProgress()
    local p = { waiting = 0, pending = 0, done = 0, failed = 0, gone = 0, total = 0 }
    if not Bulk.action then return p end
    for _, item in ipairs(Bulk.queue) do
        local st = Bulk.state[item.guid]
        local s = st and st.s or "waiting"
        p[s] = (p[s] or 0) + 1
        p.total = p.total + 1
    end
    return p
end

function PGM:BulkKicked(guid)
    return Bulk.kicked[guid] == true
end
