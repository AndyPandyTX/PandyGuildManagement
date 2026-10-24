-- Stats.lua: the numbers behind the Overview page, and CSV exports.
--
-- Class mix, race overview, level spread, activity and a vitality score.
-- Level bands sit under the game's cap (90, or 60 on WoW Forever), only classes
-- the guild has are listed, and on retail the max-level crowd gets a Mythic+
-- spread, since that's the level spread that matters there. Race, score and
-- professions come from Club.lua.

local _, NS = ...
local PGM = NS.PGM
local C = PGM.C

-- Last-seen buckets, in days, and how much each counts toward vitality.
PGM.ACTIVITY = {
    { label = "Seen this week",   upto = 7,   weight = 1.0, col = C.jade },
    { label = "Seen last week",   upto = 14,  weight = 0.7, col = { 0.62, 0.84, 0.40 } },
    { label = "Seen this month",  upto = 30,  weight = 0.4, col = C.gold },
    { label = "Away 30-59 days",  upto = 60,  weight = 0.1, col = C.amber },
    { label = "Away 60+ days",    upto = nil, weight = 0.0, col = C.red },
}

local MPLUS_BANDS = { 3000, 2500, 2000, 1500, 1 }

-- Three ten-level bands under the cap, a wider one, then the rest: 90 gives
-- 50-69 and 10-49, Forever's 60 gives 20-39 and 10-19.
local function levelBands(max)
    local wide = math.max(11, max - 40)
    return {
        { label = tostring(max) .. " (max)", lo = max, hi = 999 },
        { label = (max - 10) .. "-" .. (max - 1), lo = max - 10, hi = max - 1 },
        { label = (max - 20) .. "-" .. (max - 11), lo = max - 20, hi = max - 11 },
        { label = wide .. "-" .. (max - 21), lo = wide, hi = max - 21 },
        { label = "10-" .. (wide - 1), lo = 10, hi = wide - 1 },
        { label = "1-9", lo = 1, hi = 9 },
    }
end

function PGM:ActivityBucket(rec)
    local days = PGM.DaysSince(rec.lastOnline)
    if not days then return nil end
    for i, b in ipairs(PGM.ACTIVITY) do
        if not b.upto or days <= b.upto then return i end
    end
end

-- Does this member count under the Overview's scope?
function PGM:InScope(guid, rec, scope, mainsOnly)
    if mainsOnly and PGM:IsAlt(guid) then return false end
    if scope == "max" then return (rec.level or 0) >= PGM.MaxLevel() end
    if scope == "active" then
        local d = PGM.DaysSince(rec.lastOnline)
        return d ~= nil and d <= 30
    end
    return true
end

