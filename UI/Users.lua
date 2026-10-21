-- Users.lua (UI): who in the guild runs the addon, and on which version.
-- Built from the hellos every copy sends when its player logs in, so it
-- fills in as people log on, and remembers them between sessions.

local _, NS = ...
local PGM = NS.PGM
local C = PGM.C
local UI = PGM.UI
local W = UI.W

local function buildRow(list)
    local r = W.Row(list)
    r.name = W.FS(r, 12, C.text)
    r.name:SetPoint("LEFT", 6, 0)
    r.name:SetWidth(200)
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
        if button == "RightButton" then UI:MemberMenu(s, s.it.guid) else UI:OpenProfile(s.it.guid) end
    end)
    return r
end

local function updateRow(r, it)
    r.it = it
    r.name:SetText(PGM.ColorName(it.rec))
    r.rank:SetText(it.rec.rank or "")
    if it.outdated then
        r.ver:SetText(PGM.Hex(C.amber) .. "v" .. it.v .. "  (update)|r")
    else
        r.ver:SetText(PGM.Hex(C.jade) .. "v" .. it.v .. "|r")
    end
    r.seen:SetText(it.rec.online and (PGM.Hex(C.jade) .. "Online|r") or ("Heard from " .. PGM.AgoText(it.seen)))
end

local function build(p)
    p.title = W.FS(p, 14, C.accent)
    p.title:SetPoint("TOPLEFT", 0, -2)
    p.sub = W.FS(p, 11, C.text2)
    p.sub:SetPoint("TOPLEFT", 0, -22)
    p.sub:SetPoint("TOPRIGHT", 0, -22)
    p.sub:SetWordWrap(true)

    local header = CreateFrame("Frame", nil, p)
    header:SetPoint("TOPLEFT", 0, -50)
    header:SetPoint("TOPRIGHT", 0, -50)
    header:SetHeight(20)
    local hbg = W.Solid(header, "BACKGROUND", C.side)
    hbg:SetAllPoints()
    for _, h in ipairs({ { "Name", 6 }, { "Rank", 212 }, { "Version", 358 }, { "Last seen", 514 } }) do
        local fs = W.FS(header, 11, C.text2)
        fs:SetPoint("LEFT", h[2], 0)
        fs:SetText(h[1])
    end

    p.list = W.List(p, 22, buildRow, updateRow)
    p.list:SetPoint("TOPLEFT", 0, -72)
    p.list:SetPoint("BOTTOMRIGHT")
end

local function refresh(p)
    local users, latest = PGM:AddonUsers()
    local outdated = 0
    for _, it in ipairs(users) do if it.outdated then outdated = outdated + 1 end end
    p.title:SetText(("%d guild member%s run Pandy Guild Management"):format(#users, #users == 1 and "" or "s"))
    p.sub:SetText(("Newest version in the guild: v%s%s. Copies say hello when their player logs in, so this fills in as people log on.")
        :format(latest, outdated > 0 and (", " .. outdated .. " on an older one") or ""))
    p.list:SetData(users, true)
end

UI:AddTab({ id = "users", label = "Addon Users", build = build, refresh = refresh })
