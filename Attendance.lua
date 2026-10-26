-- Attendance.lua: records who showed up to raids, with no setup.
--
-- While you're in a raid instance with a raid group, the group is sampled
-- once a minute and at every boss kill. A guildie who is online and in the
-- raid's zone in any sample counts as present (sitting in the group from a
-- city doesn't). A session is kept only if it ran at least five minutes with
-- enough guildies, so a transmog run never counts. Raid Finder is skipped.
--
-- No combat log anywhere: Midnight removed it from addons. Boss kills come
-- from ENCOUNTER_END, which is still available.

local _, NS = ...
local PGM = NS.PGM
local P = PGM.Plain

local SAMPLE_EVERY = 60
local MIN_DURATION = 5 * 60
local GRACE = 25 * 60      -- time outside the raid (repairs, a hearth, a disconnect) before a session ends
-- Raid Finder (current and legacy) isn't a guild raid night.
local SKIP_DIFFICULTY = { [7] = true, [17] = true }
local MAX_SESSIONS = 300

local function newId(start)
    return ("%d-%d"):format(start or PGM.Now(), math.random(1000, 9999))
end

local function store()
    local g = PGM.GuildDB(true)
    if not g then return nil end
    g.raids = g.raids or { sessions = {} }
    g.raids.sessions = g.raids.sessions or {}
    -- Every night needs an id to be shared; older ones get one now.
    for _, s in ipairs(g.raids.sessions) do
        if not s.id then s.id = newId(s.start) end
    end
    return g.raids
end

local function canEdit()
    return PGM.CanEdit ~= nil and PGM:CanEdit()
end

local function inRaidInstance()
    if not IsInRaid() then return false end
    local _, itype, difficultyID = GetInstanceInfo()
    if P(itype) ~= "raid" then return false end
    return not SKIP_DIFFICULTY[P(difficultyID) or 0]
end

local function instanceID()
    return P((select(8, GetInstanceInfo())))
end

local function presentCount(s)
    local n = 0
    for _ in pairs(s.present) do n = n + 1 end
    return n
end

PGM.MAX_RAID_NIGHTS = MAX_SESSIONS

-- Two records are the same raid night when they're the same raid at the
-- same difficulty and they overlap in time, or started within half an hour:
-- two officers recording one night, or a late joiner's shorter record. A
-- Normal night and a later Heroic one, or two teams back to back, stay apart.
--
-- Two teams can run the same raid and difficulty at the same time, though.
-- Those are two groups: each record keeps the raid leaders it saw, and two
-- raids at once never share a leader. Records from older copies have no
-- leaders; then two full records with nobody in common are two raids.
local SAME_START = 30 * 60
local function twoGroups(a, b)
    if a.leaders and b.leaders and next(a.leaders) and next(b.leaders) then
        for guid in pairs(a.leaders) do
            if b.leaders[guid] then return false end
        end
        return true
    end
    local na, nb = 0, 0
    for guid in pairs(a.present or {}) do
        na = na + 1
        if b.present and b.present[guid] then return false end
    end
    for _ in pairs(b.present or {}) do nb = nb + 1 end
    return na >= 5 and nb >= 5
end

function PGM:SameRaidNight(a, b)
    if not (a.instance and a.instance ~= 0 and a.instance == b.instance) then return false end
    local da, db = a.diffID, b.diffID
    if da and db and da ~= 0 and db ~= 0 and da ~= db then return false end
    local as, bs = a.start or 0, b.start or 0
    if math.abs(as - bs) > SAME_START and not (as < (b.stop or bs) and bs < (a.stop or as)) then return false end
    return not twoGroups(a, b)
end

-- The saved night that `night` is a record of, if any (never `except`).
function PGM:FindRaidNight(night, except)
    local g = PGM.GuildDB()
    for _, x in ipairs(g and g.raids and g.raids.sessions or {}) do
        if x ~= except and PGM:SameRaidNight(x, night) then return x end
    end
end

-- Fold one record of a night into another: everyone present in either,
-- every boss, the widest times, the newer team tag.
function PGM:MergeRaidNight(into, from)
    into.start = math.min(into.start or from.start or 0, from.start or into.start or 0)
    into.stop = math.max(into.stop or 0, from.stop or 0)
    into.present = into.present or {}
    for guid in pairs(from.present or {}) do into.present[guid] = true end
    into.bosses = into.bosses or {}
    for _, boss in ipairs(from.bosses or {}) do
        if not tContains(into.bosses, boss) then table.insert(into.bosses, boss) end
    end
    if (from.teamU or 0) > (into.teamU or 0) then into.team, into.teamU = from.team, from.teamU end
    for guid in pairs(from.leaders or {}) do
        into.leaders = into.leaders or {}
        into.leaders[guid] = true
    end
    into.diffID = into.diffID or from.diffID
    into.diff = into.diff or from.diff
    into.count = presentCount(into)
