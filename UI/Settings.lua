-- Settings.lua (UI): announcements, raid tracking, window, and data.

local _, NS = ...
local PGM = NS.PGM
local C = PGM.C
local UI = PGM.UI
local W = UI.W

StaticPopupDialogs.PANDYGUILD_RESET = {
    text = "Forget everything Pandy Guild Management has recorded for this guild (history, alts, notes, raids)?",
    button1 = YES, button2 = NO,
    OnAccept = function()
        local key = PGM.GuildKey()
        if key then PandyGuildDB.guilds[key] = nil end
        PGM:RequestRoster(true)
        PGM:Fire("ROSTER")
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs.PANDYGUILD_RELOAD = {
    text = "Reload the interface now to use the new accent colour?",
    button1 = "Reload", button2 = "Later",
    OnAccept = function() ReloadUI() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

-- The chosen accent swatch wears a bright frame.
local function refreshSwatches(p)
    for _, sw in ipairs(p.swatches or {}) do
        local c = sw.id == PGM.opt("accent") and C.text or C.frame
        sw:SetBackdropBorderColor(c[1], c[2], c[3], 1)
    end
end

local function heading(p, text, y)
    local fs = W.FS(p, 14, C.accent)
    fs:SetPoint("TOPLEFT", 0, y)
    fs:SetText(text)
    return fs
end

-- "label  [-] value [+]"
local function stepper(p, label, y, get, set, lo, hi, step, fmt)
    local l = W.FS(p, 12, C.text)
    l:SetPoint("TOPLEFT", 0, y)
    l:SetText(label)
    local minus = W.Button(p, "-", 24, 20, C.text2)
    minus:SetPoint("TOPLEFT", 260, y + 3)
    local v = W.FS(p, 12, C.jade, "CENTER")
    v:SetPoint("LEFT", minus, "RIGHT", 4, 0)
    v:SetWidth(50)
    local plus = W.Button(p, "+", 24, 20, C.text2)
    plus:SetPoint("LEFT", v, "RIGHT", 4, 0)
    local function sync() v:SetText((fmt or "%s"):format(get())) end
    minus:SetScript("OnClick", function() set(math.max(lo, get() - step)) sync() end)
    plus:SetScript("OnClick", function() set(math.min(hi, get() + step)) sync() end)
    sync()
    return sync
end

local function build(p)
    p.syncers = {}
    local y = 0
    heading(p, "Tell me in chat when someone...", y)
    local announce = PGM.opt("announce")
    local options = {
        { "join", "joins or rejoins the guild" },
        { "leave", "leaves the guild" },
        { "rank", "is promoted or demoted" },
        { "maxLevel", "reaches max level" },
        { "rename", "changes their name" },
    }
    y = y - 26
    for _, o in ipairs(options) do
        local cb = W.Check(p, o[2], function() return announce[o[1]] end, function(v) announce[o[1]] = v end)
        cb:SetPoint("TOPLEFT", 4, y)
        y = y - 22
    end
    local hint = W.FS(p, 11, C.text3)
    hint:SetPoint("TOPLEFT", 4, y - 2)
    hint:SetText("Only you see these. Nothing is ever posted to guild chat.")

    y = y - 40
    heading(p, "Raid attendance", y)
    y = y - 28
    p.syncers[#p.syncers + 1] = stepper(p, "Guildies needed for a raid to count", y,
        function() return PGM.opt("raidMinGuildies") end,
        function(v) PGM.setOpt("raidMinGuildies", v) end, 2, 30, 1)

    y = y - 40
    heading(p, "Window", y)
    y = y - 28
    p.syncers[#p.syncers + 1] = stepper(p, "Scale", y,
        function() return PGM.opt("scale") end,
        function(v)
            v = math.floor(v * 100 + 0.5) / 100
            PGM.setOpt("scale", v)
            UI:HideSecure()
            UI.frame:SetScale(v)
        end, 0.6, 1.6, 0.05, "%.2f")

    -- Accent colour swatches, on their own row under Scale.
    y = y - 32
    local al = W.FS(p, 12, C.text)
    al:SetPoint("TOPLEFT", 0, y)
    al:SetText("Accent colour")
    p.swatches = {}
    for i, a in ipairs(PGM.ACCENTS) do
        local sw = CreateFrame("Button", nil, p, "BackdropTemplate")
        sw:SetSize(22, 22)
        sw:SetPoint("TOPLEFT", 260 + (i - 1) * 28, y + 4)
        W.Backdrop(sw, a.col, C.frame, 1)
        sw:SetScript("OnEnter", function(s)
            GameTooltip:SetOwner(s, "ANCHOR_TOP")
            GameTooltip:SetText(a.name)
            GameTooltip:Show()
        end)
        sw:SetScript("OnLeave", function() GameTooltip:Hide() end)
        sw:SetScript("OnClick", function()
            if PGM.opt("accent") == a.id then return end
            PGM.setOpt("accent", a.id)
            refreshSwatches(p)
            StaticPopup_Show("PANDYGUILD_RELOAD")
        end)
        sw.id = a.id
        p.swatches[i] = sw
    end

    y = y - 40
    heading(p, "Your characters", y)
    y = y - 26
    p.mainText = W.FS(p, 12, C.text2)
    p.mainText:SetPoint("TOPLEFT", 4, y)
    p.mainText:SetWidth(380)
    p.mainText:SetWordWrap(true)
    y = y - 34
    local setMain = W.Button(p, "Make this character my main", 210, 22)
    setMain:SetPoint("TOPLEFT", 4, y)
    setMain:SetScript("OnClick", function()
        PGM:SetMyMain(PGM:MyGuid())
        UI:Refresh()
    end)

    y = y - 44
    heading(p, "Data", y)
    y = y - 28
    local reset = W.Button(p, "Reset this guild's data", 180, 22, C.red)
    reset:SetPoint("TOPLEFT", 4, y)
    reset:SetScript("OnClick", function() StaticPopup_Show("PANDYGUILD_RESET") end)
    local about = W.FS(p, 11, C.text3)
    about:SetPoint("TOPLEFT", 4, y - 34)
    about:SetWidth(380)
    about:SetWordWrap(true)
    about:SetText("Pandy Guild Management v" .. PGM.VERSION .. ". Shared with the guild: raid teams, raid nights, alt links. "
        .. "Never shared: private notes, settings.")

    -- Right column: guild sync.
    local X = 420
    heading(p, "Guild sync", 0):SetPoint("TOPLEFT", X, 0)
    p.syncStatus = W.FS(p, 11, C.text2)
    p.syncStatus:SetPoint("TOPLEFT", X, -24)
    p.syncStatus:SetWidth(310)
    p.syncStatus:SetWordWrap(true)
    p.syncStatus:SetJustifyV("TOP")
    local share = W.Check(p, "Share with the guild",
        function() return PGM.opt("syncEnabled") ~= false end,
        function(v) PGM.setOpt("syncEnabled", v and true or false) end)
    share:SetPoint("TOPLEFT", X + 4, -94)
    share:SetWidth(200)
    local now = W.Button(p, "Sync now", 90, 22)
    now:SetPoint("TOPLEFT", X + 210, -94)
    now.tip = "Ask officers who are online for anything you're missing."
    now:SetScript("OnClick", function()
        if PGM.SyncNow then PGM.SyncNow() end
        PGM.Print("Asked online officers for anything new.")
    end)

    -- The guild master decides which ranks are officers.
    p.cutLabel = W.FS(p, 12, C.text)
    p.cutLabel:SetPoint("TOPLEFT", X, -134)
    p.cutLabel:SetText("Officers are")
    p.cutMinus = W.Button(p, "-", 24, 20, C.text2)
    p.cutMinus:SetPoint("TOPLEFT", X + 84, -131)
    p.cutValue = W.FS(p, 12, C.accent, "CENTER")
    p.cutValue:SetPoint("LEFT", p.cutMinus, "RIGHT", 4, 0)
    p.cutValue:SetWidth(170)
    p.cutPlus = W.Button(p, "+", 24, 20, C.text2)
    p.cutPlus:SetPoint("LEFT", p.cutValue, "RIGHT", 4, 0)
    p.cutNote = W.FS(p, 10, C.text3)
    p.cutNote:SetPoint("TOPLEFT", X, -156)
    p.cutNote:SetWidth(310)
    p.cutNote:SetWordWrap(true)
    -- Steps through: by rank name (nil), then each rank from the top.
    local function stepCut(delta)
        local g = PGM.GuildDB()
        local cur = g and g.sync and g.sync.officerRank
        local numRanks = (GuildControlGetNumRanks and PGM.Plain(GuildControlGetNumRanks())) or 10
        local v = (cur or -1) + delta
        if v < -1 then v = -1 end
        if v > numRanks - 1 then v = numRanks - 1 end
        if PGM.SyncOfficerRank then PGM:SyncOfficerRank(v >= 0 and v or nil) end
        PGM:Fire("ROSTER")
    end
    p.cutMinus:SetScript("OnClick", function() stepCut(-1) end)
    p.cutPlus:SetScript("OnClick", function() stepCut(1) end)

    -- Who runs the addon.
    heading(p, "Addon users", 0):SetPoint("TOPLEFT", X, -200)
    p.usersText = W.FS(p, 11, C.text2)
    p.usersText:SetPoint("TOPLEFT", X, -224)
    p.usersText:SetWidth(310)
    p.usersText:SetWordWrap(true)
    local see = W.Button(p, "See who", 90, 22)
    see:SetPoint("TOPLEFT", X, -262)
    see:SetScript("OnClick", function() UI:Show("users") end)

    -- One-time import from Guild Roster Manager.
    heading(p, "Import from GRM", 0):SetPoint("TOPLEFT", X, -304)
    p.grmText = W.FS(p, 11, C.text2)
    p.grmText:SetPoint("TOPLEFT", X, -328)
    p.grmText:SetWidth(310)
    p.grmText:SetWordWrap(true)
    p.grmText:SetJustifyV("TOP")
    p.grmButton = W.Button(p, "Import from GRM", 130, 22)
    p.grmButton:SetPoint("TOPLEFT", X, -400)
    p.grmButton.tip = "Brings over GRM's alt groups, join dates, rank history and custom notes for this guild. Safe to run again; anything set by hand is kept."
    p.grmButton:SetScript("OnClick", function()
        local res, err = PGM:ImportGRM()
        if not res then
            PGM.Print(err)
            return
        end
        PGM.Print(("Imported from GRM: %d join dates, %d alt links, %d notes, %d history entries.")
            :format(res.joins, res.links, res.notes, res.history))
        if res.skippedLinks > 0 then
            PGM.Print(("%d alt links skipped: only officers can change shared alt links."):format(res.skippedLinks))
        elseif res.links + res.joins > 0 then
            PGM.Print("Sharing them with the guild in the background (a few minutes).")
        end
        UI:Refresh()
    end)
end

local function refresh(p)
    refreshSwatches(p)

    -- Guild sync status.
    local g = PGM.GuildDB()
    local S = PGM.Sync or {}
    local me = g and g.members[PGM:MyGuid() or ""]
    local lines = {}
    if PGM.opt("syncEnabled") == false then
        lines[#lines + 1] = PGM.Hex(C.amber) .. "Off.|r Nothing is sent or received."
    else
        local peers = PGM.SyncPeers and PGM:SyncPeers() or 0
        lines[#lines + 1] = PGM.Hex(C.jade) .. "On.|r " .. (peers > 0
            and ("Heard from %d officer%s this hour."):format(peers, peers == 1 and "" or "s")
            or "No officers with the addon heard from yet.")
        if S.lastApplied then
            lines[#lines + 1] = "Last shared change: " .. PGM.AgoText(S.lastApplied) .. "."
        end
        local waiting = PGM.SyncQueued and PGM:SyncQueued() or 0
        if waiting > 0 then
            lines[#lines + 1] = ("%d message%s waiting to send%s."):format(waiting, waiting == 1 and "" or "s",
                IsInInstance() and " (after you leave this instance)" or "")
        end
    end
    lines[#lines + 1] = PGM:CanEdit() and (PGM.Hex(C.jade) .. "You can edit|r teams, raid nights and alt links.")
        or "You can view shared teams; officers edit them."
    p.syncStatus:SetText(table.concat(lines, "\n"))

    local users, latest = PGM:AddonUsers()
    local old = 0
    for _, it in ipairs(users) do if it.outdated then old = old + 1 end end
    p.usersText:SetText(("%d member%s it. Newest version: v%s%s."):format(#users, #users == 1 and " runs" or "s run", latest,
        old > 0 and (" (" .. old .. " need to update)") or ""))

    local grmReady = PGM:GRMAvailable()
    local r = g and g.grmResult
    local grmLines = {}
    if g and g.grmImported and r then
        grmLines[#grmLines + 1] = ("Imported %s: %d join dates, %d alt links, %d notes, %d history entries.")
            :format(PGM.AgoText(g.grmImported), r.joins, r.links, r.notes, r.history)
    end
    grmLines[#grmLines + 1] = grmReady and (PGM.Hex(C.jade) .. "GRM's data for this guild is loaded.|r")
        or "GRM isn't loaded. Enable Guild Roster Manager and /reload to import."
    if grmReady and not PGM:CanEdit() then
        grmLines[#grmLines + 1] = "Alt links are imported by officers (they're shared); join dates and notes import for you."
    end
    p.grmText:SetText(table.concat(grmLines, "\n"))
    p.grmButton:SetShown(grmReady)

    local cut = g and g.sync and g.sync.officerRank
    local rankName = cut and GuildControlGetRankName and PGM.Plain(GuildControlGetRankName(cut + 1))
    p.cutValue:SetText(cut and (((rankName and rankName ~= "") and rankName or ("Rank " .. (cut + 1))) .. " and up")
        or "by rank name")
    local gm = PGM:IsGuildMaster()
    p.cutMinus:SetShown(gm)
    p.cutPlus:SetShown(gm)
    p.cutNote:SetText(gm and "You're the guild master: this applies to everyone with the addon."
        or (cut and "Set by the guild master." or "Ranks named Officer, Leader or Guild Master (including officer alts) until the guild master sets a rank."))
    -- The scale can change from the window's corner grabber too.
    for _, sync in ipairs(p.syncers) do sync() end
    local mainGuid = PandyGuildDB.myMain
    local c = mainGuid and PandyGuildDB.chars[mainGuid]
    p.mainText:SetText(c and ("Main: %s%s|r. Your other characters in this guild are linked to it as alts automatically."):format(
        PGM.ClassHex(c.class), c.name or "?")
        or "No main picked, so your highest-level character in this guild counts as your main.")
end

UI:AddTab({ id = "settings", label = "Settings", build = build, refresh = refresh })
