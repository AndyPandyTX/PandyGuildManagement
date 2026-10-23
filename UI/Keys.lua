-- Keys.lua (UI): everyone's keystone this week. Click a column to sort
-- (key level, dungeon, who, M+ score, when it was seen). Your own key can
-- be listed in Blizzard's Group Finder, or posted to the guild, from here.

local _, NS = ...
local G = NS.G
if not G.ok then return end
local PGM = G.PGM
local C = PGM.C
local UI = PGM.UI
local W = UI.W
local GU = G.UI

local COLS = {
    { "Key", 6, "level" }, { "Dungeon", 56, "map" }, { "Who", 232, "who" }, { "M+", 486, "score" }, { "Seen", 546, "seen" },
}

-- The sort each column means, and which way is natural (highest first
-- for numbers, A to Z for names).
local LESS = {
    level = function(a, b) return a.level > b.level end,
    map = function(a, b) return a.name < b.name end,
    who = function(a, b) return PGM.NameLess(a.rec.short, b.rec.short) end,
    score = function(a, b) return (a.score or 0) > (b.score or 0) end,
    seen = function(a, b) return (a.u or 0) > (b.u or 0) end,
}

local function buildRow(list)
    local r = W.Row(list)
    r.wash = W.Solid(r, "BORDER", C.accent, 0.08)
    r.wash:SetAllPoints()
    r.level = W.FS(r, 13, C.accent)
    r.level:SetPoint("LEFT", 6, 0)
    r.level:SetWidth(46)
    r.key = W.FS(r, 12, C.text)
    r.key:SetPoint("LEFT", 56, 0)
    r.key:SetWidth(172)
    r.who = W.FS(r, 12, C.text)
    r.who:SetPoint("LEFT", 232, 0)
    r.who:SetWidth(250)
    r.score = W.FS(r, 12, C.text)
    r.score:SetPoint("LEFT", 486, 0)
    r.score:SetWidth(56)
    r.seen = W.FS(r, 11, C.text3)
    r.seen:SetPoint("LEFT", 546, 0)
    r.seen:SetWidth(60)
    r.b1 = W.Button(r, "", 58, 18)
    r.b1:SetPoint("RIGHT", -66, 0)
    r.b2 = W.Button(r, "", 58, 18)
    r.b2:SetPoint("RIGHT", -4, 0)
    r.b1:SetScript("OnClick", function(s)
        local it = s:GetParent().it
        if it.current then G:ListMyKey() end
    end)
    r.b2:SetScript("OnClick", function(s)
        local it = s:GetParent().it
        if it.current then
            G.UI.ShowView("post")
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

local function enable(b, on, tip)
    b:SetEnabled(on)
    b:SetAlpha(on and 1 or 0.45)
    b.tip = tip
end

local function updateRow(r, it)
    r.it = it
    -- Pinned to the top by Mine first: tinted, so the order makes sense.
    r.wash:SetShown(it.pinned)
    r.level:SetText("+" .. it.level)
    r.key:SetText(it.name)
    r.who:SetText(G.WhoText(it.rec))
    r.score:SetText(it.score and (PGM.Hex(PGM:ScoreColor(it.score)) .. it.score .. "|r") or "")
    r.seen:SetText(PGM.AgoText(it.u))
    if it.current then
        r.b1:Show()
        r.b1:SetLabel("List")
        enable(r.b1, not G:IsListed(), G:IsListed() and "You're already listed." or
            "Opens the Group Finder's Start a Group on this key. You click List Group there.")
        r.b2:SetLabel("Post")
        enable(r.b2, not G.mine, G.mine and "Close the group you have posted first." or
            "A guild-only post for this key (or a scheduled one).")
    else
        r.b1:Hide()
        r.b2:SetLabel("Whisper")
        enable(r.b2, (it.rec.online and not it.mine) and true or false, nil)
    end
end

local function build(p)
    GU.Title(p)
    p.online = W.Chip(p, "Online only", function()
        G.setOpt("keysOnline", not G.opt("keysOnline"))
        UI:Refresh()
    end)
    p.online:SetPoint("TOPLEFT", 0, -46)
    p.mineFirst = W.Chip(p, "Mine first", function()
        G.setOpt("keysPinMine", not G.opt("keysPinMine"))
        UI:Refresh()
    end)
    p.mineFirst:SetPoint("LEFT", p.online, "RIGHT", 4, 0)

    p.header = GU.SortHeader(p, -78, COLS,
        function() return G.opt("keysSort"), G.opt("keysReverse") end,
        function(key, rev)
            G.setOpt("keysSort", key)
            G.setOpt("keysReverse", rev)
        end)
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
    local list = G.UI.KeyRows()
    local online, mineFirst = G.opt("keysOnline"), G.opt("keysPinMine")
    p.title:SetText(("Keystones this week: %d%s"):format(#list, online and " online" or ""))
    p.sub:SetText("From guildies running this module (with their alts' keys), or BigWigs, LittleWigs or EllesmereUI (LibKeystone). Click a column to sort.")
    p.online:SetActive(online and true or false)
    p.mineFirst:SetActive(mineFirst and true or false)
    p.header:Update()
    p.list:SetData(list, true)
    p.empty:SetText(#list == 0 and (online and "No keys from anyone online yet. Turn off Online only to see everyone's."
        or "No keys heard yet. They arrive as guildies log in, and from anyone running BigWigs or EllesmereUI.") or "")
end

-- The rows, filtered and sorted as the page's settings say.
function G.UI.KeyRows()
    local me = PGM:MyGuid()
    local myMain = PGM:MainOf(me or "")
    local online, mineFirst = G.opt("keysOnline"), G.opt("keysPinMine")
    local list = {}
    for _, it in ipairs(G:KeyList()) do
        it.mine = PGM:MainOf(it.guid) == myMain
        it.current = it.guid == me
        it.score = PGM:MPlusScore(it.rec)
        it.pinned = mineFirst and it.mine or false
        if not online or it.rec.online then list[#list + 1] = it end
    end
    local key = LESS[G.opt("keysSort")] and G.opt("keysSort") or "level"
    local less, rev = LESS[key], G.opt("keysReverse")
    table.sort(list, function(a, b)
        if mineFirst and a.mine ~= b.mine then return a.mine end
        if less(a, b) ~= less(b, a) then
            if rev then return less(b, a) end
            return less(a, b)
        end
        if a.level ~= b.level then return a.level > b.level end
        return PGM.NameLess(a.rec.short, b.rec.short)
    end)
    return list
end

UI:AddTab({ id = "keys", label = "Keystones", build = build, refresh = refresh, module = true,
            icon = "Interface\\Icons\\INV_Relics_Hourglass" })
