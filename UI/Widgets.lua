-- Widgets.lua: the handful of building blocks every page is made of.
--
-- Clean and dark: flat near-black panels in crisp one-pixel frames, bright
-- text, and the accent colour only where something should stand out (the
-- selected page, active filters, card stripes, key numbers).

local _, NS = ...
local PGM = NS.PGM
local C = PGM.C

local UI = {}
PGM.UI = UI
local W = {}
UI.W = W

local FONT = STANDARD_TEXT_FONT
local WHITE = "Interface\\Buttons\\WHITE8x8"
local INK = { 0.020, 0.021, 0.025 }   -- wells inside controls: inputs, bar tracks

function W.Solid(parent, layer, col, alpha)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND")
    t:SetColorTexture(col[1], col[2], col[3], alpha or 1)
    return t
end

-- A flat fill in a one-pixel frame.
function W.Backdrop(f, bg, border, alpha)
    f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    f:SetBackdropColor(bg[1], bg[2], bg[3], alpha or 0.98)
    border = border or C.frame
    f:SetBackdropBorderColor(border[1], border[2], border[3], 1)
end
W.Thin = W.Backdrop

-- The accent, darkened: the fill behind selected things.
function W.AccentFill(f, strength)
    local k = strength or 0.18
    f:SetBackdropColor(C.accent[1] * k, C.accent[2] * k, C.accent[3] * k, 1)
end

function W.FS(parent, size, col, justify, flags)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FONT, size or 12, flags or "")
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 1)
    col = col or C.text
    fs:SetTextColor(col[1], col[2], col[3])
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    return fs
end

-- A small uppercase section label in the accent colour.
function W.Heading(parent, text, size)
    local fs = W.FS(parent, size or 10, C.accent)
    fs:SetText(text and text:upper() or "")
    return fs
end

