-- Roster.lua: reads the guild roster, diffs it against last time, writes the
-- history log and announces what changed.
--
-- Two rules keep it honest:
--   1. Only a COMPLETE read may detect departures. If offline members are
--      hidden, a partial read would look like half the guild quit.
--   2. The first complete read seeds; it doesn't report. Otherwise installing
--      the addon logs the whole guild as "joined".

local _, NS = ...
local PGM = NS.PGM
local P = PGM.Plain

local lastRequest = 0
local scanQueued = false
local pendingAfterCombat = false

-- ============================================================
-- READ
-- ============================================================

-- The game only knows "last online" as a rounded offset, so fold it back into
-- an approximate timestamp that sorts and compares.
local function lastOnlineEpoch(i, online, now)
    if online then return now end
    local ok, y, m, d, h = pcall(GetGuildRosterLastOnline, i)
    if not ok then return nil end
    y, m, d, h = P(y), P(m), P(d), P(h)
    if not y then return nil end
    return now - ((y * 365 + (m or 0) * 30 + (d or 0)) * 86400 + (h or 0) * 3600)
end

-- Once per session: if you untick "Show Offline" in the guild window after
-- that, your choice stands (scans then just can't spot departures).
local offlineChecked = false
local function ensureOfflineVisible()
    if offlineChecked then return end
    offlineChecked = true
    if not GetGuildRosterShowOffline or not SetGuildRosterShowOffline then return end
    local ok, showing = pcall(GetGuildRosterShowOffline)
    if ok and P(showing) == false then pcall(SetGuildRosterShowOffline, true) end
end

-- { [guid] = record } and whether the read covered everyone.
function PGM:ScanRoster()
    if not IsInGuild() then return nil, false end
    ensureOfflineVisible()

    local okN, total = pcall(GetNumGuildMembers)
    total = okN and P(total) or nil
    if not total or total == 0 then return nil, false end

    local now, snap, seen = PGM.Now(), {}, 0
    -- Walk until the rows run out rather than trusting the count, which is
    -- capped and can lag behind what's populated. 1500 is a runaway guard.
    for i = 1, 1500 do
        local ok, name, rankName, rankIndex, level, _, zone, note, officerNote,
              isOnline, _, classFile, achPoints, _, isMobile, _, _, guid = pcall(GetGuildRosterInfo, i)
        if not ok then break end
        -- The roster goes secret in some instanced content. No roster then.
        -- (Checked before anything else: even comparing a secret raises.)
        if (issecretvalue and (issecretvalue(name) or issecretvalue(guid))) then return nil, false end
        if name == nil then break end
        -- No GUID yet means the row isn't populated; skip it rather than key
        -- someone by name and poison the next diff.
        if guid then
            local short, realm = PGM.SplitName(name)
            local online = P(isOnline) and true or false
            snap[guid] = {
                guid       = guid,
                name       = short .. "-" .. (realm or "?"),
                short      = short,
                realm      = realm,
                rank       = P(rankName),
                rankIndex  = P(rankIndex),
                level      = P(level),
                class      = P(classFile),
                zone       = P(zone),
                note       = P(note) or "",
                onote      = P(officerNote) or "",
                online     = online,
                mobile     = P(isMobile) and true or false,
                ach        = P(achPoints),
                lastOnline = lastOnlineEpoch(i, online, now),
            }
            seen = seen + 1
        end
    end
    return snap, seen >= total
end

-- ============================================================
-- LOG
-- ============================================================

function PGM:AddLog(g, kind, rec, extra)
    local e = extra or {}
    e.t = e.t or PGM.Now()
    e.kind = kind
    e.guid = rec.guid
    e.name = rec.short or rec.name
    e.class = rec.class
    if PGM.CreditLog then PGM:CreditLog(e) end
    g.log[#g.log + 1] = e

    local cap = PGM.opt("logCap") or 3000
    if #g.log > cap then
        local drop = #g.log - cap + 100
        local keep = {}
        for i = drop + 1, #g.log do keep[#keep + 1] = g.log[i] end
        g.log = keep
    end
    return e
end

-- " Still here: A, B, C +2" for someone who left characters behind.
local function stillHere(e)
    local alts = e.alts
    if type(alts) ~= "table" or #alts == 0 then return "" end
    local shown = {}
    for i = 1, math.min(3, #alts) do shown[i] = alts[i] end
    local more = #alts > 3 and (" +" .. (#alts - 3)) or ""
    return ". Still here: " .. table.concat(shown, ", ") .. more
end

-- One line of plain English for a log entry, shared by the Log page and chat.
-- `e.by` is whoever made the change, when the game said (GuildEvents.lua).
function PGM.LogText(e)
    local who = PGM.ClassHex(e.class) .. (e.name or "?") .. "|r"
    local by = e.by and (" by " .. e.by) or ""
    local k = e.kind
    if k == "join" or k == "rejoin" then
        return who .. (k == "join" and " joined the guild" or " rejoined the guild")
            .. (e.by and (" (invited by " .. e.by .. ")") or "")
    elseif k == "leave" then
        return who .. (e.removed and (" was removed from the guild" .. by) or " left the guild") .. stillHere(e)
    elseif k == "promote" then return ("%s promoted%s: %s > %s"):format(who, by, e.from or "?", e.to or "?")
    elseif k == "demote" then return ("%s demoted%s: %s > %s"):format(who, by, e.from or "?", e.to or "?")
    elseif k == "rename" then return ("%s renamed from %s"):format(who, e.from or "?")
    elseif k == "maxlevel" then return ("%s reached level %d"):format(who, e.level or PGM.MaxLevel())
    elseif k == "seeded" then return ("Started tracking %d members"):format(e.n or 0)
    end
    return who .. " " .. tostring(k)
end

local ANNOUNCE_KEY = {
    join = "join", rejoin = "join", leave = "leave", promote = "rank",
    demote = "rank", rename = "rename", maxlevel = "maxLevel",
}

-- Changes are announced to the player only (never to guild chat). A login
-- after a few days can turn up a pile at once, so past four we summarize.
local function announce(entries)
    local wanted = {}
    local opts = PGM.opt("announce")
    for _, e in ipairs(entries) do
        local key = ANNOUNCE_KEY[e.kind]
        if key and opts[key] then wanted[#wanted + 1] = e end
    end
    if #wanted == 0 then return end
    if #wanted > 4 then
        PGM.Print(("%d guild changes since the last scan. |cff55d194/pgm log|r to see them."):format(#wanted))
        return
    end
    for _, e in ipairs(wanted) do PGM.Print(PGM.LogText(e)) end
end

-- ============================================================
-- DIFF
-- ============================================================

local function count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

function PGM:ApplyRoster(snap, complete)
    local g = PGM.GuildDB(true)
    if not g then return end
    local now = PGM.Now()
    local maxLevel = PGM.MaxLevel()

    -- Race, M+ score and professions come from the Communities roster, read
    -- alongside. When it has nothing this time, keep what we knew.
    local club = PGM.ClubDetails and PGM:ClubDetails() or {}
    local function enrich(new, old)
        local d = club[new.guid]
        old = old or g.former[new.guid]
        -- Field by field, so one hidden or unloaded value never wipes what
        -- we knew. A field the game kept secret this time keeps its old value.
        for _, k in ipairs({ "rank", "rankIndex", "level", "class" }) do
            if new[k] == nil and old then new[k] = old[k] end
        end
        new.race = (d and d.race) or (old and old.race)
        if d and d.scoreKnown then new.score = d.score else new.score = old and old.score end
        if d and d.profKnown then new.prof = d.prof else new.prof = old and old.prof end
    end

    if not g.seeded then
        if not complete then return end
        for guid, rec in pairs(snap) do
            enrich(rec)
            g.members[guid] = rec
        end
        g.seeded = now
        PGM:AddLog(g, "seeded", { name = "" }, { n = count(snap) })
        g.lastScan, g.lastComplete = now, now
        PGM:Fire("ROSTER")
        return
    end

    local fresh = {}
    for guid, new in pairs(snap) do
        local old = g.members[guid]
        enrich(new, old)
        if not old then
            local kind = g.former[guid] and "rejoin" or "join"
            g.former[guid] = nil
            new.joined = now
            fresh[#fresh + 1] = PGM:AddLog(g, kind, new)
        else
            new.joined = old.joined
            if old.short and new.short and old.short ~= new.short then
                fresh[#fresh + 1] = PGM:AddLog(g, "rename", new, { from = old.short })
            end
            if old.rankIndex and new.rankIndex and old.rankIndex ~= new.rankIndex then
                -- Lower index is the higher rank: 0 is the guild master.
                local kind = new.rankIndex < old.rankIndex and "promote" or "demote"
                fresh[#fresh + 1] = PGM:AddLog(g, kind, new, { from = old.rank, to = new.rank })
            end
            if new.level and old.level and new.level >= maxLevel and old.level < maxLevel then
                fresh[#fresh + 1] = PGM:AddLog(g, "maxlevel", new, { level = new.level })
            end
            -- An offline row's last-seen is rounded to the hour; never let that
            -- rounding move a better reading backwards.
            if not new.online and old.lastOnline and (not new.lastOnline or new.lastOnline < old.lastOnline) then
                new.lastOnline = old.lastOnline
            end
        end
        g.members[guid] = new
    end

    if complete then
        local gone = {}
        for guid in pairs(g.members) do
            if not snap[guid] then gone[#gone + 1] = guid end
        end
        -- A third of the guild vanishing at once is a bad read, not an exodus.
        local members = count(g.members)
        if #gone > 10 and #gone > members / 3 then
            PGM.Debug("ignoring", #gone, "departures from a suspicious read")
        else
            local leaving = {}
            for _, guid in ipairs(gone) do leaving[guid] = true end
            local me = g.members[PGM.MyGuid and PGM:MyGuid() or ""]
            for _, guid in ipairs(gone) do
                local old = g.members[guid]
                -- Their characters still here: the rest of their group, as
                -- it was before this read (not anyone leaving with them).
                local still = {}
                for _, other in ipairs(PGM.GroupOf and PGM:GroupOf(guid) or {}) do
                    local orec = other ~= guid and not leaving[other] and g.members[other]
                    if orec and orec.short then still[#still + 1] = orec.short end
                end
                table.sort(still, PGM.NameLess)
                old.left = now
                g.former[guid] = old
                g.members[guid] = nil
                local extra = { alts = #still > 0 and still or nil }
                -- Our own Bulk Actions kick, in case no message credits it.
                if PGM.BulkKicked and PGM:BulkKicked(guid) then
                    extra.removed, extra.by = true, me and me.short
                end
                fresh[#fresh + 1] = PGM:AddLog(g, "leave", old, extra)
            end
        end
        g.lastComplete = now
    end
    g.lastScan = now

    -- Former members are kept a year, in case they come back.
    for guid, old in pairs(g.former) do
        if old.left and now - old.left > 365 * 86400 then g.former[guid] = nil end
    end

    announce(fresh)
    PGM:Fire("ROSTER")
end

-- ============================================================
-- SCHEDULING
-- ============================================================

local function scanNow()
    scanQueued = false
    if InCombatLockdown() then
        pendingAfterCombat = true
        return
    end
    local snap, complete = PGM:ScanRoster()
    if snap then PGM:ApplyRoster(snap, complete) end
end

-- GUILD_ROSTER_UPDATE comes in bursts; one scan a second is plenty.
local function queueScan()
    if scanQueued then return end
    scanQueued = true
    C_Timer.After(1, scanNow)
end

-- Ask the server for fresh data. It throttles this itself, so we keep to one
-- request every 15 seconds unless forced.
function PGM:RequestRoster(force)
    if not IsInGuild() then return end
    local now = GetTime()
    if not force and now - lastRequest < 15 then return end
    lastRequest = now
    if C_GuildInfo and C_GuildInfo.GuildRoster then
        pcall(C_GuildInfo.GuildRoster)
    end
    if force then queueScan() end
end

function PGM:CountMembers()
    local g = PGM.GuildDB()
    if not g then return 0, 0 end
    local total, online = 0, 0
    for _, rec in pairs(g.members) do
        total = total + 1
        if rec.online then online = online + 1 end
    end
    return total, online
end

PGM:RegisterEvent("GUILD_ROSTER_UPDATE", queueScan)
-- Fires for other units too; only our own guild changing matters.
PGM:RegisterEvent("PLAYER_GUILD_UPDATE", function(_, unit)
    if unit == nil or unit == "player" then PGM:RequestRoster() end
end)

PGM:RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if pendingAfterCombat then
        pendingAfterCombat = false
        queueScan()
    end
end)

PGM:On("LOGIN", function()
    C_Timer.After(4, function() PGM:RequestRoster(true) end)
    C_Timer.NewTicker(60, function() PGM:RequestRoster() end)
end)
