-- Professions.lua (UI): who in the guild has what, and who to ask now.
--
-- Left: every profession, counted by player (a main and their alts), with
-- how many were active this week; thin ones stand out. Right: everyone with
-- the chosen one. By player, each player shows once, under the character
-- that has it; if that character is offline but the player is on another
-- one, the row says so, since you can still ask them.

local _, NS = ...
local PGM = NS.PGM
local C = PGM.C
local UI = PGM.UI
local W = UI.W

-- recipe: a recipe picked in "Who can craft..." ({ recipe, line, name });
-- while set, the right side lists who knows it instead of a profession.
local state = { selected = nil, onlineOnly = false, search = "", recipe = nil }

-- The profession the right side is about: the picked recipe's, or the one
-- selected on the left.
local function currentProf()
    return state.recipe and state.recipe.line or state.selected
end

local function byPlayer()
    return PGM.opt("profByPlayer") ~= false
end

-- A character's skill in the profession on the right (Forever only).
local function skillOf(rec)
    local id = currentProf()
    for _, pr in ipairs(rec and rec.prof or {}) do
        if pr.id == id then return PGM.ProfSkill(pr) end
    end
    return nil
end

-- Blizzard's own recipe view for a guild member, the same one the guild
-- window's "View Recipes" opens: everything they know, and don't.
-- (No CanViewGuildRecipes check first: in Midnight it can say no for a
-- profession whose recipe view then opens fine. The game decides.)
local function viewRecipes(guid, professionId)
    if not (C_GuildInfo and C_GuildInfo.QueryGuildMemberRecipes and guid and professionId) then return end
    pcall(C_GuildInfo.QueryGuildMemberRecipes, guid, professionId)
end

