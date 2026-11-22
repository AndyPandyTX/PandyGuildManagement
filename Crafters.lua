-- Crafters.lua: who in the guild can craft a recipe, and recipes to search.
--
-- The game keeps every guild member's known recipes. Asked about one recipe
-- (C_GuildInfo.QueryGuildMembersForRecipe), it answers with everyone who
-- knows it, addon or not: GUILD_RECIPE_KNOWN_BY_MEMBERS, then
-- GetGuildRecipeInfoPostQuery and GetGuildRecipeMember. Answers are matched
-- to our roster (so mains, alts and "online as" work as on the Professions
-- page) and kept for ten minutes.
--
-- To search recipes by name or item, the addon needs their ids, and the
-- game only lists a profession's recipes while its window is open. So every
-- profession window that opens (yours, or a guildie's recipes) adds its
-- recipes to an index, keeping only the newest expansion's: they're the
-- ones people craft, and it keeps the saved file small.
--
-- WOW FOREVER: the server answers that question with nobody, so there each
-- copy reads which recipes its own character knows whenever one of their
-- profession windows opens, and tells the guild (record "r", Sync.lua).
-- Who knows a recipe is then answered from those lists: guildies running the
-- addon who've opened that profession's window. A shared list also makes
-- its recipes searchable here, by name, once this client has shown that a
-- recipe's id is its spell's (so the spell's name is the recipe's).

local _, NS = ...
local PGM = NS.PGM
local P = PGM.Plain

local KEEP_ANSWER = 600
local WAIT_FOR_ANSWER = 3

-- ============================================================
-- WHO KNOWS A RECIPE
-- ============================================================

local answers = {}        -- ["line:recipe"] = { t = when, guids = { guid, ... } }
local pending             -- the one question out: { line, recipe, callbacks }

local function key(line, recipe) return line .. ":" .. recipe end

-- The game's answer: the guild members who know the recipe.
local function readAnswer()
    if type(GetGuildRecipeInfoPostQuery) ~= "function" or type(GetGuildRecipeMember) ~= "function" then return nil end
    local ok, line, recipe, n = pcall(GetGuildRecipeInfoPostQuery)
    line, recipe, n = ok and P(line), ok and P(recipe), ok and P(n)
    if not (line and recipe) then return nil end
    local guids, seen = {}, {}
    for i = 1, n or 0 do
        local okM, display, full = pcall(GetGuildRecipeMember, i)
        full = okM and (P(full) or P(display))
        local guid = full and PGM:FindMember(full)
        if guid and not seen[guid] then
            seen[guid] = true
            guids[#guids + 1] = guid
        end
    end
    return line, recipe, guids
end

-- Rows like the Professions page uses (guid, rec, main, onlineAs), online
-- first. Built when asked for, so who's online is never stale: the roster
-- replaces its records on every read.
local function rows(guids)
    local g = PGM.GuildDB()
    local online = PGM.PlayersOnline and PGM:PlayersOnline() or {}
    local list = {}
    for _, guid in ipairs(guids) do
        local rec = g and g.members[guid]
        if rec then
            local main = PGM:MainOf(guid)
            list[#list + 1] = { guid = guid, rec = rec, main = main, onlineAs = online[main], others = {} }
        end
    end
    local function rank(it)
        if it.rec.online then return 2 end
        if it.onlineAs then return 1 end
        return 0
    end
    table.sort(list, function(a, b)
        local ra, rb = rank(a), rank(b)
        if ra ~= rb then return ra > rb end
        local la, lb = a.rec.lastOnline or 0, b.rec.lastOnline or 0
        if la ~= lb then return la > lb end
        return PGM.NameLess(a.rec.short, b.rec.short)
    end)
    return list
end

local function settle()
    local line, recipe, guids = readAnswer()
    if not (pending and line == pending.line and recipe == pending.recipe) then return false end
    local done = pending
    pending = nil
    answers[key(line, recipe)] = { t = PGM.Now(), guids = guids }
    local list = rows(guids)
    for _, fn in ipairs(done.callbacks) do pcall(fn, list) end
    PGM:Fire("CRAFTERS", line, recipe)
    return true
end

PGM:RegisterEvent("GUILD_RECIPE_KNOWN_BY_MEMBERS", settle)

-- Everyone in the guild who knows a recipe, then callback(list). The answer
-- may be from the last ten minutes. One question at a time: asking about
-- another recipe drops the wait for the first (the newest is what's on
-- screen).
local sharedRows
function PGM:RecipeCrafters(line, recipe, callback)
    line, recipe = tonumber(line), tonumber(recipe)
    if not (line and recipe) or not IsInGuild() then return false end
    if PGM.IS_FOREVER then
        if callback then callback(sharedRows(line, recipe)) end
        return true
    end
    local known = answers[key(line, recipe)]
    if known and PGM.Now() - known.t < KEEP_ANSWER then
        if callback then callback(rows(known.guids)) end
        return true
    end
    if pending and pending.line == line and pending.recipe == recipe then
        if callback then table.insert(pending.callbacks, callback) end
        return true
    end
    if not (C_GuildInfo and C_GuildInfo.QueryGuildMembersForRecipe) then return false end
    pending = { line = line, recipe = recipe, callbacks = { callback } }
    pcall(C_GuildInfo.QueryGuildMembersForRecipe, line, recipe)
    -- In case the event doesn't come, read the answer anyway after a moment.
    -- No answer for this recipe by then (the server dropped or throttled the
    -- question): give up, so picking it again asks again.
    C_Timer.After(WAIT_FOR_ANSWER, function()
        if pending and pending.line == line and pending.recipe == recipe and not settle() then
            pending = nil
            PGM:Fire("CRAFTERS", line, recipe)
        end
    end)
    return true
end

-- The answer we already have for a recipe, if any (nil while asking, or
-- when the server didn't answer).
function PGM:KnownCrafters(line, recipe)
    if PGM.IS_FOREVER then return sharedRows(tonumber(line) or 0, tonumber(recipe) or 0) end
    local known = answers[key(tonumber(line) or 0, tonumber(recipe) or 0)]
    return known and rows(known.guids)
end

-- Whether that question is still out.
function PGM:CraftersAsking(line, recipe)
    if PGM.IS_FOREVER then return false end
    return pending ~= nil and pending.line == tonumber(line) and pending.recipe == tonumber(recipe)
end

-- ============================================================
-- THE RECIPE INDEX
-- ============================================================
-- PandyGuildDB.recipes[base profession id] = { line = newest expansion's
-- skill line, list = { [recipeID] = { n = name, i = item id } } }.
-- Not per guild: recipes are the same everywhere.

local function index()
    if not PandyGuildDB then return nil end
    PandyGuildDB.recipes = PandyGuildDB.recipes or {}
    return PandyGuildDB.recipes
end

-- The profession of the window that's open, on Forever, for a recipe the
-- game won't place. Only asked while a window is open and ready, so it's
-- the recipe's own profession.
local function openProfession()
    if not (PGM.IS_FOREVER and C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo) then return nil end
    if C_TradeSkillUI.IsTradeSkillReady and not C_TradeSkillUI.IsTradeSkillReady() then return nil end
    local ok, info = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
    local id = ok and type(info) == "table" and P(info.professionID) or nil
    return (type(id) == "number" and id > 0) and id or nil
end

-- Which profession and expansion a recipe belongs to: base id (171 is
-- Alchemy) and the expansion's skill line, or the base twice when the game
-- doesn't say (WoW Forever).
local function lineOf(recipe)
    local info
    if C_TradeSkillUI and C_TradeSkillUI.GetProfessionInfoByRecipeID then
        local ok, res = pcall(C_TradeSkillUI.GetProfessionInfoByRecipeID, recipe)
        info = ok and res or nil
    end
    local line = type(info) == "table" and P(info.professionID) or nil
    if not line or line == 0 then
        line = openProfession()
        return line, line
    end
    local base = P(info.parentProfessionID)
    if not base or base == 0 then base = line end
    return base, line
end

-- The profession id to ask the guild about for a recipe (the base one,
-- like 171 for Alchemy), or nil.
function PGM:RecipeProfession(recipe)
    return (lineOf(recipe))
end

-- Learn the recipes of the profession window that's open now. Returns how
-- many were added or updated.
function PGM:LearnOpenRecipes()
    local idx = index()
    if not (idx and C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs and C_TradeSkillUI.GetRecipeInfo) then return 0 end
    if C_TradeSkillUI.IsTradeSkillReady and not C_TradeSkillUI.IsTradeSkillReady() then return 0 end
    local ok, ids = pcall(C_TradeSkillUI.GetAllRecipeIDs)
    if not ok or type(ids) ~= "table" or #ids == 0 then return 0 end
    -- The newest expansion's skill line for each base profession here.
    local lines, newest = {}, {}
    for _, recipe in ipairs(ids) do
        local base, line = lineOf(recipe)
        if base and line then
            lines[recipe] = { base, line }
            if not newest[base] or line > newest[base] then newest[base] = line end
        end
    end
    local n = 0
    for _, recipe in ipairs(ids) do
        local bl = lines[recipe]
        if bl and bl[2] == newest[bl[1]] then
            local okI, info = pcall(C_TradeSkillUI.GetRecipeInfo, recipe)
            local name = okI and type(info) == "table" and P(info.name)
            if name then
                local e = idx[bl[1]]
                if not e or (e.line or 0) < bl[2] then
                    -- A newer expansion starts afresh; names from shared
                    -- lists (line 0) are kept.
                    e = { line = bl[2], list = (e and (e.line or 0) == 0) and e.list or {} }
                    idx[bl[1]] = e
                end
                local item
                if C_TradeSkillUI.GetRecipeOutputItemData then
                    local okO, out = pcall(C_TradeSkillUI.GetRecipeOutputItemData, recipe)
                    item = okO and type(out) == "table" and P(out.itemID) or nil
                end
                local old = e.list[recipe]
                if not old or old.n ~= name or old.i ~= item then
                    e.list[recipe] = { n = name, i = item }
                    n = n + 1
                end
            end
        end
    end
    if PGM.IS_FOREVER then PGM:CheckRecipeSpells(ids) end
    if n > 0 then PGM:Fire("RECIPES") end
    return n
end

-- A profession window opening, or its list filling in.
local learnQueued = false
local function queueLearn()
    if learnQueued then return end
    learnQueued = true
    C_Timer.After(1, function()
        learnQueued = false
        PGM:LearnOpenRecipes()
        if PGM.SyncMyRecipes then PGM:SyncMyRecipes() end
    end)
end
PGM:RegisterEvent("TRADE_SKILL_SHOW", queueLearn)
PGM:RegisterEvent("TRADE_SKILL_LIST_UPDATE", queueLearn)

-- How many recipes are searchable.
function PGM:RecipeCount()
    local n = 0
    for _, e in pairs(index() or {}) do
        for _ in pairs(e.list) do n = n + 1 end
    end
    return n
end

-- Recipes matching what was typed: a name (or part of one, accents
-- ignored) or an item link. Each: { recipe, line (to ask about), base,
-- name, item }. Best first: exact name, then names starting with it.
function PGM:FindRecipes(text, limit)
    local out = {}
    text = strtrim(text or "")
    if text == "" then return out end
    local itemID = tonumber(text:match("|Hitem:(%d+)") or text:match("^item:(%d+)"))
    local q = not itemID and PGM.SortKey(text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
    for base, e in pairs(index() or {}) do
        for recipe, r in pairs(e.list) do
            local hit, score
            if itemID then
                hit, score = r.i == itemID, 0
            else
                local name = PGM.SortKey(r.n)
                local at = name:find(q, 1, true)
                hit = at ~= nil
                score = (name == q and 0) or (at == 1 and 1) or 2
            end
            if hit then
                out[#out + 1] = { recipe = recipe, line = base, base = base, name = r.n, item = r.i, score = score }
            end
        end
    end
    table.sort(out, function(a, b)
        if a.score ~= b.score then return a.score < b.score end
        return PGM.NameLess(a.name, b.name)
    end)
    while limit and #out > limit do table.remove(out) end
    return out
end

-- ============================================================
-- SHARED RECIPES (WoW Forever)
-- ============================================================
-- g.known[guid][base profession] = { u = stamp, ids = text }, text being the
-- recipe ids, sorted, in base 36: the first in full, each after it as the
-- gap from the one before, joined by "." ("" knows none).

local MAX_KNOWN = 1000   -- more recipes than any one profession has

local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
local function b36(n)
    if n == 0 then return "0" end
    local out = ""
    while n > 0 do
        local d = n % 36
        out = DIGITS:sub(d + 1, d + 1) .. out
        n = (n - d) / 36
    end
    return out
end

local function sorted(ids)
    local list, seen = {}, {}
    for _, id in ipairs(ids or {}) do
        if type(id) == "number" and id > 0 and not seen[id] then
            seen[id] = true
            list[#list + 1] = id
        end
    end
    table.sort(list)
    return list
end

function PGM.RecipeText(ids)
    local list, out = sorted(ids), {}
    for i, id in ipairs(list) do out[i] = b36(i == 1 and id or id - list[i - 1]) end
    return table.concat(out, ".")
end

-- The ids a text holds, or nil if it isn't one.
function PGM.RecipeParse(text)
    text = tostring(text or "")
    local out, at = {}, 0
    if text == "" then return out end
    for part in (text .. "."):gmatch("([^.]*)%.") do
        if not part:match("^[0-9a-z]+$") or #part > 7 then return nil end
        at = at + tonumber(part, 36)
        out[#out + 1] = at
        if #out > MAX_KNOWN or at > 2147483647 then return nil end
    end
    return out
end

-- The same ids as texts that each fit in room bytes, each starting over
-- (its first id in full), so every piece reads on its own. At least one.
function PGM.RecipeChunks(ids, room)
    local list, out, cur, size, prev = sorted(ids), {}, {}, 0, nil
    for _, id in ipairs(list) do
        local piece = b36(prev and id - prev or id)
        if prev and size + 1 + #piece > room then
            out[#out + 1] = table.concat(cur, ".")
            cur, size, piece = {}, 0, b36(id)
        end
        cur[#cur + 1] = piece
        size = size + (#cur > 1 and 1 or 0) + #piece
        prev = id
    end
    out[#out + 1] = table.concat(cur, ".")
    return out
end

-- Parsed lists, kept while their text is the same.
local sets = {}
local function knows(e, key, recipe)
    local c = sets[key]
    if not c or c.text ~= e.ids then
        c = { text = e.ids, set = {} }
        for _, id in ipairs(PGM.RecipeParse(e.ids) or {}) do c.set[id] = true end
        sets[key] = c
    end
    return c.set[recipe] == true
end

-- Whether the roster still shows rec with that profession (a dropped one
-- leaves its old list behind). Unknown professions don't rule anyone out.
local function stillHas(rec, base)
    if not (rec.prof and #rec.prof > 0) then return true end
    for _, pr in ipairs(rec.prof) do
        if pr.id == base then return true end
    end
    return false
end

sharedRows = function(base, recipe)
    local g = PGM.GuildDB()
    local guids = {}
    for guid, profs in pairs(g and g.known or {}) do
        local e, rec = profs[base], g.members[guid]
        if e and rec and stillHas(rec, base) and knows(e, guid .. ":" .. base, recipe) then
            guids[#guids + 1] = guid
        end
    end
    return rows(guids)
end

-- How many guildies have shared a list for a profession.
function PGM:RecipeSharers(base)
    local g, n = PGM.GuildDB(), 0
    for guid, profs in pairs(g and g.known or {}) do
        if profs[base] and g.members[guid] then n = n + 1 end
    end
    return n
end

-- The window that's open is my own profession: not a linked or guild view,
-- or an NPC's.
local function ownWindow()
    local T = C_TradeSkillUI
    for _, name in ipairs({ "IsTradeSkillLinked", "IsTradeSkillGuild", "IsNPCCrafting", "IsRuneforging" }) do
        if type(T[name]) == "function" then
            local ok, v = pcall(T[name])
            if ok and P(v) then return false end
        end
    end
    return true
end

-- What my character knows in the profession window that's open: its base
-- profession and the recipe ids, or nil (not my own window, or not ready).
function PGM:ReadMyRecipes()
    local T = C_TradeSkillUI
    if not (PGM.IS_FOREVER and T and T.GetAllRecipeIDs and T.GetRecipeInfo) then return nil end
    if T.IsTradeSkillReady and not T.IsTradeSkillReady() then return nil end
    if not ownWindow() then return nil end
    local base = openProfession()
    local mine = PGM.ReadMySkills and PGM.ReadMySkills()
    if not (base and mine and mine[base]) then return nil end
    local ok, ids = pcall(T.GetAllRecipeIDs)
    if not ok or type(ids) ~= "table" or #ids == 0 then return nil end
    local learned = {}
    for _, recipe in ipairs(ids) do
        if lineOf(recipe) == base then
            local okI, info = pcall(T.GetRecipeInfo, recipe)
            if okI and type(info) == "table" and P(info.learned) then learned[#learned + 1] = recipe end
        end
    end
    return base, learned
end

-- A recipe's name from its spell, once this client has shown that's the
-- same thing.
local function spellName(id)
    local name
    if C_Spell and C_Spell.GetSpellName then
        local ok, n = pcall(C_Spell.GetSpellName, id)
        name = ok and P(n) or nil
    elseif GetSpellInfo then
        local ok, n = pcall(GetSpellInfo, id)
        name = ok and P(n) or nil
    end
    return (type(name) == "string" and name ~= "") and name or nil
end

-- With a window open: do this client's recipe ids name their spells? A few
-- recipes are compared; the answer is kept (PandyGuildDB.recipeSpells).
function PGM:CheckRecipeSpells(ids)
    if not (PandyGuildDB and C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo) then return end
    local same, tried = 0, 0
    for _, recipe in ipairs(ids or {}) do
        if tried >= 5 then break end
        local ok, info = pcall(C_TradeSkillUI.GetRecipeInfo, recipe)
        local name = ok and type(info) == "table" and P(info.name)
        if name then
            tried = tried + 1
            if spellName(recipe) == name then same = same + 1 end
        end
    end
    if tried == 0 then return end
    local was = PandyGuildDB.recipeSpells
    PandyGuildDB.recipeSpells = same == tried
    if PandyGuildDB.recipeSpells and not was then
        local g = PGM.GuildDB()
        for _, profs in pairs(g and g.known or {}) do
            for base, e in pairs(profs) do PGM:IndexSharedRecipes(base, PGM.RecipeParse(e.ids)) end
        end
    end
end

-- A shared list's recipes, made searchable by name.
function PGM:IndexSharedRecipes(base, ids)
    local idx = index()
    if not (idx and ids and PandyGuildDB.recipeSpells) then return 0 end
    local e = idx[base]
    if not e then
        e = { line = 0, list = {} }
        idx[base] = e
    end
    local n = 0
    for _, id in ipairs(ids) do
        if not e.list[id] then
            local name = spellName(id)
            if name then
                e.list[id] = { n = name }
                n = n + 1
            end
        end
    end
    if n > 0 then PGM:Fire("RECIPES") end
    return n
end
