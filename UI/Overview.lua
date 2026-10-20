-- Overview.lua: the guild at a glance.

local _, NS = ...
local PGM = NS.PGM
local C = PGM.C
local UI = PGM.UI
local W = UI.W

local GAP = 12

-- A headline number: framed icon, small label, big
-- gold value, quiet note.
local function tile(parent, label, icon)
    local t = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    W.Backdrop(t, C.card, C.cardLine, 0.98)
    t:SetHeight(70)
    if icon and GetFileIDFromPath and not GetFileIDFromPath(icon) then icon = nil end
    local x = 12
    if icon then
        t.icon = W.FramedIcon(t, 40, icon)
        t.icon:SetPoint("LEFT", 9, 0)
        x = 58
    end
    t.label = W.FS(t, 10, C.text2)
    t.label:SetPoint("TOPLEFT", x, -11)
    t.label:SetText(label:upper())
    t.value = W.FS(t, 22, C.accent)
    t.value:SetPoint("TOPLEFT", x, -25)
    t.note = W.FS(t, 10, C.text3)
    t.note:SetPoint("BOTTOMLEFT", x, 9)
    t.note:SetPoint("BOTTOMRIGHT", -8, 9)
    return t
end

-- Eight weeks of joins (up) against leaves (down).
local function trendCard(parent)
    local card = W.Card(parent, "Joins and leaves", "Per week, last 8 weeks. Green joined, red left.")
    card:SetHeight(182)
    card.cols = {}
    for i = 1, 8 do
        local col = {}
        col.up = W.Solid(card, "ARTWORK", C.jade, 0.9)
        col.down = W.Solid(card, "ARTWORK", C.red, 0.9)
        col.label = W.FS(card, 9, C.text3, "CENTER")
        col.n = W.FS(card, 9, C.jade, "CENTER")    -- joins, above the green bar
        col.m = W.FS(card, 9, C.red, "CENTER")     -- leaves, below the red bar
        card.cols[i] = col
    end
    card.axis = W.Divider(card)
    function card:SetTrend(trend)
        local w = self:GetWidth() - 24
        if w <= 0 then return end
        local slot = w / 8
        local peak = 1
        for _, t in ipairs(trend) do peak = math.max(peak, t.joins, t.leaves) end
        local mid, half = -100, 38
        self.axis:ClearAllPoints()
        self.axis:SetPoint("TOPLEFT", 12, mid)
        self.axis:SetPoint("TOPRIGHT", -12, mid)
        for i, t in ipairs(trend) do
            local col = self.cols[i]
            local x = 12 + (i - 1) * slot + slot * 0.25
            local bw = slot * 0.5
            local up = math.max(1, half * t.joins / peak)
            local down = math.max(1, half * t.leaves / peak)
            col.up:ClearAllPoints()
            col.up:SetPoint("BOTTOMLEFT", self, "TOPLEFT", x, mid)
            col.up:SetSize(bw, up)
            col.up:SetShown(t.joins > 0)
            col.down:ClearAllPoints()
            col.down:SetPoint("TOPLEFT", self, "TOPLEFT", x, mid - 1)
            col.down:SetSize(bw, down)
            col.down:SetShown(t.leaves > 0)
            col.n:ClearAllPoints()
            col.n:SetPoint("BOTTOM", self, "TOPLEFT", x + bw / 2, mid + up + 2)
            col.n:SetText(t.joins > 0 and ("+" .. t.joins) or "")
            col.m:ClearAllPoints()
            col.m:SetPoint("TOP", self, "TOPLEFT", x + bw / 2, mid - 1 - down - 2)
            col.m:SetText(t.leaves > 0 and ("-" .. t.leaves) or "")
            col.label:ClearAllPoints()
            col.label:SetPoint("TOP", self, "TOPLEFT", x + bw / 2, -160)
            col.label:SetText(i == 8 and "now" or ((8 - i) .. "w"))
        end
    end
    return card
end