-- A flat button. A red accent makes it the destructive kind. `template`
-- lets a secure button share the look; `name` gives it the global name a
-- key binding needs to click it.
function W.Button(parent, text, w, h, accent, template, name)
    local b = CreateFrame("Button", name, parent, template and (template .. ",BackdropTemplate") or "BackdropTemplate")
    b:SetSize(w or 90, h or 24)
    accent = accent or C.accent
    local destructive = accent == C.red
    b.restBorder = destructive and { 0.55, 0.20, 0.19 } or C.frame
    b.restFill = destructive and { 0.16, 0.05, 0.05 } or C.button
    W.Backdrop(b, b.restFill, b.restBorder, 1)
    b.accent = accent
    b.fs = W.FS(b, 12, accent, "CENTER")
    b.fs:SetPoint("CENTER", 0, 0)
    b.fs:SetText(text)
    b.glow = b:CreateTexture(nil, "HIGHLIGHT")
    b.glow:SetPoint("TOPLEFT", 1, -1)
    b.glow:SetPoint("BOTTOMRIGHT", -1, 1)
    b.glow:SetColorTexture(1, 1, 1, 0.06)
    b:HookScript("OnEnter", function(s)
        s:SetBackdropBorderColor(s.accent[1], s.accent[2], s.accent[3], 1)
        if s.tip then
            GameTooltip:SetOwner(s, "ANCHOR_TOP")
            GameTooltip:SetText(s.tip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    b:HookScript("OnLeave", function(s)
        local c = s.active and C.accent or s.restBorder
        s:SetBackdropBorderColor(c[1], c[2], c[3], 1)
        if s.tip then GameTooltip:Hide() end
    end)
    b:HookScript("OnMouseDown", function(s) s.fs:SetPoint("CENTER", 1, -1) end)
    b:HookScript("OnMouseUp", function(s) s.fs:SetPoint("CENTER", 0, 0) end)
    function b:SetLabel(t) self.fs:SetText(t) end
    function b:SetAccent(col)
        self.accent = col
        self.fs:SetTextColor(col[1], col[2], col[3])
    end
    return b
end

-- A toggle chip: quiet when off, accent-lit when on.
function W.Chip(parent, text, onClick)
    local b = W.Button(parent, text, 0, 22, C.text2)
    b.fs:SetFont(FONT, 11, "")
    b:SetWidth(b.fs:GetStringWidth() + 24)
    function b:SetActive(on)
        self.active = on
        if on then
            W.AccentFill(self, 0.2)
            self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
            self:SetAccent(C.text)
        else
            self:SetBackdropColor(C.button[1], C.button[2], C.button[3], 1)
            self:SetBackdropBorderColor(C.frame[1], C.frame[2], C.frame[3], 1)
            self:SetAccent(C.text2)
        end
    end
    b:SetScript("OnClick", function(s) onClick(s) end)
    b:SetActive(false)
    return b
end

-- A flat input box with a placeholder hint; the frame lights up while typing.
function W.EditBox(parent, w, h, placeholder)
    local e = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    e:SetSize(w, h or 22)
    W.Backdrop(e, INK, C.frame, 1)
    e:SetAutoFocus(false)
    e:SetFont(FONT, 12, "")
    e:SetTextColor(C.text[1], C.text[2], C.text[3])
    e:SetTextInsets(7, 7, 0, 0)
    e.hint = W.FS(e, 11, C.text3)
    e.hint:SetPoint("LEFT", 8, 0)
    e.hint:SetText(placeholder or "")
    local function hint(s)
        s.hint:SetShown(s:GetText() == "" and not s:HasFocus())
    end
    -- Escape cancels: put back what was there before editing, then leave.
    e:SetScript("OnEscapePressed", function(s)
        if s.before ~= nil and s:GetText() ~= s.before then
            s:SetText(s.before)
            if s.onChange then s.onChange(s) end
        end
        s:ClearFocus()
    end)
    e:SetScript("OnEnterPressed", function(s)
        s:ClearFocus()
        if s.onEnter then s.onEnter(s) end
    end)
    e:SetScript("OnEditFocusGained", function(s)
        s.before = s:GetText()
        s:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
        hint(s)
    end)
    e:SetScript("OnEditFocusLost", function(s)
        s:SetBackdropBorderColor(C.frame[1], C.frame[2], C.frame[3], 1)
        hint(s)
        if s.onCommit then s.onCommit(s) end
    end)
    e:SetScript("OnTextChanged", function(s, user)
        hint(s)
        if user and s.onChange then s.onChange(s) end
    end)
    return e
end

-- Guildies to pick from as you type a name into a box: names starting with
-- what's typed first, then online, then A-Z, in class colour, alts marked
-- with their main. Click or Tab fills the box (Up and Down move); Enter
-- takes the highlighted one before the box's own onEnter runs, so set that
-- first. opts.up opens the list above the box; opts.skip(guid) leaves
-- someone out.
local SUGGEST_MAX = 8

function W.NameSuggest(box, opts)
    opts = opts or {}
    local list = CreateFrame("Frame", nil, box, "BackdropTemplate")
    list:SetFrameStrata("DIALOG")
    list:SetWidth(math.max(box:GetWidth(), 200))
    if opts.up then
        list:SetPoint("BOTTOMLEFT", box, "TOPLEFT", 0, 2)
    else
        list:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -2)
    end
    W.Backdrop(list, C.bg, C.accent, 1)
    list:Hide()
    list.found, list.sel, list.rows = {}, 1, {}

    -- What to type for them: the bare name, or Name-Realm from another realm.
    local function typed(rec)
        local myRealm = GetNormalizedRealmName and GetNormalizedRealmName()
        if rec.name and rec.realm and myRealm and rec.realm ~= myRealm then return rec.name end
        return rec.short or rec.name
    end

    local function paint()
        for i, b in ipairs(list.rows) do b.sel:SetShown(i == list.sel) end
    end

    local function pick(it)
        box:SetText(typed(it.rec) or "")
        box:SetCursorPosition(#box:GetText())
        list:Hide()
    end

    for i = 1, SUGGEST_MAX do
        local b = CreateFrame("Button", nil, list)
        b:SetHeight(20)
        b:SetPoint("TOPLEFT", 3, -3 - (i - 1) * 20)
        b:SetPoint("RIGHT", -3, 0)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.08)
        b.sel = W.Solid(b, "BACKGROUND", C.accent, 0.18)
        b.sel:SetAllPoints()
        b.fs = W.FS(b, 11, C.text)
        b.fs:SetPoint("LEFT", 6, 0)
        b.alt = W.FS(b, 11, C.text3, "RIGHT")
        b.alt:SetPoint("RIGHT", -6, 0)
        b:SetScript("OnClick", function(s)
            pick(s.it)
            box:SetFocus()
        end)
        list.rows[i] = b
    end

    local function update()
        local g = PGM.GuildDB()
        local want = strtrim(box:GetText() or ""):lower()
        local found = {}
        if g and want ~= "" and box:HasFocus() then
            for guid, rec in pairs(g.members) do
                local short = rec.short and rec.short:lower()
                local at = short and short:find(want, 1, true)
                if not at and rec.name and rec.name:lower():find(want, 1, true) == 1 then at = 1 end
                if at and not (opts.skip and opts.skip(guid)) then
                    found[#found + 1] = { guid = guid, rec = rec, exact = short == want, starts = at == 1 }
                end
            end
        end
        table.sort(found, function(a, b)
            if a.exact ~= b.exact then return a.exact end
            if a.starts ~= b.starts then return a.starts end
            if (a.rec.online and true) ~= (b.rec.online and true) then return a.rec.online and true or false end
            return (a.rec.short or "") < (b.rec.short or "")
        end)
        list.found, list.sel = found, 1
        if #found == 0 then list:Hide() return end
        for i, b in ipairs(list.rows) do
            local it = found[i]
            b:SetShown(it ~= nil)
            if it then
                b.it = it
                b.fs:SetText(PGM.ColorName(it.rec))
                b.fs:SetAlpha(it.rec.online and 1 or 0.6)
                local main = PGM.KnownMain and PGM:KnownMain(it.guid)
                local mrec = main and g.members[main]
                b.alt:SetText(mrec and ("alt of " .. (mrec.short or mrec.name or "?")) or "")
            end
        end
        list:SetHeight(math.min(#found, SUGGEST_MAX) * 20 + 6)
        paint()
        list:Show()
    end

    box:HookScript("OnTextChanged", function(_, user) if user then update() end end)
    box:HookScript("OnEditFocusLost", function() C_Timer.After(0.2, function() list:Hide() end) end)
    box:SetScript("OnTabPressed", function()
        local it = list:IsShown() and list.found[list.sel]
        if it then pick(it) end
    end)
    box:HookScript("OnArrowPressed", function(_, key)
        if not list:IsShown() then return end
        local n = math.min(#list.found, SUGGEST_MAX)
        if key == "DOWN" then list.sel = list.sel % n + 1 elseif key == "UP" then list.sel = (list.sel - 2) % n + 1 end
        paint()
    end)
    local enter = box.onEnter
    box.onEnter = function(s)
        local it = list:IsShown() and list.found[list.sel]
        if it then pick(it) end
        list:Hide()
        if enter then enter(s) end
    end
    return list
end

-- A labelled horizontal bar: label | framed bar | count.
function W.Bar(parent, labelW)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(16)
    labelW = labelW or 120
    f.label = W.FS(f, 11, C.text)
    f.label:SetPoint("LEFT", 0, 0)
    f.label:SetWidth(labelW)
    f.value = W.FS(f, 11, C.text2, "RIGHT")
    f.value:SetPoint("RIGHT", 0, 0)
    f.value:SetWidth(64)
    f.frame = CreateFrame("Frame", nil, f, "BackdropTemplate")
    f.frame:SetPoint("LEFT", labelW + 6, 0)
    f.frame:SetPoint("RIGHT", -70, 0)
    f.frame:SetHeight(10)
    W.Backdrop(f.frame, INK, C.line, 1)
    f.track = f.frame
    f.fill = f.frame:CreateTexture(nil, "ARTWORK")
    f.fill:SetTexture(WHITE)
    f.fill:SetPoint("TOPLEFT", 1, -1)
    f.fill:SetPoint("BOTTOMLEFT", 1, 1)
    f:EnableMouse(true)
    f:SetScript("OnEnter", function(s)
        if not s.tip then return end
        GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
        for i, line in ipairs(s.tip) do
            if i == 1 then GameTooltip:SetText(line, 1, 1, 1) else GameTooltip:AddLine(line, 0.85, 0.85, 0.85, true) end
        end
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    function f:Set(label, value, maxValue, col, valueText, labelCol)
        self.label:SetText(label)
        labelCol = labelCol or C.text
        self.label:SetTextColor(labelCol[1], labelCol[2], labelCol[3])
        self.value:SetText(valueText or tostring(value))
        col = col or C.accent
        self.fill:SetVertexColor(col[1], col[2], col[3], 1)
        self.frac = (maxValue and maxValue > 0) and math.min(1, value / maxValue) or 0
        self:UpdateFill()
        self.fill:SetShown(value > 0)
    end
    -- The bar has no width until the card is laid out, so the fill is
    -- sized again whenever the bar's size settles.
    function f:UpdateFill()
        local w = self.frame:GetWidth()
        if w and w > 2 then self.fill:SetWidth(math.max(1, (w - 2) * (self.frac or 0))) end
    end
    f:SetScript("OnSizeChanged", function(s) s:UpdateFill() end)
    return f
end

-- A segmented breakdown bar: one coloured slice per part, sized by
-- share, each with its own tooltip. parts: { value, col, tip = { lines } }
function W.SegmentBar(parent)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetHeight(12)
    W.Backdrop(f, INK, C.line, 1)
    f.segs = {}
    function f:SetParts(parts)
        self.parts = parts
        self:Layout()
    end
    function f:Layout()
        local parts = self.parts or {}
        local total = 0
        for _, p in ipairs(parts) do total = total + p.value end
        local w = self:GetWidth() - 2
        local x = 1
        for i, p in ipairs(parts) do
            local s = self.segs[i]
            if not s then
                s = CreateFrame("Frame", nil, self)
                s.tex = s:CreateTexture(nil, "ARTWORK")
                s.tex:SetPoint("TOPLEFT")
                s.tex:SetPoint("BOTTOMRIGHT", -1, 0)   -- a hairline gap between slices
                s.tex:SetTexture(WHITE)
                s:EnableMouse(true)
                s:SetScript("OnEnter", function(seg)
                    if not seg.tip then return end
                    GameTooltip:SetOwner(seg, "ANCHOR_TOP")
                    for li, line in ipairs(seg.tip) do
                        if li == 1 then GameTooltip:SetText(line) else GameTooltip:AddLine(line, 0.85, 0.85, 0.85) end
                    end
                    GameTooltip:Show()
                end)
                s:SetScript("OnLeave", function() GameTooltip:Hide() end)
                self.segs[i] = s
            end
            local sw = (total > 0 and w > 0) and (w * p.value / total) or 0
            s:ClearAllPoints()
            s:SetPoint("TOPLEFT", x, -1)
            s:SetPoint("BOTTOMLEFT", x, 1)
            s:SetWidth(math.max(1, sw))
            s.tex:SetVertexColor(p.col[1], p.col[2], p.col[3], 1)
            s.tip = p.tip
            s:SetShown(sw >= 1)
            x = x + sw
        end
        for i = #parts + 1, #self.segs do self.segs[i]:Hide() end
    end
    f:SetScript("OnSizeChanged", function(s) s:Layout() end)
    return f
end

-- A card: flat panel, an accent stripe down the left, a bright title.
-- Bars are created as needed.
function W.Card(parent, title, subtitle, accent)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    W.Backdrop(f, C.card, C.cardLine, 1)
    f.stripe = f:CreateTexture(nil, "ARTWORK")
    f.stripe:SetWidth(3)
    f.stripe:SetPoint("TOPLEFT", 1, -1)
    f.stripe:SetPoint("BOTTOMLEFT", 1, 1)
    accent = accent or C.accent
    f.stripe:SetColorTexture(accent[1], accent[2], accent[3], 1)
    f.title = W.FS(f, 14, C.text)
    f.title:SetPoint("TOPLEFT", 14, -10)
    f.title:SetText(title)
    f.sub = W.FS(f, 10, C.text3)
    f.sub:SetPoint("TOPLEFT", 14, -28)
    f.sub:SetPoint("TOPRIGHT", -12, -28)
    f.sub:SetText(subtitle or "")
    f.bars = {}
    f.top = 46
    function f:SetAccentColor(col) self.stripe:SetColorTexture(col[1], col[2], col[3], 1) end
    -- items: { label, value, max, col, valueText, labelCol, tip }
    function f:SetBars(items, labelW)
        for i, it in ipairs(items) do
            local bar = self.bars[i]
            if not bar then
                bar = W.Bar(self, labelW)
                bar:SetPoint("TOPLEFT", 14, -(self.top + (i - 1) * 19))
                bar:SetPoint("TOPRIGHT", -12, -(self.top + (i - 1) * 19))
                self.bars[i] = bar
            end
            bar.tip = it.tip
            bar:Show()
            bar:Set(it.label, it.value, it.max, it.col, it.valueText, it.labelCol)
        end
        for i = #items + 1, #self.bars do self.bars[i]:Hide() end
        local rows = math.max(1, #items)
        self:SetHeight(self.top + rows * 19 + 12)
        if #items == 0 then
            self.empty = self.empty or W.FS(self, 11, C.text3)
            self.empty:SetPoint("TOPLEFT", 14, -self.top)
            self.empty:SetText(self.emptyText or "Nothing to show yet.")
            self.empty:Show()
        elseif self.empty then
            self.empty:Hide()
        end
    end
    return f
end

-- A game icon in a thin dark frame.
function W.FramedIcon(parent, size, texture)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetSize(size, size)
    W.Backdrop(f, { 0, 0, 0 }, C.frame, 1)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetPoint("TOPLEFT", 2, -2)
    f.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if texture then f.icon:SetTexture(texture) end
    return f
end

-- A virtual list: only enough row frames to fill the height, recycled as
-- you scroll, so a 900-member guild costs the same as a 20-member one.
-- Rows made with W.Row get alternating stripes.
function W.List(parent, rowH, buildRow, updateRow)
    local list = CreateFrame("Frame", nil, parent)
    list.rows, list.data, list.offset, list.rowH = {}, {}, 0, rowH
    list:EnableMouseWheel(true)
    list.track = W.Solid(list, "ARTWORK", C.line, 0.6)
    list.track:SetPoint("TOPRIGHT", 0, 0)
    list.track:SetPoint("BOTTOMRIGHT", 0, 0)
    list.track:SetWidth(3)
    list.thumb = W.Solid(list, "OVERLAY", C.accent, 1)
    list.thumb:SetWidth(3)

    function list:Layout()
        local n = math.floor((self:GetHeight() or 0) / rowH)
        for i = #self.rows + 1, n do
            local r = buildRow(self, i)
            r:SetHeight(rowH)
            r:SetPoint("TOPLEFT", 0, -(i - 1) * rowH)
            r:SetPoint("TOPRIGHT", -9, -(i - 1) * rowH)
            self.rows[i] = r
        end
        self.visible = n
    end

    function list:Refresh()
        if not self.visible or self.visible ~= math.floor((self:GetHeight() or 0) / rowH) then self:Layout() end
        local maxOff = math.max(0, #self.data - self.visible)
        if self.offset > maxOff then self.offset = maxOff end
        for i, r in ipairs(self.rows) do
            local idx = self.offset + i
            local item = self.data[idx]
            if item and i <= self.visible then
                r:Show()
                if r.stripe then
                    local c = (idx % 2 == 0) and C.rowB or C.rowA
                    r.stripe:SetColorTexture(c[1], c[2], c[3], 1)
                end
                updateRow(r, item, idx)
            else
                r:Hide()
            end
        end
        local total = #self.data
        if total > self.visible and self.visible > 0 then
            local h = self:GetHeight()
            local th = math.max(20, h * self.visible / total)
            local pos = (h - th) * (self.offset / maxOff)
            self.thumb:ClearAllPoints()
            self.thumb:SetPoint("TOPRIGHT", 0, -pos)
            self.thumb:SetHeight(th)
            self.thumb:Show()
            self.track:Show()
        else
            self.thumb:Hide()
            self.track:Hide()
        end
    end

    function list:SetData(data, keepOffset)
        self.data = data or {}
        if not keepOffset then self.offset = 0 end
        self:Refresh()
    end

    list:SetScript("OnMouseWheel", function(s, delta)
        local maxOff = math.max(0, #s.data - (s.visible or 0))
        s.offset = math.max(0, math.min(maxOff, s.offset - delta * 3))
        s:Refresh()
    end)
    list:SetScript("OnSizeChanged", function(s) s:Refresh() end)
    return list
end

-- A list row: striped background, a soft lift and an accent edge on hover.
function W.Row(parent)
    local r = CreateFrame("Button", nil, parent)
    r.stripe = r:CreateTexture(nil, "BACKGROUND")
    r.stripe:SetAllPoints()
    r.stripe:SetColorTexture(C.rowA[1], C.rowA[2], C.rowA[3], 1)
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.07)
    local edge = r:CreateTexture(nil, "HIGHLIGHT")
    edge:SetPoint("TOPLEFT")
    edge:SetPoint("BOTTOMLEFT")
    edge:SetWidth(2)
    edge:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    r:SetScript("OnEnter", function(s) if s.onEnter then s.onEnter(s) end end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    return r
end

-- A tick box: a dark square that fills with the accent when on.
function W.Check(parent, label, get, set)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(300, 22)
    b.box = CreateFrame("Frame", nil, b, "BackdropTemplate")
    b.box:SetSize(16, 16)
    b.box:SetPoint("LEFT")
    W.Backdrop(b.box, INK, C.frame, 1)
    b.tick = W.Solid(b.box, "ARTWORK", C.accent)
    b.tick:SetPoint("TOPLEFT", 3, -3)
    b.tick:SetPoint("BOTTOMRIGHT", -3, 3)
    b.fs = W.FS(b, 12, C.text)
    b.fs:SetPoint("LEFT", b.box, "RIGHT", 8, 0)
    b.fs:SetText(label)
    b:SetScript("OnEnter", function(s)
        s.box:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
        if s.tip then
            GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
            GameTooltip:SetText(s.tip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function(s)
        s.box:SetBackdropBorderColor(C.frame[1], C.frame[2], C.frame[3], 1)
        if s.tip then GameTooltip:Hide() end
    end)
    function b:Sync() self.tick:SetShown(get() and true or false) end
    b:SetScript("OnClick", function(s) set(not get()) s:Sync() end)
    b:Sync()
    return b
end

-- A scrollable area for pages taller than the window, with the same thin
-- accent scrollbar the lists use (Blizzard's template brings its own art).
-- The bar sits in a 6px gutter just inside the area's right edge.
function W.Scroll(parent)
    local sf = CreateFrame("ScrollFrame", nil, parent)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(1, 1)
    sf:SetScrollChild(child)
    sf.child = child

    sf.track = W.Solid(sf, "ARTWORK", C.line, 0.6)
    sf.track:SetPoint("TOPRIGHT")
    sf.track:SetPoint("BOTTOMRIGHT")
    sf.track:SetWidth(3)
    sf.thumb = W.Solid(sf, "OVERLAY", C.accent, 1)
    sf.thumb:SetWidth(3)

    function sf:UpdateBar()
        local range = self:GetVerticalScrollRange() or 0
        local h = self:GetHeight() or 0
        if range <= 0 or h <= 0 then
            self.track:Hide()
            self.thumb:Hide()
            return
        end
        local th = math.max(20, h * h / (h + range))
        local pos = (h - th) * (self:GetVerticalScroll() / range)
        self.thumb:ClearAllPoints()
        self.thumb:SetPoint("TOPRIGHT", 0, -pos)
        self.thumb:SetHeight(th)
        self.track:Show()
        self.thumb:Show()
    end

    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(s, delta)
        local range = s:GetVerticalScrollRange() or 0
        local v = math.max(0, math.min(range, s:GetVerticalScroll() - delta * 60))
        s:SetVerticalScroll(v)
    end)
    sf:SetScript("OnVerticalScroll", function(s) s:UpdateBar() end)
    sf:SetScript("OnScrollRangeChanged", function(s) s:UpdateBar() end)
    -- The content stays clear of the scrollbar gutter.
    sf:SetScript("OnSizeChanged", function(s, w)
        child:SetWidth(math.max(1, w - 10))
        s:UpdateBar()
    end)
    return sf
end

function W.Divider(parent)
    local t = W.Solid(parent, "BORDER", C.line, 1)
    t:SetHeight(1)
    return t
end

-- A context menu, with the modern Menu API when it's there. Entries:
--   { "Text", fn }                       a button
--   { "Text", fn, disabled = true }      greyed out
--   { "Text", sub = { entries } }        a submenu
--   { "Text", checked = fn, toggle = fn } a tick box
--   { divider = true }
--   { "Text", title = true }              a heading
local function addEntries(parent, entries)
    for _, e in ipairs(entries) do
        if e.divider then
            parent:CreateDivider()
        elseif e.title then
            parent:CreateTitle(e[1])
        elseif e.checked then
            parent:CreateCheckbox(e[1], e.checked, e.toggle)
        elseif e.sub then
            local s = parent:CreateButton(e[1])
            addEntries(s, e.sub)
        else
            local b = parent:CreateButton(e[1], e[2])
            if e.disabled and b.SetEnabled then b:SetEnabled(false) end
        end
    end
end

function W.Menu(owner, title, entries)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(title)
        addEntries(root, entries)
    end)
end
