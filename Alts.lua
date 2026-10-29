-- Alts.lua: who is whose alt.
--
-- Sources, strongest first:
--   manual   - an officer or the player linked them in the profile
--   account  - characters on this account that are in the same guild
--   player   - another player's copy said so: each character announces its
--              account's main, and a link counts only when that main has
--              announced itself as a main too (see Sync.lua, record B)
--   note     - the public or officer note names the main: "alt of X",
--              "X's alt", "main: X", the slash format many guilds use
--              ("VA/Alt/258/Crafter/Anvar"), or, on an alt rank, just "X"
--   rank     - the rank is an alt rank ("Raider Alts", "Officer Alt") but
--              no note names the main: an alt, main unknown
-- A manual "not an alt" (links[guid] = false) beats all of them.

local _, NS = ...
local PGM = NS.PGM

local mainOf = {}    -- [altGuid] = mainGuid, rebuilt after every roster change
local sourceOf = {}  -- [altGuid] = "manual" | "account" | "player" | "note"
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
    -- Right after login the guild may not be known yet: keep the one saved.
    local old = PandyGuildDB.chars[guid]
    local guild = PGM.GuildKey() or (IsInGuild() and old and old.guild) or nil
    PandyGuildDB.chars[guid] = {
        name = PGM.Plain(name),
        realm = PGM.Plain(realm) or (GetNormalizedRealmName and GetNormalizedRealmName()),
        class = class,
        level = PGM.Plain(UnitLevel("player")),
        guild = guild,
        t = PGM.Now(),
    }
    return guild ~= (old and old.guild)
end

function PGM:MyGuid()
    return PGM.Plain(UnitGUID("player"))
end

function PGM:SetMyMain(guid)
    PandyGuildDB.myMain = guid
    PGM:RebuildAlts()
    PGM:Fire("ROSTER")
    if PGM.SyncMyMain then PGM:SyncMyMain() end
end

