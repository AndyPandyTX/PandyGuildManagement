-- Loot.lua (UI): the Loot page. Every raid drop and bonus roll this account
-- has recorded or imported (Loot.lua), with filters that all combine: when,
-- raid or M+, team, boss, difficulty, item type, drops or bonus rolls, and a
-- search for a player, item or boss. Two views: the items, or one row per
-- player with counts. Click a column's heading to sort by it. Export what's
-- showing, in the order it's showing, or import someone's export.

local _, NS = ...
local PGM = NS.PGM
local C = PGM.C
local UI = PGM.UI
local W = UI.W

-- when = "range" uses from and to: days as "2026-10-21" (either may be nil,
-- for no limit that side). sort and desc are per view.
local state = {
    search = "", when = "all", from = nil, to = nil, kind = "raid", team = nil, boss = nil, diff = nil,
    itype = nil, how = nil, mine = false, view = "items", altsAsMain = true,
    sort = { items = "date", players = "items" }, desc = { items = true, players = true },
}

local WHEN = { { "all", "All time" }, { "week", "This week" }, { "month", "Last 4 weeks" }, { "3m", "Last 3 months" } }
local KIND = { { "raid", "Raids" }, { "mplus", "Mythic+" }, { "all", "Raids + M+" } }
local DIFF = { { nil, "Any difficulty" }, { 17, "LFR" }, { 14, "Normal" }, { 15, "Heroic" }, { 16, "Mythic" } }
local ITYPE = { { nil, "Any item" }, { "token", "Tier tokens" }, { "weapon", "Weapons" }, { "trinket", "Trinkets" },
    { "jewelry", "Rings and necks" }, { "armor", "Armor" }, { "other", "Other" } }
local HOW = { { nil, "Drops + bonus" }, { "drop", "Drops only" }, { "bonus", "Bonus only" } }
local SHORT_DIFF = { [17] = "LFR", [14] = "N", [15] = "H", [16] = "M" }

local function labelOf(list, value)
    for _, o in ipairs(list) do
        if o[1] == value then return o[2] end
    end
    return list[1][2]
end

-- At most n letters, cut between letters (an accented letter is two or
-- more bytes).
local function trim(text, n)
    local letters, cut = 0, nil
    for pos in text:gmatch("()[^\128-\191]") do
        letters = letters + 1
        if letters == n then cut = pos break end
    end
    if not cut then return text end
    return text:sub(1, cut - 1) .. "…"
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

local function dayKey(t) return date("%Y-%m-%d", t or 0) end

-- "2026-10-21" back to a time, at noon that day.
local function dayTime(day)
    local y, m, d = day:match("^(%d+)-(%d+)-(%d+)$")
    return time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })
end

-- A test for whether a time is inside the When filter. Ranges go by the
-- day shown on each row.
local function windowTest()
    if state.when == "range" then
        local from, to = state.from, state.to
        return function(t)
            local day = dayKey(t)
            return (not from or day >= from) and (not to or day <= to)
        end
    end
    local from = since()
    return function(t) return (t or 0) >= from end
end

-- "Oct 21-28", "Sep 30-Oct 28", "Oct 28", "Since Oct 21" or "Until Oct 28".
local function rangeLabel()
    local from, to = state.from, state.to
    local function short(day) return (date("%b %d", dayTime(day)):gsub(" 0", " ")) end
    if from and to then
        if from == to then return short(from) end
        if from:sub(1, 7) == to:sub(1, 7) then return short(from) .. "-" .. tonumber(to:sub(9)) end
        return short(from) .. "-" .. short(to)
    end
    if from then return "Since " .. short(from) end
    if to then return "Until " .. short(to) end
    return "All time"
end

