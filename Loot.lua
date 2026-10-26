-- Loot.lua: a record of raid loot and bonus rolls, kept on this account.
--
-- What the game tells every copy in the raid:
--   * group-loot rolls: who won each drop, and whether they rolled Need,
--     Greed or Transmog (the loot history Blizzard's own window shows);
--   * personal loot: ENCOUNTER_LOOT_RECEIVED, who got what;
--   * bonus rolls: our own from BONUS_ROLL_RESULT, anywhere; everyone
--     else's from the "receives bonus loot" line in loot chat, when the game
--     lets addons read it.
-- Raid and M+ drops and bonus rolls are kept, and only epic or better
-- gear, tier tokens, mounts and pets; no reagents, currency or other
-- miscellany, and nothing that drops as a stack.
--
-- Nothing goes out over guild sync. Loot moves between players by export
-- and import (a PGM text or CSV), and comes in from MRT's loot history and
-- VoidcoreAdvisor's bonus-roll log on this account. Every way in goes
-- through AddLoot, which drops repeats: the same item to the same player,
-- the same way (a drop or a bonus roll), within 15 minutes, is one record.
--
-- PandyGuildDB.loot = { items = { record, ... }, bosses = { [encounter] =
-- name }, mrtUpTo = time, vcaUpTo = { ["Name-Realm"] = time }, deleted =
-- { [key] = { time, ... } } (entries deleted by hand, so imports don't bring
-- them back) }. A record:
--   t      when it dropped (seconds)
--   who    "Name-Realm"
--   class  class file ("DRUID"), when known
--   link   an item link, or an item string ("item:...")
--   id     item id
--   how    need | offspec | greed | tmog | roll | personal | drop | bonus
--   roll   the winning roll (1-100), when known
--   kind   raid | mplus | other
--   enc, boss, inst, diff   encounter id and name, instance id, difficulty id
--   where  the raid or dungeon's name
--   src    pgm | mrt | vca | import
--   mrtRoll  MRT's roll type for the drop (see TypeOwnMRTRolls)

local _, NS = ...
local PGM = NS.PGM
local P = PGM.Plain

local SAME_WINDOW = 15 * 60      -- seconds within which two records are one
local MAX_ITEMS = 20000          -- oldest records go past this
local MAX_DELETED = 500
local RECENT_BOSS = 15 * 60      -- a bonus roll this soon after a kill is for that boss

-- Item classes worth keeping: weapons, armor, and miscellaneous (tokens,
-- mounts and pets). Epic quality or better.
local KEEP_CLASS = { [2] = true, [4] = true, [15] = true }
local QUALITY_HEX = { a335ee = 4, ff8000 = 5, e6cc80 = 6, ["00ccff"] = 7, ["0070dd"] = 3, ["1eff00"] = 2,
    ffffff = 1, ["9d9d9d"] = 0 }
local RAID_DIFF = { [14] = true, [15] = true, [16] = true, [17] = true }
local ROLL_STATE = { [0] = "need", [1] = "offspec", [2] = "tmog", [3] = "greed" }
local SPECIFIC = { need = true, offspec = true, greed = true, tmog = true }

-- ============================================================
-- RAID TIERS
-- ============================================================
-- Which tier each boss belongs to, by encounter id, newest tier first; the
-- first is the current one. Add a tier here each season. Bosses in none of
-- these count as older raids.
PGM.LOOT_TIERS = {
    { name = "Midnight Season 2", raids = {
        { name = "The Venomous Abyss", bosses = { 3420, 3421, 3429, 3445, 3455, 3470, 3492, 3497 } },
        { name = "The Tidebound Grotto", bosses = { 3379 } },
        { name = "The Unbinding of Kith'ix", bosses = { 3513 } },
    } },
    { name = "Midnight Season 1", raids = {
        { name = "The Voidspire", bosses = { 3176, 3177, 3178, 3179, 3180, 3181 } },
        { name = "The Dreamrift", bosses = { 3306 } },
        { name = "March on Quel'Danas", bosses = { 3182, 3183 } },
        { name = "Sporefall", bosses = { 3159 } },
    } },
}

local tierOf, raidOf = {}, {}
for i, tier in ipairs(PGM.LOOT_TIERS) do
    for _, raid in ipairs(tier.raids) do
        for _, enc in ipairs(raid.bosses) do
            tierOf[enc], raidOf[enc] = i, raid.name
        end
    end
end

-- The tier (its index in LOOT_TIERS) and raid a boss is in, or nil.
function PGM.LootTierOf(enc)
    return enc and tierOf[enc], enc and raidOf[enc]
end

-- ============================================================
-- THE STORE
-- ============================================================

local function store()
    if not PandyGuildDB then return nil end
    local l = PandyGuildDB.loot
    if not l then
        l = {}
        PandyGuildDB.loot = l
    end
    l.items = l.items or {}
    l.bosses = l.bosses or {}
    l.vcaUpTo = l.vcaUpTo or {}
    l.deleted = l.deleted or {}
    return l
end

function PGM:LootItems()
    local l = store()
    return l and l.items or {}
end

local function itemId(link)
    return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

local function itemString(link)
    return type(link) == "string" and (link:match("(item:[^|%[]+)") or link) or nil
end

-- Comparable form of "Name-Realm": lower case, realm without spaces or
-- punctuation.
local function nameKey(who)
    local n, r = (who or ""):match("^([^%-]+)%-?(.*)$")
    return (n or ""):lower() .. "-" .. ((r or ""):lower():gsub("[%s'%-]", ""))
end
PGM.LootNameKey = nameKey

local function myRealm()
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    return (realm and realm ~= "") and realm or nil
end

-- The realm most of this account's characters are on: where MRT's lines,
-- which leave out the realm of whoever was recording, are from.
local function homeRealm()
    local count, best, n = {}, nil, 0
    for _, c in pairs(PandyGuildDB and PandyGuildDB.chars or {}) do
        if c.realm then
            count[c.realm] = (count[c.realm] or 0) + 1
            if count[c.realm] > n then best, n = c.realm, count[c.realm] end
        end
    end
    return best or myRealm()
end

-- The game often gives names without a realm: a group-loot roll's winner
-- always, even from another realm, and so do MRT's lines. Which realm: one
-- the raid group, the guild roster, this account's characters or other
-- records name for it, when they agree on one; else `realm` (ours).
local hints   -- [lower name] = { ["Name-Realm"] = true }
local function hint(full)
    local short = (full or ""):match("^([^%-]+)%-.+$")
    if not short then return end
    local k = short:lower()
    hints[k] = hints[k] or {}
    hints[k][full] = true
end
local function buildHints()
    hints = {}
    local g = PGM.GuildDB()
    for _, rec in pairs(g and g.members or {}) do hint(rec.name) end
    for _, c in pairs(PandyGuildDB and PandyGuildDB.chars or {}) do
        if c.name and c.realm then hint(c.name .. "-" .. c.realm) end
    end
    -- Records only count when their realm isn't one we may have added.
    local mine, home = myRealm(), homeRealm()
    for _, rec in ipairs(PandyGuildDB and PandyGuildDB.loot and PandyGuildDB.loot.items or {}) do
        local realm = (rec.who or ""):match("%-(.+)$")
        if realm and realm ~= mine and realm ~= home then hint(rec.who) end
    end
end
PGM:On("ROSTER", function() hints = nil end)

-- The raid group's own spelling of a name ("Name-Realm" for someone from
-- another realm).
local function inGroup(short)
    for i = 1, (GetNumGroupMembers and GetNumGroupMembers() or 0) do
        local ok, name = pcall(GetRaidRosterInfo, i)
        name = ok and P(name)
        if name and (name:match("^([^%-]+)") or name):lower() == short:lower() then
            return name:find("-", 1, true) and name or nil
        end
    end
