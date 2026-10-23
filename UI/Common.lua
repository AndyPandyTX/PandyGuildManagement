-- Common.lua (UI): pieces the module's pages share, built from PGM's own
-- widgets so they look the same as every other page.

local _, NS = ...
local G = NS.G
if not G.ok then return end
local PGM = G.PGM
local C = PGM.C
local UI = PGM.UI
local W = UI.W

G.UI = {}
local GU = G.UI

-- A page title and a wrapped line under it, like PGM's pages.
function GU.Title(p, y)
    p.title = W.FS(p, 14, C.accent)
    p.title:SetPoint("TOPLEFT", 0, y or -2)
    p.sub = W.FS(p, 11, C.text2)
    p.sub:SetPoint("TOPLEFT", 0, (y or -2) - 20)
    p.sub:SetPoint("TOPRIGHT", 0, (y or -2) - 20)
    p.sub:SetWordWrap(true)
end

-- A column header strip: { { label, x }, ... }.
function GU.Header(p, y, cols)
    local header = CreateFrame("Frame", nil, p)
    header:SetPoint("TOPLEFT", 0, y)
    header:SetPoint("TOPRIGHT", 0, y)
    header:SetHeight(20)
    local bg = W.Solid(header, "BACKGROUND", C.side)
    bg:SetAllPoints()
    for _, h in ipairs(cols) do
        local fs = W.FS(header, 11, C.text2, h[3])
        if h[3] == "RIGHT" then fs:SetPoint("RIGHT", header, "LEFT", h[2], 0) else fs:SetPoint("LEFT", h[2], 0) end
        fs:SetText(h[1])
    end
    return header
end

-- A small "- n +" stepper with a label in front.
function GU.Stepper(parent, label, col, onChange)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(88, 22)
    f.label = W.FS(f, 11, col or C.text2)
    f.label:SetPoint("TOPLEFT", 0, 0)
    f.label:SetText(label)
    f.minus = W.Button(f, "-", 22, 20, C.text2)
    f.minus:SetPoint("TOPLEFT", 0, -15)
    f.value = W.FS(f, 13, C.text, "CENTER")
    f.value:SetPoint("LEFT", f.minus, "RIGHT", 0, 0)
    f.value:SetWidth(30)
    f.plus = W.Button(f, "+", 22, 20, C.text2)
    f.plus:SetPoint("LEFT", f.minus, "RIGHT", 30, 0)
    f.n = 0
    function f:Set(n)
        self.n = math.max(0, math.min(f.max or 40, n or 0))
        self.value:SetText(self.n)
    end
    f.minus:SetScript("OnClick", function() f:Set(f.n - 1) if onChange then onChange(f) end end)
    f.plus:SetScript("OnClick", function() f:Set(f.n + 1) if onChange then onChange(f) end end)
    f:SetHeight(36)
    return f
end

-- A chip that cycles through choices: { { value, label }, ... }.
function GU.Cycle(parent, prefix, choices, onChange)
    local b = W.Button(parent, "", 0, 22, C.text2)
    b.fs:SetFont(STANDARD_TEXT_FONT, 11, "")
    b.choices, b.i = choices, 1
    function b:Update()
        if not self.choices[self.i] then self.i = 1 end
        local c = self.choices[self.i]
        self:SetLabel(prefix .. (c and c[2] or ""))
        self:SetWidth(self.fs:GetStringWidth() + 24)
    end
    function b:Value() return self.choices[self.i] and self.choices[self.i][1] end
    function b:SetValue(v)
        for i, c in ipairs(self.choices) do
            if c[1] == v then self.i = i end
        end
        self:Update()
    end
    function b:SetChoices(list)
        local v = self:Value()
        self.choices, self.i = list, 1
        self:SetValue(v)
    end
    b:SetScript("OnClick", function(s)
        s.i = s.i % math.max(1, #s.choices) + 1
        s:Update()
        if onChange then onChange(s) end
    end)
    b:Update()
    return b
end

-- A row's tooltip for a member (row.it.rec): who, and all their M+ scores
-- with the roles they were earned on.
function GU.MemberTooltip(row)
    local rec = row.it and row.it.rec
    if not rec then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(G.WhoText(rec))
    G.AddScoreLines(GameTooltip, G.Scores(rec.short, rec.realm, PGM:MPlusScore(rec)))
    GameTooltip:Show()
end

-- "Sat 20:30", or "Today 20:30", in local time from a server-time stamp.
function G.StartText(start)
    local t = start - (PGM.Now() - time())
    if date("%Y%m%d", t) == date("%Y%m%d") then return "Today " .. date("%H:%M", t) end
    return date("%a %H:%M", t)
end

local DAYS = { sun = 1, mon = 2, tue = 3, wed = 4, thu = 5, fri = 6, sat = 7 }

-- "now", "+30" (minutes), "20:30" (next time it's 20:30) or "Sat 20:30",
-- as a server-time stamp; 0 for now, nil when it can't be read.
function G.ParseWhen(text)
    text = strtrim((text or ""):lower())
    if text == "" or text == "now" then return 0 end
    local plus = text:match("^%+%s*(%d+)$")
    if plus then return PGM.Now() + tonumber(plus) * 60 end
    local day, h, m = text:match("^(%a+)%s+(%d+):(%d%d)$")
    if not day then h, m = text:match("^(%d+):(%d%d)$") end
    h, m = tonumber(h), tonumber(m)
    if not (h and m) or h > 23 or m > 59 then return nil end
    local now = time()
    local t = date("*t", now)
    t.hour, t.min, t.sec = h, m, 0
    local target = time(t)
    if day then
        local wday = DAYS[day:sub(1, 3)]
        if not wday then return nil end
        target = target + ((wday - t.wday) % 7) * 86400
        if target <= now then target = target + 7 * 86400 end
    elseif target <= now then
        target = target + 86400
    end
    return target + (PGM.Now() - now)
end

-- "3:12" for a number of seconds.
function G.Clock(s)
    s = math.max(0, math.floor(s))
    return ("%d:%02d"):format(math.floor(s / 60), s % 60)
end