function PGM:ComputeOverview(scope, mainsOnly)
    local g = PGM.GuildDB()
    local o = {
        total = 0, online = 0, active7 = 0, active30 = 0, atMax = 0, alts = 0,
        classes = {}, levels = {}, activity = {}, unknownActivity = 0,
        ranks = {}, zones = {}, mplus = nil, trend = {}, recent = {}, races = {}, profs = {},
        vitality = 0, scope = scope, mainsOnly = mainsOnly,
    }
    if not g then return o end
    local max = PGM.MaxLevel()
    local bands = levelBands(max)
    for i, b in ipairs(bands) do o.levels[i] = { label = b.label, count = 0 } end
    for i, b in ipairs(PGM.ACTIVITY) do o.activity[i] = { label = b.label, count = 0, col = b.col } end

    local classCount, classMax = {}, {}
    local rankCount, rankIdle = {}, {}
    local zoneCount = {}
    local mplus = { 0, 0, 0, 0, 0, 0 }
    local anyScore = false
    local races, profs = {}, {}
    local weight, known = 0, 0

    for guid, rec in pairs(g.members) do
        if PGM:InScope(guid, rec, scope, mainsOnly) then
            o.total = o.total + 1
            if PGM:IsAlt(guid) then o.alts = o.alts + 1 end
            if rec.online then
                o.online = o.online + 1
                local z = rec.mobile and "Mobile app" or rec.zone
                if z and z ~= "" then zoneCount[z] = (zoneCount[z] or 0) + 1 end
            end

            local cls = rec.class or "UNKNOWN"
            classCount[cls] = (classCount[cls] or 0) + 1
            local lvl = rec.level or 0
            if lvl >= max then
                o.atMax = o.atMax + 1
                classMax[cls] = (classMax[cls] or 0) + 1
            end
            for i, b in ipairs(bands) do
                if lvl >= b.lo and lvl <= b.hi then o.levels[i].count = o.levels[i].count + 1 break end
            end

            local bucket = PGM:ActivityBucket(rec)
            if bucket then
                o.activity[bucket].count = o.activity[bucket].count + 1
                weight = weight + PGM.ACTIVITY[bucket].weight
                known = known + 1
                if bucket == 1 then o.active7 = o.active7 + 1 end
                if bucket <= 3 then o.active30 = o.active30 + 1 end
            else
                o.unknownActivity = o.unknownActivity + 1
            end

            local ri = rec.rankIndex or 99
            rankCount[ri] = (rankCount[ri] or 0) + 1
            if bucket and bucket >= 4 then rankIdle[ri] = (rankIdle[ri] or 0) + 1 end

            if rec.race then
                -- By name: Pandaren, Dracthyr and Earthen have one race id per
                -- faction, and two "Pandaren" rows would just be confusing.
                local name, faction = PGM.RaceInfo(rec.race)
                local r = races[name]
                if not r then
                    r = { label = name, id = rec.race, faction = faction, count = 0, levels = 0, classes = {} }
                    races[name] = r
                elseif r.faction ~= faction then
                    r.faction = "Neutral"
                end
                r.count = r.count + 1
                r.levels = r.levels + lvl
                r.classes[cls] = (r.classes[cls] or 0) + 1
            end

            for _, pr in ipairs(rec.prof or {}) do
                local e = profs[pr.id]
                if not e then
                    e = { id = pr.id, label = PGM.ProfName(pr.id), count = 0, online = 0 }
                    profs[pr.id] = e
                end
                e.count = e.count + 1
                if rec.online then e.online = e.online + 1 end
            end

            if lvl >= max then
                local score = PGM:MPlusScore(rec)
                local slot = 6
                if score then
                    anyScore = true
                    for i, floor in ipairs(MPLUS_BANDS) do
                        if score >= floor then slot = i break end
                    end
                end
                mplus[slot] = mplus[slot] + 1
            end
        end
    end

    o.vitality = known > 0 and math.floor(weight / known * 100 + 0.5) or 0

    for _, cls in ipairs(PGM.CLASSES) do
        if classCount[cls] then
            o.classes[#o.classes + 1] = { class = cls, count = classCount[cls], atMax = classMax[cls] or 0 }
        end
    end
    if classCount.UNKNOWN then
        o.classes[#o.classes + 1] = { class = "UNKNOWN", count = classCount.UNKNOWN, atMax = classMax.UNKNOWN or 0 }
    end
    table.sort(o.classes, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.class < b.class
    end)

    local numRanks = GuildControlGetNumRanks and PGM.Plain(GuildControlGetNumRanks()) or 0
    for ri, n in pairs(rankCount) do
        local name = (ri < 99 and GuildControlGetRankName and PGM.Plain(GuildControlGetRankName(ri + 1))) or nil
        if name == "" then name = nil end
        o.ranks[#o.ranks + 1] = { index = ri, label = name or ("Rank " .. (ri + 1)), count = n, idle = rankIdle[ri] or 0 }
    end
    table.sort(o.ranks, function(a, b) return a.index < b.index end)
    o.numRanks = numRanks

    for z, n in pairs(zoneCount) do o.zones[#o.zones + 1] = { label = z, count = n } end
    table.sort(o.zones, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.label < b.label
    end)
    while #o.zones > 6 do table.remove(o.zones) end

    for _, r in pairs(races) do
        r.avgLevel = math.floor(r.levels / r.count * 10 + 0.5) / 10
        o.races[#o.races + 1] = r
    end
    table.sort(o.races, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.label < b.label
    end)
    for _, e in pairs(profs) do o.profs[#o.profs + 1] = e end
    table.sort(o.profs, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.label < b.label
    end)

    if anyScore then
        local labels = { "3000+", "2500-2999", "2000-2499", "1500-1999", "Under 1500", "No score" }
        o.mplus = {}
        for i, n in ipairs(mplus) do
            o.mplus[i] = { label = labels[i], count = n, score = MPLUS_BANDS[i] }
        end
    end

    -- Joins and leaves per week for the last eight weeks (oldest first).
    -- Only what happened since tracking began; the seed is not a join.
    local now = PGM.Now()
    for i = 1, 8 do o.trend[i] = { joins = 0, leaves = 0 } end
    for _, e in ipairs(g.log) do
        local week = math.floor((now - e.t) / (7 * 86400))
        if week >= 0 and week < 8 then
            local slot = o.trend[8 - week]
            if e.kind == "join" or e.kind == "rejoin" then slot.joins = slot.joins + 1
            elseif e.kind == "leave" then slot.leaves = slot.leaves + 1 end
        end
    end
    o.trackingSince = g.seeded

    return o
end

-- ============================================================
-- CSV
-- ============================================================

-- ============================================================
-- PROFESSIONS
-- ============================================================
-- Counted by player as well as by character: a player is a main and all
-- their alts, so "who can craft this" means someone you can ask, even when
-- the character with the profession is offline and they're on another one.

PGM.PROF_ACTIVE_DAYS = 7
PGM.PROF_THIN = 3   -- this few active players makes a profession thin

-- The character each player is online on, if any: { [mainGuid] = rec }.
function PGM:PlayersOnline()
    local g = PGM.GuildDB()
    local on = {}
    for guid, rec in pairs(g and g.members or {}) do
        if rec.online and not rec.mobile then
            local main = PGM:MainOf(guid)
            -- Prefer them on the main itself, then whichever character.
            if not on[main] or guid == main then on[main] = rec end
        end
    end
    return on
end

-- Per profession id: chars, players, activePlayers (any of their crafting
-- characters seen in the last PROF_ACTIVE_DAYS days), atMax (characters at
-- the level cap), onlineChars (the crafting character is on), onlinePlayers
-- (the player is on, on any character), thin.
function PGM:ProfessionStats()
    local g = PGM.GuildDB()
    local out = {}
    if not g then return out end
    local max = PGM.MaxLevel()
    local online = PGM:PlayersOnline()
    local seenPlayer = {}   -- [id] = { [main] = { active = bool } }
    for guid, rec in pairs(g.members) do
        for _, pr in ipairs(rec.prof or {}) do
            local e = out[pr.id]
            if not e then
                e = { id = pr.id, chars = 0, players = 0, activePlayers = 0, atMax = 0,
                      onlineChars = 0, onlinePlayers = 0 }
                out[pr.id] = e
                seenPlayer[pr.id] = {}
            end
            e.chars = e.chars + 1
            if (rec.level or 0) >= max then e.atMax = e.atMax + 1 end
            if rec.online then e.onlineChars = e.onlineChars + 1 end
            local main = PGM:MainOf(guid)
            local p = seenPlayer[pr.id][main]
            if not p then
                p = {}
                seenPlayer[pr.id][main] = p
                e.players = e.players + 1
                if online[main] then e.onlinePlayers = e.onlinePlayers + 1 end
            end
            local d = rec.online and 0 or PGM.DaysSince(rec.lastOnline)
            if not p.active and d and d <= PGM.PROF_ACTIVE_DAYS then
                p.active = true
                e.activePlayers = e.activePlayers + 1
            end
        end
    end
    for _, e in pairs(out) do e.thin = e.activePlayers <= PGM.PROF_THIN end
    return out
end

-- Who has a profession. byPlayer: one entry per player (their crafting
-- character that's online, else at the level cap, else last seen), with
-- the rest in `others`. Each entry: guid, rec (the crafting character),
-- main, onlineAs (the character the player is on now, if any), others.
-- Online first (the crafter, then the player on another character), then
-- the most recently seen.
function PGM:ProfessionCrafters(id, byPlayer)
    local g = PGM.GuildDB()
    local out = {}
    if not (g and id) then return out end
    local online = PGM:PlayersOnline()
    local max = PGM.MaxLevel()
    local function better(a, b)   -- is crafting character a a better pick than b?
        if (a.online and true or false) ~= (b.online and true or false) then return a.online and true or false end
        local am, bm = (a.level or 0) >= max, (b.level or 0) >= max
        if am ~= bm then return am end
        return (a.lastOnline or 0) > (b.lastOnline or 0)
    end
    local byMain = {}
    for guid, rec in pairs(g.members) do
        for _, pr in ipairs(rec.prof or {}) do
            if pr.id == id then
                local main = PGM:MainOf(guid)
                local it = { guid = guid, rec = rec, main = main, onlineAs = online[main], others = {} }
                if byPlayer then
                    local cur = byMain[main]
                    if not cur then
                        byMain[main] = it
                        out[#out + 1] = it
                    elseif better(rec, cur.rec) then
                        it.others = cur.others
                        table.insert(it.others, cur.rec)
                        byMain[main] = it
                        for i, x in ipairs(out) do if x == cur then out[i] = it break end end
                    else
                        table.insert(cur.others, rec)
                    end
                else
                    out[#out + 1] = it
                end
                break
            end
        end
    end
    local function rank(it)
        if it.rec.online then return 2 end
        if it.onlineAs then return 1 end
        return 0
    end
    table.sort(out, function(a, b)
        local ra, rb = rank(a), rank(b)
        if ra ~= rb then return ra > rb end
        local la, lb = a.rec.lastOnline or 0, b.rec.lastOnline or 0
        if la ~= lb then return la > lb end
        return PGM.NameLess(a.rec.short, b.rec.short)
    end)
    return out
end

local function csv(v)
    v = tostring(v == nil and "" or v)
    if v:find('[,"\n]') then v = '"' .. v:gsub('"', '""') .. '"' end
    return v
end

local function row(t)
    local out = {}
    for i = 1, #t do out[i] = csv(t[i]) end
    return table.concat(out, ",")
end

function PGM:RosterCSV()
    local g = PGM.GuildDB()
    if not g then return "Not in a guild." end
    local lines = { row({ "Name", "Realm", "Class", "Level", "Rank", "Main", "Last online", "Joined",
        "M+ score", "Race", "Professions", "Raid teams", "Raids attended", "Raids possible", "Public note", "Officer note" }) }
    local list = {}
    for guid, rec in pairs(g.members) do list[#list + 1] = { guid = guid, rec = rec } end
    table.sort(list, function(a, b) return (a.rec.name or "") < (b.rec.name or "") end)
    for _, it in ipairs(list) do
        local rec = it.rec
        local main = PGM:KnownMain(it.guid) and g.members[PGM:KnownMain(it.guid)]
        local present, possible = PGM:AttendanceFor(it.guid)
        lines[#lines + 1] = row({
            rec.short, rec.realm, PGM.ClassName(rec.class), rec.level, rec.rank,
            main and main.name or "",
            rec.online and "online" or (rec.lastOnline and date("%Y-%m-%d", rec.lastOnline) or ""),
            rec.joined and date("%Y-%m-%d", rec.joined) or "",
            PGM:MPlusScore(rec) or "", rec.race and PGM.RaceInfo(rec.race) or "", PGM.ProfText(rec) or "",
            PGM.TeamsText and PGM:TeamsText(it.guid) or "", present, possible, rec.note, rec.onote,
        })
    end
    return table.concat(lines, "\n")
end

function PGM:OverviewCSV(o)
    local lines = { row({ "Section", "Item", "Count", "Extra" }) }
    local function add(section, item, n, extra) lines[#lines + 1] = row({ section, item, n, extra }) end
    add("Summary", "Members", o.total)
    add("Summary", "Online", o.online)
    add("Summary", "Seen this week", o.active7)
    add("Summary", "At max level", o.atMax)
    add("Summary", "Alts", o.alts)
    add("Summary", "Vitality", o.vitality, "out of 100")
    for _, c in ipairs(o.classes) do add("Class", PGM.ClassName(c.class), c.count, c.atMax .. " at max") end
    for _, l in ipairs(o.levels) do add("Level", l.label, l.count) end
    for _, a in ipairs(o.activity) do add("Activity", a.label, a.count) end
    add("Activity", "Unknown", o.unknownActivity)
    for _, r in ipairs(o.ranks) do add("Rank", r.label, r.count, r.idle .. " away 30d+") end
    for _, m in ipairs(o.mplus or {}) do add("Mythic+", m.label, m.count) end
    for _, r in ipairs(o.races) do add("Race", r.label, r.count, r.faction .. ", avg level " .. r.avgLevel) end
    for _, e in ipairs(o.profs) do add("Profession", e.label, e.count, e.online .. " online") end
    return table.concat(lines, "\n")
end
