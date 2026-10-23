-- Activity.lua (UI): when the guild plays, and who plays when.

local _, NS = ...
local PGM = NS.PGM
local C = PGM.C
local UI = PGM.UI
local W = UI.W

local state = { days = 30, mains = true }
local PERIODS = { { 7, "7 days" }, { 30, "30 days" }, { 90, "90 days" } }

local function tile(parent, label)
    local t = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    W.Backdrop(t, C.card, C.cardLine, 1)
    t:SetHeight(64)
    t.label = W.FS(t, 10, C.text2)
    t.label:SetPoint("TOPLEFT", 12, -10)
    t.label:SetText(label:upper())
    t.value = W.FS(t, 20, C.accent)
    t.value:SetPoint("TOPLEFT", 12, -24)
    t.note = W.FS(t, 10, C.text3)
    t.note:SetPoint("BOTTOMLEFT", 12, 8)
    t.note:SetPoint("BOTTOMRIGHT", -8, 8)
    return t
end

-- 24 bars: average online at each hour of the day.
local function hourChart(parent)
    local card = W.Card(parent, "Online by hour of day", "Average online at once, your local time.")
    card:SetHeight(178)
    card.hbars = {}
    for hr = 0, 23 do
        local f = CreateFrame("Frame", nil, card)
        f.fill = W.Solid(f, "ARTWORK", C.accent)
        f.fill:SetPoint("BOTTOMLEFT")
        f.fill:SetPoint("BOTTOMRIGHT")
        f:EnableMouse(true)
        f:SetScript("OnEnter", function(s)
            if not s.info then return end
            GameTooltip:SetOwner(s, "ANCHOR_TOP")
            GameTooltip:SetText(PGM.HourLabel(hr))
            GameTooltip:AddLine(s.info, 0.85, 0.85, 0.85)
            GameTooltip:Show()
        end)
        f:SetScript("OnLeave", function() GameTooltip:Hide() end)
        card.hbars[hr] = f
        if hr % 6 == 0 then
            f.lab = W.FS(card, 9, C.text3, "LEFT")
        end
    end
    function card:SetData(o)
        local w = self:GetWidth() - 28
        if w <= 0 then return end
        local slot = w / 24
        local top = 1
        for hr = 0, 23 do
            local b = o.byHour[hr]
            if b.n > 0 then top = math.max(top, b.sum / b.n) end
        end
        for hr = 0, 23 do
            local f, b = self.hbars[hr], o.byHour[hr]
            local avg = b.n > 0 and b.sum / b.n or 0
            f:ClearAllPoints()
            f:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 14 + hr * slot + 1, 28)
            f:SetSize(math.max(2, slot - 2), 100)
            f.fill:SetHeight(math.max(1, 100 * avg / top))
            f.fill:SetShown(b.n > 0)
            f.info = b.n > 0 and ("%.1f online on average, %d at most (%d hours seen)"):format(avg, b.peak, b.n)
                or "Not seen yet"
            if f.lab then
                f.lab:ClearAllPoints()
                f.lab:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -4)
                f.lab:SetText(PGM.HourLabel(hr))
            end
        end
    end
    return card
end

