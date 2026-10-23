-- Professions.lua (UI): who in the guild has what, and how far along.
--
-- Pick a profession on the left; the right lists everyone with it, online
-- first and then by skill, so "who can craft this right now?" is one click.

local _, NS = ...
local PGM = NS.PGM
local C = PGM.C
local UI = PGM.UI
local W = UI.W

local state = { selected = nil, onlineOnly = false, search = "" }

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
    local g = PGM.GuildDB()
    local byId = {}
    for _, rec in pairs(g and g.members or {}) do
        for _, p in ipairs(rec.prof or {}) do
            local e = byId[p.id]
            if not e then
                e = { id = p.id, name = PGM.ProfName(p.id), count = 0, online = 0 }
                byId[p.id] = e
            end
            e.count = e.count + 1
            if rec.online then e.online = e.online + 1 end
        end
    end
    local out = {}
    for _, e in pairs(byId) do out[#out + 1] = e end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

local function memberList(id)
    local g = PGM.GuildDB()
    local out = {}
    local q = state.search:lower()
    for guid, rec in pairs(g and g.members or {}) do
        for _, p in ipairs(rec.prof or {}) do
            if p.id == id and (not state.onlineOnly or rec.online)
                and (q == "" or (rec.short and rec.short:lower():find(q, 1, true))) then
                out[#out + 1] = { guid = guid, rec = rec }
            end
        end
    end
    -- Online first, then the most recently seen.
    table.sort(out, function(a, b)
        if a.rec.online ~= b.rec.online then return a.rec.online end
        local la, lb = a.rec.lastOnline or 0, b.rec.lastOnline or 0
        if la ~= lb then return la > lb end
        return PGM.NameLess(a.rec.short, b.rec.short)
    end)
    return out
end

local function profRow(list)
    local r = W.Row(list)
    r.mark = W.Solid(r, "ARTWORK", C.jade)
    r.mark:SetPoint("TOPLEFT")
    r.mark:SetPoint("BOTTOMLEFT")
    r.mark:SetWidth(3)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(20, 20)
    r.icon:SetPoint("LEFT", 10, 0)
    r.name = W.FS(r, 12, C.text)
    r.name:SetPoint("LEFT", 36, 0)
    r.n = W.FS(r, 11, C.text2, "RIGHT")
    r.n:SetPoint("RIGHT", -6, 0)
    r:SetScript("OnClick", function(s)
        state.selected = s.e.id
        UI.tabs.professions.panel.members.offset = 0
        UI:Refresh()
    end)
    r.onEnter = function(s)
        GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
        GameTooltip:SetText(s.e.name)
        GameTooltip:AddLine(("%d in the guild, %d online now"):format(s.e.count, s.e.online), 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end
    return r
end

local function profUpdate(r, e)
    r.e = e
    r.icon:SetTexture(PGM.ProfIcon(e.id))
    r.name:SetText(e.name)
    r.n:SetText(e.count .. (e.online > 0 and (PGM.Hex(C.jade) .. "  " .. e.online .. " on|r") or ""))
    r.mark:SetShown(state.selected == e.id)
end

local function memberRow(list)
    local r = W.Row(list)
    r.name = W.FS(r, 12, C.text)
    r.name:SetPoint("LEFT", 6, 0)
    r.name:SetWidth(220)
    -- No skill column: the guild roster's profession "rank" isn't Midnight
    -- skill (most members read 1, the rest 600-800), so it isn't shown.
    r.level = W.FS(r, 12, C.text2)
    r.level:SetPoint("LEFT", 230, 0)
    r.level:SetWidth(90)
    r.seen = W.FS(r, 12, C.text2)
    r.seen:SetPoint("LEFT", 330, 0)
    r.onEnter = function(s)
        GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
        GameTooltip:SetText(PGM.ColorName(s.it.rec))
        GameTooltip:AddLine("Click to see their " .. PGM.ProfName(state.selected) .. " recipes: what they know and don't.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Right-click for more.", 0.45, 0.45, 0.45)
        GameTooltip:Show()
    end
    r.seen:SetPoint("RIGHT", -6, 0)
    r:SetScript("OnClick", function(s, button)
        if button == "RightButton" then
            UI:MemberMenu(s, s.it.guid, {
                { "View their " .. PGM.ProfName(state.selected) .. " recipes", function() viewRecipes(s.it.guid, state.selected) end },
            })
        else
            viewRecipes(s.it.guid, state.selected)
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
    r.name:SetText(PGM.ColorName(rec) .. tag)
    local max = PGM.MaxLevel()
    r.level:SetText(((rec.level or 0) >= max and PGM.Hex(C.text) or PGM.Hex(C.text2)) .. "Level " .. (rec.level or "?") .. "|r")
    if rec.online then
        r.seen:SetText(PGM.Hex(C.jade) .. (rec.mobile and "Mobile" or ((rec.zone and rec.zone ~= "") and rec.zone or "Online")) .. "|r")
    else
        r.seen:SetText(PGM.AgoText(rec.lastOnline))
    end
end

local function build(p)
    p.search = W.EditBox(p, 180, 24, "Search a name...")
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
    p.title = W.FS(p, 14, C.accent)
    p.title:SetPoint("TOPLEFT", 0, -4)

    p.profs = W.List(p, 30, profRow, profUpdate)
    p.profs:SetPoint("TOPLEFT", 0, -34)
    p.profs:SetPoint("BOTTOMLEFT")
    p.profs:SetWidth(240)

    p.members = W.List(p, 22, memberRow, memberUpdate)
    p.members:SetPoint("TOPLEFT", 260, -34)
    p.members:SetPoint("BOTTOMRIGHT")

    p.empty = W.FS(p, 12, C.text3, "CENTER")
    p.empty:SetPoint("CENTER", p.members, "CENTER")
    p.empty:SetWidth(440)
    p.empty:SetWordWrap(true)
end

local function refresh(p)
    local profs = profList()
    local found = false
    for _, e in ipairs(profs) do
        if e.id == state.selected then found = true end
    end
    if not found then
        local best
        for _, e in ipairs(profs) do
            if not best or e.count > best.count then best = e end
        end
        state.selected = best and best.id
    end
    p.profs:SetData(profs, true)
    p.title:SetText(#profs > 0 and "Professions" or "")

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