end

local function fullName(who, realm, live)
    who = who and strtrim(who) or ""
    if who == "" then return nil end
    if who:find("-", 1, true) then return who end
    local found = live and inGroup(who)
    if found then return found end
    if not hints then buildHints() end
    local only, n = nil, 0
    for full in pairs(hints[who:lower()] or {}) do only, n = full, n + 1 end
    if n == 1 then return only end
    realm = realm or myRealm()
    return realm and (who .. "-" .. realm) or who
end

local function myName()
    local ok, name, realm = pcall(UnitFullName, "player")
    name, realm = ok and P(name), ok and P(realm)
    if not name then return nil end
    if not realm or realm == "" then realm = GetNormalizedRealmName and GetNormalizedRealmName() end
    return realm and (name .. "-" .. realm) or name
end

local function myClass()
    local ok, _, file = pcall(UnitClass, "player")
    return ok and P(file) or nil
end

local function qualityOf(link)
    if type(link) ~= "string" then return nil end
    local q = link:match("|cnIQ(%d+)")
    if q then return tonumber(q) end
    local hex = link:match("|cff(%x%x%x%x%x%x)")
    if hex then return QUALITY_HEX[hex:lower()] end
    local id = itemId(link)
    if id and C_Item and C_Item.GetItemQualityByID then
        local ok, quality = pcall(C_Item.GetItemQualityByID, id)
        return ok and P(quality) or nil
    end
end

local function itemInfo(id)
    local get = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
    if not (get and id) then return nil end
    local ok, _, _, _, equipLoc, _, classID, subclassID = pcall(get, id)
    if not ok then return nil end
    return P(classID), P(subclassID), P(equipLoc)
end

