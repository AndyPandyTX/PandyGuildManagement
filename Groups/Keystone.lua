-- Keystone.lua: my keystone, and everyone else's.
--
-- Each copy reads its own character's key and tells the guild when it
-- changes, along with the keys this account's other characters in the guild
-- had when last logged in (saved here). A copy that logs in asks for the keys
-- it missed ("W"); one copy that has newer ones volunteers ("V", so the rest
-- stand down) and sends them packed. Keys are low stakes, so anyone may relay
-- them: newest wins, and a key from before the weekly reset is dropped. Only
-- the owner's copy may say its key is newer than now (see K, below).
-- Guildies without the module are heard through LibKeystone (below).
--
-- WIRE (inside "1G"):
--   K guid u map level [guid u map level ...]   keys (map 0 = no key)
--   W since                                     keys newer than since, please
--   V target                                    I'm sending target's

local _, NS = ...
local G = NS.G
local PGM = G.PGM
local P = PGM.Plain

local function isGuid(v)
    return type(v) == "string" and v:match("^Player%-%d+%-%x+$") ~= nil
end

-- ============================================================
-- READING
-- ============================================================

function G.DungeonName(map)
    map = tonumber(map)
    if not (map and map > 0 and C_ChallengeMode and C_ChallengeMode.GetMapUIInfo) then return nil end
    local ok, name = pcall(C_ChallengeMode.GetMapUIInfo, map)
    return ok and P(name) or nil
end

-- A dungeon's keystone art (the same texture Chonky Character Sheet and
-- the game's own M+ pages use), by challenge map id.
function G.DungeonIcon(map)
    map = tonumber(map)
    if not (map and map > 0 and C_ChallengeMode and C_ChallengeMode.GetMapUIInfo) then return nil end
    local ok, _, _, _, texture = pcall(C_ChallengeMode.GetMapUIInfo, map)
    return ok and P(texture) or nil
end

