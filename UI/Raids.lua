-- Raids.lua (UI): recorded raid nights and who keeps showing up.

local _, NS = ...
local PGM = NS.PGM
local C = PGM.C
local UI = PGM.UI
local W = UI.W

local WINDOW = 10

-- Which raid nights to show: nil = all, a team id, or "none" (untagged).
local state = { team = nil }

StaticPopupDialogs.PANDYGUILD_DELETE_RAID = {
    text = "Delete the raid on %s from attendance?",
    button1 = YES, button2 = NO,
    OnAccept = function(_, session) PGM:DeleteRaid(session) end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

local function presentNames(s)
    local g = PGM.GuildDB()
    local names = {}
    for guid in pairs(s.present) do
        local rec = g.members[guid] or g.former[guid]
        names[#names + 1] = rec and PGM.ColorName(rec) or "?"
    end
    table.sort(names)
    return names
end

local function sessionRow(list)
    local r = W.Row(list)
    r.date = W.FS(r, 11, C.text3)
    r.date:SetPoint("LEFT", 6, 0)
    r.date:SetWidth(96)
    r.name = W.FS(r, 12, C.text)
    r.name:SetPoint("LEFT", 104, 0)
    r.name:SetWidth(230)
    r.n = W.FS(r, 12, C.text2, "RIGHT")
    r.n:SetPoint("RIGHT", -6, 0)
    r:SetScript("OnClick", function(s, button)
        if button == "RightButton" and PGM:CanEdit() then
            local sess = s.s
            local entries = {}
            for _, t in ipairs(PGM:Teams()) do
                if t.id ~= sess.team then
                    entries[#entries + 1] = { "Tag as " .. t.name, function() PGM:AssignRaid(sess, t.id) end }
                end
            end
            if sess.team then
                entries[#entries + 1] = { "Remove team tag", function() PGM:AssignRaid(sess, nil) end }
            end
            entries[#entries + 1] = { "Delete this raid", function()
                StaticPopup_Show("PANDYGUILD_DELETE_RAID", PGM.Date(sess.start, true), nil, sess)
            end }
            W.Menu(s, sess.name, entries)
        end
    end)
    r.onEnter = function(s)
        local sess = s.s
        GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
        GameTooltip:SetText(sess.name .. (sess.diff and (" (" .. sess.diff .. ")") or ""))
        GameTooltip:AddLine(("%s, %d minutes"):format(PGM.Date(sess.start, true), (sess.stop - sess.start) / 60), 0.8, 0.8, 0.8)
        local team = sess.team and PGM:TeamById(sess.team)
        if team then GameTooltip:AddLine("Team: " .. team.name, 0.72, 0.54, 1) end
        if #sess.bosses > 0 then
            GameTooltip:AddLine("Kills: " .. table.concat(sess.bosses, ", "), 0.33, 0.82, 0.58, true)
        end
        GameTooltip:AddLine(" ")
        local names = presentNames(sess)
        for i = 1, #names, 3 do
            GameTooltip:AddLine(table.concat({ names[i], names[i + 1] or "", names[i + 2] or "" }, "   "))
        end
        if PGM:CanEdit() then GameTooltip:AddLine("Right-click to tag a team or delete", 0.45, 0.45, 0.45) end
        GameTooltip:Show()
    end
    return r
end

local function sessionUpdate(r, s)
    r.s = s
    r.date:SetText(PGM.Date(s.start, true))
    local kills = #s.bosses > 0 and (PGM.Hex(C.jade) .. "  " .. #s.bosses .. " kills|r") or ""
    local team = s.team and PGM:TeamById(s.team)
    local tag = team and (PGM.Hex(C.purple) .. team.name .. "|r  ") or ""
    r.name:SetText(tag .. s.name .. (s.diff and (PGM.Hex(C.text3) .. " " .. s.diff .. "|r") or "") .. kills)
    r.n:SetText(s.count or 0)
end

local function boardRow(list)
    local r = W.Row(list)
    r.name = W.FS(r, 12, C.text)
    r.name:SetPoint("LEFT", 6, 0)
    r.name:SetWidth(150)
    r.bar = W.Bar(r, 0)
    r.bar:SetPoint("LEFT", 160, 0)
    r.bar:SetPoint("RIGHT", -6, 0)
    r.bar:EnableMouse(false) -- let clicks reach the row
    r:SetScript("OnClick", function(s) UI:OpenProfile(s.it.guid) end)
    return r
end

local function boardUpdate(r, it)
    r.it = it
    r.name:SetText(PGM.ColorName(it.rec))
    if it.possible == 0 then
        r.bar:Set("", 0, 1, C.text3, PGM.Hex(C.text3) .. "no raids yet|r")
        return
    end
    local pct = it.present / it.possible
    local col = pct >= 0.8 and C.jade or (pct >= 0.5 and C.gold or C.red)
    r.bar:Set("", it.present, it.possible, col, ("%d/%d  %d%%"):format(it.present, it.possible, pct * 100 + 0.5))
end

local function build(p)
    p.status = W.FS(p, 12, C.text2)
    p.status:SetPoint("TOPLEFT")
    p.status:SetPoint("TOPRIGHT", -130, 0)
    p.status:SetWordWrap(true)
    p.stop = W.Button(p, "Stop and save", 120, 22)
    p.stop:SetPoint("TOPRIGHT")
    p.stop:SetScript("OnClick", function() PGM:CloseRaid(true) end)

    -- Team filter chips, made as teams appear.
    p.chips = {}

    local lt = W.FS(p, 13, C.accent)
    lt:SetPoint("TOPLEFT", 0, -78)
    lt:SetText("Raid nights")
    p.boardTitle = W.FS(p, 13, C.accent)
    p.boardTitle:SetPoint("TOPLEFT", 396, -78)
    p.boardTitle:SetPoint("TOPRIGHT", 0, -78)

    p.sessions = W.List(p, 22, sessionRow, sessionUpdate)
    p.sessions:SetPoint("TOPLEFT", 0, -100)
    p.sessions:SetPoint("BOTTOMLEFT")
    p.sessions:SetWidth(380)

    p.board = W.List(p, 22, boardRow, boardUpdate)
    p.board:SetPoint("TOPLEFT", 396, -100)
    p.board:SetPoint("BOTTOMRIGHT")

    p.empty = W.FS(p, 12, C.text3, "CENTER")
    p.empty:SetPoint("CENTER")
    p.empty:SetWidth(500)
    p.empty:SetWordWrap(true)
end

local function refresh(p)
    local active = PGM:ActiveRaid()
    if active then
        local n = 0
        for _ in pairs(active.present) do n = n + 1 end
        p.status:SetText(("%sRecording|r %s%s: %d guildies seen, %d min so far."):format(PGM.Hex(C.jade),
            active.name, active.diff and (" (" .. active.diff .. ")") or "", n, (PGM.Now() - active.start) / 60))
        p.stop:Show()
    else
        p.status:SetText(("Raids are recorded automatically when you're in a raid instance with %d or more guildies. Nothing to set up."):format(PGM.opt("raidMinGuildies") or 5))
        p.stop:Hide()
    end

    -- Filter chips: All raids, each team, No team.
    local teams = PGM:Teams()
    if state.team and state.team ~= "none" and not PGM:TeamById(state.team) then state.team = nil end
    if state.team == "none" and #teams == 0 then state.team = nil end
    local options = { { false, "All raids" } }
    for _, t in ipairs(teams) do options[#options + 1] = { t.id, t.name } end
    if #teams > 0 then options[#options + 1] = { "none", "No team" } end
    for i, o in ipairs(options) do
        local chip = p.chips[i]
        if not chip then
            chip = W.Chip(p, "", function(s)
                state.team = s.value or nil
                p.sessions.offset, p.board.offset = 0, 0
                UI:Refresh()
            end)
            if i == 1 then
                chip:SetPoint("TOPLEFT", 0, -40)
            else
                chip:SetPoint("LEFT", p.chips[i - 1], "RIGHT", 6, 0)
            end
            p.chips[i] = chip
        end
        chip.value = o[1]
        -- Long team names are shortened so the row fits.
        local label = #o[2] > 18 and (o[2]:sub(1, 16) .. "...") or o[2]
        chip:SetLabel(label)
        chip:SetWidth(chip.fs:GetStringWidth() + 22)
        chip:SetActive((state.team or false) == o[1])
        chip:Show()
    end
    for i = #options + 1, #p.chips do p.chips[i]:Hide() end
    -- More teams than fit on one line: the ones past the edge stay hidden
    -- (every raid is still under "All raids").
    local room, used = p:GetWidth(), 0
    for i = 1, #options do
        used = used + p.chips[i]:GetWidth() + 6
        if room > 0 and used > room then p.chips[i]:Hide() end
    end

    local all = PGM:RaidSessions()
    local sessions = {}
    for _, s in ipairs(all) do
        if state.team == nil or (state.team == "none" and not s.team) or s.team == state.team then
            sessions[#sessions + 1] = s
        end
    end
    p.sessions:SetData(sessions, true)

    local g = PGM.GuildDB()
    local board = {}
    local team = state.team and state.team ~= "none" and PGM:TeamById(state.team)
    if team then
        -- The whole roster, so no-shows are listed too.
        p.boardTitle:SetText(("%s, last %d of its raids"):format(team.name, WINDOW))
        for guid in pairs(team.members) do
            local rec = g and g.members[guid]
            if rec then
                local present, possible = PGM:AttendanceFor(guid, WINDOW, team.id)
                board[#board + 1] = { guid = guid, rec = rec, present = present, possible = possible }
            end
        end
    elseif g and #sessions > 0 then
        -- All raids, or (with "No team") just the untagged ones.
        local filter = state.team == "none" and "none" or nil
        p.boardTitle:SetText(filter and ("Untagged raids, last %d"):format(WINDOW)
            or ("Last %d raids (alts count for their main)"):format(WINDOW))
        for guid, rec in pairs(g.members) do
            if not PGM:KnownMain(guid) then
                local present, possible = PGM:AttendanceFor(guid, WINDOW, filter)
                if possible > 0 and present > 0 then
                    board[#board + 1] = { guid = guid, rec = rec, present = present, possible = possible }
                end
            end
        end
    else
        p.boardTitle:SetText("Attendance")
    end
    if #board > 0 then
        table.sort(board, function(a, b)
            local pa = a.possible > 0 and a.present / a.possible or -1
            local pb = b.possible > 0 and b.present / b.possible or -1
            if pa ~= pb then return pa > pb end
            if a.present ~= b.present then return a.present > b.present end
            return PGM.NameLess(a.rec.short, b.rec.short)
        end)
    end
    p.board:SetData(board, true)
    p.empty:SetText(#all == 0 and "No raids recorded yet. Your next raid night will show up here on its own." or "")
end

UI:AddTab({ id = "raids", label = "Raids", build = build, refresh = refresh })
