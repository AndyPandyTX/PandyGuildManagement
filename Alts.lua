-- Alts.lua: who is whose alt.
--
-- Sources, strongest first:
--   manual   - an officer or the player linked them in the profile
--   account  - characters on this account that are in the same guild
--   note     - the public or officer note names the main: "alt of X",
--              "X's alt", "main: X", the slash format many guilds use
--              ("VA/Alt/258/Crafter/Anvar"), or, on an alt rank, just "X"
--   rank     - the rank is an alt rank ("Raider Alts", "Officer Alt") but
--              no note names the main: an alt, main unknown
-- A manual "not an alt" (links[guid] = false) beats all of them.

local _, NS = ...
local PGM = NS.PGM

local mainOf = {}    -- [altGuid] = mainGuid, rebuilt after every roster change
local sourceOf = {}  -- [altGuid] = "manual" | "account" | "note"
local altsOf = {}    -- [mainGuid] = { altGuid, ... }
local rankAlt = {}   -- [guid] = true: alt by rank, main unknown

-- ============================================================
-- OWN CHARACTERS
-- ============================================================

local function registerSelf()
    local guid = PGM.Plain(UnitGUID("player"))
    if not guid then return end
    local name, realm = UnitFullName("player")
    local _, class = UnitClass("player")
    PandyGuildDB.chars[guid] = {
        name = PGM.Plain(name),
        realm = PGM.Plain(realm) or (GetNormalizedRealmName and GetNormalizedRealmName()),
        class = class,
        level = PGM.Plain(UnitLevel("player")),
        guild = PGM.GuildKey(),
        t = PGM.Now(),
    }
end

function PGM:MyGuid()
    return PGM.Plain(UnitGUID("player"))
end

function PGM:SetMyMain(guid)
    PandyGuildDB.myMain = guid
    PGM:RebuildAlts()
    PGM:Fire("ROSTER")
end

-- ============================================================
-- NOTE PARSING
-- ============================================================

-- A "word" is any run without spaces, punctuation or digits, so accented
-- names (their UTF-8 bytes are none of those) survive.
local W = "([^%s%p%d]+)"
local PATTERNS = {
    "alt%s+of%s+" .. W,
    "alt[%s:%-/=]+" .. W,
    "main[%s:%-/=]+" .. W,
    W .. "'s%s+alt",
    W .. "s%s+alt",
    W .. "%s+alt",
}

-- Is this an alt rank? Guilds name them "Alt", "Alts", "Raider Alts"...
function PGM.IsAltRank(rec)
    local r = rec and rec.rank
    return r ~= nil and r:lower():find("alt", 1, true) ~= nil
end

-- Only a name that is actually in the roster counts (and never their own),
-- which is what keeps "tank alt" from linking someone to "tank".
local function resolve(word, byName, self)
    local guid = word and byName[word]
    if guid and guid ~= self then return guid end
end