-- This season's dungeons: { map, name, icon, best } by name, where best
-- is my highest timed (or else completed) level, or 0.
local season
function G.SeasonDungeons()
    if season then return season end
    local out = {}
    if PGM.IS_FOREVER or not (C_ChallengeMode and C_ChallengeMode.GetMapTable) then return out end
    local ok, maps = pcall(C_ChallengeMode.GetMapTable)
    for _, map in ipairs(ok and type(maps) == "table" and maps or {}) do
        map = P(map)
        local name = map and G.DungeonName(map)
        if name then
            local best = 0
            if C_MythicPlus and C_MythicPlus.GetSeasonBestForMap then
                local okb, intime, overtime = pcall(C_MythicPlus.GetSeasonBestForMap, map)
                local run = okb and (type(intime) == "table" and intime or (type(overtime) == "table" and overtime))
                best = run and tonumber(P(run.level)) or 0
            end
            out[#out + 1] = { map = map, name = name, icon = G.DungeonIcon(map), best = best }
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    -- The map list comes in once the game has it; keep only a full one.
    if #out > 0 then season = out end
    return out
end

-- The icon for a dungeon by name ("Voidscar Arena"), from this season's.
function G.DungeonIconByName(name)
    for _, d in ipairs(G.SeasonDungeons()) do
        if d.name == name then return d.icon end
    end
end

-- Season's best runs change after a run; read them again next time.
G:RegisterEvent("CHALLENGE_MODE_COMPLETED", function() season = nil end)

-- The key in my bags: map id and level, or nil.
function G.ReadMyKey()
    if PGM.IS_FOREVER or not C_MythicPlus then return nil end
    local ok, map = pcall(C_MythicPlus.GetOwnedKeystoneChallengeMapID)
    local ok2, level = pcall(C_MythicPlus.GetOwnedKeystoneLevel)
    map, level = ok and P(map) or nil, ok2 and P(level) or nil
    if type(map) == "number" and map > 0 and type(level) == "number" and level > 0 then
        return map, level
    end
end

-- Keys known for this guild, newer than the weekly reset: [guid] = { map, level, u }.
function G:Keys()
    local d = G.DB()
    if not d then return {} end
    local reset = G.LastReset()
    for guid, k in pairs(d.keys) do
        if (k.u or 0) < reset then d.keys[guid] = nil end
    end
    return d.keys
end

-- { guid, rec, map, level, u, name } for members with a key this week.
function G:KeyList()
    local g = PGM.GuildDB()
    local out = {}
    for guid, k in pairs(G:Keys()) do
        local rec = g and g.members[guid]
        if rec and (k.map or 0) > 0 then
            out[#out + 1] = { guid = guid, rec = rec, map = k.map, level = k.level, u = k.u,
                              name = G.DungeonName(k.map) or ("Dungeon " .. k.map) }
        end
    end
    return out
end

-- ============================================================
-- SENDING
-- ============================================================

local function row(guid, k)
    return { guid, k.u, k.map or 0, k.level or 0 }
end

-- My character's key, and my account's other characters' saved ones.
local function myRows()
    local rows = {}
    local key = PGM.GuildKey()
    local g = PGM.GuildDB()
    local reset = G.LastReset()
    local me = PGM:MyGuid()
    for guid, c in pairs(PandyGuildGroupsDB.chars) do
        -- Another character counts if PGM files it under this guild.
        local pc = PandyGuildDB.chars and PandyGuildDB.chars[guid]
        local here = guid == me or (pc and pc.guild == key)
        if c.key and (c.key.u or 0) >= reset and here and g and g.members[guid] then
            rows[#rows + 1] = row(guid, c.key)
        end
    end
    return rows
end

-- Read my key; if it changed, save it, note it, and tell the guild.
local lastSent
function G:CheckMyKey(force)
    local me = PGM:MyGuid()
    local d = G.DB()
    if not (me and d) then return end
    local map, level = G.ReadMyKey()
    map, level = map or 0, level or 0
    local c = PandyGuildGroupsDB.chars[me] or {}
    PandyGuildGroupsDB.chars[me] = c
    local old = c.key
    if not old or old.map ~= map or old.level ~= level or (old.u or 0) < G.LastReset() then
        c.key = { map = map, level = level, u = PGM.Stamp(old and old.u) }
        d.keys[me] = { map = map, level = level, u = c.key.u }
        G:Fire("KEYS")
        force = true
    end
    if force and G.CanTalk() and lastSent ~= c.key.u then
        lastSent = c.key.u
        G.SendPacked(false, "K", myRows())
    end
end

-- ============================================================
-- RECEIVING
-- ============================================================

-- A key's stamp may run a little ahead (the owner's PGM.Stamp can), but only
-- in the owner's own message: a relayed key (a catch-up, or anyone else
-- sending it) is held to now at most. Otherwise anyone could stamp someone's
-- key minutes ahead and beat the owner's real update when it comes.
function G.handlers.K(f, sender, rec)
    local d = G.DB()
    local g = PGM.GuildDB()
    local reset, now, any = G.LastReset(), PGM.Now(), false
    for i = 3, #f, 4 do
        local guid, u, map, level = f[i], G.ClampStamp(f[i + 1]), tonumber(f[i + 2]), tonumber(f[i + 3])
        if isGuid(guid) and u and map and level and g.members[guid] and guid ~= PGM:MyGuid() then
            if not (rec and rec.guid == guid) then u = math.min(u, now) end
            local cur = d.keys[guid]
            if u >= reset and u > (cur and cur.u or 0) and level >= 0 and level < 100 then
                d.keys[guid] = { map = map, level = level, u = u }
                any = true
            end
        end
    end
    if any then G:Fire("KEYS") end
end

