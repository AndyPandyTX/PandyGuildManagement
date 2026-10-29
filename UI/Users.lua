-- Users.lua (UI): who in the guild runs the addon, and on which version.
-- Built from the hellos every copy sends when its player logs in, so it
-- fills in as people log on, and remembers them between sessions.
--
-- One row per player (their main), with how many of their characters run
-- it; click the row to show those characters under it. "Every character"
-- lists them all instead.

local _, NS = ...
local PGM = NS.PGM
local C = PGM.C
local UI = PGM.UI
local W = UI.W

local state = { every = false, open = {} }

local function versionText(v, outdated)
    if outdated then return PGM.Hex(C.amber) .. "v" .. v .. "  (update)|r" end
    return PGM.Hex(C.jade) .. "v" .. v .. "|r"
end

local function seenText(online, seen)
    return online and (PGM.Hex(C.jade) .. "Online|r") or ("Heard from " .. PGM.AgoText(seen))
end

local function buildRow(list)
    local r = W.Row(list)
    r.arrow = W.FS(r, 12, C.text3)
    r.arrow:SetPoint("LEFT", 6, 0)
    r.arrow:SetWidth(12)
    r.name = W.FS(r, 12, C.text)
    r.name:SetPoint("LEFT", 20, 0)
    r.name:SetWidth(186)
    r.rank = W.FS(r, 12, C.text2)
    r.rank:SetPoint("LEFT", 212, 0)
    r.rank:SetWidth(140)
    r.ver = W.FS(r, 12, C.text)
    r.ver:SetPoint("LEFT", 358, 0)
    r.ver:SetWidth(150)
    r.seen = W.FS(r, 12, C.text2)
    r.seen:SetPoint("LEFT", 514, 0)
    r.seen:SetPoint("RIGHT", -6, 0)
    r:SetScript("OnClick", function(s, button)
        local it = s.it
        if button == "RightButton" then
            UI:MemberMenu(s, it.guid)
        elseif it.player and #it.player.chars > 1 then
            -- A player with more than one character here: show or hide them.
            state.open[it.guid] = not state.open[it.guid] or nil
            UI:Refresh()
        else
            UI:OpenProfile(it.guid)
        end
    end)
    return r
end

local function updateRow(r, it)
    r.it = it
    local p = it.player
    if p then
        local n = #p.chars
        r.arrow:SetText(n > 1 and (state.open[it.guid] and "-" or "+") or "")
        local others = n > 1 and (PGM.Hex(C.text3) .. "  +" .. (n - 1) .. (n == 2 and " alt" or " alts") .. "|r") or ""
        r.name:SetText(PGM.ColorName(p.rec) .. others)
        r.rank:SetText(p.rec.rank or "")
        r.ver:SetText(versionText(p.v, p.outdated))
        r.seen:SetText(seenText(p.online, p.seen))
    else
        -- One character: under its player, or in the full list.
        local u = it.user
        r.arrow:SetText("")
        r.name:SetText((it.indent and "    " or "") .. PGM.ColorName(u.rec))
        r.rank:SetText(u.rec.rank or "")
        r.ver:SetText(versionText(u.v, u.outdated))
        r.seen:SetText(seenText(u.rec.online, u.seen))
    end
end

local function build(p)
    p.title = W.FS(p, 14, C.accent)
    p.title:SetPoint("TOPLEFT", 0, -2)
    p.every = W.Chip(p, "Every character", function()
        state.every = not state.every
        UI:Refresh()
    end)
    p.every:SetPoint("TOPRIGHT", 0, 0)
    p.sub = W.FS(p, 11, C.text2)
    p.sub:SetPoint("TOPLEFT", 0, -26)
    p.sub:SetPoint("TOPRIGHT", 0, -26)
    p.sub:SetWordWrap(true)

    local header = CreateFrame("Frame", nil, p)
    header:SetPoint("TOPLEFT", 0, -54)
    header:SetPoint("TOPRIGHT", 0, -54)
    header:SetHeight(20)
    local hbg = W.Solid(header, "BACKGROUND", C.side)
    hbg:SetAllPoints()
    for _, h in ipairs({ { "Name", 20 }, { "Rank", 212 }, { "Version", 358 }, { "Last seen", 514 } }) do
        local fs = W.FS(header, 11, C.text2)
        fs:SetPoint("LEFT", h[2], 0)
        fs:SetText(h[1])
    end

    p.list = W.List(p, 22, buildRow, updateRow)
    p.list:SetPoint("TOPLEFT", 0, -76)
    p.list:SetPoint("BOTTOMRIGHT")
end

local function refresh(p)
    local players, latest, chars = PGM:AddonUsersByMain()
    local rows, outdated = {}, 0
    if state.every then
        local users = PGM:AddonUsers()
        for _, u in ipairs(users) do rows[#rows + 1] = { guid = u.guid, user = u } end
    else
        for _, pl in ipairs(players) do
            rows[#rows + 1] = { guid = pl.guid, player = pl }
            if state.open[pl.guid] and #pl.chars > 1 then
                for _, u in ipairs(pl.chars) do rows[#rows + 1] = { guid = u.guid, user = u, indent = true } end
            end
        end
    end
    for _, pl in ipairs(players) do if pl.outdated then outdated = outdated + 1 end end
    p.every:SetActive(state.every)
    p.title:SetText(("%d %s run " .. PGM.NAME .. " (%d %s)"):format(#players,
        #players == 1 and "player" or "players", chars, chars == 1 and "character" or "characters"))
    p.sub:SetText(("Newest version in the guild: v%s%s. Click a player to see their characters. Copies say hello when their player logs in, so this fills in as people log on.")
        :format(latest, outdated > 0 and (", " .. outdated .. " " .. (outdated == 1 and "player" or "players") .. " on an older one") or ""))
    p.list:SetData(rows, true)
end

UI:AddTab({ id = "users", label = "Addon Users", build = build, refresh = refresh })