end

function PGM:ActiveRaid()
    local r = PGM.GuildDB() and PGM.GuildDB().raids
    return r and r.open
end

local function sample()
    local r = store()
    local s = r and r.open
    if not s then return end
    local g = PGM.GuildDB()
    local here = P(GetRealZoneText and GetRealZoneText())
    local function add(unit)
        local ok, guid = pcall(UnitGUID, unit)
        guid = ok and P(guid) or nil
        if guid and g.members[guid] then s.present[guid] = true end
    end
    for i = 1, (GetNumGroupMembers() or 0) do
        -- Online and in this zone. When the game won't say, count them.
        local ok, _, rank, _, _, _, _, zone, online = pcall(GetRaidRosterInfo, i)
        zone, online = ok and P(zone), ok and P(online)
        local away = (online == false) or (here and zone and zone ~= here)
        if not away then add("raid" .. i) end
        -- Who leads this group tells it apart from another team's raid in
        -- the same place (see SameRaidNight).
        if ok and P(rank) == 2 then
            local okG, guid = pcall(UnitGUID, "raid" .. i)
            guid = okG and P(guid) or nil
            if guid then
                s.leaders = s.leaders or {}
                s.leaders[guid] = true
            end
        end
    end
    add("player")
    s.samples = (s.samples or 0) + 1
    s.last = PGM.Now()
end

local function open()
    local r = store()
    if not r or r.open then return end
    local name, _, difficultyID, diffName = GetInstanceInfo()
    r.open = {
        id = newId(),
        start = PGM.Now(),
        name = P(name) or "Raid",
        diff = P(diffName),
        diffID = P(difficultyID),
        instance = instanceID(),
        present = {},
        bosses = {},
        samples = 0,
    }
    sample()
    PGM.Debug("raid session opened:", r.open.name)
    PGM:Fire("RAIDS")
end

-- Ends the open session, keeping it only if it was a real guild raid.
function PGM:CloseRaid(force)
    local r = store()
    local s = r and r.open
    if not s then return end
    r.open = nil
    -- Stopped by hand while still inside: don't start a new night in this
    -- same instance until they've left it.
    if force and inRaidInstance() then r.suppress = instanceID() or true end
    s.stop = s.last or PGM.Now()
    s.samples = nil
    local heads = presentCount(s)
    local minGuildies = PGM.opt("raidMinGuildies") or 5
    if not force and (s.stop - s.start < MIN_DURATION or heads < minGuildies) then
        PGM.Debug(("raid session discarded (%ds, %d guildies)"):format(s.stop - s.start, heads))
    else
        s.count = heads
        local same = PGM:FindRaidNight(s)
        if same then
            -- Another officer's record of this night arrived while ours was
            -- still open: one night, not two.
            PGM:MergeRaidNight(same, s)
            if not same.team then
                same.team = PGM:GuessTeam(same)
                same.teamU = same.team and PGM.Now() or 0
            end
            s = same
        else
            s.team = PGM:GuessTeam(s)
            s.teamU = s.team and PGM.Now() or 0
            s.id = s.id or newId(s.start)
            table.insert(r.sessions, s)
            while #r.sessions > MAX_SESSIONS do table.remove(r.sessions, 1) end
        end
        -- An officer's raid night goes to the guild (merged with any other
        -- officer's record of the same night).
        if canEdit() and PGM.SyncRaid then PGM:SyncRaid(s) end
        local team = s.team and PGM:TeamById(s.team)
        PGM.Print(("Saved raid attendance: %s, %d guildies%s."):format(s.name, heads,
            team and (" (" .. team.name .. ")") or ""))
    end
    PGM:Fire("RAIDS")
end

-- By the session itself, not its position: positions shift when old
-- sessions are trimmed.
-- Deleting a raid night is shared, so it's officers only.
function PGM:DeleteRaid(session)
    local r = store()
    local index = r and tIndexOf(r.sessions, session)
    if index and canEdit() then
        table.remove(r.sessions, index)
        if PGM.SyncRaidDeleted and session.id then PGM:SyncRaidDeleted(session) end
        PGM:Fire("RAIDS")
    end
