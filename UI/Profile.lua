-- Profile.lua: one member's full picture, opened from the roster.

local _, NS = ...
local PGM = NS.PGM
local C = PGM.C
local UI = PGM.UI
local W = UI.W

local SOURCE_LABEL = { manual = "linked by an officer", account = "same account", player = "set by the player",
    note = "from guild note", rank = "by rank" }

local function perms() return PGM:GuildPermissions() end

local function field(parent, label, y)
    local l = W.FS(parent, 11, C.text3)
    l:SetPoint("TOPLEFT", 0, y)
    l:SetWidth(90)
    l:SetText(label)
    local v = W.FS(parent, 12, C.text)
    v:SetPoint("TOPLEFT", 96, y)
    v:SetPoint("TOPRIGHT", 0, y)
    return v
end

-- Back to a harmless Remove: no macrotext, plain label. Out of combat only
-- (attributes are locked in combat); PLAYER_REGEN_DISABLED runs just before
-- the lock, so a fight can never leave it armed.
function UI:DisarmRemove()
    local h = self.secure
    local r = h and h.remove
    if not r or InCombatLockdown() then return end
    r.armed = nil
    r.armToken = (r.armToken or 0) + 1
    r:SetAttribute("macrotext", nil)
    r:SetLabel("Remove")
end

local rankName = PGM.RankName

-- The command that moves someone one rank towards another: /gpromote or
-- /gdemote, once. Rank 0 is the guild master, so a lower index is a higher
-- rank. One per click: several in one click don't land in order (some are
-- dropped, some arrive after the roster has been read again), which took
-- people past the rank picked.
local function rankMacro(name, from, to)
    if not (name and from and to) or from == to then return nil end
    return (to < from and "/gpromote " or "/gdemote ") .. name
end

local function buildSecure()
    local h = UI:SecureHolder()
    if h.setRank then return h end
    local function btn(label, col, prev)
        local b = W.Button(h, label, 96, 24, col, "SecureActionButtonTemplate")
        -- Both edges: since 10.0 a secure button acts on the edge the
        -- "ActionButtonUseKeyDown" setting picks (down, by default), and only
        -- if it's registered for that edge. Blizzard ignores the other one.
        b:RegisterForClicks("AnyUp", "AnyDown")
        b:SetAttribute("type", "macro")
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 8, 0) else b:SetPoint("LEFT") end
        return b
    end
    h.setRank = btn("Set rank", C.jade)
    h.setRank:SetWidth(110)
    h.setRank.tip = "Moves them one rank towards the rank picked on the left. Click again for the next rank once their rank has updated."
    -- Ask for the roster straight away, so the new rank shows quickly. Until
    -- it does, the button does nothing: a second click would move them again.
    h.setRank:HookScript("PostClick", function(s, _, down)
        if (down and true or false) ~= GetCVarBool("ActionButtonUseKeyDown") then return end
        h.sent = { name = h.target, from = h.fromRank, at = GetTime() }
        if not InCombatLockdown() then
            s:SetAttribute("macrotext", nil)
            s:SetLabel("Waiting...")
            s:SetAlpha(0.5)
        end
        C_Timer.After(1, function() PGM:RequestRoster(true) end)
        C_Timer.After(16, function() UI:QueueRefresh() end)   -- in case nothing changed
    end)
    h.remove = btn("Remove", C.red, h.setRank)
    h.remove.tip = "Removes them from the guild. Click once to arm, again to confirm."
    -- Removal can't be undone, so it arms first: an unarmed button has no
    -- macrotext, so the first click does nothing but arm it. PostClick, not
    -- OnClick, because OnClick belongs to the secure handler. PostClick runs
    -- for both edges, so only the edge that acted counts.
    h.remove:SetScript("PostClick", function(s, _, down)
        if InCombatLockdown() then return end
        if (down and true or false) ~= GetCVarBool("ActionButtonUseKeyDown") then return end
        if s.armed then
            UI:DisarmRemove()
        else
            s.armed = true
            s.armToken = (s.armToken or 0) + 1
            local token = s.armToken
            s:SetAttribute("macrotext", "/gremove " .. (h.target or ""))
            s:SetLabel("Confirm remove")
            C_Timer.After(5, function()
                -- Only the arm that started this timer may end it.
                if s.armToken == token and s.armed then UI:DisarmRemove() end
            end)
        end
    end)
    h.remove:SetWidth(120)
    return h
