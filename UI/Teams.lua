-- Teams.lua (UI): build raid teams, set roles, see composition and who's
-- been showing up to that team's nights.

local _, NS = ...
local PGM = NS.PGM
local C = PGM.C
local UI = PGM.UI
local W = UI.W

local state = { selected = nil }

StaticPopupDialogs.PANDYGUILD_DELETE_TEAM = {
    text = "Delete the raid team \"%s\"? Its raid nights are kept but no longer tagged to it.",
    button1 = YES, button2 = NO,
    OnAccept = function(_, id) PGM:DeleteTeam(id) end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

local function selectedTeam()
    local t = state.selected and PGM:TeamById(state.selected)
    if not t then
        t = PGM:Teams()[1]
        state.selected = t and t.id
    end
    return t
end

local function teamRow(list)
    local r = W.Row(list)
    r.mark = W.Solid(r, "ARTWORK", C.jade)
    r.mark:SetPoint("TOPLEFT")
    r.mark:SetPoint("BOTTOMLEFT")
    r.mark:SetWidth(3)
    r.name = W.FS(r, 13, C.text)
    r.name:SetPoint("TOPLEFT", 12, -5)
    r.name:SetPoint("TOPRIGHT", -6, -5)
    r.sub = W.FS(r, 10, C.text3)
    r.sub:SetPoint("BOTTOMLEFT", 12, 5)
    r.sub:SetPoint("BOTTOMRIGHT", -6, 5)
    r:SetScript("OnClick", function(s)
        UI:CommitTeamEdits()
        state.selected = s.t.id
        UI:Refresh()
    end)
    return r
end

local function teamUpdate(r, t)
    r.t = t
    r.name:SetText(t.name)
    local n = 0
    local g = PGM.GuildDB()
    for guid in pairs(t.members) do
        if g and g.members[guid] then n = n + 1 end
    end
    r.sub:SetText(n .. " members" .. ((t.schedule or "") ~= "" and ("  -  " .. t.schedule) or ""))
    r.mark:SetShown(state.selected == t.id)
end

-- A small clickable label inside a row (role, status).
local function cellButton(parent, x, w, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetPoint("LEFT", x, 0)
    b:SetSize(w, 18)
    b.fs = W.FS(b, 12, C.text)
    b.fs:SetPoint("LEFT")
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(s)
        if not PGM:CanEdit() then return end
        GameTooltip:SetOwner(s, "ANCHOR_TOP")
        GameTooltip:SetText(s.tipText or "Click to change")
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

local function memberRow(list)
    local r = W.Row(list)
    r.name = W.FS(r, 12, C.text)
    r.name:SetPoint("LEFT", 6, 0)
    r.name:SetWidth(150)
    r.role = cellButton(r, 166, 60, function(s) PGM:CycleRole(state.selected, s:GetParent().it.guid) end)
    r.role.tipText = "Click to change role"
    r.status = cellButton(r, 230, 56, function(s) PGM:CycleStatus(state.selected, s:GetParent().it.guid) end)
    r.status.tipText = "Click: Core, Trial, Bench"
    r.seen = W.FS(r, 12, C.text2)
    r.seen:SetPoint("LEFT", 290, 0)
    r.seen:SetWidth(100)
    r.att = W.FS(r, 12, C.text, "RIGHT")
    r.att:SetPoint("LEFT", 396, 0)
    r.att:SetWidth(64)
    r.mplus = W.FS(r, 12, C.text2, "RIGHT")
    r.mplus:SetPoint("RIGHT", -6, 0)
    r.mplus:SetWidth(50)
    r:SetScript("OnClick", function(s, button)
        local it = s.it
        if button == "RightButton" then
            local entries = {
                { "Whisper", function() UI:Whisper(it.rec) end },
                { "Invite to group", function() UI:Invite(it.rec) end, disabled = not it.rec.online },
                { "Open profile", function() UI:OpenProfile(it.guid) end },
            }
            if PGM:CanEdit() then
                entries[#entries + 1] = { divider = true }
                entries[#entries + 1] = { "Remove from team", function() PGM:RemoveFromTeam(state.selected, it.guid) end }
            end
            W.Menu(s, it.rec.short, entries)
        else
            UI:OpenProfile(it.guid)
        end
    end)
    return r
end

local function memberUpdate(r, it)
    r.it = it
    local rec, e = it.rec, it.entry
    r.name:SetText(PGM.ColorName(rec) .. PGM.Hex(C.text3) .. " " .. (rec.level or "?") .. "|r")
    local rc = PGM.ROLE_COLOR[e.role] or C.text
    r.role.fs:SetText(PGM.Hex(rc) .. (PGM.ROLE_LABEL[e.role] or e.role) .. "|r")
    local sc = PGM.STATUS_COLOR[e.status] or C.text
    r.status.fs:SetText(PGM.Hex(sc) .. (PGM.STATUS_LABEL[e.status] or e.status) .. "|r")
    if rec.online then
        r.seen:SetText(PGM.Hex(C.jade) .. "Online|r")
    else
        r.seen:SetText(PGM.AgoText(rec.lastOnline))
    end
    if it.possible > 0 then
        local pct = it.present / it.possible
        local col = pct >= 0.8 and C.jade or (pct >= 0.5 and C.gold or C.red)
        r.att:SetText(PGM.Hex(col) .. it.present .. "/" .. it.possible .. "|r")
    else
        r.att:SetText(PGM.Hex(C.text3) .. "-|r")
    end
    local score = PGM:MPlusScore(rec)
    if PGM.IS_FOREVER then r.mplus:SetText("")
    else r.mplus:SetText(score and (PGM.Hex(PGM:ScoreColor(score)) .. score .. "|r") or (PGM.Hex(C.text3) .. "-|r")) end
end

local ROLE_ORDER = { TANK = 1, HEALER = 2, DPS = 3 }
local STATUS_ORDER = { core = 1, trial = 2, bench = 3 }

local function rosterOf(t)
    local g = PGM.GuildDB()
    local out = {}
    for guid, e in pairs(t.members) do
        local rec = g and g.members[guid]
        if rec then
            local present, possible = PGM:AttendanceFor(guid, 10, t.id)
            out[#out + 1] = { guid = guid, rec = rec, entry = e, present = present, possible = possible }
        end
    end
    table.sort(out, function(a, b)
        local sa, sb = STATUS_ORDER[a.entry.status] or 9, STATUS_ORDER[b.entry.status] or 9
        if sa ~= sb then return sa < sb end
        local ra, rb = ROLE_ORDER[a.entry.role] or 9, ROLE_ORDER[b.entry.role] or 9
        if ra ~= rb then return ra < rb end
        return (a.rec.short or "") < (b.rec.short or "")
    end)
    return out
end

local function build(p)
    -- Left: the teams.
    p.teams = W.List(p, 40, teamRow, teamUpdate)
    p.teams:SetPoint("TOPLEFT")
    p.teams:SetPoint("BOTTOMLEFT", 0, 66)
    p.teams:SetWidth(190)
    p.find = W.Button(p, "Find teams in notes", 190, 26)
    p.find:SetPoint("BOTTOMLEFT", 0, 32)
    p.find.tip = "Reads \"Team Valor\" and the like out of guild and officer notes, makes a team for each one at least three members mention, and fills it with the tagged mains. Teams that already exist are just topped up."
    p.find:SetScript("OnClick", function()
        UI:CommitTeamEdits()
        local created, joined = PGM:FindTeamsInNotes()
        if #created > 0 then
            PGM.Print(("Made %s from guild notes; %d members added."):format(table.concat(created, ", "), joined))
        else
            PGM.Print(("No new teams found in notes; %d members added to existing teams."):format(joined))
        end
    end)
    p.new = W.Button(p, "+ New raid team", 190, 26)
    p.new:SetPoint("BOTTOMLEFT")
    p.new:SetScript("OnClick", function()
        UI:CommitTeamEdits()
        local t = PGM:CreateTeam()
        if t then
            state.selected = t.id
            UI:Refresh()
            p.nameBox:SetFocus()
            p.nameBox:HighlightText()
        end
    end)

    -- Right: the selected team.
    local d = CreateFrame("Frame", nil, p)
    d:SetPoint("TOPLEFT", 204, 0)
    d:SetPoint("BOTTOMRIGHT")
    p.detail = d

    -- Each box remembers which team it was editing when it got focus, so an
    -- edit always lands on that team even if the selection moved meanwhile.
    local function remember(s) s.teamId = state.selected end
    p.nameBox = W.EditBox(d, 200, 24, "Team name")
    p.nameBox:SetPoint("TOPLEFT")
    p.nameBox:HookScript("OnEditFocusGained", remember)
    p.nameBox.onCommit = function(s)
        local t = PGM:TeamById(s.teamId)
        local name = strtrim(s:GetText() or "")
        if t and name == "" then
            s:SetText(t.name)   -- a team can't have no name; put it back
        elseif t then
            PGM:UpdateTeam(t.id, { name = name })
        end
    end
    p.schedBox = W.EditBox(d, 200, 24, "Schedule, e.g. Wed/Thu 8-11pm")
    p.schedBox:SetPoint("LEFT", p.nameBox, "RIGHT", 8, 0)
    p.schedBox:HookScript("OnEditFocusGained", remember)
    p.schedBox.onCommit = function(s)
        if s.teamId then PGM:UpdateTeam(s.teamId, { schedule = s:GetText() or "" }) end
    end
    function UI:CommitTeamEdits()
        p.nameBox:ClearFocus()
        p.schedBox:ClearFocus()
        if p.tagsBox then p.tagsBox:ClearFocus() end
    end
    p.delete = W.Button(d, "Delete", 70, 26, C.red)
    p.delete:SetPoint("TOPRIGHT")
    p.delete:SetScript("OnClick", function()
        local t = selectedTeam()
        if t then StaticPopup_Show("PANDYGUILD_DELETE_TEAM", t.name, nil, t.id) end
    end)

    p.comp = W.FS(d, 13, C.text)
    p.comp:SetPoint("TOPLEFT", 0, -38)
    p.comp:SetPoint("TOPRIGHT", 0, -38)
    p.buffs = W.FS(d, 11, C.text2)
    p.buffs:SetPoint("TOPLEFT", 0, -58)
    p.buffs:SetPoint("TOPRIGHT", 0, -58)
    p.buffs:SetWordWrap(true)
    p.buffs:SetJustifyV("TOP")
    p.buffs:SetMaxLines(2) -- a nearly empty team misses everything; the tooltip has the rest
    -- Hover the buff line for the full checklist with what each one does.
    local hover = CreateFrame("Frame", nil, d)
    hover:SetPoint("TOPLEFT", 0, -56)
    hover:SetPoint("TOPRIGHT", 0, -56)
    hover:SetHeight(32)
    hover:EnableMouse(true)
    hover:SetScript("OnEnter", function(s)
        local comp = p.compData
        if PGM.IS_FOREVER or not comp or comp.total == 0 then return end
        GameTooltip:SetOwner(s, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Raid buffs and debuffs (Midnight)")
        for _, b in ipairs(PGM.RAID_BUFFS) do
            local have = comp.classes[b.class]
            local mark = have and PGM.Hex(C.jade) .. "yes|r" or PGM.Hex(C.red) .. "no|r"
            GameTooltip:AddDoubleLine(("%s %s  %s%s|r"):format(mark, b.name, PGM.Hex(C.text3), b.effect),
                PGM.ClassHex(b.class) .. PGM.ClassName(b.class) .. (have and (" x" .. have) or "") .. "|r")
        end
        GameTooltip:AddLine(" ")
        for _, u in ipairs(PGM.RAID_UTILITY) do
            local missing = tContains(comp.missingUtility, u.name)
            GameTooltip:AddLine((missing and PGM.Hex(C.red) .. "no|r " or PGM.Hex(C.jade) .. "yes|r ") .. u.name)
        end
        GameTooltip:AddLine("Counts Core and Trial members, not Bench.", 0.45, 0.45, 0.45)
        GameTooltip:Show()
    end)
    hover:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Note tags: which guild-note tags mean this team, and whether to keep
    -- pulling in newly tagged members after every roster read.
    p.tagsBox = W.EditBox(d, 200, 24, "Note tags, e.g. Valor, VA, V")
    p.tagsBox:SetPoint("TOPLEFT", 0, -92)
    p.tagsBox:HookScript("OnEditFocusGained", remember)
    p.tagsBox.onCommit = function(s)
        if s.teamId then PGM:UpdateTeam(s.teamId, { tags = s:GetText() or "" }) end
    end
    p.import = W.Button(d, "Import from notes", 132, 24)
    p.import:SetPoint("LEFT", p.tagsBox, "RIGHT", 6, 0)
    p.import.tip = "Adds every main whose guild or officer note carries one of these tags. Never adds alts, and never re-adds anyone you removed from this team by hand."
    p.import:SetScript("OnClick", function()
        UI:CommitTeamEdits()
        local t = selectedTeam()
        if not t then return end
        if #PGM:TeamTags(t) == 0 then
            PGM.Print("Give " .. t.name .. " some note tags first, like: Valor, VA, V")
            return
        end
        local n = PGM:ImportTeamFromNotes(t.id)
        PGM.Print(("Added %d to %s from guild notes."):format(n, t.name))
    end)
    p.sync = W.Check(d, "Keep in sync", function()
        local t = selectedTeam()
        return t and t.autoSync
    end, function(v)
        local t = selectedTeam()
        if t then
            PGM:UpdateTeam(t.id, { autoSync = v })
            if v then PGM:ImportTeamFromNotes(t.id) end
        end
    end)
    p.sync:SetWidth(120)
    p.sync:SetPoint("LEFT", p.import, "RIGHT", 10, 0)
    p.sync:HookScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_TOP")
        GameTooltip:SetText("Keep in sync with notes")
        GameTooltip:AddLine("Newly tagged members join this team after each roster read. Anyone you remove stays removed.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    p.sync:HookScript("OnLeave", function() GameTooltip:Hide() end)

    -- Shown instead of the edit controls to anyone who isn't an officer.
    p.readOnly = W.FS(d, 11, C.text3)
    p.readOnly:SetPoint("TOPLEFT", 0, -128)
    p.readOnly:SetText("Shared by your officers. Only officers and raid leaders can change teams.")

    p.addBox = W.EditBox(d, 160, 24, "Add by name...")
    p.addBox:SetPoint("TOPLEFT", 0, -124)
    local function add()
        local t = selectedTeam()
        local guid = t and PGM:FindMember(p.addBox:GetText())
        if not guid then
            PGM.Print("No guild member called " .. (p.addBox:GetText() or "") .. ".")
            return
        end
        if not PGM:AddToTeam(t.id, guid) then
            local rec = PGM.GuildDB().members[guid]
            PGM.Print(((rec and rec.short) or "They") .. " is already on " .. t.name .. ".")
        end
        p.addBox:SetText("")
    end
    p.addBox.onEnter = add
    p.addBtn = W.Button(d, "Add", 50, 24)
    p.addBtn:SetPoint("LEFT", p.addBox, "RIGHT", 6, 0)
    p.addBtn:SetScript("OnClick", add)
    p.addGroup = W.Button(d, "Add my group", 104, 24)
    p.addGroup:SetPoint("LEFT", p.addBtn, "RIGHT", 6, 0)
    p.addGroup.tip = "Adds every guild member in your current party or raid."
    p.addGroup:SetScript("OnClick", function()
        local t = selectedTeam()
        if not t then return end
        local n = PGM:AddGroupToTeam(t.id)
        PGM.Print(("Added %d from your group to %s."):format(n, t.name))
    end)
    p.match = W.Button(d, "Match past raids", 124, 24)
    p.match:SetPoint("LEFT", p.addGroup, "RIGHT", 6, 0)
    p.match.tip = "Tags recorded raid nights that have no team yet to the team that was there (half or more of its roster)."
    p.match:SetScript("OnClick", function()
        local n = PGM:AutoAssignRaids()
        PGM.Print(("Matched %d raid night%s to a team."):format(n, n == 1 and "" or "s"))
    end)

    local header = CreateFrame("Frame", nil, d)
    header:SetPoint("TOPLEFT", 0, -158)
    header:SetPoint("TOPRIGHT", 0, -158)
    header:SetHeight(20)
    local hbg = W.Solid(header, "BACKGROUND", C.panel)
    hbg:SetAllPoints()
    for _, h in ipairs({ { "Name", 6 }, { "Role", 166 }, { "Status", 230 }, { "Last seen", 290 } }) do
        local fs = W.FS(header, 11, C.text2)
        fs:SetPoint("LEFT", h[2], 0)
        fs:SetText(h[1])
    end
    -- Raids is right-aligned over its right-aligned values (396-460).
    local rfs = W.FS(header, 11, C.text2, "RIGHT")
    rfs:SetPoint("LEFT", 396, 0)
    rfs:SetWidth(64)
    rfs:SetText("Raids")
    local mfs = W.FS(header, 11, C.text2, "RIGHT")
    mfs:SetPoint("RIGHT", -14, 0)
    mfs:SetText(PGM.IS_FOREVER and "" or "M+")

    p.members = W.List(d, 22, memberRow, memberUpdate)
    p.members:SetPoint("TOPLEFT", 0, -180)
    p.members:SetPoint("BOTTOMRIGHT")

    p.empty = W.FS(p, 13, C.text3, "CENTER")
    p.empty:SetPoint("CENTER", d, "CENTER")
    p.empty:SetWidth(460)
    p.empty:SetWordWrap(true)
end

local function refresh(p)
    local list = PGM:Teams()
    local t = selectedTeam()
    p.teams:SetData(list, true)
    p.detail:SetShown(t ~= nil)
    if not t then
        local canEdit = PGM:CanEdit()
        p.new:SetShown(canEdit)
        p.find:SetShown(canEdit)
        p.empty:SetText(canEdit
            and "No raid teams yet.\n\nClick \"Find teams in notes\" to build them from your guild notes, or \"+ New raid team\" to make one by hand."
            or "No raid teams yet.\n\nYour officers' teams will show up here once one of them is online.")
        return
    end
    p.empty:SetText("")

    -- Officers edit; everyone else sees the shared teams read-only.
    local canEdit = PGM:CanEdit()
    for _, w in ipairs({ p.new, p.find, p.delete, p.import, p.sync, p.addBox, p.addBtn, p.addGroup, p.match }) do
        w:SetShown(canEdit)
    end
    for _, box in ipairs({ p.nameBox, p.schedBox, p.tagsBox }) do
        box:EnableMouse(canEdit)
        if not canEdit then box:ClearFocus() end
    end
    p.readOnly:SetShown(not canEdit)

    if not p.nameBox:HasFocus() then p.nameBox:SetText(t.name) end
    if not p.schedBox:HasFocus() then p.schedBox:SetText(t.schedule or "") end
    if not p.tagsBox:HasFocus() then p.tagsBox:SetText(t.tags or "") end
    p.sync:Sync()

    local comp = PGM:TeamComposition(t)
    p.comp:SetText(("%s%d Tanks|r   %s%d Healers|r   %s%d DPS|r   %s%d active%s|r"):format(
        PGM.Hex(C.blue), comp.TANK, PGM.Hex(C.jade), comp.HEALER, PGM.Hex(C.red), comp.DPS,
        PGM.Hex(C.text2), comp.total, comp.bench > 0 and (", " .. comp.bench .. " bench") or ""))
    p.compData = comp
    if PGM.IS_FOREVER then
        -- The buff list is Midnight's; Forever's raids are a different game.
        p.buffs:SetText("")
    elseif comp.total == 0 then
        p.buffs:SetText("Add members to see which raid buffs the team brings.")
    else
        local parts = {}
        for _, b in ipairs(comp.missing) do
            parts[#parts + 1] = PGM.ClassHex(b.class) .. b.name .. "|r"
        end
        for _, u in ipairs(comp.missingUtility) do
            parts[#parts + 1] = PGM.Hex(C.red) .. "no " .. u .. "|r"
        end
        if #parts == 0 then
            p.buffs:SetText(PGM.Hex(C.jade) .. "Every raid buff and debuff is covered.|r  " .. PGM.Hex(C.text3) .. "(hover for details)|r")
        else
            p.buffs:SetText(PGM.Hex(C.amber) .. "Missing:|r " .. table.concat(parts, ", ") .. "  " .. PGM.Hex(C.text3) .. "(hover for details)|r")
        end
    end

    p.members:SetData(rosterOf(t), true)
end

UI:AddTab({ id = "teams", label = "Raid Teams", build = build, refresh = refresh })
