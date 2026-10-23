-- Grm.lua: brings over what Guild Roster Manager has collected for this
-- guild. GRM keeps it in its own saved data, which this addon can read only
-- while GRM is enabled; after one import, GRM can be switched off.
--
-- What comes across:
--   alt groups     -> alt links (officers only, shared with the guild)
--   join dates     -> "Joined" for members we've only known since tracking
--                     began (shared with the guild when an officer imports)
--   rank history   -> promotions and demotions in History
--   custom notes   -> your private notes, where you have none
--
-- Nothing already set by hand is overwritten, and importing again is safe:
-- earlier imported history is replaced, not doubled.

local _, NS = ...
local PGM = NS.PGM

-- Comparable names and guild keys: no spaces or punctuation, lower case.
local function norm(text)
    return ((text or ""):gsub("[%s%p]", "")):lower()
end

-- This guild's table inside one of GRM's saved tables, or nil.
local function forGuild(saved)
    if type(saved) ~= "table" then return nil end
    local name, _, _, realm = GetGuildInfo("player")
    name, realm = PGM.Plain(name), PGM.Plain(realm)
    if not name then return nil end
    realm = realm or (GetNormalizedRealmName and GetNormalizedRealmName()) or ""
    local want, wantName = norm(name .. realm), norm(name)
    local fallback
    for key, tbl in pairs(saved) do
        if type(key) == "string" and type(tbl) == "table" then
            local k = norm(key)
            if k == want then return tbl end
            if k:sub(1, #wantName) == wantName then fallback = fallback or tbl end
        end
    end
    return fallback
end

function PGM:GRMAvailable()
    return forGuild(_G.GRM_GuildMemberHistory_Save) ~= nil
end

-- GRM dates come as day, month, year plus a timestamp; the timestamp can
-- disagree with the date GRM shows, so the date wins (noon, to stay clear of
-- time-zone edges), and the timestamp is only a fallback.
local function dateTime(d, m, y, stamp)
    d, m, y = tonumber(d), tonumber(m), tonumber(y)
    if d and m and y and y > 2000 then return time({ year = y, month = m, day = d, hour = 12 }) end
    stamp = tonumber(stamp)
    if stamp and stamp > 1000000000 then return stamp end
end

-- Join entries: { day, month, year, "YYYYMMDD", epoch, ... }.
local function entryTime(entry)
    if type(entry) ~= "table" then return nil end
    return dateTime(entry[1], entry[2], entry[3], entry[5])
end

-- Rank history entries: { rankName, day, month, year, "YYYYMMDD", epoch, ... }.
local function rankEntryTime(entry)
    if type(entry) ~= "table" then return nil end
    return dateTime(entry[2], entry[3], entry[4], entry[6])
end

-- Rank names to their position (0 = guild master), for telling a
-- promotion from a demotion.
local function rankIndexByName()
    local out = {}
    local n = GuildControlGetNumRanks and PGM.Plain(GuildControlGetNumRanks()) or 0
    for i = 1, n do
        local name = PGM.Plain(GuildControlGetRankName(i))
        if name and name ~= "" then out[name:lower()] = i - 1 end
    end
    return out
end

-- The main of a group with none chosen: a non-alt rank first, then the best
-- M+ score, then the highest level.
local function pickMain(members, guids)
    table.sort(guids, function(a, b)
        local ra, rb = members[a], members[b]
        local aa, ab = PGM.IsAltRank(ra), PGM.IsAltRank(rb)
        if aa ~= ab then return ab end
        local sa, sb = ra.score or 0, rb.score or 0
        if sa ~= sb then return sa > sb end
        local la, lb = ra.level or 0, rb.level or 0
        if la ~= lb then return la > lb end
        return (ra.short or "") < (rb.short or "")
    end)
    return guids[1]
end

-- Runs the import. Returns a summary table, or nil and a reason.
function PGM:ImportGRM()
    local history = forGuild(_G.GRM_GuildMemberHistory_Save)
    if not history then
        return nil, "GRM's data for this guild isn't loaded. Enable Guild Roster Manager, /reload, and try again."
    end
    local g = PGM.GuildDB(true)
    if not (g and g.seeded) then
        return nil, "Wait for the guild roster to finish loading, then try again."
    end
    local members = g.members
    local canEdit = PGM:CanEdit()
    local result = { joins = 0, links = 0, notes = 0, history = 0, skippedLinks = 0 }

    local byName = {}
    for guid, rec in pairs(members) do
        if rec.name then byName[norm(rec.name)] = guid end
    end

    -- Drop history from any earlier import; it's rebuilt below.
    local kept = {}
    for _, e in ipairs(g.log) do
        if not e.grm then kept[#kept + 1] = e end
    end
    g.log = kept

    local ranks = rankIndexByName()
    local joinedGuids = {}
    -- GRM's history only fills in the time before this addon was watching;
    -- after that, our own log already has it.
    local before = g.seeded

    for _, entry in pairs(history) do
        local guid = type(entry) == "table" and entry.GUID
        local rec = guid and members[guid]
        if rec then
            -- Join date: GRM's most recent one, for anyone we haven't seen join.
            local joinedAt = not entry.joinDateUnknown and type(entry.joinDateHist) == "table"
                and entryTime(entry.joinDateHist[1])
            if joinedAt and joinedAt <= PGM.Now() then
                if not rec.joined then
                    rec.joined = joinedAt
                    joinedGuids[#joinedGuids + 1] = guid
                    result.joins = result.joins + 1
                end
                if joinedAt < before then
                    table.insert(g.log, { t = joinedAt, kind = "join", guid = guid, name = rec.short,
                                          class = rec.class, grm = true })
                    result.history = result.history + 1
                end
            end

            -- Rank history, newest first: each step is a promotion or demotion.
            local hist = type(entry.rankHist) == "table" and entry.rankHist or {}
            for i = 1, #hist - 1 do
                local newer, older = hist[i], hist[i + 1]
                local at = rankEntryTime(newer)
                local to, from = type(newer) == "table" and newer[1], type(older) == "table" and older[1]
                if at and at < before and type(to) == "string" and type(from) == "string" and to ~= from then
                    local ti, fi = ranks[to:lower()], ranks[from:lower()]
                    local kind = (ti and fi and ti > fi) and "demote" or "promote"
                    table.insert(g.log, { t = at, kind = kind, guid = guid, name = rec.short,
                                          class = rec.class, from = from, to = to, grm = true })
                    result.history = result.history + 1
                end
            end

            -- Custom note: { enabled, time, editor, text }.
            local text = type(entry.customNote) == "table" and entry.customNote[4]
            if type(text) == "string" and strtrim(text) ~= "" and not g.notes[guid] then
                g.notes[guid] = strtrim(text):sub(1, 240)
                result.notes = result.notes + 1
            end
        end
    end

    table.sort(g.log, function(a, b) return (a.t or 0) < (b.t or 0) end)
    local cap = PGM.opt("logCap") or 3000
    -- The newest `cap`, in one pass (removing from the front one at a time
    -- is slow enough to freeze the game on a big import).
    if #g.log > cap then
        local keep = {}
        for i = #g.log - cap + 1, #g.log do keep[#keep + 1] = g.log[i] end
        g.log = keep
    end

    -- Alt groups: { {name=...}, {name=...}, main = "Name-Realm" }.
    local groups = forGuild(_G.GRM_Alts)
    local linked = {}
    for _, grp in pairs(groups or {}) do
        if type(grp) == "table" then
            local guids = {}
            for _, m in ipairs(grp) do
                local guid = type(m) == "table" and byName[norm(m.name)]
                if guid then guids[#guids + 1] = guid end
            end
            if #guids >= 2 then
                if not canEdit then
                    result.skippedLinks = result.skippedLinks + #guids - 1
                else
                    local main = type(grp.main) == "string" and grp.main ~= "" and byName[norm(grp.main)]
                    if not (main and members[main]) then
                        -- No main set in GRM: whoever the group's notes and
                        -- ranks already point to, if anyone; else the best fit.
                        local votes, best = {}, nil
                        local inGroup = {}
                        for _, guid in ipairs(guids) do inGroup[guid] = true end
                        for _, guid in ipairs(guids) do
                            local m = PGM:KnownMain(guid)
                            if m and inGroup[m] then
                                votes[m] = (votes[m] or 0) + 1
                                if not best or votes[m] > votes[best] then best = m end
                            end
                        end
                        main = best or pickMain(members, guids)
                    end
                    for _, guid in ipairs(guids) do
                        -- Never over a link someone made (or refused) by hand.
                        if guid ~= main and g.links[guid] == nil then
                            g.links[guid] = main
                            linked[#linked + 1] = guid
                        end
                    end
                end
            end
        end
    end
    result.links = #linked

    -- Officers share what the guild should all see.
    if canEdit then
        if #linked > 0 and PGM.SyncLinks then PGM:SyncLinks(linked) end
        if #joinedGuids > 0 and PGM.SyncJoins then PGM:SyncJoins(joinedGuids) end
    end

    g.grmImported = PGM.Now()
    g.grmResult = result
    PGM:RebuildAlts()
    PGM:Fire("ROSTER")
    return result
end