-- A week as a grid: rows are days, columns hours, brighter = busier.
local function weekChart(parent)
    local card = W.Card(parent, "Busiest times of the week", "Brighter is busier. Hover a square for numbers.")
    card:SetHeight(178)
    card.cells = {}
    card.dayLabels = {}
    for wd = 1, 7 do
        card.cells[wd] = {}
        card.dayLabels[wd] = W.FS(card, 9, C.text3)
        for hr = 0, 23 do
            local f = CreateFrame("Frame", nil, card)
            f.tex = W.Solid(f, "ARTWORK", C.line)
            f.tex:SetAllPoints()
            f:EnableMouse(true)
            f:SetScript("OnEnter", function(s)
                GameTooltip:SetOwner(s, "ANCHOR_TOP")
                GameTooltip:SetText(PGM.WEEKDAYS[wd] .. " " .. PGM.HourLabel(hr))
                GameTooltip:AddLine(s.info or "", 0.85, 0.85, 0.85)
                GameTooltip:Show()
            end)
            f:SetScript("OnLeave", function() GameTooltip:Hide() end)
            card.cells[wd][hr] = f
        end
    end
    function card:SetData(o)
        local w = self:GetWidth() - 28 - 26
        if w <= 0 then return end
        local cw, ch = w / 24, 15
        local top = 1
        for wd = 1, 7 do
            for hr = 0, 23 do
                local c = o.byCell[wd][hr]
                if c.n > 0 then top = math.max(top, c.sum / c.n) end
            end
        end
        for wd = 1, 7 do
            local y = -48 - (wd - 1) * (ch + 2)
            local lab = self.dayLabels[wd]
            lab:ClearAllPoints()
            lab:SetPoint("TOPLEFT", 14, y - 2)
            lab:SetText(PGM.WEEKDAYS[wd])
            for hr = 0, 23 do
                local f, c = self.cells[wd][hr], o.byCell[wd][hr]
                f:ClearAllPoints()
                f:SetPoint("TOPLEFT", 14 + 26 + hr * cw, y)
                f:SetSize(math.max(2, cw - 1), ch)
                if c.n > 0 then
                    local k = 0.15 + 0.85 * (c.sum / c.n) / top
                    f.tex:SetColorTexture(C.accent[1] * k, C.accent[2] * k, C.accent[3] * k, 1)
                    f.info = ("%.1f online on average (%d hours seen)"):format(c.sum / c.n, c.n)
                else
                    f.tex:SetColorTexture(C.line[1], C.line[2], C.line[3], 0.35)
                    f.info = "Not seen yet"
                end
            end
        end
    end
    return card
end

local function buildRow(list)
    local r = W.Row(list)
    r.name = W.FS(r, 12, C.text)
    r.name:SetPoint("LEFT", 6, 0)
    r.name:SetWidth(200)
    r.hours = W.FS(r, 12, C.text, "RIGHT")
    r.hours:SetPoint("LEFT", 206, 0)
    r.hours:SetWidth(70)
    r.usual = W.FS(r, 12, C.text2)
    r.usual:SetPoint("LEFT", 300, 0)
    r.usual:SetWidth(140)
    r.day = W.FS(r, 12, C.text2)
    r.day:SetPoint("LEFT", 446, 0)
    r.day:SetWidth(70)
    r.last = W.FS(r, 12, C.text2)
    r.last:SetPoint("LEFT", 522, 0)
    r.last:SetPoint("RIGHT", -6, 0)
    r:SetScript("OnClick", function(s, button)
        if button == "RightButton" then UI:MemberMenu(s, s.p.guid) else UI:OpenProfile(s.p.guid) end
    end)
    return r
end

local function updateRow(r, p)
    r.p = p
    r.name:SetText(PGM.ColorName(p.rec))
    r.hours:SetText(p.hours .. "h")
    r.usual:SetText(PGM.UsualTime(p))
    r.day:SetText(PGM.TopDay(p))
    r.last:SetText(p.rec.online and (PGM.Hex(C.jade) .. "Online|r") or PGM.AgoText(p.last * 3600))
end

