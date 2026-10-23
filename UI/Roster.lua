-- Roster.lua (UI): the searchable, sortable member list.

local _, NS = ...
local PGM = NS.PGM
local C = PGM.C
local UI = PGM.UI
local W = UI.W

local COLS = {
    { key = "name",   label = "Name",      w = 176 },
    { key = "level",  label = "Lvl",       w = 38, justify = "CENTER" },
    { key = "rank",   label = "Rank",      w = 120 },
    { key = "seen",   label = "Last seen", w = 140 },
    { key = "mplus",  label = "M+",        w = 52, justify = "RIGHT" },
    { key = "raids",  label = "Raids",     w = 58, justify = "RIGHT" },
    { key = "note",   label = "Note",      w = 0 },
}
-- No Mythic+ on WoW Forever; the Note column takes the room.
if PGM.IS_FOREVER then
    for i = #COLS, 1, -1 do
        if COLS[i].key == "mplus" then table.remove(COLS, i) end
    end
end

local state = { sort = "seen", asc = false, search = "", filters = {} }
local refresh   -- defined below; the search box calls it

local function isColumn(key)
    for _, col in ipairs(COLS) do if col.key == key then return true end end
    return false
end

-- Blizzard's own column-sort arrow (as on the Who list).
local SORT_ARROW = "Interface\\Buttons\\UI-SortArrow"

local FILTERS = {
    { id = "online",   label = "Online" },
    { id = "max",      label = "Max level" },
    { id = "mains",    label = "Mains only" },
    { id = "inactive", label = "Away 30d+" },
    { id = "addon",    label = "Has addon" },
}

local function sortValue(it, key)
    local rec = it.rec
    if key == "name" then return (rec.short or ""):lower()
    elseif key == "level" then return rec.level or 0
    elseif key == "rank" then return rec.rankIndex or 99
    elseif key == "seen" then return rec.online and math.huge or (rec.lastOnline or 0)
    elseif key == "mplus" then return it.mplus or 0
    elseif key == "raids" then return it.possible > 0 and it.present / it.possible or -1
    elseif key == "note" then return (rec.note or ""):lower()
    end
    return 0
end

local function matches(it, q)
    if q == "" then return true end
    local rec = it.rec
    -- A numeric loop, not ipairs: any of these can be nil and ipairs would
    -- stop at the first one.
    local fields = { rec.short, rec.rank, rec.zone, rec.note, rec.onote, PGM.ClassName(rec.class), it.mainName,
        PGM.ProfText(rec), rec.race and (PGM.RaceInfo(rec.race)) }
    for i = 1, 9 do
        local field = fields[i]
        if field and field:lower():find(q, 1, true) then return true end
    end
    return false
end