-- This account's characters in this guild and which one is the main: the
-- one picked in Settings, else one on a non-alt rank, then the best M+ score,
-- then the highest level. (Not the alphabet: that once made a main into an
-- alt of its own alt.) Returns the main and the list, or nil.
function PGM:AccountMain(members)
    if not members then
        local g = PGM.GuildDB()
        members = g and g.members
        if not members then return nil end
    end
    local mine = {}
    local key = PGM.GuildKey()
    for guid, c in pairs(PandyGuildDB.chars) do
        if c.guild == key and members[guid] then mine[#mine + 1] = guid end
    end
    if #mine == 0 then return nil end
    local main = PandyGuildDB.myMain
    if not (main and members[main] and tContains(mine, main)) then
        main = PGM.PickMain(members, mine)
    end
    return main, mine
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

-- The main of a group with none chosen: a non-alt rank first, then the best
-- M+ score, then the highest level, then the name. Sorts `guids` that way.
function PGM.PickMain(members, guids)
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

-- Is this an alt rank? Guilds name them "Alt", "Alts", "Raider Alts"... As
-- a word, so "Exalted" isn't one.
function PGM.IsAltRank(rec)
    local r = rec and rec.rank
    return r ~= nil and r:lower():find("%f[%a]alts?%f[%A]") ~= nil
end

-- Only a name that is actually in the roster counts (and never their own),
-- which is what keeps "tank alt" from linking someone to "tank".
local function resolve(word, byName, self)
    local guid = word and byName[word]
    if guid and guid ~= self then return guid end
end

-- The words in one note that could name a main, best first: what the
-- patterns pick out, then (for a slash note that says "alt", or anyone on an
-- alt rank) each part from the end, then (alt rank only) any word. Parsing
-- is the slow part, and notes rarely change, so each note's list is kept;
-- which word is a real member is decided fresh every time.
local candidates = {}
local candidateCount = 0
local function noteWords(text, altRanked)
    local key = (altRanked and "1" or "0") .. text
    local list = candidates[key]
    if list then return list end
    list = {}
    local lower = text:lower()
    for _, pat in ipairs(PATTERNS) do
        local word = lower:match(pat)
        if word then list[#list + 1] = word end
    end
    -- The slash format: Team/Alt/ilvl/Role/Main. The main's name is usually
    -- the last part, so look from the end.
    if lower:find("/", 1, true) then
        local segs, altNote = {}, false
        for seg in lower:gmatch("[^/]+") do
            seg = strtrim(seg)
            segs[#segs + 1] = seg
            if seg == "alt" then altNote = true end
        end
        if altNote or altRanked then
            for i = #segs, 1, -1 do
                for word in segs[i]:gmatch(W) do list[#list + 1] = word end
            end
        end
    end
    -- On an alt rank a bare name is the main: "NattyPandy", "Jobson".
    if altRanked then
        for word in lower:gmatch(W) do list[#list + 1] = word end
    end
    if candidateCount > 5000 then wipe(candidates) candidateCount = 0 end
    candidates[key] = list
    candidateCount = candidateCount + 1
    return list
end

local function noteMain(rec, byName, altRanked)
    for _, text in ipairs({ rec.note, rec.onote }) do
        if text and text ~= "" then
            for _, word in ipairs(noteWords(text, altRanked)) do
                local guid = resolve(word, byName, rec.guid)
                if guid then return guid end
            end
        end
    end
end

-- ============================================================
-- RESOLUTION
-- ============================================================

function PGM:RebuildAlts()
    local before = {}
    for k, v in pairs(mainOf) do before[k] = v end
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

    -- What other players' copies told us about their own characters. A claim
    -- "A's main is M" counts only if M claims to be a main itself, so nobody
    -- can pull someone else's characters under their own. (The worst a false
    -- claim does is attach the claimer's own character to a stranger's main,
    -- and an officer's link or "Not an alt" overrides it.)
    local claims = g.claims or {}
    for guid, main in pairs(claims) do
        if main ~= guid and members[guid] and members[main] and claims[main] == main then
            raw[guid], src[guid] = main, "player"
        end
    end

    -- My own characters in this guild: one main, the rest alts.
    local main, mine = PGM:AccountMain(members)
    if mine and #mine > 1 then
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

    -- Bumped only when someone's main changed, so caches built on alt
    -- groups (Activity's) can tell a real change from a routine rebuild.
    local same = true
    for k, v in pairs(mainOf) do
        if before[k] ~= v then same = false break end
        before[k] = nil
    end
    if not same or next(before) then PGM.altsVersion = (PGM.altsVersion or 0) + 1 end
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
    C_Timer.After(8, function()
        if registerSelf() then PGM:RebuildAlts() end
    end)
end)

PGM:RegisterEvent("PLAYER_LEVEL_UP", function() C_Timer.After(1, registerSelf) end)
PGM:RegisterEvent("PLAYER_GUILD_UPDATE", function() C_Timer.After(2, registerSelf) end)

-- Rebuild before anything else listening for ROSTER reads the result; only
-- when the roster changed in a way alts depend on (someone joined, left or
-- was renamed, or a note or rank changed) or it's another guild. Links,
-- claims and a picked main rebuild where they change.
local builtFor
PGM:On("ROSTER", function()
    local v = (PGM.notesVersion or 0) .. ":" .. tostring(PGM.GuildKey())
    if v == builtFor then return end
    builtFor = v
    PGM:RebuildAlts()
end)

-- ============================================================
-- MAINS IN CHAT
-- ============================================================

-- When a guildie's alt talks, their main goes in front of the line,
-- "(Mainname) hi", in the main's class colour. Only on your screen; nothing
-- sent changes. During a boss fight or a Mythic+ run the game keeps chat
-- secret from addons, so lines then show as they came.
local CHAT_EVENTS = {
    "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID",
    "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "CHAT_MSG_WHISPER", "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_CHANNEL", "CHAT_MSG_COMMUNITIES_CHANNEL",
}

-- "(Mainname) " for a guild alt whose main we know, else nil.
function PGM:ChatMainTag(guid)
    if PGM.opt("chatMains") == false then return nil end
    local main = mainOf[guid]
    local g = main and main ~= guid and PGM.GuildDB()
    local rec = g and g.members[guid] and g.members[main]
    if not rec then return nil end
    return PGM.ClassHex(rec.class) .. "(" .. (rec.short or rec.name or "?") .. ")|r "
end

-- The sender's GUID is the event's 12th value, after the text and name.
local function chatFilter(_, _, msg, author, ...)
    local text, guid = PGM.Plain(msg), PGM.Plain((select(10, ...)))
    if type(text) ~= "string" or type(guid) ~= "string" then return false end
    local tag = PGM:ChatMainTag(guid)
    if not tag then return false end
    return false, tag .. text, author, ...
end

local addFilter = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
if addFilter then
    for _, e in ipairs(CHAT_EVENTS) do addFilter(e, chatFilter) end
end
