-- Club.lua: extra member details from the Communities roster.
--
-- The guild is also a "club", and C_Club.GetMemberInfo carries things the
-- classic guild roster API doesn't: race, overall Mythic+ score, and both
-- primary professions with their skill. It covers every member, with or
-- without this addon, which is how Blizzard's own guild window shows a
-- Professions column.

local _, NS = ...
local PGM = NS.PGM
local P = PGM.Plain

-- English names for when the client can't localize one yet.
local PROF_EN = {
    [164] = "Blacksmithing", [165] = "Leatherworking", [171] = "Alchemy", [182] = "Herbalism",
    [185] = "Cooking", [186] = "Mining", [197] = "Tailoring", [202] = "Engineering",
    [333] = "Enchanting", [356] = "Fishing", [393] = "Skinning", [755] = "Jewelcrafting",
    [773] = "Inscription",
}
PGM.PROF_GATHERING = { [182] = true, [186] = true, [393] = true }

-- Reading 500 members is slow, and race and professions
-- barely change, so a read is reused for a couple of minutes.
local CACHE_FOR = 120
local cached, cachedAt = nil, 0

local function isSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

-- { [guid] = { race = raceID, score = n, prof = { {id, rank}, ... },
--              scoreKnown = bool, profKnown = bool } }
-- When a *Known flag is false the field was hidden or not loaded yet, so a
-- missing value means "unknown", not "none".
function PGM:ClubDetails()
    if cached and GetTime() - cachedAt < CACHE_FOR then return cached end
    local out = self:ReadClub()
    -- An empty read (club not loaded yet) isn't worth keeping.
    if next(out) then cached, cachedAt = out, GetTime() end
    return out
end

