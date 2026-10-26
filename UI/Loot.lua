-- Loot.lua (UI): the Loot page. Every raid drop and bonus roll this account
-- has recorded or imported (Loot.lua), with filters that all combine: when,
-- raid or M+, team, boss, difficulty, item type, drops or bonus rolls, and a
-- search for a player, item or boss. Two views: the items, or one row per
-- player with counts. Export what's showing, or import someone's export.

local _, NS = ...
local PGM = NS.PGM
local C = PGM.C
local UI = PGM.UI
local W = UI.W

local state = {
    search = "", when = "all", kind = "raid", team = nil, boss = nil, diff = nil, itype = nil, how = nil,
    mine = false, view = "items", altsAsMain = true,
}

local WHEN = { { "all", "All time" }, { "week", "This week" }, { "month", "Last 4 weeks" }, { "3m", "Last 3 months" } }
local KIND = { { "raid", "Raids" }, { "mplus", "Mythic+" }, { "all", "Raids and M+" } }
local DIFF = { { nil, "Any difficulty" }, { 17, "LFR" }, { 14, "Normal" }, { 15, "Heroic" }, { 16, "Mythic" } }
local ITYPE = { { nil, "Any item" }, { "token", "Tier tokens" }, { "weapon", "Weapons" }, { "trinket", "Trinkets" },
    { "jewelry", "Rings and necks" }, { "armor", "Armor" }, { "other", "Other" } }
local HOW = { { nil, "Drops + bonus" }, { "drop", "Drops only" }, { "bonus", "Bonus rolls only" } }
local SHORT_DIFF = { [17] = "LFR", [14] = "N", [15] = "H", [16] = "M" }

local function labelOf(list, value)
    for _, o in ipairs(list) do
        if o[1] == value then return o[2] end
    end
    return list[1][2]
end

local function trim(text, n)
    if #text > n then return text:sub(1, n - 1) .. "…" end
    return text
end

-- ---- the filters ----

local function since()
    local now = PGM.Now()
    if state.when == "week" then
        local left = C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset and C_DateAndTime.GetSecondsUntilWeeklyReset()
        return now + (PGM.Plain(left) or 0) - 7 * 86400
    elseif state.when == "month" then
        return now - 28 * 86400
    elseif state.when == "3m" then
        return now - 91 * 86400
    end
    return 0
end

-- My characters: this one, and its main and alts in the guild.
local function myKeys()
    local keys = {}
    local ok, name, realm = pcall(UnitFullName, "player")
    if ok and name then
        realm = (realm and realm ~= "") and realm or (GetNormalizedRealmName and GetNormalizedRealmName()) or ""
        keys[PGM.LootNameKey(name .. "-" .. realm)] = true
    end
    local g, me = PGM.GuildDB(), PGM:MyGuid()
    if g and me and g.members[me] then
        for _, guid in ipairs(PGM:GroupOf(me)) do
            local rec = g.members[guid]
            if rec and rec.name then keys[PGM.LootNameKey(rec.name)] = true end
        end
    end
    return keys
end

local function itemName(rec)
    local name = C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(rec.link)
    return name
end

