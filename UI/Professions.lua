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

local state = { selected = nil, onlineOnly = false, search = "" }

local function byPlayer()
    return PGM.opt("profByPlayer") ~= false
end

-- Blizzard's own recipe view for a guild member, the same one the guild
-- window's "View Recipes" opens: everything they know, and don't.
local function viewRecipes(guid, professionId)
    if not (C_GuildInfo and C_GuildInfo.QueryGuildMemberRecipes) then return end
    if CanViewGuildRecipes and not CanViewGuildRecipes(professionId) then
        PGM.Print("The game doesn't share guild recipes for that profession.")
        return
    end
    C_GuildInfo.QueryGuildMemberRecipes(guid, professionId)
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
    r.sub:SetText(e.thin and (PGM.Hex(C.amber) .. "Only " .. e.activePlayers .. " active|r")
        or (e.activePlayers .. " active this week"))
    r.n:SetText(tostring(e.players))
    r.on:SetText(e.onlinePlayers > 0 and (e.onlinePlayers .. " on") or "")
    r.mark:SetShown(state.selected == e.id)
end

local function memberRow(list)
    local r = W.Row(list)
    r.name = W.FS(r, 12, C.text)
    r.name:SetPoint("LEFT", 6, 0)
    r.name:SetWidth(240)
    -- No skill column: the guild roster's profession "rank" isn't Midnight
    -- skill (most members read 1, the rest 600-800), so it isn't shown.
    r.level = W.FS(r, 12, C.text2)
    r.level:SetPoint("LEFT", 252, 0)
    r.level:SetWidth(70)
    r.seen = W.FS(r, 12, C.text2)
    r.seen:SetPoint("LEFT", 330, 0)
    r.seen:SetPoint("RIGHT", -6, 0)
    r.onEnter = function(s)
        local it = s.it
        GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
        GameTooltip:SetText(PGM.ColorName(it.rec))
        if not it.rec.online and it.onlineAs then
            GameTooltip:AddLine("Online now as " .. it.onlineAs.short .. ": whisper them there.", 0.33, 0.82, 0.58, true)
        end
        if #it.others > 0 then
            local names = {}
            for _, o in ipairs(it.others) do names[#names + 1] = (o.short or "?") .. " (" .. (o.level or "?") .. ")" end
            GameTooltip:AddLine("Also on: " .. table.concat(names, ", "), 0.8, 0.8, 0.8, true)
        end
        GameTooltip:AddLine("Click to see " .. (it.rec.short or "their") .. "'s " .. PGM.ProfName(state.selected)
            .. " recipes: what they know and don't.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Right-click for more.", 0.45, 0.45, 0.45)
        GameTooltip:Show()
    end
    r:SetScript("OnClick", function(s, button)
        local it = s.it
        if button == "RightButton" then
            local extra = {
                { "View " .. (it.rec.short or "their") .. "'s " .. PGM.ProfName(state.selected) .. " recipes",
                  function() viewRecipes(it.guid, state.selected) end },
            }
            if not it.rec.online and it.onlineAs then
                extra[#extra + 1] = { "Whisper " .. it.onlineAs.short .. " (online now)", function() UI:Whisper(it.onlineAs) end }
            end
            UI:MemberMenu(s, it.guid, extra)
        else
            viewRecipes(it.guid, state.selected)
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
    if rec.online then
        r.seen:SetText(PGM.Hex(C.jade) .. (rec.mobile and "Mobile" or ((rec.zone and rec.zone ~= "") and rec.zone or "Online")) .. "|r")
    elseif it.onlineAs then
        r.seen:SetText(PGM.Hex(C.jade) .. "Online as " .. (it.onlineAs.short or "?") .. "|r")
    else
        r.seen:SetText(PGM.AgoText(rec.lastOnline))
    end
    -- Nobody to ask right now: same colours, half as bright (as on the Roster).
    local alpha = (rec.online or it.onlineAs) and 1 or 0.5
    for _, fs in ipairs({ r.name, r.level, r.seen }) do fs:SetAlpha(alpha) end
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
    p.title = W.FS(p, 14, C.accent)
    p.title:SetPoint("TOPLEFT", 0, -4)

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
    p.title:SetText(#profs > 0 and "Professions" or "")
    p.byPlayer:SetActive(byPlayer())

    if sel then
        p.summary:SetText(("%s%s|r: %d players (%d chars)  ·  %s%d active this week|r  ·  %s%d online|r"):format(
            PGM.Hex(C.text), sel.name, sel.players, sel.chars,
            sel.thin and PGM.Hex(C.amber) or PGM.Hex(C.text2), sel.activePlayers,
            PGM.Hex(C.jade), sel.onlinePlayers))
    else
        p.summary:SetText("")
    end

    local members = state.selected and memberList(state.selected) or {}
    p.members:SetData(members, true)
    if #profs == 0 then
        p.empty:SetText("No profession data yet. It comes from the game's guild roster; if it stays empty, open the guild window (J) once so the game loads it.")
    elseif #members == 0 then
        p.empty:SetText(state.onlineOnly and "Nobody with this profession is online." or "Nobody matches.")
    else
        p.empty:SetText("")
    end
end

UI:AddTab({ id = "professions", label = "Professions", build = build, refresh = refresh })