-- Catch-up: volunteer after a random wait, unless someone beats us to it.
-- One wait per asker: a second asker mustn't cancel the first one's reply.
local volunteers = {}   -- [normalised asker name] = timer
function G.handlers.W(f, sender)
    local since = tonumber(f[3]) or 0
    local rows = {}
    for guid, k in pairs(G:Keys()) do
        if (k.u or 0) > since then rows[#rows + 1] = row(guid, k) end
    end
    if #rows == 0 then return end
    local key = PGM.SyncNorm(sender)
    if volunteers[key] then volunteers[key]:Cancel() end
    volunteers[key] = C_Timer.NewTimer(1 + math.random() * 6, function()
        volunteers[key] = nil
        if not G.CanTalk() then return end
        G.Send(true, "V", sender)
        G.SendPacked(true, "K", rows)
    end)
end

-- Someone else is sending that asker's keys: stand down for them only.
function G.handlers.V(f)
    local key = PGM.SyncNorm(f[3])
    if volunteers[key] then
        volunteers[key]:Cancel()
        volunteers[key] = nil
    end
end

-- ============================================================
-- LIBKEYSTONE
-- ============================================================

-- BigWigs, LittleWigs, EllesmereUI and others carry LibKeystone, which
-- answers a guild request ("R") with "level,map,rating" on its own prefix.
-- So guildies without this module still show their key. We speak its
-- protocol rather than embed it: replies arrive whether or not a copy of the
-- library is loaded here. A key someone hides from the guild comes as
-- "-1,-1,rating" and is left alone.
local LKS = "LibKS"
if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(LKS)
end

-- Every LibKeystone user online answers, so at most every two minutes.
local lksAsked = -1000
function G:RequestLibKeystone()
    if PGM.IS_FOREVER or GetTime() - lksAsked < 120 or not G.CanTalk() then return end
    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
    lksAsked = GetTime()
    pcall(C_ChatInfo.SendAddonMessage, LKS, "R", "GUILD")
end

G:RegisterEvent("CHAT_MSG_ADDON", function(_, prefix, msg, channel, sender)
    prefix, msg, channel, sender = P(prefix), P(msg), P(channel), P(sender)
    if prefix ~= LKS or channel ~= "GUILD" or not (msg and sender) then return end
    local level, map = msg:match("^(%d+),(%d+),%d+$")
    level, map = tonumber(level), tonumber(map)
    if not (level and map) or level >= 100 then return end
    local rec = G.RecByName(sender)
    local d = G.DB()
    if not (rec and d) or rec.guid == PGM:MyGuid() then return end
    local cur = d.keys[rec.guid]
    -- The same key again keeps its stamp, so catch-ups don't resend it.
    if cur and cur.map == map and cur.level == level and (cur.u or 0) >= G.LastReset() then return end
    d.keys[rec.guid] = { map = map, level = level, u = PGM.Stamp(cur and cur.u) }
    G:Fire("KEYS")
end)

-- ============================================================
-- WHEN
-- ============================================================

G:On("READY", function()
    C_Timer.After(10, function()
        if C_MythicPlus and C_MythicPlus.RequestMapInfo then pcall(C_MythicPlus.RequestMapInfo) end
    end)
    C_Timer.After(20, function() G:CheckMyKey(true) end)
    -- Ask for what we missed: anything newer than the newest key we hold.
    C_Timer.After(35, function()
        local newest = G.LastReset()
        for _, k in pairs(G:Keys()) do
            if (k.u or 0) > newest then newest = k.u end
        end
        G.Send(true, "W", newest)
    end)
    C_Timer.After(45, function() G:RequestLibKeystone() end)
end)

-- Keys change in bags (a run ends, a key is traded down or rerolled).
local pending
G:RegisterEvent("BAG_UPDATE_DELAYED", function()
    if pending then return end
    pending = C_Timer.NewTimer(3, function()
        pending = nil
        G:CheckMyKey()
    end)
end)
G:RegisterEvent("CHALLENGE_MODE_COMPLETED", function()
    C_Timer.After(5, function() G:CheckMyKey() end)
end)
-- Back out of an instance: share what changed while we couldn't.
G:RegisterEvent("PLAYER_ENTERING_WORLD", function()
    C_Timer.After(8, function() G:CheckMyKey(true) end)
end)
