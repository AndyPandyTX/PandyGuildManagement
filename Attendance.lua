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
        local ok, _, _, _, _, _, _, zone, online = pcall(GetRaidRosterInfo, i)
        zone, online = ok and P(zone), ok and P(online)
        local away = (online == false) or (here and zone and zone ~= here)
        if not away then add("raid" .. i) end
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
        s.team = PGM:GuessTeam(s)
        s.teamU = s.team and PGM.Now() or 0
        s.id = s.id or newId(s.start)
        table.insert(r.sessions, s)
        while #r.sessions > MAX_SESSIONS do table.remove(r.sessions, 1) end
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
        if PGM.SyncRaidDeleted and session.id then PGM:SyncRaidDeleted(session.id) end
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
-- Answers are cached until the roster, raids or teams change, since every
-- list on screen asks for every member.
local attCache = {}
local function clearCache() wipe(attCache) end
PGM:On("ROSTER", clearCache)
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
