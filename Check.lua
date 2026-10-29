-- /pgm check: what this client's game offers the group finder and the
-- professions pages, saved in PandyGuildDB.check for a look outside the game
-- (after a /reload). Made for WoW Forever, whose Classic content sits on the
-- Midnight engine, so which retail APIs answer there isn't always known.
-- Every read is guarded: a missing API is written down, never an error.
-- While it runs it also notes how Blizzard's own Group Finder calls Search,
-- CreateListing and ApplyToGroup, for the shape of those calls.

local _, NS = ...
local PGM = NS.PGM

local MAX_ROWS = 60

local function try(fn, ...)
    if type(fn) ~= "function" then return "missing" end
    local out = { pcall(fn, ...) }
    if not out[1] then return "error: " .. tostring(out[2]) end
    table.remove(out, 1)
    return out
end

-- A value as something SavedVariables can hold: tables copied a few deep,
-- functions and frames as their type.
local function plain(v, depth)
    -- A secret saved to SavedVariables would spoil the whole file.
    if issecretvalue and issecretvalue(v) then return "secret" end
    if type(v) == "table" and canaccesstable and not canaccesstable(v) then return "locked" end
    local t = type(v)
    if t == "table" then
        if (depth or 0) >= 3 then return "table" end
        if v.GetObjectType then return "frame" end
        local out, n = {}, 0
        for k, x in pairs(v) do
            n = n + 1
            if n > MAX_ROWS then break end
            out[type(k) == "number" and k or tostring(k)] = plain(x, (depth or 0) + 1)
        end
        return out
    elseif t == "function" or t == "userdata" or t == "thread" then
        return t
    end
    return v
end

local function has(name)
    local v = _G
    for part in name:gmatch("[^.]+") do
        v = type(v) == "table" and v[part] or nil
    end
    return v ~= nil
end

local function exists(names)
    local out = {}
    for _, n in ipairs(names) do out[n] = has(n) end
    return out
end

local function loaded(name)
    local fn = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    return fn and select(2, pcall(fn, name)) or false
end