-- The When menu: the quick choices, then one day, From and To, each a
-- submenu of months and the days in them that have loot (newest first).
local function whenMenu()
    local counts, days = {}, {}
    for _, rec in ipairs(PGM:LootItems()) do
        if state.kind == "all" or rec.kind == state.kind then
            local day = dayKey(rec.t)
            if not counts[day] then days[#days + 1] = day end
            counts[day] = (counts[day] or 0) + 1
        end
    end
    table.sort(days, function(a, b) return a > b end)
    local function dayMenu(isChecked, pick)
        local months, byMonth = {}, {}
        for _, day in ipairs(days) do
            local month = day:sub(1, 7)
            if not byMonth[month] then
                byMonth[month] = {}
                months[#months + 1] = { month, date("%B %Y", dayTime(day)) }
            end
            table.insert(byMonth[month], { date("%a %b %d", dayTime(day)) .. "  (" .. counts[day] .. ")",
                checked = function() return state.when == "range" and isChecked(day) end,
                toggle = function()
                    state.when = "range"
                    pick(day)
                    UI:Refresh()
                end })
        end
        local list = {}
        for _, m in ipairs(months) do list[#list + 1] = { m[2], sub = byMonth[m[1]] } end
        return list
    end
    local entries = {}
    for _, o in ipairs(WHEN) do
        entries[#entries + 1] = { o[2], checked = function() return state.when == o[1] end,
            toggle = function()
                state.when, state.from, state.to = o[1], nil, nil
                UI:Refresh()
            end }
    end
    if #days > 0 then
        entries[#entries + 1] = { divider = true }
        entries[#entries + 1] = { "One day", sub = dayMenu(
            function(day) return state.from == day and state.to == day end,
            function(day) state.from, state.to = day, day end) }
        entries[#entries + 1] = { "From", sub = dayMenu(
            function(day) return state.from == day end,
            function(day)
                state.from = day
                if state.to and state.to < day then state.to = nil end
            end) }
        entries[#entries + 1] = { "To", sub = dayMenu(
            function(day) return state.to == day end,
            function(day)
                state.to = day
                if state.from and state.from > day then state.from = nil end
            end) }
    end
    return entries
end

local function whenLabel(when)
    if when == "range" then return rangeLabel() end
    return labelOf(WHEN, when)
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

-- ---- bosses, by tier ----
-- The boss filter is an encounter id, a whole tier ("tier:1", "tier:old"
-- for raids in no tier, "tier:mplus" for M+), "?" for loot with no boss
-- known, or a boss name for records that only have a name.

local function bossKey(rec)
    if rec.enc and rec.enc ~= 0 then return rec.enc end
    return rec.boss or "?"
end

local function bossMatches(rec, want)
    if not want then return true end
    local tier = type(want) == "string" and want:match("^tier:(.+)$")
    if tier == "mplus" then return rec.kind == "mplus" end
    if tier == "old" then return rec.kind == "raid" and PGM.LootTierOf(rec.enc) == nil end
    if tier then return PGM.LootTierOf(rec.enc) == tonumber(tier) end
    return bossKey(rec) == want
end

-- Every boss with loot here: key -> { name, tier, raid, kind }. A boss's
-- raid is its tier's raid, or the place its loot was recorded most.
local function bossesWithLoot()
    local out, places = {}, {}
    for _, rec in ipairs(PGM:LootItems()) do
        local key = bossKey(rec)
        local b = out[key]
        if not b then
            local tier, raid = PGM.LootTierOf(rec.enc)
            b = { key = key, name = rec.boss or PGM:LootBossName(rec.enc), tier = tier, raid = raid, kind = rec.kind }
            out[key] = b
            places[key] = {}
        end
        b.name = b.name or rec.boss
        if rec.where then places[key][rec.where] = (places[key][rec.where] or 0) + 1 end
    end
    for key, b in pairs(out) do
        if not b.raid then
            local best, n = nil, 0
            for place, c in pairs(places[key]) do
                if c > n then best, n = place, c end
            end
            b.raid = best or "Other"
        end
    end
    return out
end

local function bossLabel(want)
    if not want then return "Any boss" end
    if want == "?" then return "Boss not known" end
    local tier = type(want) == "string" and want:match("^tier:(.+)$")
    if tier == "mplus" then return "All Mythic+" end
    if tier == "old" then return "All older raids" end
    if tier then return (PGM.LOOT_TIERS[tonumber(tier)] or {}).name or "Tier" end
    local b = bossesWithLoot()[want]
    return b and b.name or tostring(want)
end

-- The Boss menu: the current tier's bosses right there, by raid; earlier
-- tiers, older raids and M+ dungeons as submenus.
local function bossMenu()
    local bosses = bossesWithLoot()
    local function pick(value, label)
        return { label, checked = function() return state.boss == value end,
            toggle = function()
                state.boss = value
                UI:Refresh()
            end }
    end
    local function tierEntries(i, tier)
        local list = { pick("tier:" .. i, "All of " .. tier.name) }
        for _, raid in ipairs(tier.raids) do
            local shown = {}
            for _, enc in ipairs(raid.bosses) do
                local b = bosses[enc]
                if b and b.name then shown[#shown + 1] = pick(enc, b.name) end
            end
            if #shown > 0 then
                list[#list + 1] = { raid.name, title = true }
                for _, e in ipairs(shown) do list[#list + 1] = e end
            end
        end
        return list
    end
    -- Raids in no tier, and M+ dungeons, by place.
    local function byPlace(kind, allValue, allLabel)
        local places, order = {}, {}
        for _, b in pairs(bosses) do
            if b.kind == kind and not b.tier and b.key ~= "?" then
                if not places[b.raid] then
                    places[b.raid] = {}
                    order[#order + 1] = b.raid
                end
                table.insert(places[b.raid], b)
            end
        end
        if #order == 0 then return nil end
        table.sort(order)
        local list = { pick(allValue, allLabel) }
        for _, place in ipairs(order) do
            list[#list + 1] = { place, title = true }
            table.sort(places[place], function(a, b) return (a.name or "") < (b.name or "") end)
            for _, b in ipairs(places[place]) do list[#list + 1] = pick(b.key, b.name or tostring(b.key)) end
        end
        return list
    end

    local entries = { pick(nil, "Any boss") }
    local current = PGM.LOOT_TIERS[1]
    if current and state.kind ~= "mplus" then
        entries[#entries + 1] = { divider = true }
        entries[#entries + 1] = { current.name, title = true }
        for _, e in ipairs(tierEntries(1, current)) do entries[#entries + 1] = e end
    end
    entries[#entries + 1] = { divider = true }
    if state.kind ~= "mplus" then
        for i = 2, #PGM.LOOT_TIERS do
            entries[#entries + 1] = { PGM.LOOT_TIERS[i].name, sub = tierEntries(i, PGM.LOOT_TIERS[i]) }
        end
        local old = byPlace("raid", "tier:old", "All older raids")
        if old then entries[#entries + 1] = { "Older raids", sub = old } end
    end
    if state.kind ~= "raid" then
        local mplus = byPlace("mplus", "tier:mplus", "All Mythic+")
        if mplus then entries[#entries + 1] = { "Mythic+", sub = mplus } end
    end
    if bosses["?"] then entries[#entries + 1] = pick("?", "Boss not known") end
    return entries
end

local function itemName(rec)
    local name = C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(rec.link)
    return name
end

-- ---- sorting ----
-- Each column's sort key, and the way it sorts first (the rest A to Z).

local DIFF_RANK = { [17] = 1, [14] = 2, [15] = 3, [16] = 4 }

local function bossText(rec)
    if rec.kind == "mplus" then return rec.where or rec.boss or "Mythic+" end
    return rec.boss or "?"
end

local ITEM_KEY = {
    date = function(r) return r.t or 0 end,
    boss = function(r) return PGM.SortKey(bossText(r)) end,
    diff = function(r) return r.kind == "mplus" and 5 or (DIFF_RANK[r.diff] or 0) end,
    who = function(r) return PGM.SortKey(r.who) end,
    -- Names not loaded yet go last; they move up when the game sends them.
    item = function(r) return PGM.SortKey(itemName(r) or "\255") end,
    how = function(r) return PGM.SortKey(PGM.LOOT_HOW_LABEL[r.how] or r.how) end,
}
local PLAYER_KEY = {
    who = function(it) return PGM.SortKey(it.rec and it.rec.short or it.who) end,
    items = function(it) return it.items end,
    tokens = function(it) return it.tokens end,
    bonus = function(it) return it.bonus end,
    raids = function(it) return it.raids or -1 end,
    per = function(it) return (it.raids and it.raids > 0) and it.items / it.raids or -1 end,
    last = function(it) return it.last and it.last.t or 0 end,
}
local DESC_FIRST = { date = true, diff = true, items = true, tokens = true, bonus = true, raids = true,
    per = true, last = true }

-- Sorts list in place by the view's column; ties go newest first, then by
-- name, so the order never shifts on its own.
local function sortList(list, view, keys, tie)
    local key = keys[state.sort[view]]
    local desc = state.desc[view]
    local k = {}
    for _, v in ipairs(list) do k[v] = key(v) end
    table.sort(list, function(a, b)
        if k[a] ~= k[b] then
            if desc then return k[a] > k[b] end
            return k[a] < k[b]
        end
        return tie(a, b)
    end)
end

local function itemTie(a, b)
    if (a.t or 0) ~= (b.t or 0) then return (a.t or 0) > (b.t or 0) end
    if a.who ~= b.who then return PGM.NameLess(a.who, b.who) end
    return (a.id or 0) < (b.id or 0)
end

local function playerTie(a, b) return PGM.NameLess(a.who, b.who) end

-- A heading clicked: sort by it, or flip it if it's sorting already.
local function sortBy(view, key)
    if state.sort[view] == key then
        state.desc[view] = not state.desc[view]
    else
        state.sort[view], state.desc[view] = key, DESC_FIRST[key] or false
    end
    UI:Refresh()
end

local function filtered()
    local out = {}
    local inWindow = windowTest()
    local mine = state.mine and myKeys()
    local q = state.search:lower()
    for _, rec in ipairs(PGM:LootItems()) do
        local ok = inWindow(rec.t)
            and (state.kind == "all" or rec.kind == state.kind)
            and (not state.diff or rec.diff == state.diff)
            and (not state.how or (state.how == "bonus") == (rec.how == "bonus"))
            and bossMatches(rec, state.boss)
            and (not state.itype or PGM.LootType(rec.id) == state.itype)
            and (not mine or mine[PGM.LootNameKey(rec.who)])
        if ok and state.team then
            local night = PGM:LootNight(rec)
            ok = night ~= nil and night.team == state.team
        end
        if ok and q ~= "" then
            ok = (rec.who or ""):lower():find(q, 1, true) or (rec.boss or ""):lower():find(q, 1, true)
                or (rec.where or ""):lower():find(q, 1, true)
                or (itemName(rec) or ""):lower():find(q, 1, true)
        end
        if ok then out[#out + 1] = rec end
    end
    sortList(out, "items", ITEM_KEY, itemTie)
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
    local inWindow = windowTest()
    for _, it in ipairs(order) do
        if it.guid and g then
            local group = PGM:GroupOf(it.guid)
            local n = 0
            for _, s in ipairs(g.raids and g.raids.sessions or {}) do
                if inWindow(s.start) and (not state.team or s.team == state.team) then
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
    sortList(order, "players", PLAYER_KEY, playerTie)
    return order
end

-- ---- rows ----

local function whoText(who, class)
    if not class then
        -- Imports don't always say; guild members' come from the roster.
        local g, guid = PGM.GuildDB(), PGM.LootMemberGuid(who)
        class = guid and g and g.members[guid] and g.members[guid].class
    end
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
                    state.boss = bossKey(rec)
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
    -- M+ shows the dungeon; a raid, the boss.
    r.boss:SetText(bossText(rec))
    r.diff:SetText(rec.kind == "mplus" and "M+" or (SHORT_DIFF[rec.diff] or ""))
    r.who:SetText(whoText(rec.who, rec.class))
    r.item:SetText(itemText(rec))
    local how = PGM.LOOT_HOW_LABEL[rec.how] or rec.how or ""
    if rec.roll then how = how .. " " .. rec.roll end
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

-- The column headings for a view: { label, x, justify, width, key }. Each
-- is a button sorting by its key; the one sorting has an arrow.
local function header(p, view, cols)
    local h = CreateFrame("Frame", nil, p)
    h:SetPoint("TOPLEFT", 0, -88)
    h:SetPoint("TOPRIGHT", 0, -88)
    h:SetHeight(20)
    local bg = W.Solid(h, "BACKGROUND", C.panel)
    bg:SetAllPoints()
    h.cols = {}
    for _, c in ipairs(cols) do
        local b = CreateFrame("Button", nil, h)
        b:SetSize(c[4], 20)
        if c.right then
            b:SetPoint("RIGHT", -6, 0)   -- over a column that hangs off the right edge
        else
            b:SetPoint("LEFT", c[2], 0)
        end
        b.fs = W.FS(b, 11, C.text2, c[3])
        b.fs:SetAllPoints()
        b.label, b.key = c[1], c[5]
        b.onClick = function() sortBy(view, b.key) end
        b:SetScript("OnClick", b.onClick)
        b:SetScript("OnEnter", function(s) s.fs:SetTextColor(C.text[1], C.text[2], C.text[3]) end)
        b:SetScript("OnLeave", function() h:Update() end)
        h.cols[#h.cols + 1] = b
    end
    function h:Update()
        for _, b in ipairs(self.cols) do
            local on = state.sort[view] == b.key
            b.fs:SetText(on and (b.label .. (state.desc[view] and " v" or " ^")) or b.label)
            local col = on and C.accent or C.text2
            b.fs:SetTextColor(col[1], col[2], col[3])
        end
    end
    return h
end

-- A filter button showing its current choice. `list` is { value, label }
-- pairs (or a function giving them); or `custom` = { menu = fn() giving
-- menu entries, label = fn(value), default = the value that isn't
-- filtering }, for a menu with headings and submenus.
local function menuButton(p, width, title, list, key, after, custom)
    local b = W.Button(p, "", width, 22, C.text2)
    b.fs:SetWidth(width - 10)
    b.fs:SetWordWrap(false)
    b:SetScript("OnClick", function(s)
        if custom then
            W.Menu(s, title, custom.menu())
            return
        end
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
        if custom then
            b:SetLabel(trim(custom.label(state[key]), 18))
            b:SetAccent(state[key] ~= custom.default and C.text or C.text2)
            return
        end
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
    local new, known, skipped, people = 0, 0, 0, {}
    local first, last
    for _, rec in ipairs(list) do
        local would = PGM:LootWouldAdd(rec)
        if would == "new" then new = new + 1 elseif would == "known" then known = known + 1 else skipped = skipped + 1 end
        people[PGM.LootNameKey(rec.who)] = true
        first = math.min(first or rec.t, rec.t)
        last = math.max(last or rec.t, rec.t)
    end
    local n = 0
    for _ in pairs(people) do n = n + 1 end
    local lines = { ("%sAdds %d|r   %s%d already here|r"):format(PGM.Hex(C.jade), new, PGM.Hex(C.text2), known)
        .. (skipped > 0 and ("   " .. PGM.Hex(C.text3) .. skipped .. " not kept (junk, or deleted here)|r") or "") }
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
                    local added, known, skipped = PGM:ImportLoot(list or {})
                    PGM.Print(("Loot: imported %d, %d were already here%s."):format(added, known,
                        skipped > 0 and (", " .. skipped .. " not kept") or ""))
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
        menuButton(p, 100, "When", nil, "when", nil, { menu = whenMenu, label = whenLabel, default = "all" }),
        menuButton(p, 92, "Raids or M+", KIND, "kind", function() state.boss = nil end),
        menuButton(p, 104, "Team", teamList, "team"),
        menuButton(p, 120, "Boss", nil, "boss", nil, { menu = bossMenu, label = bossLabel }),
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
        state.search, state.when, state.from, state.to = "", "all", nil, nil
        state.kind, state.team, state.boss = "raid", nil, nil
        state.diff, state.itype, state.how, state.mine = nil, nil, nil, false
        p.search:SetText("")
        UI:Refresh()
    end)
    p.count = W.FS(p, 11, C.text3, "RIGHT")
    p.count:SetPoint("TOPRIGHT", 0, -64)

    p.itemHeader = header(p, "items", { { "Date", 6, nil, 52, "date" }, { "Boss", 62, nil, 150, "boss" },
        { "Diff", 216, nil, 36, "diff" }, { "Player", 254, nil, 124, "who" }, { "Item", 382, nil, 200, "item" },
        { "How", 0, "RIGHT", 96, "how", right = true } })
    p.playerHeader = header(p, "players", { { "Player", 6, nil, 150, "who" },
        { "Items", 160, "RIGHT", 52, "items" }, { "Tokens", 220, "RIGHT", 52, "tokens" },
        { "Bonus", 280, "RIGHT", 52, "bonus" }, { "Raids", 340, "RIGHT", 52, "raids" },
        { "Per raid", 400, "RIGHT", 52, "per" }, { "Last item", 470, nil, 200, "last" } })

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

    p.itemHeader:Update()
    p.playerHeader:Update()
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
