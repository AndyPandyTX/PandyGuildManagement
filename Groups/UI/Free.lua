-- Free.lua (UI): who's free. Online guildies, the ones looking for a group
-- first, then free, in a group, busy or away, and those without the module
-- (who might well be free, but can't say).

local _, NS = ...
local G = NS.G
local PGM = G.PGM
local C = PGM.C
local UI = PGM.UI
local W = UI.W
local GU = G.UI

local STATE_COLOR = { l = C.jade, f = C.jade, g = C.gold, b = C.text3, n = C.text3 }

local COLS = {
    { "Name", 6 }, { "Role", 214 }, { "ilvl", 284 }, { "M+", 334 }, { "Keystone", 384 },
    { "Zone", 514 }, { "State", 640 },
}

local function buildRow(list)
    local r = W.Row(list)
    local function cell(x, w, col, justify)
        local fs = W.FS(r, 12, col or C.text, justify)
        fs:SetPoint("LEFT", x, 0)
        fs:SetWidth(w)
        return fs
    end
    r.name = cell(6, 204)
    r.role = cell(214, 66)
    r.ilvl = cell(284, 46, C.text2)
    r.score = cell(334, 46)
    r.key = cell(384, 126, C.text2)
    r.zone = cell(514, 122, C.text2)
    r.state = W.FS(r, 12, C.text)
    r.state:SetPoint("LEFT", 640, 0)
    r.state:SetPoint("RIGHT", -6, 0)
    r:SetScript("OnClick", function(s, button)
        if button == "RightButton" then UI:MemberMenu(s, s.it.guid) else UI:OpenProfile(s.it.guid) end
    end)
    r.onEnter = G.UI.MemberTooltip
    return r
end

local function updateRow(r, it)
    r.it = it
    local rec, st = it.rec, it.st
    r.name:SetText(G.WhoText(rec))
    local roles = {}
    for l in ((st and st.role) or ""):gmatch("[THD]") do roles[#roles + 1] = G.RoleText(l) end
    r.role:SetText(table.concat(roles, " "))
    r.ilvl:SetText((st and st.ilvl > 0) and st.ilvl or "")
    local score = PGM:MPlusScore(rec)
    r.score:SetText(score and (PGM.Hex(PGM:ScoreColor(score)) .. score .. "|r") or "")
    local k = G:Keys()[it.guid]
    r.key:SetText((k and (k.map or 0) > 0) and ("+" .. k.level .. " " .. (G.DungeonName(k.map) or "")) or "")
    r.zone:SetText(rec.zone or "")
    local text = G.STATE_LABEL[it.state]
    if it.state == "g" and st then text = text .. (" (%d)"):format(st.size) end
    if it.state == "l" and st and st.kinds ~= "" then
        local kinds = {}
        for l in st.kinds:gmatch(".") do kinds[#kinds + 1] = G.KIND_LABEL[l] end
        text = text .. ": " .. table.concat(kinds, ", ")
    end
    local col = STATE_COLOR[it.state] or C.text
    r.state:SetText(PGM.Hex(col) .. text .. "|r")
end

local function build(p)
    GU.Title(p)

    -- Me: up for a group, and for what.
    p.looking = W.Chip(p, "I'm up for a group", function(s)
        G:SetLooking(not G.opt("looking"))
    end)
    p.looking:SetPoint("TOPLEFT", 0, -46)
    p.kindChips = {}
    local prev = p.looking
    for _, k in ipairs(G.KINDS) do
        local chip = W.Chip(p, G.KIND_LABEL[k], function() G:ToggleLookingKind(k) end)
        chip:SetPoint("LEFT", prev, "RIGHT", 4, 0)
        p.kindChips[k] = chip
        prev = chip
    end

    -- Filters, on the right.
    p.addonOnly = W.Chip(p, "Has the module", function()
        G.setOpt("freeAddonOnly", not G.opt("freeAddonOnly"))
        UI:Refresh()
    end)
    p.addonOnly:SetPoint("TOPRIGHT", 0, -46)
    p.maxOnly = W.Chip(p, "Max level", function()
        G.setOpt("freeMaxOnly", not G.opt("freeMaxOnly"))
        UI:Refresh()
    end)
    p.maxOnly:SetPoint("RIGHT", p.addonOnly, "LEFT", -4, 0)

    GU.Header(p, -78, COLS)
    p.list = W.List(p, 22, buildRow, updateRow)
    p.list:SetPoint("TOPLEFT", 0, -100)
    p.list:SetPoint("BOTTOMRIGHT")
    p.empty = W.FS(p, 12, C.text3)
    p.empty:SetPoint("TOPLEFT", 6, -108)
end

local function refresh(p)
    if GU.Off(p) then return end
    local list = G:WhoList()
    local counts = { l = 0, f = 0 }
    for _, it in ipairs(list) do
        if counts[it.state] then counts[it.state] = counts[it.state] + 1 end
    end
    p.title:SetText(("Who's free: %d looking, %d free"):format(counts.l, counts.f))
    p.sub:SetText("Guildies running Pandy Guild Management say when they're free or grouped. Inside an instance they go quiet, and show as busy.")
    p.looking:SetActive(G.opt("looking") and true or false)
    for k, chip in pairs(p.kindChips) do chip:SetActive(G.opt("lookingKinds")[k] and true or false) end
    p.addonOnly:SetActive(G.opt("freeAddonOnly") and true or false)
    p.maxOnly:SetActive(G.opt("freeMaxOnly") and true or false)
    p.list:SetData(list, true)
    p.empty:SetText(#list == 0 and "Nobody else online matches." or "")
end

UI:AddTab({ id = "free", label = "Who's Free", build = build, refresh = refresh, module = true, hidden = GU.Hidden,
            icon = "Interface\\Icons\\INV_Misc_GroupLooking" })
