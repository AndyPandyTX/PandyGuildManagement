-- Progress.lua: Mythic+ scores and raid progress.
--
-- The score comes from Blizzard's guild roster when it has one (Club.lua),
-- since that's live. When it doesn't, and RaiderIO is installed, its bundled
-- database fills in, along with raid progress, which Blizzard doesn't share
-- for other players at all. Without RaiderIO those parts simply stay empty.
-- WoW Forever has neither Mythic+ nor RaiderIO data, so both answer nil
-- there, and the pages hide their M+ and raid-progress spots.

local _, NS = ...
local PGM = NS.PGM

-- RaiderIO's public lookup, found once it has loaded.
local function lookup()
    local rio = _G.RaiderIO
    if type(rio) == "table" and type(rio.GetProfile) == "function" then return rio.GetProfile end
end

-- One lookup per character per session. RaiderIO knows nobody for the first
-- few seconds after login (it's still working out the region), so "no
-- profile" answers from that window aren't kept.
local profiles = {}
local sessionStart = GetTime()

local function profileOf(rec)
    local get = lookup()
    if not (get and rec and rec.short) then return nil end
    local realm = rec.realm or (GetNormalizedRealmName and GetNormalizedRealmName()) or ""
    local key = (rec.short .. "-" .. realm):lower()
    local known = profiles[key]
    if known ~= nil then return known or nil end
    local ok, found = pcall(get, rec.short, realm)
    found = ok and type(found) == "table" and found or nil
    if found or GetTime() - sessionStart > 30 then profiles[key] = found or false end
    return found
end

-- This season's Mythic+ score as a whole number, or nil.
function PGM:MPlusScore(rec)
    if PGM.IS_FOREVER then return nil end
    if rec and (rec.score or 0) > 0 then return math.floor(rec.score + 0.5) end
    local p = profileOf(rec)
    local score = p and p.mythicKeystoneProfile and tonumber(p.mythicKeystoneProfile.currentScore)
    if score and score > 0 then return math.floor(score + 0.5) end
end

-- A score's colour: RaiderIO's when it's installed (its scale keeps going
-- past orange into pink and red for the season's top scores, as LFG
-- addons show them), else the game's own (grey, green, blue, purple,
-- orange).
function PGM:ScoreColor(score)
    local rio = _G.RaiderIO
    if score and type(rio) == "table" and type(rio.GetScoreColor) == "function" then
        local ok, r, g, b = pcall(rio.GetScoreColor, score)
        if ok and type(r) == "number" and type(g) == "number" and type(b) == "number" then return { r, g, b } end
    end
    local getColor = C_ChallengeMode and C_ChallengeMode.GetDungeonScoreRarityColor
    if score and getColor then
        local ok, c = pcall(getColor, score)
        if ok and c and c.r then return { c.r, c.g, c.b } end
    end
    return PGM.C.text2
end

local LETTER = { [1] = "N", [2] = "H", [3] = "M" }

-- This character's best progress in the current raid tier, like "6/8H", as
-- { text, value } where value sorts Mythic above Heroic above Normal. Entries
-- for last tier, or borrowed from the character's main, don't count.
function PGM:RaidProgress(rec)
    if PGM.IS_FOREVER then return nil end
    local p = profileOf(rec)
    local raid = p and p.raidProfile
    local entries = raid and (raid.sortedProgress or raid.progress)
    if type(entries) ~= "table" then return nil end
    local best
    for _, entry in ipairs(entries) do
        if not (entry.isProgressPrev or entry.isMainProgress or entry.obsolete) then
            local info = entry.progress or entry
            local kills, diff = tonumber(info.progressCount), tonumber(info.difficulty)
            local bosses = info.raid and tonumber(info.raid.bossCount)
            if kills and diff and bosses and bosses > 0 and LETTER[diff] then
                local value = diff * 100 + kills
                if not best or value > best.value then
                    best = { text = ("%d/%d%s"):format(kills, bosses, LETTER[diff]), value = value }
                end
            end
        end
    end
    return best
end
