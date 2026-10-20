-- Log.lua (UI): every join, leave, rank change, rename and max-level ding.

local _, NS = ...
local PGM = NS.PGM
local C = PGM.C
local UI = PGM.UI
local W = UI.W

local KINDS = {
    { id = "joins",  label = "Joins",  kinds = { join = true, rejoin = true } },
    { id = "leaves", label = "Leaves", kinds = { leave = true } },
    { id = "ranks",  label = "Ranks",  kinds = { promote = true, demote = true } },
    { id = "levels", label = "Max level", kinds = { maxlevel = true } },
    { id = "names",  label = "Renames", kinds = { rename = true } },
}

local ICON = {
    join = C.jade, rejoin = C.jade, leave = C.red, promote = C.blue, demote = C.amber,
    rename = C.purple, maxlevel = C.gold, seeded = C.text3,
}

local state = { search = "", only = {} }

local function buildList()
    local g = PGM.GuildDB()
    local out = {}
    if not g then return out end
    local allowed
    for _, k in ipairs(KINDS) do
        if state.only[k.id] then
            allowed = allowed or {}
            for kind in pairs(k.kinds) do allowed[kind] = true end
        end
    end
    local q = state.search:lower()
    for i = #g.log, 1, -1 do
        local e = g.log[i]
        if (not allowed or allowed[e.kind])
            and (q == "" or (e.name and e.name:lower():find(q, 1, true))) then
            out[#out + 1] = e
        end
    end
    return out
end

local function buildRow(list)
    local r = W.Row(list)
    r.dot = W.Solid(r, "ARTWORK", C.jade)
    r.dot:SetSize(6, 6)
    r.dot:SetPoint("LEFT", 8, 0)
    r.date = W.FS(r, 11, C.text3)
    r.date:SetPoint("LEFT", 22, 0)
    r.date:SetWidth(110)
    r.text = W.FS(r, 12, C.text)
    r.text:SetPoint("LEFT", 136, 0)
    r.text:SetPoint("RIGHT", -6, 0)
    r:SetScript("OnClick", function(s)
        local g = PGM.GuildDB()
        if s.entry.guid and g and g.members[s.entry.guid] then UI:OpenProfile(s.entry.guid) end
    end)
    return r
end

local function updateRow(r, e)
    r.entry = e
    local col = ICON[e.kind] or C.text3
    r.dot:SetColorTexture(col[1], col[2], col[3], 1)
    r.date:SetText(PGM.Date(e.t, true))
    r.text:SetText(PGM.LogText(e))
end

local function build(p)
    p.search = W.EditBox(p, 180, 24, "Search a name...")
    p.search:SetPoint("TOPLEFT")
    p.search.onChange = function(s)
        state.search = s:GetText() or ""
        p.list.offset = 0
        UI:Refresh()
    end
    local prev = p.search
    for _, k in ipairs(KINDS) do
        local chip = W.Chip(p, k.label, function(s)
            state.only[k.id] = not state.only[k.id]
            p.list.offset = 0
            s:SetActive(state.only[k.id])
            UI:Refresh()
        end)
        chip:SetPoint("LEFT", prev, "RIGHT", 8, 0)
        prev = chip
    end
    p.count = W.FS(p, 11, C.text3, "RIGHT")
    p.count:SetPoint("TOPRIGHT", 0, -6)

    p.list = W.List(p, 22, buildRow, updateRow)
    p.list:SetPoint("TOPLEFT", 0, -34)
    p.list:SetPoint("BOTTOMRIGHT")
    p.empty = W.FS(p, 12, C.text3, "CENTER")
    p.empty:SetPoint("CENTER", p.list, "CENTER")
end

local function refresh(p)
    p.list:SetData(buildList(), true)
    p.count:SetText(#p.list.data .. " entries")
    p.empty:SetText(#p.list.data == 0 and "No history yet. Joins, leaves and rank changes show up here." or "")
end

UI:AddTab({ id = "log", label = "History", build = build, refresh = refresh })