local function filtered()
    local out = {}
    local from = since()
    local mine = state.mine and myKeys()
    local q = state.search:lower()
    for _, rec in ipairs(PGM:LootItems()) do
        local ok = (rec.t or 0) >= from
            and (state.kind == "all" or rec.kind == state.kind)
            and (not state.diff or rec.diff == state.diff)
            and (not state.how or (state.how == "bonus") == (rec.how == "bonus"))
            and (not state.boss or (rec.boss or "?") == state.boss)
            and (not state.itype or PGM.LootType(rec.id) == state.itype)
            and (not mine or mine[PGM.LootNameKey(rec.who)])
        if ok and state.team then
            local night = PGM:LootNight(rec)
            ok = night ~= nil and night.team == state.team
        end
        if ok and q ~= "" then
            ok = (rec.who or ""):lower():find(q, 1, true) or (rec.boss or ""):lower():find(q, 1, true)
                or (itemName(rec) or ""):lower():find(q, 1, true)
        end
        if ok then out[#out + 1] = rec end
    end
    table.sort(out, function(a, b) return (a.t or 0) > (b.t or 0) end)
    return out
end

-- One row per player (or per main, with alts folded in).
local function byPlayer(items)
    local g = PGM.GuildDB()
    local groups, order = {}, {}
    for _, rec in ipairs(items) do
        local guid = PGM.LootMemberGuid(rec.who)
        local main = guid and state.altsAsMain and PGM:MainOf(guid) or guid
        local key = main or PGM.LootNameKey(rec.who)
        local it = groups[key]
        if not it then
            it = { key = key, guid = main, who = rec.who, class = rec.class, items = 0, tokens = 0, bonus = 0 }
            groups[key] = it
            order[#order + 1] = it
        end
        it.items = it.items + 1
        if PGM.LootType(rec.id) == "token" then it.tokens = it.tokens + 1 end
        if rec.how == "bonus" then it.bonus = it.bonus + 1 end
        if not it.last or rec.t > it.last.t then it.last = rec end
    end
    -- Raids attended in the same window (and team), for guild members.
    local from = since()
    for _, it in ipairs(order) do
        if it.guid and g then
            local group = PGM:GroupOf(it.guid)
            local n = 0
            for _, s in ipairs(g.raids and g.raids.sessions or {}) do
                if (s.start or 0) >= from and (not state.team or s.team == state.team) then
                    for _, gu in ipairs(group) do
                        if s.present and s.present[gu] then n = n + 1 break end
                    end
                end
            end
            it.raids = n
            local rec = g.members[it.guid]
            if rec then it.rec = rec end
        end
    end
    table.sort(order, function(a, b)
        if a.items ~= b.items then return a.items > b.items end
        return PGM.NameLess(a.who, b.who)
    end)
    return order
end

-- ---- rows ----

local function whoText(who, class)
    local name, realm = (who or "?"):match("^([^%-]+)%-?(.*)$")
    local myRealm = GetNormalizedRealmName and GetNormalizedRealmName()
    local tag = (realm and realm ~= "" and myRealm and realm ~= myRealm) and "*" or ""
    return PGM.ClassHex(class) .. (name or "?") .. tag .. "|r"
end

local function itemText(rec)
    local link
    if C_Item and C_Item.GetItemInfo then
        local _, full = C_Item.GetItemInfo(rec.link)
        link = full
    end
    if link then return link end
    if rec.link and rec.link:find("|H", 1, true) then return rec.link end
    if C_Item and C_Item.RequestLoadItemDataByID and rec.id then pcall(C_Item.RequestLoadItemDataByID, rec.id) end
    return PGM.Hex(C.text3) .. "Item " .. (rec.id or "?") .. "|r"
end

local function showItemTip(owner, rec)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, rec.link)
    if not ok then GameTooltip:SetText("Item " .. (rec.id or "?")) end
    GameTooltip:Show()
end

local function itemRow(list)
    local r = W.Row(list)
    r.date = W.FS(r, 11, C.text3)
    r.date:SetPoint("LEFT", 6, 0)
    r.date:SetWidth(52)
    r.boss = W.FS(r, 11, C.text2)
    r.boss:SetPoint("LEFT", 62, 0)
    r.boss:SetWidth(150)
    r.diff = W.FS(r, 11, C.text2)
    r.diff:SetPoint("LEFT", 216, 0)
    r.diff:SetWidth(36)
    r.who = W.FS(r, 12, C.text)
    r.who:SetPoint("LEFT", 254, 0)
    r.who:SetWidth(124)
    r.how = W.FS(r, 11, C.text2, "RIGHT")
    r.how:SetPoint("RIGHT", -6, 0)
    r.how:SetWidth(96)
    r.item = W.FS(r, 12, C.text)
    r.item:SetPoint("LEFT", 382, 0)
    r.item:SetPoint("RIGHT", r.how, "LEFT", -6, 0)
    r.onEnter = function(s) showItemTip(s, s.rec) end
    r:SetScript("OnClick", function(s, button)
        local rec = s.rec
        local short = (rec.who or ""):match("^([^%-]+)") or rec.who
        if button == "RightButton" then
            local entries = { { "Only " .. short, function()
                state.search = short
                UI:Refresh()
            end } }
            if rec.boss then
                entries[#entries + 1] = { "Only " .. rec.boss, function()
                    state.boss = rec.boss
                    UI:Refresh()
                end }
            end
            entries[#entries + 1] = { divider = true }
            entries[#entries + 1] = { "Delete this entry", function() PGM:DeleteLoot(rec) end }
            W.Menu(s, itemName(rec) or "Loot", entries)
        else
            state.search = short
            UI:Refresh()
        end
    end)
    return r
end

local function itemUpdate(r, rec)
    r.rec = rec
    r.date:SetText(date("%b %d", rec.t))
    r.boss:SetText(rec.boss or (rec.kind == "mplus" and "Mythic+" or "?"))
    r.diff:SetText(rec.kind == "mplus" and "M+" or (SHORT_DIFF[rec.diff] or ""))
    r.who:SetText(whoText(rec.who, rec.class))
    r.item:SetText(itemText(rec))
    local how = PGM.LOOT_HOW_LABEL[rec.how] or rec.how or ""
    r.how:SetText(rec.how == "bonus" and (PGM.Hex(C.gold) .. how .. "|r") or how)
end

local function playerRow(list)
    local r = W.Row(list)
    r.who = W.FS(r, 12, C.text)
    r.who:SetPoint("LEFT", 6, 0)
    r.who:SetWidth(150)
    r.cols = {}
    for i, x in ipairs({ 160, 220, 280, 340, 400 }) do
        local fs = W.FS(r, 12, C.text, "RIGHT")
        fs:SetPoint("LEFT", x, 0)
        fs:SetWidth(52)
        r.cols[i] = fs
    end
    r.last = W.FS(r, 11, C.text2)
    r.last:SetPoint("LEFT", 470, 0)
    r.last:SetPoint("RIGHT", -6, 0)
    r.onEnter = function(s) if s.it.last then showItemTip(s, s.it.last) end end
    r:SetScript("OnClick", function(s)
        state.view = "items"
        state.search = (s.it.rec and s.it.rec.short) or ((s.it.who or ""):match("^([^%-]+)") or "")
        UI:Refresh()
    end)
    return r
end

local function playerUpdate(r, it)
    r.it = it
    r.who:SetText(it.rec and PGM.ColorName(it.rec) or whoText(it.who, it.class))
    local per = (it.raids and it.raids > 0) and ("%.1f"):format(it.items / it.raids) or "-"
    local values = { it.items, it.tokens, it.bonus, it.raids or "-", per }
    for i, fs in ipairs(r.cols) do fs:SetText(tostring(values[i])) end
    r.last:SetText(it.last and ("Last: " .. itemText(it.last)) or "")
end

-- ---- the page ----

local function header(p, cols)
    local h = CreateFrame("Frame", nil, p)
    h:SetPoint("TOPLEFT", 0, -88)
    h:SetPoint("TOPRIGHT", 0, -88)
    h:SetHeight(20)
    local bg = W.Solid(h, "BACKGROUND", C.panel)
    bg:SetAllPoints()
    for _, c in ipairs(cols) do
        local fs = W.FS(h, 11, C.text2, c[3])
        if c.right then
            fs:SetPoint("RIGHT", -6, 0)   -- over a column that hangs off the right edge
        else
            fs:SetPoint("LEFT", c[2], 0)
        end
        if c[4] then fs:SetWidth(c[4]) end
        fs:SetText(c[1])
    end
    return h
end

local function menuButton(p, width, title, list, key, after)
    local b = W.Button(p, "", width, 22, C.text2)
    b.fs:SetWidth(width - 10)
    b.fs:SetWordWrap(false)
    b:SetScript("OnClick", function(s)
        local entries = {}
        for _, o in ipairs(type(list) == "function" and list() or list) do
            entries[#entries + 1] = { o[2], checked = function() return state[key] == o[1] end,
                toggle = function()
                    state[key] = o[1]
                    if after then after() end
                    UI:Refresh()
                end }
        end
        W.Menu(s, title, entries)
    end)
    b.sync = function()
        local current = type(list) == "function" and list() or list
        b:SetLabel(trim(labelOf(current, state[key]), 18))
        b:SetAccent((state[key] ~= current[1][1]) and C.text or C.text2)
    end
    return b
end

local function teamList()
    local out = { { nil, "Any team" } }
    for _, t in ipairs(PGM:Teams()) do out[#out + 1] = { t.id, t.name } end
    return out
end

local function bossList()
    local seen, names = {}, {}
    for _, rec in ipairs(PGM:LootItems()) do
        if (state.kind == "all" or rec.kind == state.kind) then
            local b = rec.boss or "?"
            if not seen[b] then
                seen[b] = true
                names[#names + 1] = b
            end
        end
    end
    table.sort(names, function(a, b)
        if a == "?" then return false end
        if b == "?" then return true end
        return a < b
    end)
    local out = { { nil, "Any boss" } }
    for _, n in ipairs(names) do out[#out + 1] = { n, n == "?" and "Boss not known" or n } end
    return out
end

local function exportMenu(owner, p)
    W.Menu(owner, "Export what's showing", {
        { "PGM text (for another player's PGM)", function()
            UI:ShowExport("Loot export: paste into Import on another PGM", PGM:LootExportText(p.items or {}))
        end },
        { "CSV (for a spreadsheet)", function()
            UI:ShowExport("Loot CSV", PGM:LootCSV(p.items or {}))
        end },
    })
end

local function previewImport(text)
    if strtrim(text) == "" then return PGM.Hex(C.text3) .. "Paste a loot export from another player's PGM.|r", false end
    local list, err = PGM:ParseLootExport(text)
    if not list then return PGM.Hex(C.amber) .. err .. "|r", false end
    local new, known, people = 0, 0, {}
    local first, last
    for _, rec in ipairs(list) do
        if PGM:LootKnown(rec) then known = known + 1 else new = new + 1 end
        people[PGM.LootNameKey(rec.who)] = true
        first = math.min(first or rec.t, rec.t)
        last = math.max(last or rec.t, rec.t)
    end
    local n = 0
    for _ in pairs(people) do n = n + 1 end
    local lines = { ("%sAdds %d|r   %s%d already here|r"):format(PGM.Hex(C.jade), new, PGM.Hex(C.text2), known) }
    if first then
        lines[#lines + 1] = ("%d items for %d %s, %s to %s."):format(#list, n, n == 1 and "player" or "players",
            date("%b %d", first), date("%b %d", last))
    end
    return table.concat(lines, "\n\n"), new > 0
end

local function importMenu(owner)
    W.Menu(owner, "Import loot", {
        { "Paste a PGM loot export...", function()
            UI:ShowPasteBox({
                title = "Import loot",
                hint = "Paste a loot export from another player's PGM (Export, then PGM text). Items already here are skipped.",
                preview = previewImport,
                import = function(text)
                    local list = PGM:ParseLootExport(text)
                    local added, known = PGM:ImportLoot(list or {})
                    PGM.Print(("Loot: imported %d, %d were already here."):format(added, known))
                end,
            })
        end },
        { "Pull from MRT and VoidcoreAdvisor again", function()
            local a, b = PGM:PullLoot(true)
            if a == nil and b == nil then
                PGM.Print("Loot: neither MRT nor VoidcoreAdvisor is loaded.")
            else
                PGM.Print(("Loot: %s from MRT, %s bonus rolls from VoidcoreAdvisor (this character)."):format(
                    a and (a .. " new") or "not loaded", b and (b .. " new") or "not loaded"))
            end
        end },
    })
end

local function build(p)
    p.search = W.EditBox(p, 200, 24, "Search player, item or boss...")
    p.search:SetPoint("TOPLEFT")
    p.search.onChange = function(s)
        state.search = s:GetText() or ""
        p.itemList.offset, p.playerList.offset = 0, 0
        UI:Refresh()
    end
    p.viewItems = W.Chip(p, "Items", function()
        state.view = "items"
        UI:Refresh()
    end)
    p.viewItems:SetPoint("LEFT", p.search, "RIGHT", 10, 0)
    p.viewPlayers = W.Chip(p, "By player", function()
        state.view = "players"
        UI:Refresh()
    end)
    p.viewPlayers:SetPoint("LEFT", p.viewItems, "RIGHT", 6, 0)
    p.export = W.Button(p, "Export", 70, 24)
    p.export:SetPoint("TOPRIGHT")
    p.export:SetScript("OnClick", function(s) exportMenu(s, p) end)
    p.import = W.Button(p, "Import", 70, 24)
    p.import:SetPoint("RIGHT", p.export, "LEFT", -6, 0)
    p.import:SetScript("OnClick", function(s) importMenu(s) end)

    -- The filters, as menus showing what each is set to.
    p.menus = {
        menuButton(p, 92, "When", WHEN, "when"),
        menuButton(p, 92, "Raids or M+", KIND, "kind", function() state.boss = nil end),
        menuButton(p, 104, "Team", teamList, "team"),
        menuButton(p, 120, "Boss", bossList, "boss"),
        menuButton(p, 100, "Difficulty", DIFF, "diff"),
        menuButton(p, 100, "Item type", ITYPE, "itype"),
        menuButton(p, 104, "Drops or bonus rolls", HOW, "how"),
    }
    local prev
    for _, b in ipairs(p.menus) do
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("TOPLEFT", 0, -30) end
        prev = b
    end

    -- Shortcuts.
    p.mine = W.Chip(p, "Mine", function()
        state.mine = not state.mine
        UI:Refresh()
    end)
    p.mine:SetPoint("TOPLEFT", 0, -60)
    p.myBonus = W.Chip(p, "My bonus rolls", function()
        local on = not (state.mine and state.how == "bonus")
        state.mine, state.how = on, on and "bonus" or nil
        if on then state.when, state.kind, state.view = "all", "all", "items" end
        UI:Refresh()
    end)
    p.myBonus:SetPoint("LEFT", p.mine, "RIGHT", 6, 0)
    p.tokens = W.Chip(p, "Tier tokens", function()
        state.itype = state.itype ~= "token" and "token" or nil
        UI:Refresh()
    end)
    p.tokens:SetPoint("LEFT", p.myBonus, "RIGHT", 6, 0)
    p.alts = W.Chip(p, "Alts as main", function()
        state.altsAsMain = not state.altsAsMain
        UI:Refresh()
    end)
    p.alts:SetPoint("LEFT", p.tokens, "RIGHT", 6, 0)
    p.clear = W.Button(p, "Clear filters", 96, 22, C.text2)
    p.clear:SetPoint("LEFT", p.alts, "RIGHT", 10, 0)
    p.clear:SetScript("OnClick", function()
        state.search, state.when, state.kind, state.team, state.boss = "", "all", "raid", nil, nil
        state.diff, state.itype, state.how, state.mine = nil, nil, nil, false
        p.search:SetText("")
        UI:Refresh()
    end)
    p.count = W.FS(p, 11, C.text3, "RIGHT")
    p.count:SetPoint("TOPRIGHT", 0, -64)

    p.itemHeader = header(p, { { "Date", 6 }, { "Boss", 62 }, { "Diff", 216 }, { "Player", 254 }, { "Item", 382 },
        { "How", 0, "RIGHT", right = true } })
    p.playerHeader = header(p, { { "Player", 6 }, { "Items", 160, "RIGHT", 52 }, { "Tokens", 220, "RIGHT", 52 },
        { "Bonus", 280, "RIGHT", 52 }, { "Raids", 340, "RIGHT", 52 }, { "Per raid", 400, "RIGHT", 52 },
        { "Last item", 470 } })

    p.itemList = W.List(p, 22, itemRow, itemUpdate)
    p.itemList:SetPoint("TOPLEFT", 0, -110)
    p.itemList:SetPoint("BOTTOMRIGHT")
    p.playerList = W.List(p, 22, playerRow, playerUpdate)
    p.playerList:SetPoint("TOPLEFT", 0, -110)
    p.playerList:SetPoint("BOTTOMRIGHT")

    p.empty = W.FS(p, 12, C.text3, "CENTER")
    p.empty:SetPoint("CENTER", p.itemList, "CENTER")
    p.empty:SetWidth(520)
    p.empty:SetWordWrap(true)
end

local function refresh(p)
    -- A team that's gone isn't a filter any more.
    if state.team and not PGM:TeamById(state.team) then state.team = nil end
    if not p.search:HasFocus() and (p.search:GetText() or "") ~= state.search then p.search:SetText(state.search) end
    for _, b in ipairs(p.menus) do b.sync() end
    p.viewItems:SetActive(state.view == "items")
    p.viewPlayers:SetActive(state.view == "players")
    p.mine:SetActive(state.mine)
    p.myBonus:SetActive(state.mine and state.how == "bonus")
    p.tokens:SetActive(state.itype == "token")
    p.alts:SetActive(state.altsAsMain)
    p.alts:SetShown(state.view == "players")

    p.items = filtered()
    local players = state.view == "players"
    p.itemHeader:SetShown(not players)
    p.itemList:SetShown(not players)
    p.playerHeader:SetShown(players)
    p.playerList:SetShown(players)
    if players then
        local rows = byPlayer(p.items)
        p.playerList:SetData(rows, true)
        p.count:SetText(("%d players, %d items"):format(#rows, #p.items))
    else
        p.itemList:SetData(p.items, true)
        p.count:SetText(#p.items .. (#p.items == 1 and " item" or " items"))
    end
    if #PGM:LootItems() == 0 then
        p.empty:SetText("No loot yet.\n\nRaid drops and bonus rolls are recorded as they happen. MRT's loot history and VoidcoreAdvisor's bonus rolls come in at login, or use Import.")
    elseif #p.items == 0 then
        p.empty:SetText("Nothing matches these filters.")
    else
        p.empty:SetText("")
    end
end

UI:AddTab({ id = "loot", label = "Loot", build = build, refresh = refresh })

PGM:On("LOOT", function() UI:QueueRefresh() end)
-- Item names arrive from the server a moment after first asked for.
PGM:RegisterEvent("GET_ITEM_INFO_RECEIVED", function()
    if UI.current == "loot" and UI.frame and UI.frame:IsShown() then UI:QueueRefresh() end
end)