local function build(p)
    -- Scope controls.
    p.scopeChips = {}
    local scopes = { { "all", "Everyone" }, { "max", "Max level" }, { "active", "Active 30d" } }
    local prev
    for _, s in ipairs(scopes) do
        local chip = W.Chip(p, s[2], function()
            PGM.setOpt("overviewScope", s[1])
            UI:Refresh()
        end)
        chip.scope = s[1]
        if prev then chip:SetPoint("LEFT", prev, "RIGHT", 6, 0) else chip:SetPoint("TOPLEFT", 0, 0) end
        p.scopeChips[#p.scopeChips + 1] = chip
        prev = chip
    end
    p.mains = W.Chip(p, "Mains only", function()
        PGM.setOpt("overviewMainsOnly", not PGM.opt("overviewMainsOnly"))
        UI:Refresh()
    end)
    p.mains:SetPoint("LEFT", prev, "RIGHT", 16, 0)

    p.export = W.Button(p, "Export CSV", 96, 22)
    p.export:SetPoint("TOPRIGHT", 0, 0)
    p.export:SetScript("OnClick", function()
        UI:ShowExport("Guild overview CSV", PGM:OverviewCSV(p.data))
    end)

    p.scroll = W.Scroll(p)
    p.scroll:SetPoint("TOPLEFT", 0, -34)
    p.scroll:SetPoint("BOTTOMRIGHT", 0, 0)
    local body = p.scroll.child

    p.tiles = {
        tile(body, "Members", "Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend"),
        tile(body, "Active this week", "Interface\\Icons\\INV_Misc_PocketWatch_01"),
        tile(body, "At max level", "Interface\\Icons\\Achievement_Level_90"),
        tile(body, "Vitality", "Interface\\Icons\\Spell_Nature_Rejuvenation"),
    }

    p.classes = W.Card(body, "Class mix", "Members per class. Hover for how many are at max level.")
    -- A breakdown strip across the top of the card.
    p.classes.seg = W.SegmentBar(p.classes)
    p.classes.seg:SetPoint("TOPLEFT", 16, -46)
    p.classes.seg:SetPoint("TOPRIGHT", -14, -46)
    p.classes.top = 70
    p.levels = W.Card(body, "Level spread", "", C.blue)
    p.activity = W.Card(body, "Activity", "Last seen by the guild roster.", C.jade)
    p.ranks = W.Card(body, "Ranks", "Per rank. Orange: away 30+ days.", C.purple)
    p.mplus = W.Card(body, "Mythic+ at max level", "Blizzard's current score; RaiderIO fills gaps.")
    p.races = W.Card(body, "Race overview", "Members per race. Hover for average level and class mix.")
    p.races.seg = W.SegmentBar(p.races)
    p.races.seg:SetPoint("TOPLEFT", 16, -46)
    p.races.seg:SetPoint("TOPRIGHT", -14, -46)
    p.races.top = 70
    p.profs = W.Card(body, "Professions", "Members with each profession. Hover for who's online.")
    p.profs.emptyText = "No profession data yet. Open the guild window (J) once if this stays empty."
    p.zones = W.Card(body, "Where everyone is", "Online members by zone.", C.jade)
    p.zones.emptyText = "Nobody online right now."
    p.trend = trendCard(body)
end

local function layout(p)
    local body = p.scroll.child
    local width = body:GetWidth()
    if not width or width < 100 then width = p:GetWidth() - 10 end

    local tw = (width - GAP * 3) / 4
    for i, t in ipairs(p.tiles) do
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", (i - 1) * (tw + GAP), 0)
        t:SetWidth(tw)
    end

    -- Two columns, each card stacked under the last.
    local cw = (width - GAP) / 2
    local left = { p.classes, p.races, p.ranks, p.trend }
    local right = { p.levels, p.activity, p.profs }
    if p.data and p.data.mplus then table.insert(right, p.mplus) p.mplus:Show() else p.mplus:Hide() end
    table.insert(right, p.zones)
    local function stack(cards, x)
        local y = -(70 + GAP)
        for _, card in ipairs(cards) do
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", x, y)
            card:SetWidth(cw)
            y = y - card:GetHeight() - GAP
        end
        return -y
    end
    local hl = stack(left, 0)
    local hr = stack(right, cw + GAP)
    body:SetHeight(math.max(hl, hr))
end

local function refresh(p)
    local scope = PGM.opt("overviewScope") or "all"
    local mainsOnly = PGM.opt("overviewMainsOnly") and true or false
    for _, chip in ipairs(p.scopeChips) do chip:SetActive(chip.scope == scope) end
    p.mains:SetActive(mainsOnly)

    -- The page has no size on its very first paint; lay out again once it does.
    if not p.sizeHooked then
        p.sizeHooked = true
        p.scroll:HookScript("OnSizeChanged", function()
            if p.data then
                layout(p)
                p.trend:SetTrend(p.data.trend)
            end
        end)
    end

    local o = PGM:ComputeOverview(scope, mainsOnly)
    p.data = o
    local max = PGM.MaxLevel()

    local t = p.tiles
    t[1].value:SetText(o.total)
    t[1].note:SetText(("%d online, %d alts"):format(o.online, o.alts))
    t[2].value:SetText(o.active7)
    t[2].note:SetText(o.total > 0 and ("%d%% of guild"):format(o.active7 / o.total * 100 + 0.5) or "")
    t[3].value:SetText(o.atMax)
    t[3].note:SetText(("Level %d"):format(max))
    local vcol = o.vitality >= 70 and C.jade or (o.vitality >= 40 and C.gold or C.red)
    t[4].value:SetText(PGM.Hex(vcol) .. o.vitality .. "|r" .. PGM.Hex(C.text3) .. " / 100|r")
    t[4].note:SetText(("%d this month"):format(o.active30))
    t[4]:EnableMouse(true)
    t[4]:SetScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Vitality")
        GameTooltip:AddLine("Each member counts by how recently they were online: this week 100%, last week 70%, this month 40%, 30-59 days 10%, longer 0%. The score is the average.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    t[4]:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Class mix.
    local peak = 1
    for _, c in ipairs(o.classes) do peak = math.max(peak, c.count) end
    local items, parts = {}, {}
    for _, c in ipairs(o.classes) do
        local r, g, b = PGM.ClassColor(c.class)
        local col = { r, g, b }
        parts[#parts + 1] = { value = c.count, col = col,
            tip = { PGM.ClassHex(c.class) .. PGM.ClassName(c.class) .. "|r", ("%d members (%d%%)"):format(c.count, o.total > 0 and c.count / o.total * 100 + 0.5 or 0) } }
        items[#items + 1] = {
            label = PGM.ClassIconMarkup(c.class, 14) .. " " .. PGM.ClassName(c.class), labelCol = col, col = col,
            value = c.count, max = peak,
            valueText = c.count .. PGM.Hex(C.text3) .. (" (%d%%)"):format(o.total > 0 and c.count / o.total * 100 + 0.5 or 0) .. "|r",
            tip = { PGM.ClassName(c.class), ("%d members, %d at max level"):format(c.count, c.atMax) },
        }
    end
    p.classes:SetBars(items, 120)
    p.classes.seg:SetParts(parts)

    -- Levels.
    p.levels.sub:SetText(o.atMax == o.total and o.total > 0 and "Everyone here is at max level."
        or ("Midnight's cap is %d."):format(max))
    peak = 1
    for _, l in ipairs(o.levels) do peak = math.max(peak, l.count) end
    items = {}
    for i, l in ipairs(o.levels) do
        items[#items + 1] = { label = l.label, value = l.count, max = peak, col = i == 1 and C.jade or C.blue }
    end
    p.levels:SetBars(items, 90)

    -- Activity.
    peak = 1
    for _, a in ipairs(o.activity) do peak = math.max(peak, a.count) end
    items = {}
    for _, a in ipairs(o.activity) do
        items[#items + 1] = { label = a.label, value = a.count, max = peak, col = a.col }
    end
    if o.unknownActivity > 0 then
        items[#items + 1] = { label = "Unknown", value = o.unknownActivity, max = peak, col = C.text3 }
    end
    p.activity:SetBars(items, 110)

    -- Ranks.
    peak = 1
    for _, r in ipairs(o.ranks) do peak = math.max(peak, r.count) end
    items = {}
    for _, r in ipairs(o.ranks) do
        items[#items + 1] = {
            label = r.label, value = r.count, max = peak, col = C.purple,
            valueText = r.count .. (r.idle > 0 and (PGM.Hex(C.amber) .. " (" .. r.idle .. ")|r") or ""),
            tip = { r.label, ("%d members, %d away 30+ days"):format(r.count, r.idle) },
        }
    end
    p.ranks:SetBars(items, 110)

    -- Mythic+.
    if o.mplus then
        peak = 1
        for _, m in ipairs(o.mplus) do peak = math.max(peak, m.count) end
        items = {}
        for _, m in ipairs(o.mplus) do
            local col = m.score and PGM:ScoreColor(m.score) or C.text3
            items[#items + 1] = { label = m.label, value = m.count, max = peak, col = col, labelCol = col }
        end
        p.mplus:SetBars(items, 90)
    end

    -- Races, coloured by faction.
    peak = 1
    for _, r in ipairs(o.races) do peak = math.max(peak, r.count) end
    items = {}
    local FACTION_COL = { Alliance = C.blue, Horde = C.red, Neutral = C.gold }
    local factions = {}
    for _, r in ipairs(o.races) do
        local tip = { r.label .. " (" .. r.faction .. ")", ("%d members, average level %.1f"):format(r.count, r.avgLevel) }
        local mix = {}
        for cls, n in pairs(r.classes) do mix[#mix + 1] = { cls = cls, n = n } end
        table.sort(mix, function(a, b) return a.n > b.n end)
        for _, m in ipairs(mix) do tip[#tip + 1] = PGM.ClassHex(m.cls) .. PGM.ClassName(m.cls) .. "|r  " .. m.n end
        items[#items + 1] = { label = PGM.RaceIconMarkup(r.id, 14) .. " " .. r.label, value = r.count, max = peak,
            col = FACTION_COL[r.faction] or C.gold, tip = tip }
        factions[r.faction] = (factions[r.faction] or 0) + r.count
    end
    parts = {}
    for _, fname in ipairs({ "Alliance", "Horde", "Neutral" }) do
        local n = factions[fname]
        if n then
            parts[#parts + 1] = { value = n, col = FACTION_COL[fname],
                tip = { fname, ("%d members"):format(n) } }
        end
    end
    p.races.seg:SetParts(parts)
    p.races.emptyText = "No race data yet."
    p.races:SetBars(items, 130)

    -- Professions.
    peak = 1
    for _, e in ipairs(o.profs) do peak = math.max(peak, e.count) end
    items = {}
    for _, e in ipairs(o.profs) do
        items[#items + 1] = {
            label = "|T" .. PGM.ProfIcon(e.id) .. ":13:13|t " .. e.label, value = e.count, max = peak,
            col = PGM.PROF_GATHERING[e.id] and C.gold or C.jade,
            valueText = tostring(e.count),
            tip = { e.label, ("%d members, %d online now"):format(e.count, e.online), "See the Professions page for names." },
        }
    end
    p.profs:SetBars(items, 120)

    -- Zones.
    peak = 1
    for _, z in ipairs(o.zones) do peak = math.max(peak, z.count) end
    items = {}
    for _, z in ipairs(o.zones) do
        items[#items + 1] = { label = z.label, value = z.count, max = peak, col = C.gold }
    end
    p.zones:SetBars(items, 140)

    layout(p)
    p.trend:SetTrend(o.trend)
    p.trend.sub:SetText(o.trackingSince
        and ("Weekly since %s. Green joined, red left."):format(PGM.Date(o.trackingSince))
        or "Starts once the first full roster has been read.")
end

UI:AddTab({ id = "overview", label = "Overview", build = build, refresh = refresh })