local function noteMain(rec, byName, altRanked)
    for _, text in ipairs({ rec.note, rec.onote }) do
        if text and text ~= "" then
            local lower = text:lower()
            for _, pat in ipairs(PATTERNS) do
                local guid = resolve(lower:match(pat), byName, rec.guid)
                if guid then return guid end
            end
            -- The slash format: Team/Alt/ilvl/Role/Main. Only for a note
            -- that says "alt" in it, or a character on an alt rank; the
            -- main's name is usually the last part, so look from the end.
            if lower:find("/", 1, true) then
                local segs, altNote = {}, false
                for seg in lower:gmatch("[^/]+") do
                    seg = strtrim(seg)
                    segs[#segs + 1] = seg
                    if seg == "alt" then altNote = true end
                end
                if altNote or altRanked then
                    for i = #segs, 1, -1 do
                        for word in segs[i]:gmatch(W) do
                            local guid = resolve(word, byName, rec.guid)
                            if guid then return guid end
                        end
                    end
                end
            end
            -- On an alt rank a bare name is the main: "NattyPandy", "Jobson".
            if altRanked then
                for word in lower:gmatch(W) do
                    local guid = resolve(word, byName, rec.guid)
                    if guid then return guid end
                end
            end
        end
    end
end

-- ============================================================
-- RESOLUTION
-- ============================================================

function PGM:RebuildAlts()
    wipe(mainOf); wipe(sourceOf); wipe(altsOf); wipe(rankAlt)
    local g = PGM.GuildDB()
    if not g then return end
    local members, links = g.members, g.links

    -- Short names to GUIDs. When two realms share a name, the player's own
    -- realm wins; notes almost never carry a realm.
    local myRealm = GetNormalizedRealmName and GetNormalizedRealmName()
    local byName = {}
    for guid, rec in pairs(members) do
        local key = rec.short and rec.short:lower()
        if key then
            local prev = byName[key]
            if not prev then
                byName[key] = guid
            elseif rec.realm == myRealm then
                byName[key] = guid
            end
        end
    end

    local raw, src = {}, {}

    for guid, rec in pairs(members) do
        local m = noteMain(rec, byName, PGM.IsAltRank(rec))
        if m then raw[guid], src[guid] = m, "note" end
    end

    -- My own characters in this guild: one main, the rest alts.
    local mine = {}
    local key = PGM.GuildKey()
    for guid, c in pairs(PandyGuildDB.chars) do
        if c.guild == key and members[guid] then mine[#mine + 1] = guid end
    end
    if #mine > 1 then
        local main = PandyGuildDB.myMain
        if not (main and members[main]) then
            -- No main picked: a character on a non-alt rank, then the best
            -- M+ score, then the highest level. (Not the alphabet: that once
            -- made a main into an alt of its own alt.)
            table.sort(mine, function(a, b)
                local ra, rb = members[a], members[b]
                local aa, ab = PGM.IsAltRank(ra), PGM.IsAltRank(rb)
                if aa ~= ab then return ab end
                local sa, sb = ra.score or 0, rb.score or 0
                if sa ~= sb then return sa > sb end
                local la, lb = ra.level or 0, rb.level or 0
                if la ~= lb then return la > lb end
                return (ra.short or "") < (rb.short or "")
            end)
            main = mine[1]
        end
        for _, guid in ipairs(mine) do
            if guid ~= main then raw[guid], src[guid] = main, "account" end
        end
        raw[main], src[main] = nil, nil
    end

    for guid, target in pairs(links) do
        if target == false then
            raw[guid], src[guid] = nil, nil
        elseif members[guid] and members[target] then
            raw[guid], src[guid] = target, "manual"
        end
    end

    -- Follow chains (an alt of an alt) to the top, with a guard for loops.
    for guid in pairs(raw) do
        local top, hops = raw[guid], 0
        while raw[top] and hops < 6 do top, hops = raw[top], hops + 1 end
        if top ~= guid and not raw[top] then
            mainOf[guid] = top
            sourceOf[guid] = src[guid]
            altsOf[top] = altsOf[top] or {}
            table.insert(altsOf[top], guid)
        end
    end

    -- On an alt rank with no main found: still an alt, main unknown. (Not if
    -- someone marked them "not an alt", and not if they have alts themselves.)
    for guid, rec in pairs(members) do
        if not mainOf[guid] and not altsOf[guid] and links[guid] ~= false and PGM.IsAltRank(rec) then
            rankAlt[guid] = true
        end
    end
end

function PGM:MainOf(guid)
    return mainOf[guid] or guid
end

-- The main's GUID when we know who it is, else nil.
function PGM:KnownMain(guid)
    return mainOf[guid]
end

-- An alt, whether or not we know whose.
function PGM:IsAlt(guid)
    return mainOf[guid] ~= nil or rankAlt[guid] == true
end

function PGM:AltSource(guid)
    return sourceOf[guid] or (rankAlt[guid] and "rank") or nil
end

function PGM:AltCount(mainGuid)
    local list = altsOf[mainGuid]
    return list and #list or 0
end

-- Main first, then alts by level.
function PGM:GroupOf(guid)
    local main = PGM:MainOf(guid)
    local g = PGM.GuildDB()
    local members = g and g.members or {}
    local list = { main }
    local alts = {}
    for _, a in ipairs(altsOf[main] or {}) do alts[#alts + 1] = a end
    table.sort(alts, function(a, b)
        return ((members[a] and members[a].level) or 0) > ((members[b] and members[b].level) or 0)
    end)
    for _, a in ipairs(alts) do list[#list + 1] = a end
    return list
end

-- Hand-made links are shared guild-wide, so only officers make them.
local function canEdit()
    return PGM.CanEdit ~= nil and PGM:CanEdit()
end
local function share(guid)
    if PGM.SyncLink then PGM:SyncLink(guid) end
end

function PGM:LinkAlt(altGuid, mainGuid)
    local g = PGM.GuildDB(true)
    if not g or altGuid == mainGuid or not canEdit() then return false end
    -- Linking to someone's alt means linking to their main.
    mainGuid = PGM:MainOf(mainGuid)
    if mainGuid == altGuid then return false end
    g.links[altGuid] = mainGuid
    share(altGuid)
    PGM:RebuildAlts()
    PGM:Fire("ROSTER")
    return true
end

function PGM:UnlinkAlt(guid)
    local g = PGM.GuildDB(true)
    if not g or not canEdit() then return end
    g.links[guid] = false
    share(guid)
    PGM:RebuildAlts()
    PGM:Fire("ROSTER")
end

-- Make this character the main of its group: every other member of the
-- group is relinked to it by hand.
function PGM:MakeMain(guid)
    local g = PGM.GuildDB(true)
    if not g or not canEdit() then return end
    local group = PGM:GroupOf(guid)
    for _, other in ipairs(group) do
        if other ~= guid then
            g.links[other] = guid
            share(other)
        end
    end
    g.links[guid] = false
    share(guid)
    PGM:RebuildAlts()
    PGM:Fire("ROSTER")
end

-- Finds a roster member by name typed by a person: "Name" or "Name-Realm".
function PGM:FindMember(text)
    local g = PGM.GuildDB()
    if not g or not text or text == "" then return nil end
    local want = strtrim(text):lower()
    local short = want:match("^([^-]+)") or want
    local best
    for guid, rec in pairs(g.members) do
        if rec.name and rec.name:lower() == want then return guid end
        if rec.short and rec.short:lower() == short then best = best or guid end
    end
    return best
end

PGM:On("LOGIN", function()
    registerSelf()
    -- From saved data, in case the first roster read is a while coming.
    PGM:RebuildAlts()
    -- The guild may not be known for a few seconds after login.
    C_Timer.After(8, registerSelf)
end)

PGM:RegisterEvent("PLAYER_LEVEL_UP", function() C_Timer.After(1, registerSelf) end)
PGM:RegisterEvent("PLAYER_GUILD_UPDATE", function() C_Timer.After(2, registerSelf) end)

-- Rebuild before anything else listening for ROSTER reads the result.
PGM:On("ROSTER", function() PGM:RebuildAlts() end)