local function buildList()
    local g = PGM.GuildDB()
    local out = {}
    if not g then return out end
    local max = PGM.MaxLevel()
    local q = state.search:lower()
    local f = state.filters
    for guid, rec in pairs(g.members) do
        local keep = true
        if f.online and not rec.online then keep = false end
        if f.max and (rec.level or 0) < max then keep = false end
        if f.mains and PGM:IsAlt(guid) then keep = false end
        if f.addon and not PGM:AddonUserOf(guid) then keep = false end
        if f.inactive then
            local d = PGM.DaysSince(rec.lastOnline)
            if rec.online or not d or d < 30 then keep = false end
        end
        if keep then
            local main = PGM:KnownMain(guid) and g.members[PGM:KnownMain(guid)]
            local present, possible = PGM:AttendanceFor(guid)
            local it = {
                guid = guid, rec = rec, main = main, mainName = main and main.short,
                alts = PGM:AltCount(guid), mplus = PGM:MPlusScore(rec),
                present = present, possible = possible,
            }
            if matches(it, q) then out[#out + 1] = it end
        end
    end
    local key, asc = state.sort, state.asc
    table.sort(out, function(a, b)
        local va, vb = sortValue(a, key), sortValue(b, key)
        if va == vb then return (a.rec.short or "") < (b.rec.short or "") end
        if asc then return va < vb end
        return va > vb
    end)
    return out
end

local function seenText(rec)
    if rec.online then
        if rec.mobile then return PGM.Hex(C.blue) .. "Mobile|r" end
        return PGM.Hex(C.jade) .. (rec.zone ~= "" and rec.zone or "Online") .. "|r"
    end
    if not rec.lastOnline then return PGM.Hex(C.text3) .. "?|r" end
    local d = PGM.DaysSince(rec.lastOnline)
    local col = d < 7 and C.text or (d < 30 and C.text2 or (d < 60 and C.amber or C.red))
    return PGM.Hex(col) .. PGM.AgoText(rec.lastOnline) .. "|r"
end

local function buildRow(list)
    local r = W.Row(list)
    r.cells = {}
    local x = 0
    for _, col in ipairs(COLS) do
        local fs = W.FS(r, 12, C.text, col.justify)
        fs:SetPoint("LEFT", x + 6, 0)
        if col.w > 0 then fs:SetWidth(col.w - 12) else fs:SetPoint("RIGHT", -6, 0) end
        r.cells[col.key] = fs
        x = x + col.w
    end
    r:SetScript("OnClick", function(s, button)
        if button == "RightButton" then
            UI:MemberMenu(s, s.item.guid)
        else
            UI:OpenProfile(s.item.guid)
        end
    end)
    r.onEnter = function(s)
        local it, rec = s.item, s.item.rec
        GameTooltip:SetOwner(s, "ANCHOR_CURSOR_RIGHT")
        GameTooltip:SetText(PGM.ColorName(rec) .. (rec.realm and (PGM.Hex(C.text3) .. " - " .. rec.realm .. "|r") or ""))
        GameTooltip:AddLine(("Level %s %s, %s"):format(rec.level or "?", PGM.ClassName(rec.class), rec.rank or "?"), 1, 1, 1)
        if it.main then
            GameTooltip:AddLine("Alt of " .. PGM.ColorName(it.main))
        elseif PGM:IsAlt(it.guid) then
            GameTooltip:AddLine("Alt (main unknown - link them in their profile)", 0.7, 0.55, 1)
        end
        if it.alts > 0 then GameTooltip:AddLine(it.alts .. (it.alts == 1 and " alt" or " alts"), 0.7, 0.55, 1) end
        if rec.note ~= "" then GameTooltip:AddLine("Note: " .. rec.note, 0.8, 0.8, 0.8, true) end
        if rec.onote ~= "" then GameTooltip:AddLine("Officer: " .. rec.onote, 0.6, 0.9, 0.6, true) end
        local profs = PGM.ProfText(rec, true)
        if profs then GameTooltip:AddLine(profs, 0.85, 0.85, 0.85) end
        local teams = PGM:TeamsText(it.guid)
        if teams ~= "" then GameTooltip:AddLine("Raid teams: " .. teams, 0.72, 0.54, 1) end
        local user = PGM:AddonUserOf(it.guid)
        if user then GameTooltip:AddLine("Runs Pandy Guild Management v" .. (user.v or "?"), 0.33, 0.82, 0.58) end
        local mine = PGM.GuildDB() and PGM.GuildDB().notes[it.guid]
        if mine and mine ~= "" then GameTooltip:AddLine("Your note: " .. mine, 1, 0.82, 0.4, true) end
        GameTooltip:AddLine("Click for profile, right-click for actions", 0.45, 0.45, 0.45)
        GameTooltip:Show()
    end
    return r
end

local function updateRow(r, it)
    r.item = it
    local rec = it.rec
    local name = PGM.ColorName(rec)
    if it.main or PGM:IsAlt(it.guid) then
        name = name .. PGM.Hex(C.purple) .. " alt|r"
    elseif it.alts > 0 then
        name = name .. PGM.Hex(C.text3) .. " +" .. it.alts .. "|r"
    end
    r.cells.name:SetText(name)
    local max = PGM.MaxLevel()
    r.cells.level:SetText(((rec.level or 0) >= max and PGM.Hex(C.text) or PGM.Hex(C.text2)) .. (rec.level or "?") .. "|r")
    r.cells.rank:SetText(rec.rank or "?")
    r.cells.rank:SetTextColor(C.text2[1], C.text2[2], C.text2[3])
    r.cells.seen:SetText(seenText(rec))
    if not r.cells.mplus then
        -- No M+ column on WoW Forever.
    elseif it.mplus then
        local col = PGM:ScoreColor(it.mplus)
        r.cells.mplus:SetText(PGM.Hex(col) .. it.mplus .. "|r")
    else
        r.cells.mplus:SetText(PGM.Hex(C.text3) .. "-|r")
    end
    if it.possible > 0 then
        local pct = it.present / it.possible
        local col = pct >= 0.8 and C.jade or (pct >= 0.5 and C.gold or C.red)
        r.cells.raids:SetText(PGM.Hex(col) .. it.present .. "/" .. it.possible .. "|r")
    else
        r.cells.raids:SetText(PGM.Hex(C.text3) .. "-|r")
    end
    r.cells.note:SetText(rec.note or "")
    r.cells.note:SetTextColor(C.text2[1], C.text2[2], C.text2[3])
end

local function build(p)
    p.search = W.EditBox(p, 150, 24, "Search...")
    p.search:SetPoint("TOPLEFT", 0, 0)
    -- New search, filter or sort: back to the top of the list.
    p.search.onChange = function(s)
        state.search = s:GetText() or ""
        p.list.offset = 0
        refresh(p)
    end

    p.chips = {}
    local prev = p.search
    for _, f in ipairs(FILTERS) do
        local chip = W.Chip(p, f.label, function(s)
            state.filters[f.id] = not state.filters[f.id]
            s:SetActive(state.filters[f.id])
            p.list.offset = 0
            UI:Refresh()
        end)
        chip:SetPoint("LEFT", prev, "RIGHT", 8, 0)
        prev = chip
    end

    p.export = W.Button(p, "Export CSV", 96, 24)
    p.export:SetPoint("TOPRIGHT", 0, 0)
    p.export:SetScript("OnClick", function() UI:ShowExport("Roster CSV", PGM:RosterCSV()) end)

    p.count = W.FS(p, 11, C.text3, "RIGHT")
    p.count:SetPoint("RIGHT", p.export, "LEFT", -10, 0)

    -- Column headers: click to sort, click again to flip. The choice is
    -- remembered between sessions.
    local saved = PGM.opt("rosterSort")
    if type(saved) == "table" and isColumn(saved.key) then state.sort, state.asc = saved.key, saved.asc and true or false end
    local header = CreateFrame("Frame", nil, p)
    header:SetPoint("TOPLEFT", 0, -34)
    header:SetPoint("TOPRIGHT", 0, -34)
    header:SetHeight(22)
    local hbg = W.Solid(header, "BACKGROUND", C.side)
    hbg:SetAllPoints()
    local hline = W.Divider(header)
    hline:SetPoint("BOTTOMLEFT")
    hline:SetPoint("BOTTOMRIGHT")
    p.headers = {}
    local x = 0
    for _, col in ipairs(COLS) do
        local b = CreateFrame("Button", nil, header)
        b:SetPoint("TOPLEFT", x, 0)
        b:SetHeight(22)
        if col.w > 0 then b:SetWidth(col.w) else b:SetPoint("TOPRIGHT") end
        b.fs = W.FS(b, 11, C.text2, col.justify)
        b.fs:SetPoint("LEFT", 6, 0)
        b.fs:SetPoint("RIGHT", -6, 0)
        b.fs:SetText(col.label)
        b.arrow = b:CreateTexture(nil, "OVERLAY")
        b.arrow:SetSize(9, 9)
        b.arrow:SetTexture(SORT_ARROW)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.06)
        b.col = col
        b:SetScript("OnClick", function()
            if state.sort == col.key then state.asc = not state.asc
            else
                state.sort = col.key
                state.asc = (col.key == "name" or col.key == "rank" or col.key == "note")
            end
            PGM.setOpt("rosterSort", { key = state.sort, asc = state.asc })
            p.list.offset = 0
            UI:Refresh()
        end)
        b:SetScript("OnEnter", function(s)
            GameTooltip:SetOwner(s, "ANCHOR_TOP")
            GameTooltip:SetText("Sort by " .. col.label:lower())
            GameTooltip:AddLine("Click again to reverse.", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        p.headers[#p.headers + 1] = b
        x = x + col.w
    end

    p.list = W.List(p, 22, buildRow, updateRow)
    p.list:SetPoint("TOPLEFT", 0, -58)
    p.list:SetPoint("BOTTOMRIGHT", 0, 0)

    p.empty = W.FS(p, 12, C.text3, "CENTER")
    p.empty:SetPoint("CENTER", p.list, "CENTER")
end

function refresh(p)
    -- The sorted column is lit, with an arrow just past its label (just
    -- before it, for right-aligned columns).
    for _, b in ipairs(p.headers) do
        local on = state.sort == b.col.key
        local col = on and C.accent or C.text2
        b.fs:SetTextColor(col[1], col[2], col[3])
        b.arrow:SetShown(on)
        if on then
            b.arrow:SetVertexColor(C.accent[1], C.accent[2], C.accent[3])
            -- The game's arrow points down and fills the left 9/16 of its
            -- file; flipped, it points up (ascending), as Blizzard does it.
            if state.asc then b.arrow:SetTexCoord(0, 0.5625, 1, 0) else b.arrow:SetTexCoord(0, 0.5625, 0, 1) end
            local w = b.fs:GetStringWidth()
            b.arrow:ClearAllPoints()
            if b.col.justify == "RIGHT" then
                b.arrow:SetPoint("RIGHT", b, "RIGHT", -6 - w - 3, 0)
            elseif b.col.justify == "CENTER" then
                b.arrow:SetPoint("LEFT", b, "CENTER", w / 2 + 2, 0)
            else
                b.arrow:SetPoint("LEFT", b, "LEFT", 6 + w + 3, 0)
            end
        end
    end
    p.list:SetData(buildList(), true)
    local g = PGM.GuildDB()
    local total = g and PGM:CountMembers() or 0
    p.count:SetText(("%d of %d"):format(#p.list.data, total))
    if not IsInGuild() then
        p.empty:SetText("You're not in a guild on this character.")
    elseif not (g and g.seeded) then
        p.empty:SetText("Reading the guild roster...")
    elseif #p.list.data == 0 then
        p.empty:SetText("Nobody matches.")
    else
        p.empty:SetText("")
    end
end

-- The right-click menu for a guild member, wherever they're listed.
-- (Promote, demote and remove aren't here: Blizzard only allows those from a
-- real button click, so they live on the profile page.)
function UI:MemberMenu(owner, guid, extra)
    local g = PGM.GuildDB()
    local rec = g and g.members[guid]
    if not rec then return end
    local isMe = guid == PGM:MyGuid()
    local entries = {}
    for _, e in ipairs(extra or {}) do entries[#entries + 1] = e end
    for _, e in ipairs({
        { "Whisper", function() UI:Whisper(rec) end, disabled = isMe },
        { "Invite to group", function() UI:Invite(rec) end, disabled = isMe or not rec.online },
        { "Open profile", function() UI:OpenProfile(guid) end },
        { divider = true },
    }) do entries[#entries + 1] = e end

    -- Teams and alt links are shared with the guild: officers only.
    if not PGM:CanEdit() then
        entries[#entries] = nil   -- the divider
        W.Menu(owner, rec.short or "?", entries)
        return
    end

    local teams = {}
    for _, t in ipairs(PGM:Teams()) do
        teams[#teams + 1] = {
            t.name,
            checked = function() return t.members[guid] ~= nil end,
            toggle = function()
                if t.members[guid] then PGM:RemoveFromTeam(t.id, guid) else PGM:AddToTeam(t.id, guid) end
            end,
        }
    end
    if #teams == 0 then
        teams[1] = { "Make a raid team first", function() UI:Show("teams") end }
    end
    entries[#entries + 1] = { "Raid teams", sub = teams }

    local main = PGM:KnownMain(guid) and g.members[PGM:KnownMain(guid)]
    if main then
        entries[#entries + 1] = { "Make this the main", function() PGM:MakeMain(guid) end }
        entries[#entries + 1] = { "Unlink from " .. (main.short or "main"), function() PGM:UnlinkAlt(guid) end }
    elseif PGM:IsAlt(guid) then
        -- An alt by rank alone; this says otherwise.
        entries[#entries + 1] = { "Not an alt", function() PGM:UnlinkAlt(guid) end }
    end
    W.Menu(owner, rec.short or "?", entries)
end

-- Shared member actions.
function UI:Whisper(rec)
    local target = rec.name
    if ChatFrameUtil and ChatFrameUtil.SendTell then
        ChatFrameUtil.SendTell(target)
    elseif ChatFrame_SendTell then
        ChatFrame_SendTell(target)
    end
end

function UI:Invite(rec)
    if C_PartyInfo and C_PartyInfo.InviteUnit then
        C_PartyInfo.InviteUnit(rec.name)
    end
end

UI:AddTab({ id = "roster", label = "Roster", build = build, refresh = refresh })
