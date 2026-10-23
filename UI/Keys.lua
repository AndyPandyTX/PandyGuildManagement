-- Keys.lua (UI): everyone's keystone this week, highest first or by
-- dungeon. Each alt's key sits under its main's name. Your own keys can be
-- posted as a group in one click.

local _, NS = ...
local G = NS.G
if not G.ok then return end
local PGM = G.PGM
local C = PGM.C
local UI = PGM.UI
local W = UI.W
local GU = G.UI

local COLS = { { "Key", 6 }, { "Who", 200 }, { "M+", 470 }, { "Seen", 530 } }

local function buildRow(list)
    local r = W.Row(list)
    r.key = W.FS(r, 12, C.text)
    r.key:SetPoint("LEFT", 6, 0)
    r.key:SetWidth(190)
    r.who = W.FS(r, 12, C.text)
    r.who:SetPoint("LEFT", 200, 0)
    r.who:SetWidth(266)
    r.score = W.FS(r, 12, C.text)
    r.score:SetPoint("LEFT", 470, 0)
    r.score:SetWidth(56)
    r.seen = W.FS(r, 11, C.text3)
    r.seen:SetPoint("LEFT", 530, 0)
    r.seen:SetWidth(90)
    r.post = W.Button(r, "", 96, 18)
    r.post:SetPoint("RIGHT", -6, 0)
    r.post:SetScript("OnClick", function(s)
        local it = s:GetParent().it
        if it.mine then
            UI:Show("groups")   -- builds the page first if it's new
            G.UI.FillForm({ kind = "M", what = it.name, level = tostring(it.level), size = 5 })
            UI:Refresh()
        else
            UI:Whisper(it.rec)
        end
    end)
    r:SetScript("OnClick", function(s, button)
        if button == "RightButton" then UI:MemberMenu(s, s.it.guid) else UI:OpenProfile(s.it.guid) end
    end)
    r.onEnter = G.UI.MemberTooltip
    return r
end

local function updateRow(r, it)
    r.it = it
    r.key:SetText(PGM.Hex(C.accent) .. "+" .. it.level .. "|r  " .. it.name)
    r.who:SetText(G.WhoText(it.rec))
    local score = PGM:MPlusScore(it.rec)
    r.score:SetText(score and (PGM.Hex(PGM:ScoreColor(score)) .. score .. "|r") or "")
    r.seen:SetText(PGM.AgoText(it.u))
    if it.mine then
        local canPost = it.guid == PGM:MyGuid() and not G.mine
        r.post:SetLabel("Post a group")
        r.post:SetEnabled(canPost)
        r.post:SetAlpha(canPost and 1 or 0.45)
        r.post.tip = not canPost and "Log on to that character, and close any group you have posted." or nil
    else
        r.post:SetLabel("Whisper")
        r.post:SetEnabled(it.rec.online and true or false)
        r.post:SetAlpha(it.rec.online and 1 or 0.45)
        r.post.tip = nil
    end
end

local function build(p)
    GU.Title(p)
    p.sortLevel = W.Chip(p, "Highest first", function()
        G.setOpt("keysSort", "level")
        UI:Refresh()
    end)
    p.sortLevel:SetPoint("TOPLEFT", 0, -46)
    p.sortMap = W.Chip(p, "By dungeon", function()
        G.setOpt("keysSort", "map")
        UI:Refresh()
    end)
    p.sortMap:SetPoint("LEFT", p.sortLevel, "RIGHT", 4, 0)
    p.online = W.Chip(p, "Online only", function(s)
        p.onlineOnly = not p.onlineOnly
        s:SetActive(p.onlineOnly)
        UI:Refresh()
    end)
    p.online:SetPoint("LEFT", p.sortMap, "RIGHT", 10, 0)

    GU.Header(p, -78, COLS)
    p.list = W.List(p, 22, buildRow, updateRow)
    p.list:SetPoint("TOPLEFT", 0, -100)
    p.list:SetPoint("BOTTOMRIGHT")
    p.empty = W.FS(p, 12, C.text3)
    p.empty:SetPoint("TOPLEFT", 6, -108)
    p.empty:SetPoint("TOPRIGHT", -6, -108)
    p.empty:SetWordWrap(true)
end

local function refresh(p)
    if PGM.IS_FOREVER then
        p.title:SetText("Keystones")
        p.sub:SetText("WoW Forever has no Mythic+.")
        p.list:SetData({})
        p.empty:SetText("")
        return
    end
    G:RequestLibKeystone()   -- at most every two minutes
    local myMain = PGM:MainOf(PGM:MyGuid() or "")
    local list = {}
    for _, it in ipairs(G:KeyList()) do
        it.mine = PGM:MainOf(it.guid) == myMain
        if not p.onlineOnly or it.rec.online or it.mine then list[#list + 1] = it end
    end
    local byMap = G.opt("keysSort") == "map"
    table.sort(list, function(a, b)
        if a.mine ~= b.mine then return a.mine end
        if byMap and a.name ~= b.name then return a.name < b.name end
        if a.level ~= b.level then return a.level > b.level end
        return PGM.NameLess(a.rec.short, b.rec.short)
    end)
    p.title:SetText(("Keystones this week: %d"):format(#list))
    p.sub:SetText("From guildies running this module (with their alts' keys), or BigWigs, LittleWigs or EllesmereUI (LibKeystone).")
    p.sortLevel:SetActive(not byMap)
    p.sortMap:SetActive(byMap)
    p.list:SetData(list, true)
    p.empty:SetText(#list == 0 and "No keys heard yet. They arrive as guildies log in, and from anyone running BigWigs or EllesmereUI." or "")
end

UI:AddTab({ id = "keys", label = "Keystones", build = build, refresh = refresh, module = true,
            icon = "Interface\\Icons\\INV_Relics_Hourglass" })