end

local function build()
    local content = UI.frame.content
    local p = CreateFrame("Frame", nil, content, "BackdropTemplate")
    p:SetAllPoints()
    p:SetFrameLevel(content:GetFrameLevel() + 20)
    W.Backdrop(p, C.panel, C.panel, 1)
    p:EnableMouse(true)
    -- Swallow the wheel so the list underneath doesn't scroll unseen.
    p:EnableMouseWheel(true)
    p:SetScript("OnMouseWheel", function() end)
    p:Hide()
    UI.profile = p

    p.back = W.Button(p, "< Back", 70, 22, C.text2)
    p.back:SetPoint("TOPLEFT")
    p.back:SetScript("OnClick", function() UI:HideProfile() end)

    p.name = W.FS(p, 22, C.text)
    p.name:SetPoint("TOPLEFT", 0, -34)
    p.sub = W.FS(p, 12, C.text2)
    p.sub:SetPoint("TOPLEFT", 0, -62)

    -- Left: facts, your note, alts.
    local left = CreateFrame("Frame", nil, p)
    left:SetPoint("TOPLEFT", 0, -92)
    left:SetPoint("BOTTOMLEFT", 0, 40)
    left:SetWidth(370)
    -- WoW Forever has no Mythic+ score or raid progress to show, so those two
    -- rows go and everything below moves up to close the gap.
    local lift = PGM.IS_FOREVER and 40 or 0
    p.status = field(left, "Status", 0)
    p.joined = field(left, "Joined", -20)
    if not PGM.IS_FOREVER then
        p.mplus = field(left, "Mythic+", -40)
        p.raid = field(left, "Raid", -60)
    end
    p.profs = field(left, "Professions", -80 + lift)
    p.teams = field(left, "Raid teams", -100 + lift)
    p.note = field(left, "Guild note", -120 + lift)
    p.onote = field(left, "Officer note", -140 + lift)

    local nl = W.FS(left, 11, C.text3)
    nl:SetPoint("TOPLEFT", 0, -168 + lift)
    nl:SetText("Your private note (only you see this)")
    p.mine = W.EditBox(left, 370, 24, "Add a note...")
    p.mine:SetPoint("TOPLEFT", 0, -184 + lift)
    p.mine:SetMaxLetters(240)
    p.mine.onCommit = function(s)
        local g = PGM.GuildDB(true)
        if not (g and p.guid) then return end
        local text = strtrim(s:GetText() or "")
        g.notes[p.guid] = text ~= "" and text or nil
    end

    local al = W.FS(left, 13, C.accent)
    al:SetPoint("TOPLEFT", 0, -220 + lift)
    al:SetText("Characters")
    p.altLines = {}
    for i = 1, 6 do
        local fs = W.FS(left, 12, C.text)
        fs:SetPoint("TOPLEFT", 0, -240 + lift - (i - 1) * 18)
        fs:SetPoint("TOPRIGHT", 0, -240 + lift - (i - 1) * 18)
        p.altLines[i] = fs
    end

    p.linkBox = W.EditBox(left, 150, 22, "Main's name")
    p.linkBox:SetPoint("BOTTOMLEFT", 0, 0)
    p.link = W.Button(left, "Link as alt", 88, 22)
    p.link:SetPoint("LEFT", p.linkBox, "RIGHT", 6, 0)
    local function doLink()
        local main = PGM:FindMember(p.linkBox:GetText())
        if not main then
            PGM.Print("No guild member called " .. (p.linkBox:GetText() or "") .. ".")
            return
        end
        if PGM:LinkAlt(p.guid, main) then p.linkBox:SetText("") end
    end
    p.link:SetScript("OnClick", doLink)
    p.linkBox.onEnter = doLink
    W.NameSuggest(p.linkBox, { up = true, skip = function(guid) return guid == p.guid end })
    p.unlink = W.Button(left, "Unlink", 60, 22, C.text2)
    p.unlink:SetPoint("LEFT", p.link, "RIGHT", 6, 0)
    p.unlink:SetScript("OnClick", function() PGM:UnlinkAlt(p.guid) end)
    p.makeMain = W.Button(left, "Make main", 70, 22)
    p.makeMain:SetPoint("LEFT", p.unlink, "RIGHT", 6, 0)
    p.makeMain:SetScript("OnClick", function() PGM:MakeMain(p.guid) end)

    -- Right: attendance and history.
    local right = CreateFrame("Frame", nil, p)
    right:SetPoint("TOPLEFT", 400, -92)
    right:SetPoint("BOTTOMRIGHT", 0, 40)
    local att = W.FS(right, 13, C.accent)
    att:SetPoint("TOPLEFT")
    att:SetText("Raid attendance")
    p.attText = W.FS(right, 12, C.text2)
    p.attText:SetPoint("TOPLEFT", 0, -20)
    p.attText:SetPoint("TOPRIGHT", 0, -20)
    p.strip = {}
    for i = 1, 10 do
        local t = W.Solid(right, "ARTWORK", C.line)
        t:SetSize(26, 10)
        t:SetPoint("TOPLEFT", (i - 1) * 30, -42)
        p.strip[i] = t
    end

    p.played = W.FS(right, 12, C.text2)
    p.played:SetPoint("TOPLEFT", 0, -62)
    p.played:SetPoint("TOPRIGHT", 0, -62)

    local hl = W.FS(right, 13, C.accent)
    hl:SetPoint("TOPLEFT", 0, -92)
    hl:SetText("History")
    p.history = {}
    for i = 1, 14 do
        local d = W.FS(right, 11, C.text3)
        d:SetPoint("TOPLEFT", 0, -112 - (i - 1) * 18)
        d:SetWidth(80)
        local t = W.FS(right, 12, C.text)
        t:SetPoint("TOPLEFT", 84, -112 - (i - 1) * 18)
        t:SetPoint("TOPRIGHT", 0, -112 - (i - 1) * 18)
        p.history[i] = { date = d, text = t }
    end

    -- Bottom: actions. The secure trio is placed over secureSpot.
    p.whisper = W.Button(p, "Whisper", 80, 24)
    p.whisper:SetPoint("BOTTOMLEFT")
    p.whisper:SetScript("OnClick", function() if p.rec then UI:Whisper(p.rec) end end)
    p.invite = W.Button(p, "Invite", 80, 24)
    p.invite:SetPoint("LEFT", p.whisper, "RIGHT", 8, 0)
    p.invite:SetScript("OnClick", function() if p.rec then UI:Invite(p.rec) end end)
    p.addTeam = W.Button(p, "Raid teams...", 100, 24)
    p.addTeam:SetPoint("LEFT", p.invite, "RIGHT", 8, 0)
    p.addTeam:SetScript("OnClick", function(s)
        if not p.rec then return end
        local entries = {}
        for _, t in ipairs(PGM:Teams()) do
            if t.members[p.guid] then
                entries[#entries + 1] = { "Remove from " .. t.name, function() PGM:RemoveFromTeam(t.id, p.guid) end }
            else
                entries[#entries + 1] = { "Add to " .. t.name, function() PGM:AddToTeam(t.id, p.guid) end }
            end
        end
        if #entries == 0 then
            entries[1] = { "Make a team first (Raid Teams page)", function() UI:Show("teams") end }
        end
        W.Menu(s, p.rec and p.rec.short or "Raid teams", entries)
    end)
    p.secureSpot = CreateFrame("Frame", nil, p)
    p.secureSpot:SetSize(238, 24)
    p.secureSpot:SetPoint("BOTTOMRIGHT")
    -- The rank to move them to. A plain button: picking a rank only changes
    -- what the secure Set rank button next to it will do.
    p.rankPick = W.Button(p, "", 150, 24, C.text2)
    p.rankPick:SetPoint("RIGHT", p.secureSpot, "LEFT", -8, 0)
    p.rankPick:Hide()
    p.rankPick:SetScript("OnClick", function(s)
        local rec = p.rec
        local my = PGM.MyRankIndex and PGM:MyRankIndex()
        if not (rec and my) or InCombatLockdown() then return end
        local num = GuildControlGetNumRanks and PGM.Plain(GuildControlGetNumRanks()) or 0
        local can = perms()
        local entries = {}
        for i = my + 1, (num or 0) - 1 do
            local allowed = (i < rec.rankIndex and can.promote) or (i > rec.rankIndex and can.demote) or i == rec.rankIndex
            entries[#entries + 1] = { rankName(i) .. (i == rec.rankIndex and " (now)" or ""),
                function() p.targetRank = i UI:RefreshProfile() end, disabled = not allowed }
        end
        W.Menu(s, "Move " .. (rec.short or "them") .. " to", entries)
    end)
    -- How Set rank goes, over it: the game moves a rank per click. A child
    -- of the picker, so it shows only when they can be moved.
    p.rankHelp = W.FS(p.rankPick, 11, C.text3, "RIGHT")
    p.rankHelp:SetPoint("BOTTOMRIGHT", p.secureSpot, "TOPRIGHT", 0, 4)
    p.rankHelp:SetText("One rank per click: wait for it to update, then click again.")
    p.combatNote = W.FS(p, 11, C.text3, "RIGHT")
    p.combatNote:SetPoint("BOTTOMRIGHT", 0, 6)

    p:SetScript("OnHide", function() UI:HideSecure() end)
    UI:On("MOVED", function() if p:IsVisible() then UI:RefreshProfile() end end)
    return p
end

function UI:OpenProfile(guid)
    if not self.profile then build() end
    -- Commit a half-typed private note to whoever it was for, and put away
    -- any secure button from the page underneath (an armed Bulk run among
    -- them) before this page covers it.
    self.profile.mine:ClearFocus()
    self:HideSecure()
    if self.profile.guid ~= guid then self.profile.targetRank = nil end
    self.profile.guid = guid
    self.profile.mine:SetText("")
    local g = PGM.GuildDB()
    self.profile.mine:SetText((g and g.notes[guid]) or "")
    self.profile:Show()
    self:RefreshProfile()
end

function UI:HideProfile()
    if self.profile then self.profile:Hide() end
    self:HideSecure()
end

function UI:RefreshProfile()
    local p = self.profile
    if not (p and p:IsVisible()) then return end
    local g = PGM.GuildDB()
    local rec = g and g.members[p.guid]
    p.rec = rec
    -- Actions only make sense for someone still in the guild.
    for _, b in ipairs({ p.whisper, p.invite }) do b:SetShown(rec ~= nil) end
    -- Teams and alt links are shared with the guild: officers only.
    local canEdit = rec ~= nil and PGM:CanEdit()
    for _, b in ipairs({ p.addTeam, p.link, p.linkBox }) do b:SetShown(canEdit) end
    if not rec then
        -- They left (or we changed guilds) while the page was open, or the
        -- page was opened from an old raid list. Show nothing of anyone else.
        local former = g and g.former[p.guid]
        p.name:SetText(former and PGM.ColorName(former) or "?")
        p.sub:SetText(PGM.Hex(C.text3) .. "No longer in the guild|r")
        for _, key in ipairs({ "status", "joined", "mplus", "raid", "profs", "teams", "note", "onote", "attText", "played" }) do
            if p[key] then p[key]:SetText("") end
        end
        for _, fs in ipairs(p.altLines) do fs:SetText("") end
        for _, line in ipairs(p.history) do line.date:SetText("") line.text:SetText("") end
        for _, t in ipairs(p.strip) do t:SetColorTexture(C.line[1], C.line[2], C.line[3], 0.35) end
        p.unlink:Hide()
        p.makeMain:Hide()
        UI:HideSecure()
        return
    end

    p.name:SetText(PGM.ColorName(rec))
    local race = rec.race and PGM.RaceInfo(rec.race)
    p.sub:SetText(("Level %s %s%s  -  %s  -  %s"):format(rec.level or "?", race and (race .. " ") or "",
        PGM.ClassName(rec.class), rec.rank or "?", rec.realm or ""))

    if rec.online then
        p.status:SetText(PGM.Hex(C.jade) .. "Online|r" .. (rec.mobile and " (mobile)" or (rec.zone and (" in " .. rec.zone) or "")))
    elseif rec.lastOnline then
        p.status:SetText(("Last seen %s (%s)"):format(PGM.AgoText(rec.lastOnline), PGM.Date(rec.lastOnline)))
    else
        p.status:SetText("Unknown")
    end
    if rec.joined then
        p.joined:SetText(("%s (%s)"):format(PGM.Date(rec.joined), PGM.AgoText(rec.joined)))
    else
        p.joined:SetText(PGM.Hex(C.text3) .. "Before tracking began " .. PGM.Date(g.seeded) .. "|r")
    end
    if p.mplus then
        local score = PGM:MPlusScore(rec)
        p.mplus:SetText(score and (PGM.Hex(PGM:ScoreColor(score)) .. score .. "|r")
            or PGM.Hex(C.text3) .. "No score this season" .. "|r")
        local prog = PGM:RaidProgress(rec)
        p.raid:SetText(prog and prog.text or (PGM.Hex(C.text3) .. "-|r"))
    end
    p.profs:SetText(PGM.ProfText(rec, true) or (PGM.Hex(C.text3) .. "None known|r"))
    local teamParts = {}
    for _, it in ipairs(PGM:TeamsOf(p.guid)) do
        local present, possible = PGM:AttendanceFor(p.guid, 10, it.team.id)
        teamParts[#teamParts + 1] = ("%s %s(%s, %s%s)|r"):format(it.team.name, PGM.Hex(C.text3),
            PGM.ROLE_LABEL[it.entry.role] or "?", PGM.STATUS_LABEL[it.entry.status] or "?",
            possible > 0 and (", " .. present .. "/" .. possible) or "")
    end
    p.teams:SetText(#teamParts > 0 and table.concat(teamParts, "; ") or (PGM.Hex(C.text3) .. "None|r"))
    p.note:SetText(rec.note ~= "" and rec.note or (PGM.Hex(C.text3) .. "-|r"))
    p.onote:SetText(rec.onote ~= "" and rec.onote or (PGM.Hex(C.text3) .. "-|r"))

    -- Characters in this group.
    local group = PGM:GroupOf(p.guid)
    for i, fs in ipairs(p.altLines) do
        local gu = group[i]
        local m = gu and g.members[gu]
        if m then
            local tag
            if i == 1 then
                tag = (PGM:IsAlt(gu) and not PGM:KnownMain(gu)) and (PGM.Hex(C.purple) .. "alt|r" .. PGM.Hex(C.text3) .. ", alt rank - main unknown; link them below|r")
                    or (PGM.Hex(C.jade) .. "main|r")
            else
                tag = PGM.Hex(C.purple) .. "alt|r" .. PGM.Hex(C.text3) .. ", " .. (SOURCE_LABEL[PGM:AltSource(gu)] or "") .. "|r"
            end
            local here = gu == p.guid and PGM.Hex(C.gold) .. " <|r" or ""
            fs:SetText(("%s  %s%d|r  %s%s"):format(PGM.ColorName(m), PGM.Hex(C.text3), m.level or 0, tag, here))
        elseif i == 1 then
            fs:SetText(PGM.Hex(C.text3) .. "No alts known.|r")
        else
            fs:SetText("")
        end
        if i == #p.altLines and #group > i then fs:SetText(PGM.Hex(C.text3) .. "+" .. (#group - i + 1) .. " more|r") end
    end
    p.unlink:SetShown(canEdit and PGM:IsAlt(p.guid))
    p.makeMain:SetShown(canEdit and PGM:KnownMain(p.guid) ~= nil)

    -- Attendance.
    local present, possible, strip = PGM:AttendanceFor(p.guid)
    if possible > 0 then
        p.attText:SetText(("%d of the last %d raids (%d%%), counting alts. Newest on the left."):format(
            present, possible, present / possible * 100 + 0.5))
    else
        p.attText:SetText("No guild raids recorded since they joined.")
    end
    for i, t in ipairs(p.strip) do
        local there = strip[i]
        if there == nil then
            t:SetColorTexture(C.line[1], C.line[2], C.line[3], 0.35)
        elseif there then
            t:SetColorTexture(C.jade[1], C.jade[2], C.jade[3], 0.9)
        else
            t:SetColorTexture(C.red[1], C.red[2], C.red[3], 0.6)
        end
    end

    -- Play time, last 30 days, alts included.
    local act = PGM:ActivityFor(p.guid)
    p.played:SetText(act and ("Played %dh in the last 30 days, usually %s, most often on %s."):format(
        act.hours, PGM.UsualTime(act), PGM.TopDay(act)) or "No play time recorded in the last 30 days.")

    -- History for the whole group, newest first.
    local inGroup = {}
    for _, gu in ipairs(group) do inGroup[gu] = true end
    local entries = {}
    for i = #g.log, 1, -1 do
        local e = g.log[i]
        if e.guid and inGroup[e.guid] then entries[#entries + 1] = e end
        if #entries >= #p.history then break end
    end
    for i, line in ipairs(p.history) do
        local e = entries[i]
        line.date:SetText(e and PGM.Date(e.t, true) or "")
        line.text:SetText(e and PGM.LogText(e) or (i == 1 and (PGM.Hex(C.text3) .. "No changes recorded yet.|r") or ""))
    end

    -- Secure rank buttons.
    if InCombatLockdown() then
        p.combatNote:SetText("Rank actions return after combat.")
        p.rankPick:Hide()
        return
    end
    p.combatNote:SetText("")
    local can = perms()
    if not (can.promote or can.demote or can.remove) or p.guid == PGM:MyGuid() then
        UI:HideSecure()
        p.rankPick:Hide()
        return
    end
    local h = buildSecure()
    -- Refreshes come after every roster scan; only a new person disarms
    -- Remove, or "Confirm remove" could reset under your cursor.
    if h.target ~= rec.name then UI:DisarmRemove() end
    h.target = rec.name
    -- Only someone below your own rank can be moved, and only to a rank
    -- below yours (the game refuses anything else).
    local my = PGM.MyRankIndex and PGM:MyRankIndex()
    local movable = my and rec.rankIndex and rec.rankIndex > my and (can.promote or can.demote)
    local target = p.targetRank
    if not movable or not target or target <= my then target = rec.rankIndex end
    p.rankPick:SetShown(movable and true or false)
    p.rankPick:SetLabel((target and rankName(target) or "?") .. "  v")
    h.fromRank = rec.rankIndex
    -- Just clicked: wait for the roster to show the new rank (or give up
    -- after 15 seconds, say if the game refused).
    local sent = h.sent
    if sent and (sent.name ~= rec.name or sent.from ~= rec.rankIndex or GetTime() - sent.at > 15) then
        h.sent, sent = nil, nil
    end
    local text
    if sent then
        h.setRank:SetLabel("Waiting...")
    elseif movable and target ~= rec.rankIndex then
        local promoting = target < rec.rankIndex
        if (promoting and can.promote) or (not promoting and can.demote) then
            text = rankMacro(rec.name, rec.rankIndex, target)
            local left = math.abs(target - rec.rankIndex)
            h.setRank:SetLabel((promoting and "Promote" or "Demote") .. (left > 1 and (" (" .. left .. ")") or ""))
        else
            h.setRank:SetLabel(promoting and "Can't promote" or "Can't demote")
        end
    else
        h.setRank:SetLabel("Set rank")
    end
    h.setRank:SetAttribute("macrotext", text)
    h.setRank:SetAlpha(text and 1 or 0.5)
    h.setRank:SetShown(movable and true or false)
    h.remove:SetShown(can.remove)
    -- Right after the page first shows, its layout may not be resolved yet;
    -- try again on the next frame.
    if not UI:PlaceSecure(p.secureSpot) then
        C_Timer.After(0, function()
            if p:IsVisible() and not InCombatLockdown() then UI:PlaceSecure(p.secureSpot) end
        end)
    end
end