local function profList()
    local out = {}
    for id, e in pairs(PGM:ProfessionStats()) do
        e.name = PGM.ProfName(id)
        out[#out + 1] = e
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

local function matches(it, q)
    if q == "" then return true end
    if it.rec.short and it.rec.short:lower():find(q, 1, true) then return true end
    local g = PGM.GuildDB()
    local main = g and g.members[it.main]
    if main and main.short and main.short:lower():find(q, 1, true) then return true end
    for _, o in ipairs(it.others) do
        if o.short and o.short:lower():find(q, 1, true) then return true end
    end
    return false
end

local function memberList(id)
    local out = {}
    local q = state.search:lower()
    for _, it in ipairs(PGM:ProfessionCrafters(id, byPlayer())) do
        if (not state.onlineOnly or it.rec.online or it.onlineAs) and matches(it, q) then
            out[#out + 1] = it
        end
    end
    return out
end

local function profRow(list)
    local r = W.Row(list)
    r.mark = W.Solid(r, "ARTWORK", C.jade)
    r.mark:SetPoint("TOPLEFT")
    r.mark:SetPoint("BOTTOMLEFT")
    r.mark:SetWidth(3)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(22, 22)
    r.icon:SetPoint("LEFT", 10, 0)
    r.name = W.FS(r, 12, C.text)
    r.name:SetPoint("TOPLEFT", 40, -4)
    r.sub = W.FS(r, 10, C.text3)
    r.sub:SetPoint("BOTTOMLEFT", 40, 4)
    r.n = W.FS(r, 12, C.text, "RIGHT")
    r.n:SetPoint("TOPRIGHT", -6, -4)
    r.on = W.FS(r, 10, C.jade, "RIGHT")
    r.on:SetPoint("BOTTOMRIGHT", -6, 4)
    r:SetScript("OnClick", function(s)
        state.selected = s.e.id
        state.recipe = nil
        UI.tabs.professions.panel.members.offset = 0
        UI:Refresh()
    end)
    r.onEnter = function(s)
        local e = s.e
        GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
        GameTooltip:SetText(e.name)
        GameTooltip:AddLine(("%d players (%d characters, alts included)"):format(e.players, e.chars), 0.85, 0.85, 0.85)
        GameTooltip:AddLine(("%d active in the last %d days"):format(e.activePlayers, PGM.PROF_ACTIVE_DAYS), 0.85, 0.85, 0.85)
        GameTooltip:AddLine(("%d characters at level %d"):format(e.atMax, PGM.MaxLevel()), 0.85, 0.85, 0.85)
        if e.skillKnown then
            GameTooltip:AddLine(("%d players at Artisan skill (%d+), %d of them active"):format(e.artisans,
                PGM.SKILL_ARTISAN, e.activeArtisans), 0.85, 0.85, 0.85)
        end
        GameTooltip:AddLine(("%d players online now (%d on the crafting character)"):format(e.onlinePlayers, e.onlineChars),
            0.33, 0.82, 0.58)
        if e.thin then
            GameTooltip:AddLine("Few active crafters: worth recruiting for.", 1, 0.66, 0.3)
        end
        GameTooltip:Show()
    end
    return r
end

local function profUpdate(r, e)
    r.e = e
    r.icon:SetTexture(PGM.ProfIcon(e.id))
    r.name:SetText(e.name)
    if e.skillKnown then
        -- Forever: what counts is who can make the good stuff.
        r.sub:SetText(e.thin and (PGM.Hex(C.amber) .. "Only " .. e.activeArtisans .. " active artisans|r")
            or (e.activePlayers .. " active, " .. e.artisans .. " artisans"))
    else
        r.sub:SetText(e.thin and (PGM.Hex(C.amber) .. "Only " .. e.activePlayers .. " active|r")
            or (e.activePlayers .. " active this week"))
    end
    r.n:SetText(tostring(e.players))
    r.on:SetText(e.onlinePlayers > 0 and (e.onlinePlayers .. " on") or "")
    r.mark:SetShown(not state.recipe and state.selected == e.id)
end

local function memberRow(list)
    local r = W.Row(list)
    r.name = W.FS(r, 12, C.text)
    r.name:SetPoint("LEFT", 6, 0)
    r.name:SetWidth(240)
    -- No skill column on retail: the guild roster's profession "rank" isn't
    -- Midnight skill (most members read 1, the rest 600-800). On Forever it
    -- is Classic skill, 1-300, so it gets one.
    r.level = W.FS(r, 12, C.text2)
    r.level:SetPoint("LEFT", 252, 0)
    r.level:SetWidth(70)
    local seenAt = 330
    if PGM.IS_FOREVER then
        r.skill = W.FS(r, 12, C.text2, "RIGHT")
        r.skill:SetPoint("LEFT", 326, 0)
        r.skill:SetWidth(34)
        seenAt = 374
    end
    r.seen = W.FS(r, 12, C.text2)
    r.seen:SetPoint("LEFT", seenAt, 0)
    r.seen:SetPoint("RIGHT", -6, 0)
    r.onEnter = function(s)
        local it = s.it
        GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
        GameTooltip:SetText(PGM.ColorName(it.rec))
        local skill = skillOf(it.rec)
        if skill then
            GameTooltip:AddLine(("%s %d (%s)"):format(PGM.ProfName(currentProf()), skill, PGM.SkillTier(skill)), 1, 1, 1)
        end
        if not it.rec.online and it.onlineAs then
            GameTooltip:AddLine("Online now as " .. it.onlineAs.short .. ": whisper them there.", 0.33, 0.82, 0.58, true)
        end
        if #it.others > 0 then
            local names = {}
            for _, o in ipairs(it.others) do
                local os = skillOf(o)
                names[#names + 1] = (o.short or "?") .. " (" .. (os and ("skill " .. os) or (o.level or "?")) .. ")"
            end
            GameTooltip:AddLine("Also on: " .. table.concat(names, ", "), 0.8, 0.8, 0.8, true)
        end
        GameTooltip:AddLine("Click to see " .. (it.rec.short or "their") .. "'s " .. PGM.ProfName(currentProf())
            .. " recipes: what they know and don't.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Right-click for more.", 0.45, 0.45, 0.45)
        GameTooltip:Show()
    end
    r:SetScript("OnClick", function(s, button)
        local it = s.it
        if button == "RightButton" then
            local extra = {
                { "View " .. (it.rec.short or "their") .. "'s " .. PGM.ProfName(currentProf()) .. " recipes",
                  function() viewRecipes(it.guid, currentProf()) end },
            }
            if not it.rec.online and it.onlineAs then
                extra[#extra + 1] = { "Whisper " .. it.onlineAs.short .. " (online now)", function() UI:Whisper(it.onlineAs) end }
            end
            UI:MemberMenu(s, it.guid, extra)
        else
            viewRecipes(it.guid, currentProf())
        end
    end)
    return r
end

local function memberUpdate(r, it)
    r.it = it
    local rec = it.rec
    local tag = ""
    if PGM:IsAlt(it.guid) then
        local g = PGM.GuildDB()
        local mg = PGM:KnownMain(it.guid)
        local main = mg and g.members[mg]
        tag = PGM.Hex(C.text3) .. " (" .. (main and (main.short .. "'s alt") or "alt") .. ")|r"
    end
    local more = #it.others > 0 and (PGM.Hex(C.text3) .. " +" .. #it.others .. "|r") or ""
    r.name:SetText(PGM.ColorName(rec) .. tag .. more)
    local max = PGM.MaxLevel()
    r.level:SetText(((rec.level or 0) >= max and PGM.Hex(C.text) or PGM.Hex(C.text2)) .. "Level " .. (rec.level or "?") .. "|r")
    if r.skill then
        local skill = skillOf(rec)
        r.skill:SetText(skill and (((skill >= PGM.SKILL_ARTISAN) and PGM.Hex(C.text) or PGM.Hex(C.text2)) .. skill .. "|r") or "")
    end
    if rec.online then
        r.seen:SetText(PGM.Hex(C.jade) .. (rec.mobile and "Mobile" or ((rec.zone and rec.zone ~= "") and rec.zone or "Online")) .. "|r")
    elseif it.onlineAs then
        r.seen:SetText(PGM.Hex(C.jade) .. "Online as " .. (it.onlineAs.short or "?") .. "|r")
    else
        r.seen:SetText(PGM.AgoText(rec.lastOnline))
    end
    -- Nobody to ask right now: same colours, half as bright (as on the Roster).
    local alpha = (rec.online or it.onlineAs) and 1 or 0.5
    for _, fs in ipairs({ r.name, r.level, r.seen, r.skill }) do fs:SetAlpha(alpha) end
end

local function build(p)
    p.search = W.EditBox(p, 170, 24, "Search a name...")
    p.search:SetPoint("TOPLEFT", 260, 0)
    p.search.onChange = function(s)
        state.search = s:GetText() or ""
        p.members.offset = 0
        UI:Refresh()
    end
    p.online = W.Chip(p, "Online only", function(s)
        state.onlineOnly = not state.onlineOnly
        p.members.offset = 0
        s:SetActive(state.onlineOnly)
        UI:Refresh()
    end)
    p.online:SetPoint("LEFT", p.search, "RIGHT", 8, 0)
    p.byPlayer = W.Chip(p, "By player", function(s)
        PGM.setOpt("profByPlayer", not byPlayer())
        p.members.offset = 0
        s:SetActive(byPlayer())
        UI:Refresh()
    end)
    p.byPlayer:SetPoint("LEFT", p.online, "RIGHT", 6, 0)
    p.byPlayer.tip = "One row per player (a main and their alts), under the character that has the profession."
    p.byPlayer:SetActive(byPlayer())
    -- Who can craft...: a recipe name, or an item link (shift-click an item
    -- while the box has focus). Matches drop down under it; picking one asks
    -- the guild who knows it.
    p.find = W.EditBox(p, 240, 24, "Who can craft... (name or item)")
    p.find:SetPoint("TOPLEFT", 0, 0)
    p.find:SetMaxLetters(200)
    p.suggest = CreateFrame("Frame", nil, p, "BackdropTemplate")
    p.suggest:SetPoint("TOPLEFT", p.find, "BOTTOMLEFT", 0, -2)
    p.suggest:SetSize(240, 8 * 22 + 6)
    p.suggest:SetFrameLevel(p:GetFrameLevel() + 30)
    W.Backdrop(p.suggest, C.bg, C.accent, 1)
    p.suggest:Hide()
    p.suggest.rows = {}
    for i = 1, 8 do
        local b = CreateFrame("Button", nil, p.suggest)
        b:SetSize(232, 22)
        b:SetPoint("TOPLEFT", 4, -3 - (i - 1) * 22)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.08)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetSize(16, 16)
        b.icon:SetPoint("LEFT", 4, 0)
        b.fs = W.FS(b, 11, C.text)
        b.fs:SetPoint("LEFT", 26, 0)
        b.fs:SetPoint("RIGHT", -4, 0)
        b:SetScript("OnClick", function(self) UI:ProfessionsPickRecipe(self.match) end)
        p.suggest.rows[i] = b
    end
    p.suggestNote = W.FS(p.suggest, 11, C.text3)
    p.suggestNote:SetPoint("TOPLEFT", 8, -6)
    p.suggestNote:SetPoint("TOPRIGHT", -8, -6)
    p.suggestNote:SetWordWrap(true)

    local function showMatches()
        local text = p.find:GetText() or ""
        if not p.find:HasFocus() or strtrim(text) == "" then p.suggest:Hide() return end
        local found = PGM:FindRecipes(text, 8)
        p.suggest.first = found[1]
        for i, b in ipairs(p.suggest.rows) do
            local m = found[i]
            b.match = m
            b:SetShown(m ~= nil)
            if m then
                b.icon:SetTexture(PGM.ProfIcon(m.base))
                b.fs:SetText(m.name)
            end
        end
        if #found == 0 then
            p.suggestNote:SetText(PGM:RecipeCount() == 0
                and "No recipes learned yet. Open a profession window (yours, or click a crafter to see theirs) and its recipes become searchable."
                or "No recipe matches. Recipes are learned from profession windows as they're opened.")
            p.suggest:SetHeight(64)
        else
            p.suggestNote:SetText("")
            p.suggest:SetHeight(#found * 22 + 6)
        end
        p.suggest:Show()
    end
    p.find.onChange = showMatches
    p.find:HookScript("OnEditFocusGained", showMatches)
    -- Late enough that a click on a match still lands.
    p.find:HookScript("OnEditFocusLost", function() C_Timer.After(0.2, function() p.suggest:Hide() end) end)
    p.find.onEnter = function() if p.suggest.first then UI:ProfessionsPickRecipe(p.suggest.first) end end
    p.back = W.Button(p, "Back to professions", 140, 20, C.text2)
    p.back:SetPoint("TOPRIGHT", 0, -32)
    p.back:SetScript("OnClick", function()
        state.recipe = nil
        p.find:SetText("")
        UI:Refresh()
    end)
    p.back:Hide()

    p.profs = W.List(p, 34, profRow, profUpdate)
    p.profs:SetPoint("TOPLEFT", 0, -34)
    p.profs:SetPoint("BOTTOMLEFT")
    p.profs:SetWidth(240)

    p.summary = W.FS(p, 11, C.text2)
    p.summary:SetPoint("TOPLEFT", 266, -36)
    p.summary:SetPoint("TOPRIGHT", 0, -36)

    p.members = W.List(p, 22, memberRow, memberUpdate)
    p.members:SetPoint("TOPLEFT", 260, -56)
    p.members:SetPoint("BOTTOMRIGHT")

    p.empty = W.FS(p, 12, C.text3, "CENTER")
    p.empty:SetPoint("CENTER", p.members, "CENTER")
    p.empty:SetWidth(440)
    p.empty:SetWordWrap(true)
end

local function refresh(p)
    local profs = profList()
    local sel
    for _, e in ipairs(profs) do
        if e.id == state.selected then sel = e end
    end
    if not sel then
        for _, e in ipairs(profs) do
            if not sel or e.players > sel.players then sel = e end
        end
        state.selected = sel and sel.id
    end
    p.profs:SetData(profs, true)
    p.byPlayer:SetActive(byPlayer())

    p.back:SetShown(state.recipe ~= nil)
    -- Leave room for the Back button beside the summary.
    p.summary:SetPoint("TOPRIGHT", state.recipe and -150 or 0, -36)
    -- Who knows the picked recipe, or nil while the guild is still asked.
    local known = state.recipe and PGM:KnownCrafters(state.recipe.line, state.recipe.recipe)
    if state.recipe then
        local list = known
        local on = 0
        for _, it in ipairs(list or {}) do if it.rec.online or it.onlineAs then on = on + 1 end end
        p.summary:SetText(("%s%s|r (%s): %s"):format(PGM.Hex(C.text), state.recipe.name or "?",
            PGM.ProfName(state.recipe.line),
            not list and (PGM.Hex(C.text3) .. "asking the guild...|r")
            or (#list .. (#list == 1 and " guildie knows it" or " guildies know it") .. "  ·  " .. PGM.Hex(C.jade) .. on .. " online|r")))
    elseif sel then
        p.summary:SetText(("%s%s|r: %d players (%d chars)  ·  %s%d active this week|r%s  ·  %s%d online|r"):format(
            PGM.Hex(C.text), sel.name, sel.players, sel.chars,
            sel.thin and not sel.skillKnown and PGM.Hex(C.amber) or PGM.Hex(C.text2), sel.activePlayers,
            sel.skillKnown and (("  ·  %s%d artisans|r"):format(sel.thin and PGM.Hex(C.amber) or PGM.Hex(C.text2),
                sel.artisans)) or "",
            PGM.Hex(C.jade), sel.onlinePlayers))
    else
        p.summary:SetText("")
    end

    local members
    if state.recipe then
        members = {}
        local q = state.search:lower()
        for _, it in ipairs(known or {}) do
            if (not state.onlineOnly or it.rec.online or it.onlineAs) and matches(it, q) then members[#members + 1] = it end
        end
    else
        members = state.selected and memberList(state.selected) or {}
    end
    p.members:SetData(members, true)
    if state.recipe and #members == 0 then
        local r = state.recipe
        local asking = PGM:CraftersAsking(r.line, r.recipe)
        p.empty:SetText(not known
            and (asking and "Asking the guild..." or "No answer from the server. Pick the recipe again to ask again.")
            or (state.onlineOnly and "Nobody who knows it is online." or "Nobody in the guild knows this recipe."))
    elseif #profs == 0 then
        p.empty:SetText("No profession data yet. It comes from the game's guild roster; if it stays empty, open the guild window (J) once so the game loads it.")
    elseif #members == 0 then
        p.empty:SetText(state.onlineOnly and "Nobody with this profession is online." or "Nobody matches.")
    else
        p.empty:SetText("")
    end
end

-- Show who knows a recipe (from Who can craft...).
function UI:ProfessionsPickRecipe(m)
    local p = UI.tabs.professions and UI.tabs.professions.panel
    if not (m and p) then return end
    state.recipe = { recipe = m.recipe, line = m.line, name = m.name }
    p.find:SetText(m.name or "")
    p.find:ClearFocus()
    p.suggest:Hide()
    p.members.offset = 0
    PGM:RecipeCrafters(m.line, m.recipe, function() UI:Refresh() end)
    UI:Refresh()
end

-- Shift-clicking an item while Who can craft... has focus puts its link
-- there, as it would in chat.
-- Both hooks are kept, as either name may be the one called; a link already
-- put in this same moment (one calling the other) isn't put in twice.
local lastLink, lastAt
local function insertLink(link)
    local p = UI.tabs.professions and UI.tabs.professions.panel
    if not (p and p.find and p.find:HasFocus() and type(link) == "string") then return end
    if link == lastLink and GetTime() == lastAt then return end
    lastLink, lastAt = link, GetTime()
    p.find:Insert(link)
end
if ChatFrameUtil and ChatFrameUtil.InsertLink then hooksecurefunc(ChatFrameUtil, "InsertLink", insertLink) end
if ChatEdit_InsertLink then hooksecurefunc("ChatEdit_InsertLink", insertLink) end

PGM:On("CRAFTERS", function()
    if UI.current == "professions" then UI:Refresh() end
end)

UI:AddTab({ id = "professions", label = "Professions", build = build, refresh = refresh })