local function build(p)
    p.chips = {}
    local prev
    for _, per in ipairs(PERIODS) do
        local chip = W.Chip(p, per[2], function()
            state.days = per[1]
            p.list.offset = 0
            UI:Refresh()
        end)
        chip.days = per[1]
        if prev then chip:SetPoint("LEFT", prev, "RIGHT", 6, 0) else chip:SetPoint("TOPLEFT", 0, 0) end
        p.chips[#p.chips + 1] = chip
        prev = chip
    end
    p.mains = W.Chip(p, "Mains only", function()
        state.mains = not state.mains
        UI:Refresh()
    end)
    p.mains:SetPoint("LEFT", prev, "RIGHT", 16, 0)
    p.coverage = W.FS(p, 11, C.text3, "RIGHT")
    p.coverage:SetPoint("TOPRIGHT", 0, -5)

    p.tiles = { tile(p, "Average online"), tile(p, "Peak online"), tile(p, "Busiest time"), tile(p, "Hours observed") }
    p.byHour = hourChart(p)
    p.week = weekChart(p)

    local header = CreateFrame("Frame", nil, p)
    header:SetHeight(20)
    local hbg = W.Solid(header, "BACKGROUND", C.side)
    hbg:SetAllPoints()
    for _, h in ipairs({ { "Name", 6, "LEFT" }, { "Played", 206, "RIGHT", 70 }, { "Usually on", 300 },
                         { "Most on", 446 }, { "Last on", 522 } }) do
        local fs = W.FS(header, 11, C.text2, h[3])
        fs:SetPoint("LEFT", h[2], 0)
        if h[4] then fs:SetWidth(h[4]) end
        fs:SetText(h[1])
    end
    p.header = header
    p.list = W.List(p, 22, buildRow, updateRow)

    p.empty = W.FS(p, 12, C.text3, "CENTER")
    p.empty:SetWidth(520)
    p.empty:SetWordWrap(true)
end

local function layout(p)
    local width = p:GetWidth()
    if width < 100 then return end
    local tw = (width - 36) / 4
    for i, t in ipairs(p.tiles) do
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", (i - 1) * (tw + 12), -32)
        t:SetWidth(tw)
    end
    local cw = (width - 12) / 2
    p.byHour:ClearAllPoints()
    p.byHour:SetPoint("TOPLEFT", 0, -106)
    p.byHour:SetWidth(cw)
    p.week:ClearAllPoints()
    p.week:SetPoint("TOPLEFT", cw + 12, -106)
    p.week:SetWidth(cw)
    p.header:ClearAllPoints()
    p.header:SetPoint("TOPLEFT", 0, -296)
    p.header:SetPoint("TOPRIGHT", 0, -296)
    p.list:ClearAllPoints()
    p.list:SetPoint("TOPLEFT", 0, -318)
    p.list:SetPoint("BOTTOMRIGHT")
    p.empty:ClearAllPoints()
    p.empty:SetPoint("TOP", p.list, "TOP", 0, -40)
end

local function refresh(p)
    for _, chip in ipairs(p.chips) do chip:SetActive(chip.days == state.days) end
    p.mains:SetActive(state.mains)
    if not p.sized then
        p.sized = true
        p:HookScript("OnSizeChanged", function() layout(p) UI:Refresh() end)
    end
    layout(p)

    local o = PGM:ComputeActivity(state.days, state.mains)
    local t = p.tiles
    t[1].value:SetText(("%.1f"):format(o.avg))
    t[1].note:SetText("in game at once")
    t[2].value:SetText(o.peak)
    t[2].note:SetText(o.peakAt and date("%a %b %d, %I%p", o.peakAt):gsub(" 0", " ") or "-")
    if o.busiest then
        t[3].value:SetText(PGM.WEEKDAYS[o.busiest.wd] .. " " .. PGM.HourLabel(o.busiest.hr))
        t[3].note:SetText(("%.1f online on average"):format(o.busiest.avg))
    else
        t[3].value:SetText("-")
        t[3].note:SetText("")
    end
    t[4].value:SetText(("%d%%"):format(o.possible > 0 and o.observed / o.possible * 100 + 0.5 or 0))
    t[4].note:SetText(("%d of %d hours"):format(o.observed, o.possible))
    p.coverage:SetText(("%d people seen playing"):format(#o.people))

    p.byHour:SetData(o)
    p.week:SetData(o)
    p.list:SetData(o.people, true)
    p.empty:SetText(o.observed == 0
        and "Nothing recorded yet. While you're logged in, the addon notes who's online every 5 minutes; other members running it fill in the hours you're not on."
        or "")
end

UI:AddTab({ id = "activity", label = "Activity", build = build, refresh = refresh })