-- A tier token: miscellaneous, and its tooltip says which classes may use
-- it. True, false, or nil while the game hasn't loaded the item yet.
local tokenCache = {}
local function isToken(id)
    if tokenCache[id] ~= nil then return tokenCache[id] end
    local prefix = type(ITEM_CLASSES_ALLOWED) == "string" and ITEM_CLASSES_ALLOWED:match("^(.-)%%s")
    if not (prefix and prefix ~= "" and C_TooltipInfo and C_TooltipInfo.GetItemByID) then return nil end
    local ok, data = pcall(C_TooltipInfo.GetItemByID, id)
    local lines = ok and type(data) == "table" and data.lines
    if type(lines) ~= "table" or #lines < 2 then return nil end
    local found = false
    for _, line in ipairs(lines) do
        local text = type(line) == "table" and P(line.leftText)
        if type(text) == "string" and text:sub(1, #prefix) == prefix then found = true break end
    end
    tokenCache[id] = found
    return found
end
PGM.LootIsToken = isToken

-- Miscellaneous items worth keeping: companion pets (2) and mounts (5), and
-- "junk" (0) only when it's a tier token.
local KEEP_MISC = { [2] = true, [5] = true }

-- Epic or better, and gear, a tier token, a mount or a pet; never a stack.
-- What can't be told yet (an item the game hasn't loaded) counts as yes,
-- and PruneLoot looks again later.
function PGM.LootWorthKeeping(link, quantity)
    local id = itemId(link)
    if not id then return false end
    if (tonumber(quantity) or 1) > 1 then return false end
    local classID, subclassID = itemInfo(id)
    if classID and not KEEP_CLASS[classID] then return false end
    if classID == 15 and not KEEP_MISC[subclassID] then
        if subclassID ~= 0 or isToken(id) == false then return false end
    end
    local q = qualityOf(link)
    if q and q < 4 then return false end
    return true
end

-- What kind of item: token | weapon | trinket | jewelry | armor | other.
local WEAPON_SLOT = { INVTYPE_WEAPON = true, INVTYPE_2HWEAPON = true, INVTYPE_WEAPONMAINHAND = true,
    INVTYPE_WEAPONOFFHAND = true, INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_HOLDABLE = true,
    INVTYPE_SHIELD = true, INVTYPE_THROWN = true }
local typeCache = {}
function PGM.LootType(id)
    if not id then return "other" end
    if typeCache[id] then return typeCache[id] end
    local classID, subclassID, equipLoc = itemInfo(id)
    local t
    if not classID then
        return "other"   -- not known yet; don't remember the guess
    elseif equipLoc == "INVTYPE_TRINKET" then
        t = "trinket"
    elseif equipLoc == "INVTYPE_FINGER" or equipLoc == "INVTYPE_NECK" then
        t = "jewelry"
    elseif classID == 2 or WEAPON_SLOT[equipLoc] then
        t = "weapon"
    elseif equipLoc and equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE" then
        t = "armor"
    elseif classID == 15 and subclassID == 0 then
        local token = isToken(id)
        if token == nil then return "other" end   -- not loaded yet; don't remember the guess
        t = token and "token" or "other"
    else
        t = "other"
    end
    typeCache[id] = t
    return t
end

-- ---- repeats ----

local index   -- [nameKey:itemId] = { record, ... }

local function indexKey(rec) return nameKey(rec.who) .. ":" .. rec.id end

local function buildIndex()
    index = {}
    for _, rec in ipairs(PGM:LootItems()) do
        if rec.who and rec.id then
            local k = indexKey(rec)
            index[k] = index[k] or {}
            table.insert(index[k], rec)
        end
    end
end

local function findSame(rec)
    if not index then buildIndex() end
    local bonus = rec.how == "bonus"
    for _, it in ipairs(index[indexKey(rec)] or {}) do
        if (it.how == "bonus") == bonus and math.abs((it.t or 0) - rec.t) <= SAME_WINDOW then return it end
    end
end

-- A second account of the same drop fills in what the first didn't know.
local function merge(into, from)
    for _, k in ipairs({ "class", "enc", "boss", "inst", "diff", "kind", "where", "roll", "mrtRoll" }) do
        if into[k] == nil then into[k] = from[k] end
    end
    if SPECIFIC[from.how] and not SPECIFIC[into.how] then into.how = from.how end
    if from.link and from.link:find("|H", 1, true) and not (into.link or ""):find("|H", 1, true) then
        into.link = from.link
    end
end

local function deletedKey(rec) return indexKey(rec) .. (rec.how == "bonus" and ":b" or "") end

local function wasDeleted(l, rec)
    for _, t in ipairs(l.deleted[deletedKey(rec)] or {}) do
        if math.abs(t - rec.t) <= SAME_WINDOW then return true end
    end
    return false
end

-- Tidy a record for keeping. Returns it, or nil and why ("skip": not worth
-- keeping or not a record at all).
local function prepare(rec)
    rec.who = fullName(rec.who, rec.src == "mrt" and homeRealm() or nil, rec.src == "pgm")
    rec.t = tonumber(rec.t)
    rec.id = rec.id or itemId(rec.link)
    if not (rec.who and rec.t and rec.id) then return nil end
    rec.link = rec.link or ("item:" .. rec.id)
    if not PGM.LootWorthKeeping(rec.link, rec.qty) then return nil end
    rec.qty = nil
    return rec
end

-- Keep a record unless it's a repeat, junk, or deleted by hand. Returns
-- true if it was new; else false and "known" or "skip".
function PGM:AddLoot(rec)
    local l = store()
    if not (l and rec and prepare(rec)) then return false, "skip" end
    if wasDeleted(l, rec) then return false, "skip" end
    local same = findSame(rec)
    if same then
        merge(same, rec)
        return false, "known"
    end
    table.insert(l.items, rec)
    local k = indexKey(rec)
    index[k] = index[k] or {}
    table.insert(index[k], rec)
    if #l.items > MAX_ITEMS then
        table.remove(l.items, 1)
        index = nil
    end
    return true
end