end

local function check()
    local r = store()
    if not r then return end
    -- A session left open across a logout (out Wednesday, back in Thursday)
    -- is closed first, so two raid nights never merge into one.
    if r.open and PGM.Now() - (r.open.last or r.open.start) > GRACE then
        PGM:CloseRaid()
    end
    if inRaidInstance() then
        if r.suppress and (r.suppress == true or r.suppress == instanceID()) then return end
        r.suppress = nil
        -- A different raid, or the same one at another difficulty (Normal,
        -- then Heroic), is a new night.
        if r.open then
            local diffID = P((select(3, GetInstanceInfo())))
            local inst = instanceID()
            if (inst and r.open.instance and inst ~= r.open.instance)
                or (diffID and r.open.diffID and diffID ~= r.open.diffID) then
                PGM:CloseRaid()
            end
        end
        if not r.open then open() else sample() end
    else
        r.suppress = nil
        if r.open and PGM.Now() - (r.open.last or r.open.start) > GRACE then PGM:CloseRaid() end
    end
end

PGM:RegisterEvent("ENCOUNTER_END", function(_, _, encounterName, _, _, success)
    local r = store()
    if not (r and r.open) then return end
    if P(success) == 1 then
        local boss = P(encounterName)
        if boss then table.insert(r.open.bosses, boss) end
    end
    -- Give the raid a moment to settle, then count everyone who was there.
    C_Timer.After(3, sample)
end)

PGM:RegisterEvent("ZONE_CHANGED_NEW_AREA", function() C_Timer.After(3, check) end)
PGM:RegisterEvent("GROUP_ROSTER_UPDATE", function() C_Timer.After(2, check) end)

PGM:On("LOGIN", function()
    -- A /reload mid-raid keeps the open session; check() resumes or closes it.
    C_Timer.After(10, check)
    C_Timer.NewTicker(SAMPLE_EVERY, check)
end)

-- ============================================================
-- READING
-- ============================================================

-- Sessions newest first.
function PGM:RaidSessions()
    local r = PGM.GuildDB() and PGM.GuildDB().raids
    local list = {}
    if not r then return list end
    for i = #r.sessions, 1, -1 do list[#list + 1] = r.sessions[i] end
    return list
end

-- Of the last `window` raids since this member joined, how many did they, or
-- any of their alts, attend? Returns present, possible, and a history strip
-- (newest first, true = there). With teamId, only that team's raid nights
-- ("none": only nights tagged to no team).
-- Answers are cached until the raids, the teams, the members or their alt
-- links change, since every list on screen asks for every member. (Not on
-- every roster read: most only change who's online.)
local attCache = {}
local function clearCache() wipe(attCache) end
local cachedFor
PGM:On("ROSTER", function()
    local v = (PGM.membersVersion or 0) .. ":" .. (PGM.altsVersion or 0)
    if v ~= cachedFor then
        cachedFor = v
        clearCache()
    end
end)
PGM:On("RAIDS", clearCache)
PGM:On("TEAMS", clearCache)

function PGM:AttendanceFor(guid, window, teamId)
    window = window or 10
    local key = guid .. "|" .. window .. "|" .. tostring(teamId)
    local hit = attCache[key]
    if hit then return hit[1], hit[2], hit[3] end
    local present, possible, strip = self:ComputeAttendance(guid, window, teamId)
    attCache[key] = { present, possible, strip }
    return present, possible, strip
end

function PGM:ComputeAttendance(guid, window, teamId)
    local g = PGM.GuildDB()
    if not g then return 0, 0, {} end
    local group = {}
    for _, gu in ipairs(PGM:GroupOf(guid)) do group[gu] = true end
    local rec = g.members[guid]
    local joined = rec and rec.joined
    local present, possible, strip = 0, 0, {}
    local sessions = g.raids and g.raids.sessions or {}
    for i = #sessions, 1, -1 do
        local s = sessions[i]
        -- Newest first, so once we're past their join date we're done.
        if possible >= window or (joined and s.start < joined) then break end
        if not teamId or s.team == teamId or (teamId == "none" and not s.team) then
            possible = possible + 1
            local there = false
            for gu in pairs(group) do
                if s.present[gu] then there = true break end
            end
            if there then present = present + 1 end
            strip[#strip + 1] = there
        end
    end
    return present, possible, strip
end