function PGM:ReadClub()
    local out = {}
    if not (C_Club and C_Club.GetGuildClubId and C_Club.GetClubMembers and C_Club.GetMemberInfo) then return out end
    local ok, clubId = pcall(C_Club.GetGuildClubId)
    clubId = ok and P(clubId) or nil
    if not clubId then return out end
    local okM, ids = pcall(C_Club.GetClubMembers, clubId)
    ids = okM and P(ids) or nil
    if type(ids) ~= "table" then return out end
    for _, memberId in ipairs(ids) do
        local okI, m = pcall(C_Club.GetMemberInfo, clubId, memberId)
        local guid = okI and m and P(m.guid)
        -- No name means the entry is still loading.
        if guid and P(m.name) then
            local d = { prof = {} }
            -- What this read can be trusted on. A hidden field, or an entry
            -- whose level hasn't loaded yet, says nothing either way.
            local loaded = P(m.level) ~= nil
            d.scoreKnown = loaded and not isSecret(m.overallDungeonScore)
            d.profKnown = loaded and not (isSecret(m.profession1ID) or isSecret(m.profession2ID)
                or isSecret(m.profession1Rank) or isSecret(m.profession2Rank))
            local race = P(m.race)
            if type(race) == "number" and race > 0 then d.race = race end
            -- 0 (a new season, or no runs) is a real answer: no score.
            local score = P(m.overallDungeonScore)
            if type(score) == "number" and score > 0 then d.score = score end
            for i = 1, 2 do
                local id, rank = P(m["profession" .. i .. "ID"]), P(m["profession" .. i .. "Rank"])
                if type(id) == "number" and id > 0 then
                    d.prof[#d.prof + 1] = { id = id, rank = type(rank) == "number" and rank or 0 }
                end
            end
            out[guid] = d
        end
    end
    return out
end

local profNames = {}
function PGM.ProfName(id)
    if profNames[id] then return profNames[id] end
    if C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillDisplayName then
        local ok, n = pcall(C_TradeSkillUI.GetTradeSkillDisplayName, id)
        if ok and type(n) == "string" and n ~= "" then
            profNames[id] = n
            return n
        end
    end
    -- Not cached: the client may just not have the name yet.
    return PROF_EN[id] or ("Profession " .. tostring(id))
end

function PGM.ProfIcon(id)
    if C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillTexture then
        local ok, tex = pcall(C_TradeSkillUI.GetTradeSkillTexture, id)
        if ok and tex then return tex end
    end
    return 134400 -- question mark
end

-- "Alchemy, Herbalism", or nil. Names only: the roster's profession "rank"
-- isn't Midnight skill (most members read 1, others 600-800).
function PGM.ProfText(rec, withIcons)
    if not (rec and rec.prof and #rec.prof > 0) then return nil end
    local parts = {}
    for _, p in ipairs(rec.prof) do
        local icon = withIcons and ("|T" .. PGM.ProfIcon(p.id) .. ":14:14|t ") or ""
        parts[#parts + 1] = icon .. PGM.ProfName(p.id)
    end
    return table.concat(parts, ", ")
end

local raceCache = {}
-- name, faction ("Alliance" / "Horde" / "Neutral")
function PGM.RaceInfo(raceID)
    if not raceID then return nil end
    local hit = raceCache[raceID]
    if hit then return hit[1], hit[2], hit[3] end
    local name, faction, file
    if C_CreatureInfo and C_CreatureInfo.GetRaceInfo then
        local ok, info = pcall(C_CreatureInfo.GetRaceInfo, raceID)
        if ok and info then name, file = info.raceName, info.clientFileString end
    end
    if C_CreatureInfo and C_CreatureInfo.GetFactionInfo then
        local ok, info = pcall(C_CreatureInfo.GetFactionInfo, raceID)
        if ok and info then faction = info.groupTag end
    end
    name = name or ("Race " .. raceID)
    faction = (faction == "Alliance" or faction == "Horde") and faction or "Neutral"
    raceCache[raceID] = { name, faction, file }
    return name, faction, file
end

-- Inline icon markup ("|T...|t" or an atlas) for a race, or "" when the
-- client has none we can find. Every candidate is checked before use, so a
-- guess that's wrong shows nothing instead of a green square.
local raceIcons = {}
local ICON_FILE_ALIAS = { Scourge = "Undead" }
function PGM.RaceIconMarkup(raceID, size)
    size = size or 14
    local key = tostring(raceID) .. ":" .. size
    if raceIcons[key] then return raceIcons[key] end
    local _, _, file = PGM.RaceInfo(raceID)
    local markup = ""
    if file then
        local low = file:lower()
        local hasAtlas = C_Texture and C_Texture.GetAtlasInfo
        for _, atlas in ipairs({ "raceicon128-" .. low .. "-male", "raceicon-" .. low .. "-male" }) do
            if hasAtlas and C_Texture.GetAtlasInfo(atlas) and CreateAtlasMarkup then
                markup = CreateAtlasMarkup(atlas, size, size)
                break
            end
        end
        if markup == "" and GetFileIDFromPath then
            local base = ICON_FILE_ALIAS[file] or file
            for _, path in ipairs({
                "Interface\\Icons\\Achievement_Character_" .. base .. "_Male",
                "Interface\\Icons\\Achievement_AlliedRace_" .. base,
                "Interface\\Icons\\Achievement_Character_" .. base .. "_Female",
            }) do
                if GetFileIDFromPath(path) then
                    markup = ("|T%s:%d:%d:0:0:64:64:5:59:5:59|t"):format(path, size, size)
                    break
                end
            end
        end
    end
    raceIcons[key] = markup
    return markup
end

-- The game's class crest, inline.
function PGM.ClassIconMarkup(classFile, size)
    size = size or 14
    if not classFile or not CreateAtlasMarkup then return "" end
    local atlas = "classicon-" .. classFile:lower()
    if C_Texture and C_Texture.GetAtlasInfo and not C_Texture.GetAtlasInfo(atlas) then return "" end
    return CreateAtlasMarkup(atlas, size, size)
end