-- What adding a record (say, from an import being previewed) would do:
-- "new", "known" or "skip". Nothing is kept.
function PGM:LootWouldAdd(rec)
    local l = store()
    local copy = {}
    for k, v in pairs(rec) do copy[k] = v end
    if not (l and prepare(copy)) or wasDeleted(l, copy) then return "skip" end
    return findSame(copy) and "known" or "new"
end

function PGM:LootKnown(rec)
    return PGM:LootWouldAdd(rec) == "known"
end

-- Deleted by hand: gone, and remembered, so pulling from MRT again or an
-- import doesn't bring it back.
function PGM:DeleteLoot(rec)
    local l = store()
    local i = l and tIndexOf(l.items, rec)
    if i then
        table.remove(l.items, i)
        local key = deletedKey(rec)
        l.deleted[key] = l.deleted[key] or {}
        table.insert(l.deleted[key], rec.t)
        l.deletedCount = (l.deletedCount or 0) + 1
        if l.deletedCount > MAX_DELETED then
            -- Forget the oldest half (by time), roughly.
            local times = {}
            for _, list in pairs(l.deleted) do
                for _, t in ipairs(list) do times[#times + 1] = t end
            end
            table.sort(times)
            local cut = times[math.floor(#times / 2)] or 0
            local n = 0
            for key2, list in pairs(l.deleted) do
                for j = #list, 1, -1 do
                    if list[j] <= cut then table.remove(list, j) else n = n + 1 end
                end
                if #list == 0 then l.deleted[key2] = nil end
            end
            l.deletedCount = n
        end
        index = nil
        PGM:Fire("LOOT")
    end
end

-- Records that turn out not to be worth keeping, once the game has loaded
-- their items (a tier token or not is in the tooltip). Returns how many it
-- removed and how many items it couldn't tell yet.
function PGM:PruneLoot()
    local l = store()
    if not l then return 0, 0 end
    local removed, unsure = 0, 0
    for i = #l.items, 1, -1 do
        local rec = l.items[i]
        local classID, subclassID = itemInfo(rec.id)
        if classID == 15 and not KEEP_MISC[subclassID] then
            local token = subclassID == 0 and isToken(rec.id)
            if token == nil and subclassID == 0 then
                unsure = unsure + 1
                if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, rec.id) end
            elseif not token then
                table.remove(l.items, i)
                removed = removed + 1
            end
        end
    end
    if removed > 0 then
        index = nil
        PGM:Fire("LOOT")
    end
    return removed, unsure
end

-- One player's records under two spellings of their name (a realm we added
-- that wasn't theirs): spelled the way the hints say, and repeats merged.
-- Returns how many records changed.
function PGM:FixLootNames()
    local l = store()
    if not l then return 0 end
    buildHints()
    local mine, home = myRealm(), homeRealm()
    local n = 0
    for _, rec in ipairs(l.items) do
        local short, realm = (rec.who or ""):match("^([^%-]+)%-(.+)$")
        if short and (realm == mine or realm == home) then
            local options, only, count = hints[short:lower()] or {}, nil, 0
            for full in pairs(options) do only, count = full, count + 1 end
            if count == 1 and only ~= rec.who and not options[rec.who] then
                rec.who = only
                n = n + 1
            end
        end
    end
    -- Now-identical records: keep the first, fold the rest into it.
    if n > 0 then
        index = {}
        local keep = {}
        for _, rec in ipairs(l.items) do
            local k = indexKey(rec)
            local twin
            for _, it in ipairs(index[k] or {}) do
                if (it.how == "bonus") == (rec.how == "bonus") and math.abs(it.t - rec.t) <= SAME_WINDOW then twin = it break end
            end
            if twin then
                merge(twin, rec)
            else
                index[k] = index[k] or {}
                table.insert(index[k], rec)
                keep[#keep + 1] = rec
            end
        end
        l.items = keep
        PGM:Fire("LOOT")
    end
    return n
end

-- A bonus roll that doesn't say which boss (VoidcoreAdvisor's don't) is
-- for the kill whose drops were recorded closest to it, within a few
-- minutes: the boss, raid and difficulty come from those. Returns how many
-- it filled in.
local BONUS_AFTER_KILL = 5 * 60
function PGM:FillBonusBosses()
    local drops = {}
    for _, rec in ipairs(PGM:LootItems()) do
        if rec.how ~= "bonus" and (rec.boss or rec.where) then drops[#drops + 1] = rec end
    end
    local n = 0
    for _, rec in ipairs(PGM:LootItems()) do
        if rec.how == "bonus" and not rec.boss then
            local best, gap
            for _, d in ipairs(drops) do
                local dt = math.abs((d.t or 0) - rec.t)
                -- In M+ the difficulty is the key's, said differently by
                -- different sources; raid difficulties must agree.
                local diffOK = rec.kind == "mplus" or not rec.diff or not d.diff or d.diff == rec.diff
                if dt <= BONUS_AFTER_KILL and d.kind == rec.kind and diffOK
                    and (not gap or dt < gap) then
                    best, gap = d, dt
                end
            end
            if best then
                rec.enc, rec.boss, rec.where = best.enc, best.boss, rec.where or best.where
                rec.inst, rec.diff = rec.inst or best.inst, rec.diff or best.diff
                n = n + 1
            end
        end
    end
    return n
end

-- Many records at once (an import). Returns how many were new, how many
-- were already known, and how many weren't kept (junk, or deleted by hand).
function PGM:ImportLoot(list)
    local added, known, skipped = 0, 0, 0
    for _, rec in ipairs(list or {}) do
        local new, why = PGM:AddLoot(rec)
        if new then
            added = added + 1
        elseif why == "known" then
            known = known + 1
        else
            skipped = skipped + 1
        end
    end
    if PGM:FillBonusBosses() > 0 or added > 0 then PGM:Fire("LOOT") end
    return added, known, skipped
end

function PGM:LootBossName(enc)
    local l = store()
    return enc and l and l.bosses[enc] or nil
end

-- ============================================================
-- RECORDING
-- ============================================================

local function where()
    local ok, name, instType, diff, _, _, _, _, inst = pcall(GetInstanceInfo)
    if not ok then return { kind = "other" } end
    name, instType, diff, inst = P(name), P(instType), P(diff), P(inst)
    local kind = "other"
    if instType == "raid" then
        kind = "raid"
    elseif instType == "party" and diff == 8 then
        kind = "mplus"
    end
    return { inst = inst ~= 0 and inst or nil, diff = diff ~= 0 and diff or nil, kind = kind, where = name }
end

local fight = {}   -- the last boss killed here: where(), plus enc, boss, t

local function killed(enc, name)
    enc, name = P(enc), P(name)
    if not enc or enc == 0 then return end
    fight = where()
    fight.enc, fight.boss, fight.t = enc, name, PGM.Now()
    local l = store()
    if l and name then l.bosses[enc] = name end
end

local changedQueued = false
local function changed()
    if changedQueued then return end
    changedQueued = true
    C_Timer.After(1, function()
        changedQueued = false
        PGM:Fire("LOOT")
    end)
end

local function record(rec)
    if PGM:AddLoot(rec) then changed() end
end

-- Only events this client has (WoW Forever lacks some of them).
local function listen(event, fn)
    if C_EventUtils and C_EventUtils.IsEventValid and not C_EventUtils.IsEventValid(event) then return end
    PGM:RegisterEvent(event, fn)
end

listen("ENCOUNTER_END", function(_, enc, name, _, _, success)
    if P(success) == 1 then killed(enc, name) end
end)
listen("BOSS_KILL", function(_, enc, name) killed(enc, name) end)

-- Personal loot (in M+ too), and in some raids the winners of rolls.
listen("ENCOUNTER_LOOT_RECEIVED", function(_, enc, _, link, quantity, who, class)
    local w = where()
    if w.kind == "other" then return end
    enc = P(enc)
    record({ t = PGM.Now(), who = P(who), class = P(class), link = P(link), qty = P(quantity), how = "personal", enc = enc,
        boss = PGM:LootBossName(enc), inst = w.inst, diff = w.diff, kind = w.kind, where = w.where, src = "pgm" })
end)

-- Group loot: who won each drop of a boss, and how they rolled. Each drop
-- is read again on every update (and after a /reload), so it's kept once,
-- by encounter and drop, and later reads only fill in how it was won.
local seenDrops = {}   -- ["enc:lootListID"] = record
local function readDrops(enc)
    enc = P(enc)
    local w = where()
    if w.kind ~= "raid" or not enc or not (C_LootHistory and C_LootHistory.GetSortedDropsForEncounter) then return end
    local ok, drops = pcall(C_LootHistory.GetSortedDropsForEncounter, enc)
    if not ok or type(drops) ~= "table" then return end
    for _, d in ipairs(drops) do
        local win = type(d) == "table" and d.winner
        local link = type(d) == "table" and P(d.itemHyperlink)
        local who = type(win) == "table" and P(win.playerName)
        if link and who then
            local state, roll = P(win.state), P(win.roll)
            -- If the drop's summary leaves out how the winner rolled, the
            -- full list of everyone's rolls says.
            if state == nil and C_LootHistory.GetSortedInfoForDrop and P(d.lootListID) then
                local okI, info = pcall(C_LootHistory.GetSortedInfoForDrop, enc, P(d.lootListID))
                for _, r in ipairs(okI and type(info) == "table" and type(info.rollInfos) == "table" and info.rollInfos or {}) do
                    if type(r) == "table" and P(r.isWinner) then
                        state, roll = P(r.state), P(r.roll)
                        break
                    end
                end
            end
            local rec = { t = PGM.Now(), who = who, class = P(win.playerClass), link = link, how = ROLL_STATE[state] or "roll",
                roll = tonumber(roll), enc = enc, boss = PGM:LootBossName(enc), inst = w.inst, diff = w.diff,
                kind = "raid", where = w.where, src = "pgm" }
            local key = enc .. ":" .. (P(d.lootListID) or link)
            local seen = seenDrops[key]
            if seen then
                if SPECIFIC[rec.how] and not SPECIFIC[seen.how] then seen.how, seen.roll = rec.how, rec.roll end
            else
                record(rec)
                seenDrops[key] = rec.who and findSame(rec) or nil
            end
        end
    end
end
listen("LOOT_HISTORY_UPDATE_ENCOUNTER", function(_, enc) readDrops(enc) end)
listen("LOOT_HISTORY_UPDATE_DROP", function(_, enc) readDrops(enc) end)

-- Our own bonus roll, raid or M+. The roll comes after a kill, so it's for
-- the boss just killed; the result can arrive after leaving the instance.
local function context()
    if fight.t and PGM.Now() - fight.t <= RECENT_BOSS then return fight end
    return where()
end

listen("BONUS_ROLL_RESULT", function(_, kindOfReward, link)
    if P(kindOfReward) ~= "item" then return end
    link = P(link)
    if not link then return end
    local ctx = context()
    record({ t = PGM.Now(), who = myName(), class = myClass(), link = link, how = "bonus", enc = ctx.enc,
        boss = ctx.boss, inst = ctx.inst, diff = ctx.diff, kind = ctx.kind, where = ctx.where, src = "pgm" })
end)

-- Everyone else's bonus rolls, from loot chat: "%s receives bonus loot: %s."
-- The pattern is built from the game's own text, so it follows the game's
-- language (as long as the name comes before the item, as in English).
local function patternOf(fmt)
    if type(fmt) ~= "string" then return nil end
    -- Placeholders for %s and %d (and "%1$s"), then the rest of the text
    -- made literal, then the captures.
    local p = fmt:gsub("%%%d%$s", "\001"):gsub("%%%d%$d", "\002"):gsub("%%s", "\001"):gsub("%%d", "\002")
    p = p:gsub("([%%%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    p = p:gsub("\001", "(.+)"):gsub("\002", "(%%d+)")
    return "^" .. p .. "$"
end
local BONUS_LINES
local function bonusLines()
    if not BONUS_LINES then
        BONUS_LINES = {}
        for _, fmt in ipairs({ _G.LOOT_ITEM_BONUS_ROLL_MULTIPLE, _G.LOOT_ITEM_BONUS_ROLL }) do
            local p = patternOf(fmt)
            if p then table.insert(BONUS_LINES, p) end
        end
    end
    return BONUS_LINES
end

function PGM:ReadBonusLootLine(msg)
    msg = P(msg)
    if not msg then return nil end
    for _, p in ipairs(bonusLines()) do
        local who, link = msg:match(p)
        if who and link and link:find("item:", 1, true) then return who, link end
    end
end

listen("CHAT_MSG_LOOT", function(_, msg)
    local who, link = PGM:ReadBonusLootLine(msg)
    if not who then return end
    local ctx = context()
    if ctx.kind == "other" then return end
    record({ t = PGM.Now(), who = who, link = link, how = "bonus", enc = ctx.enc, boss = ctx.boss,
        inst = ctx.inst, diff = ctx.diff, kind = ctx.kind, where = ctx.where, src = "pgm" })
end)

-- ============================================================
-- FROM OTHER ADDONS ON THIS ACCOUNT
-- ============================================================

-- MRT's loot history: "time#encounter#instance#difficulty#name#classID#
-- quantity#itemString[#rollType]". Raid and M+ records newer than `since`.
function PGM:LootFromMRT(since)
    local v = _G.VMRT
    local lh = type(v) == "table" and v.LootHistory
    if type(lh) ~= "table" or type(lh.list) ~= "table" then return nil end
    local bosses = type(lh.bossNames) == "table" and lh.bossNames or {}
    local places = type(lh.instanceNames) == "table" and lh.instanceNames or {}
    local out = {}
    for _, line in ipairs(lh.list) do
        if type(line) == "string" then
            local t, enc, inst, diff, name, classID, qty, item, roll = strsplit("#", line)
            t, enc, inst, diff = tonumber(t), tonumber(enc), tonumber(inst), tonumber(diff)
            local kind = diff and (RAID_DIFF[diff] and "raid" or (diff == 8 and "mplus")) or nil
            if t and t > (since or 0) and kind and name and name ~= "" and item then
                local class
                if GetClassInfo and tonumber(classID) then
                    local ok, _, file = pcall(GetClassInfo, tonumber(classID))
                    class = ok and file or nil
                end
                out[#out + 1] = { t = t, who = name, class = class, link = item, qty = tonumber(qty),
                    how = (roll and roll ~= "") and "roll" or "drop", mrtRoll = (roll and roll ~= "") and roll or nil,
                    enc = enc ~= 0 and enc or nil, boss = enc and bosses[enc] or nil,
                    inst = inst ~= 0 and inst or nil, diff = diff, kind = kind, where = inst and places[inst] or nil,
                    src = "mrt" }
            end
        end
    end
    return out
end

-- VoidcoreAdvisor's log of this character's bonus rolls (raid and M+). It
-- doesn't say which boss.
function PGM:LootFromVCA(since)
    local db = _G.VoidcoreAdvisorCharDB
    local log = type(db) == "table" and db.bonusRollLog
    if type(log) ~= "table" then return nil end
    local me, class = myName(), myClass()
    local out = {}
    for _, e in ipairs(log) do
        local t = type(e) == "table" and tonumber(e.timestamp)
        if t and t > (since or 0) and (e.itemLink or e.itemID) then
            local kind = (e.sourceType == "MYTHIC_PLUS" and "mplus") or (e.raidInstanceID and "raid") or "other"
            -- M+ as Mythic Keystone (8), as MRT and the game's loot say it.
            out[#out + 1] = { t = t, who = me, class = class, link = e.itemLink or ("item:" .. e.itemID),
                how = "bonus", diff = kind == "mplus" and 8 or tonumber(e.difficultyID), kind = kind, src = "vca" }
        end
    end
    return out
end

local function newest(list)
    local n = 0
    for _, rec in ipairs(list or {}) do n = math.max(n, rec.t or 0) end
    return n
end

-- New records from MRT and VoidcoreAdvisor since last time. `all` reads
-- their whole history again (repeats are still dropped). Returns how many
-- were added from each, or nil for an addon that isn't loaded.
-- MRT saves how the person playing rolled on each drop, not how the winner
-- did. So its roll type is the winner's only where the winner is one of
-- this account's characters (only one of them can be in the raid). 1 is
-- Need, 2 Greed, 3 Transmog.
local MRT_ROLL = { ["1"] = "need", ["2"] = "greed", ["3"] = "tmog" }
function PGM:TypeOwnMRTRolls()
    local mine = {}
    for _, c in pairs(PandyGuildDB and PandyGuildDB.chars or {}) do
        if c.name then mine[nameKey(c.name .. "-" .. (c.realm or ""))] = true end
    end
    local me = myName()
    if me then mine[nameKey(me)] = true end
    local n = 0
    for _, rec in ipairs(PGM:LootItems()) do
        if rec.src == "mrt" and not SPECIFIC[rec.how] and MRT_ROLL[rec.mrtRoll or ""] and mine[nameKey(rec.who)] then
            rec.how = MRT_ROLL[rec.mrtRoll]
            n = n + 1
        end
    end
    return n
end

local PULL_VERSION = 4   -- 2: M+ loot and place names from MRT; 3: MRT's roll types; 4: realms, junk
function PGM:PullLoot(all)
    local l = store()
    if not l then return nil, nil end
    -- Once after an update that reads more from them: their whole history
    -- again (repeats only fill in what was missing).
    if (l.pullVersion or 0) < PULL_VERSION then
        all = true
        if (l.pullVersion or 0) < 4 then
            -- VoidcoreAdvisor's M+ rolls were kept as difficulty 23.
            for _, rec in ipairs(l.items) do
                if rec.src == "vca" and rec.kind == "mplus" then rec.diff = 8 end
            end
            PGM:FixLootNames()
        end
        l.pullVersion = PULL_VERSION
    end
    local fromMRT, fromVCA
    local mrt = PGM:LootFromMRT(not all and l.mrtUpTo or nil)
    if mrt then
        fromMRT = PGM:ImportLoot(mrt)
        l.mrtUpTo = math.max(l.mrtUpTo or 0, newest(mrt))
    end
    local me = myName()
    local vca = me and PGM:LootFromVCA(not all and l.vcaUpTo[me] or nil)
    if vca then
        fromVCA = PGM:ImportLoot(vca)
        l.vcaUpTo[me] = math.max(l.vcaUpTo[me] or 0, newest(vca))
    end
    if PGM:TypeOwnMRTRolls() > 0 then PGM:Fire("LOOT") end
    return fromMRT, fromVCA
end

PGM:On("LOGIN", function()
    -- After the other addons have loaded their saved data.
    C_Timer.After(6, function()
        local a, b = PGM:PullLoot()
        local parts = {}
        if (a or 0) > 0 then parts[#parts + 1] = a .. " from MRT" end
        if (b or 0) > 0 then parts[#parts + 1] = b .. " bonus rolls from VoidcoreAdvisor" end
        if #parts > 0 then PGM.Print("Loot: added " .. table.concat(parts, " and ") .. ".") end
        -- Junk the game couldn't tell apart from tier tokens until it had
        -- loaded the items: look again once it has.
        local _, unsure = PGM:PruneLoot()
        if unsure > 0 then C_Timer.After(30, function() PGM:PruneLoot() end) end
    end)
end)

-- ============================================================
-- EXPORT AND IMPORT
-- ============================================================
-- One record per line, fields split by ";": time; who; class; item string;
-- how; kind; encounter; instance; difficulty; boss; place; roll. Compressed and base64
-- when the game can ("PGMLOOT2:"), plain text otherwise ("PGMLOOT1").

local function clean(s) return (tostring(s or ""):gsub("[;\r\n]", ",")) end

local function lootLines(list)
    local lines = {}
    for _, r in ipairs(list) do
        lines[#lines + 1] = table.concat({ r.t, clean(r.who), clean(r.class), clean(itemString(r.link)), clean(r.how),
            clean(r.kind), r.enc or "", r.inst or "", r.diff or "", clean(r.boss), clean(r.where), r.roll or "" }, ";")
    end
    return table.concat(lines, "\n")
end

local function encoder()
    local E = C_EncodingUtil
    if E and E.CompressString and E.DecompressString and E.EncodeBase64 and E.DecodeBase64 then return E end
end

function PGM:LootExportText(list)
    local text = lootLines(list)
    local E = encoder()
    if E then
        local ok, packed = pcall(E.CompressString, text)
        local ok2, b64 = ok and pcall(E.EncodeBase64, packed)
        if ok2 and type(b64) == "string" then return "PGMLOOT2:" .. b64 end
    end
    return "PGMLOOT1\n" .. text
end

-- The records in an export, or nil and why not.
function PGM:ParseLootExport(text)
    text = strtrim(text or "")
    local body
    if text:sub(1, 9) == "PGMLOOT2:" then
        local E = encoder()
        if not E then return nil, "This game can't unpack that export." end
        local ok, packed = pcall(E.DecodeBase64, (text:sub(10):gsub("%s", "")))
        local ok2, plain = ok and pcall(E.DecompressString, packed)
        if not (ok2 and type(plain) == "string") then return nil, "That export looks cut off or changed." end
        body = plain
    elseif text:sub(1, 8) == "PGMLOOT1" then
        body = text:sub(9)
    else
        return nil, "That isn't a Pandy Guild Management loot export."
    end
    local out = {}
    for line in body:gmatch("[^\r\n]+") do
        local f = {}
        for v in (line .. ";"):gmatch("(.-);") do f[#f + 1] = v end
        local t, item = tonumber(f[1]), f[4]
        if t and f[2] ~= "" and item and item:find("item:", 1, true) then
            out[#out + 1] = { t = t, who = f[2], class = f[3] ~= "" and f[3] or nil, link = item,
                how = f[5] ~= "" and f[5] or "drop", kind = f[6] ~= "" and f[6] or "raid",
                enc = tonumber(f[7]), inst = tonumber(f[8]), diff = tonumber(f[9]),
                boss = f[10] ~= "" and f[10] or nil, where = (f[11] or "") ~= "" and f[11] or nil, roll = tonumber(f[12]), src = "import" }
        end
    end
    return out
end

local HOW_LABEL = { need = "Need", offspec = "Need (OS)", greed = "Greed", tmog = "Transmog", roll = "Won roll",
    personal = "Personal", drop = "Drop", bonus = "Bonus roll" }
PGM.LOOT_HOW_LABEL = HOW_LABEL
local DIFF_LABEL = { [17] = "LFR", [14] = "Normal", [15] = "Heroic", [16] = "Mythic", [8] = "Mythic+", [23] = "Mythic" }
PGM.LOOT_DIFF_LABEL = DIFF_LABEL

local function csvField(s)
    s = tostring(s or "")
    if s:find('[,"]') then s = '"' .. s:gsub('"', '""') .. '"' end
    return s
end

function PGM:LootCSV(list)
    local rows = { "Date,Player,Item,Item ID,How,Boss,Difficulty,Content" }
    for _, r in ipairs(list) do
        local name = C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(r.link)
        rows[#rows + 1] = table.concat({ csvField(date("%Y-%m-%d %H:%M", r.t)), csvField(r.who), csvField(name or ""),
            r.id or "", csvField(HOW_LABEL[r.how] or r.how), csvField(r.boss or ""), csvField(DIFF_LABEL[r.diff] or ""),
            r.kind == "mplus" and "M+" or (r.kind == "raid" and "Raid" or "") }, ",")
    end
    return table.concat(rows, "\n")
end

-- ============================================================
-- WHICH RAID NIGHT (AND SO WHICH TEAM)
-- ============================================================
-- A raid drop belongs to the guild raid night it fell in: same raid and
-- difficulty, inside the night's times. When two nights fit (two teams in
-- the same raid at once), the one its winner attended.

local nightOf = setmetatable({}, { __mode = "k" })
local guidByName
PGM:On("RAIDS", function() nightOf = setmetatable({}, { __mode = "k" }) end)
-- Only when who's in the guild changed: a roster read comes every few
-- seconds in a busy guild, and working out nights isn't cheap.
local membersSeen
PGM:On("ROSTER", function()
    if membersSeen == PGM.membersVersion then return end
    membersSeen = PGM.membersVersion
    guidByName = nil
    nightOf = setmetatable({}, { __mode = "k" })
end)

local function memberGuid(who)
    local g = PGM.GuildDB()
    if not g then return nil end
    if not guidByName then
        guidByName = {}
        for guid, rec in pairs(g.members) do
            if rec.name then guidByName[nameKey(rec.name)] = guid end
        end
    end
    return guidByName[nameKey(who)]
end
PGM.LootMemberGuid = memberGuid

function PGM:LootNight(rec)
    if rec.kind ~= "raid" then return nil end
    local known = nightOf[rec]
    if known ~= nil then return known or nil end
    local g = PGM.GuildDB()
    local guid = memberGuid(rec.who)
    -- Two nights that fit equally well (two teams at once, and a winner
    -- who isn't a guild member): neither, rather than whichever came first.
    local best, bestScore, tied
    for _, s in ipairs(g and g.raids and g.raids.sessions or {}) do
        if (not rec.inst or not s.instance or s.instance == rec.inst)
            and (not rec.diff or not s.diffID or s.diffID == rec.diff)
            and rec.t >= (s.start or 0) - 900 and rec.t <= (s.stop or s.start or 0) + 1800 then
            local score = (guid and s.present and s.present[guid]) and 2 or 1
            if not best or score > bestScore then
                best, bestScore, tied = s, score, false
            elseif score == bestScore then
                tied = true
            end
        end
    end
    if tied then best = nil end
    nightOf[rec] = best or false
    return best
end