local function groupFinder(out)
    local L = C_LFGList or {}
    out.api = exists({
        "C_LFGList.Search", "C_LFGList.CreateListing", "C_LFGList.UpdateListing", "C_LFGList.ApplyToGroup",
        "C_LFGList.GetApplicants", "C_LFGList.GetApplicantMemberInfo", "C_LFGList.GetSearchResultMemberCounts",
        "C_LFGList.GetSearchResultPlayerInfo", "C_LFGList.GetAvailableActivities", "C_LFGList.GetAdvancedFilter",
        "C_PartyInfo.RequestInviteFromUnit", "PVEFrame_ShowFrame", "PVEFrame_ToggleFrame", "LFGListFrame",
        "LFGParentFrame", "ToggleLFGParentFrame", "LFGBrowseFrame", "LFGListingFrame",
        "LFGListSearchEntry_Update", "LFGListUtil_SetSearchEntryTooltip", "Enum.LFGListFilter",
    })
    out.vanillaStyleLoaded = loaded("Blizzard_GroupFinder_VanillaStyle")
    out.retailLoaded = loaded("Blizzard_GroupFinder")
    out.filters = plain(Enum and Enum.LFGListFilter)
    out.categories = {}
    local cats = try(L.GetAvailableCategories)
    for _, id in ipairs(type(cats) == "table" and type(cats[1]) == "table" and cats[1] or {}) do
        local info = try(L.GetLfgCategoryInfo, id)
        local c = { id = id, info = plain(type(info) == "table" and info[1]), activities = {} }
        local acts = try(L.GetAvailableActivities, id)
        for i, a in ipairs(type(acts) == "table" and type(acts[1]) == "table" and acts[1] or {}) do
            if i > MAX_ROWS then break end
            local t = try(L.GetActivityInfoTable, a)
            t = type(t) == "table" and t[1] or {}
            c.activities[#c.activities + 1] = {
                id = a, fullName = t.fullName, categoryID = t.categoryID, maxNumPlayers = t.maxNumPlayers,
                isMythicPlusActivity = t.isMythicPlusActivity, isCurrentRaidActivity = t.isCurrentRaidActivity,
                groupFinderActivityGroupID = t.groupFinderActivityGroupID, filters = t.filters,
            }
        end
        out.categories[#out.categories + 1] = c
    end
    local events = {}
    for _, e in ipairs({ "LFG_LIST_ACTIVE_ENTRY_UPDATE", "LFG_LIST_SEARCH_RESULTS_RECEIVED",
            "LFG_LIST_SEARCH_RESULT_UPDATED", "LFG_LIST_APPLICATION_STATUS_UPDATED", "LFG_LIST_APPLICANT_LIST_UPDATED",
            "LFG_LIST_APPLICANT_UPDATED", "CHALLENGE_MODE_COMPLETED", "PLAYER_SPECIALIZATION_CHANGED",
            "GUILD_RECIPE_KNOWN_BY_MEMBERS", "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE" }) do
        events[e] = C_EventUtils and C_EventUtils.IsEventValid and C_EventUtils.IsEventValid(e) or "unknown"
    end
    out.events = events
    local spec = GetSpecialization and select(2, pcall(GetSpecialization))
    out.spec = {
        current = spec, count = plain(try(GetNumSpecializations)),
        role = plain(try(GetSpecializationRole, tonumber(spec) or 1)),
        info = plain(try(GetSpecializationInfo, tonumber(spec) or 1)),
    }
    out.active = plain(try(L.GetActiveEntryInfo))
    -- Raid difficulties, for reading loot: id, name, type, raid?, size.
    out.difficulties = {}
    for id = 1, 220 do
        local d = try(GetDifficultyInfo, id)
        if type(d) == "table" and d[1] then
            -- name, groupType, ..., minPlayers, maxPlayers
            out.difficulties[#out.difficulties + 1] = plain({ id = id, name = d[1], type = d[2], size = d[10] })
        end
    end
    local inst = try(GetInstanceInfo)
    out.instance = plain(type(inst) == "table" and inst or nil)
end

local function professions(out)
    out.mine = {}
    local slots = try(GetProfessions)
    for i = 1, 6 do
        local idx = type(slots) == "table" and slots[i]
        if idx then
            local p = try(GetProfessionInfo, idx)
            if type(p) == "table" then
                out.mine[#out.mine + 1] = { slot = i, name = p[1], rank = p[3], maxRank = p[4], skillLine = p[7] }
            end
        end
    end
    -- The guild roster's profession fields, for a few members.
    out.roster = {}
    local club = C_Club and C_Club.GetGuildClubId and select(2, pcall(C_Club.GetGuildClubId))
    local ids = club and try(C_Club.GetClubMembers, club)
    for i, id in ipairs(type(ids) == "table" and type(ids[1]) == "table" and ids[1] or {}) do
        if i > 20 then break end
        local m = try(C_Club.GetMemberInfo, club, id)
        m = type(m) == "table" and m[1]
        if type(m) == "table" then
            out.roster[#out.roster + 1] = plain({ name = m.name, level = m.level,
                p1 = m.profession1ID, p1Rank = m.profession1Rank, p1Name = m.profession1Name,
                p2 = m.profession2ID, p2Rank = m.profession2Rank, p2Name = m.profession2Name })
        end
    end
    local T = C_TradeSkillUI or {}
    out.api = exists({
        "C_TradeSkillUI.GetAllRecipeIDs", "C_TradeSkillUI.GetRecipeInfo", "C_TradeSkillUI.GetProfessionInfoByRecipeID",
        "C_TradeSkillUI.GetBaseProfessionInfo", "C_TradeSkillUI.GetChildProfessionInfos",
        "C_TradeSkillUI.GetTradeSkillDisplayName", "C_TradeSkillUI.GetTradeSkillTexture",
        "C_TradeSkillUI.GetRecipeOutputItemData", "C_TradeSkillUI.OpenTradeSkill",
        "C_GuildInfo.QueryGuildMembersForRecipe", "C_GuildInfo.QueryGuildMemberRecipes",
        "GetGuildRecipeInfoPostQuery", "GetGuildRecipeMember", "CanViewGuildRecipes",
        "ProfessionsFrame", "TradeSkillFrame", "CraftFrame",
    })
    out.professionsLoaded = loaded("Blizzard_Professions")
    out.tradeSkillLoaded = loaded("Blizzard_TradeSkillUI")
    out.names, out.icons = {}, {}
    for _, line in ipairs({ 129, 164, 165, 171, 182, 185, 186, 197, 202, 333, 356, 393 }) do
        out.names[line] = plain(try(T.GetTradeSkillDisplayName, line))
        out.icons[line] = plain(try(T.GetTradeSkillTexture, line))
    end
    out.canViewAlchemy = plain(try(CanViewGuildRecipes, 171))
    out.bindings = { guild = GetBindingKey and GetBindingKey("TOGGLEGUILDTAB"), social = GetBindingKey and GetBindingKey("TOGGLESOCIAL") }
    -- With a profession window open: what its recipe list gives.
    if T.IsTradeSkillReady and select(2, pcall(T.IsTradeSkillReady)) then
        local all = try(T.GetAllRecipeIDs)
        all = type(all) == "table" and type(all[1]) == "table" and all[1] or {}
        local learned = 0
        for _, id in ipairs(all) do
            local r = try(T.GetRecipeInfo, id)
            if type(r) == "table" and type(r[1]) == "table" and r[1].learned then learned = learned + 1 end
        end
        out.open = {
            recipes = #all, learned = learned, first = all[1],
            firstProfession = plain(all[1] and try(T.GetProfessionInfoByRecipeID, all[1])),
            firstOutput = plain(all[1] and try(T.GetRecipeOutputItemData, all[1])),
            base = plain(try(T.GetBaseProfessionInfo)),
        }
    end
    if ProfessionsFrame then
        local f = ProfessionsFrame
        out.frame = { right = f.GetRight and f:GetRight(), craftingPage = f.CraftingPage ~= nil,
                      bookPage = f.BookPage ~= nil, rightTabs = f.rightProfessionTabs and #f.rightProfessionTabs or nil }
    end
end

-- Blizzard's own calls, as they happen, so their argument order is known.
-- Kept for the session, so a second /pgm check still has them.
local seen
local function watch(name)
    if not (C_LFGList and type(C_LFGList[name]) == "function" and hooksecurefunc) then return end
    hooksecurefunc(C_LFGList, name, function(...)
        local list = seen[name] or {}
        seen[name] = list
        if #list < 5 then list[#list + 1] = plain({ ... }) end
    end)
end

-- It's for a look soon after, so it doesn't stay in saved data for good.
PGM:On("LOGIN", function()
    local c = PandyGuildDB and PandyGuildDB.check
    if c and (c.at or 0) < time() - 14 * 86400 then PandyGuildDB.check = nil end
end)

function PGM:ForeverCheck()
    PandyGuildDB = PandyGuildDB or {}
    local out = {
        at = time(), version = PGM.VERSION, forever = PGM.IS_FOREVER,
        build = plain({ GetBuildInfo and GetBuildInfo() }),
        project = WOW_PROJECT_ID, camelot = WOW_PROJECT_CAMELOT,
        groupFinder = {}, professions = {}, calls = seen or {},
    }
    local ok, err = pcall(groupFinder, out.groupFinder)
    if not ok then out.groupFinder.error = tostring(err) end
    ok, err = pcall(professions, out.professions)
    if not ok then out.professions.error = tostring(err) end
    -- Who in the guild knows Minor Healing Potion (Alchemy), if the server
    -- answers that on this client.
    if C_GuildInfo and C_GuildInfo.QueryGuildMembersForRecipe then
        pcall(C_GuildInfo.QueryGuildMembersForRecipe, 171, 2330)
        C_Timer.After(3, function()
            local q = try(GetGuildRecipeInfoPostQuery)
            out.professions.guildQuery = { info = plain(q), first = plain(try(GetGuildRecipeMember, 1)) }
        end)
    end
    if not seen then
        seen = out.calls
        for _, n in ipairs({ "Search", "CreateListing", "UpdateListing", "ApplyToGroup" }) do watch(n) end
    end
    PandyGuildDB.check = out
    PGM.Print("Checked. Now, if you can: search for a group in Looking for Group, open a profession window and type /pgm check again, then /reload to save it all.")
end
