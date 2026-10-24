-- Main.lua: the window, its navigation, and keeping pages fresh.
--
-- The layout: a header plate across the top, a sidebar on the left
-- with section headings over its tabs, and the page in an inset well on the
-- right. A grabber in the corner scales the whole window.

local _, NS = ...
local PGM = NS.PGM
local C = PGM.C
local UI = PGM.UI
local W = UI.W

local WIDTH, HEIGHT, SIDE_W = 1020, 660, 210

-- Sidebar sections, in order. A page not listed lands in the last one.
local NAV = {
    { heading = "Guild",   ids = { "overview", "roster", "activity", "professions" } },
    { heading = "Raiding", ids = { "teams", "raids" } },
    { heading = "Records", ids = { "log", "users", "bulk", "settings" } },
}

local NAV_ICONS = {
    overview    = "Interface\\Icons\\INV_Misc_Spyglass_03",
    roster      = "Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend",
    professions = "Interface\\Icons\\Trade_BlackSmithing",
    activity    = "Interface\\Icons\\INV_Misc_PocketWatch_02",
    teams       = "Interface\\Icons\\INV_Misc_GroupNeedMore",
    raids       = "Interface\\Icons\\Achievement_Boss_Ragnaros",
    log         = "Interface\\Icons\\INV_Scroll_03",
    users       = "Interface\\Icons\\INV_Misc_GroupLooking",
    bulk        = "Interface\\Icons\\Ability_Warrior_RallyingCry",
    settings    = "Interface\\Icons\\Trade_Engineering",
}

UI.tabs = {}
UI.order = {}

-- Pages register themselves: { id, label, build(panel), refresh(panel) }.
function UI:AddTab(tab)
    self.tabs[tab.id] = tab
    table.insert(self.order, tab.id)
end

local function savePosition(f)
    local point, _, relPoint, x, y = f:GetPoint()
    PandyGuildDB.window = { point, relPoint, x, y }
end

-- An icon path the client actually has, or nil (so a wrong guess shows
-- nothing rather than a green square).
local function knownIcon(path)
    if not path then return nil end
    if GetFileIDFromPath and not GetFileIDFromPath(path) then return nil end
    return path
end

local function navTab(parent, id, label)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(SIDE_W - 22, 28)
    W.Backdrop(b, C.side, C.side, 1)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.06)
    -- The selected page gets an accent bar down its left edge.
    b.mark = b:CreateTexture(nil, "ARTWORK")
    b.mark:SetPoint("TOPLEFT", 1, -1)
    b.mark:SetPoint("BOTTOMLEFT", 1, 1)
    b.mark:SetWidth(3)
    b.mark:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    local icon = knownIcon(NAV_ICONS[id])
    if icon then
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetSize(16, 16)
        b.icon:SetPoint("LEFT", 10, 0)
        b.icon:SetTexture(icon)
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    b.fs = W.FS(b, 13, C.text2)
    b.fs:SetPoint("LEFT", icon and 34 or 12, 0)
    b.fs:SetText(label)
    function b:SetSelected(on)
        if on then
            W.AccentFill(self, 0.16)
            self:SetBackdropBorderColor(C.accent[1] * 0.45, C.accent[2] * 0.45, C.accent[3] * 0.45, 1)
            self.fs:SetTextColor(C.text[1], C.text[2], C.text[3])
            self.mark:Show()
            if self.icon then self.icon:SetDesaturated(false) self.icon:SetAlpha(1) end
        else
            self:SetBackdropColor(C.side[1], C.side[2], C.side[3], 1)
            self:SetBackdropBorderColor(C.side[1], C.side[2], C.side[3], 1)
            self.fs:SetTextColor(C.text2[1], C.text2[2], C.text2[3])
            self.mark:Hide()
            if self.icon then self.icon:SetDesaturated(true) self.icon:SetAlpha(0.7) end
        end
    end
    b:SetScript("OnClick", function() UI:Show(id) end)
    return b
end

function UI:Create()
    if self.frame then return self.frame end
    local f = CreateFrame("Frame", "PandyGuildManagementFrame", UIParent, "BackdropTemplate")
    self.frame = f
    f:SetSize(WIDTH, HEIGHT)
    local pos = PandyGuildDB.window
    if pos then f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else f:SetPoint("CENTER") end
    f:SetScale(PGM.opt("scale") or 1)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function()
        UI:HideSecure()
        f:StartMoving()
    end)
    f:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        savePosition(f)
        UI:Fire("MOVED")
    end)
    W.Backdrop(f, C.bg, C.frame, 0.98)
    tinsert(UISpecialFrames, f:GetName())
    f:Hide()

    -- Header plate.
    local header = CreateFrame("Frame", nil, f, "BackdropTemplate")
    header:SetPoint("TOPLEFT", 15, -10)
    header:SetPoint("TOPRIGHT", -15, -10)
    header:SetHeight(54)
    W.Backdrop(header, C.panel, C.frame, 1)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", f:GetScript("OnDragStart"))
    header:SetScript("OnDragStop", f:GetScript("OnDragStop"))

    local portrait = W.FramedIcon(header, 42, "Interface\\AddOns\\PandyGuildManagement\\Media\\Logo")
    portrait:SetPoint("LEFT", 6, 0)

    local title = W.FS(header, 17, C.text)
    title:SetPoint("TOPLEFT", portrait, "TOPRIGHT", 10, -3)
    title:SetText(PGM.Hex(C.jade) .. "Pandy|r Guild Management")
    f.guildName = W.FS(header, 12, C.text2)
    f.guildName:SetPoint("BOTTOMLEFT", portrait, "BOTTOMRIGHT", 10, 4)
    f.guildName:SetWidth(420)

    f.statusTop = W.FS(header, 12, C.text, "RIGHT")
    f.statusTop:SetPoint("TOPRIGHT", -42, -10)
    f.statusTop:SetWidth(360)
    f.statusBottom = W.FS(header, 11, C.text3, "RIGHT")
    f.statusBottom:SetPoint("BOTTOMRIGHT", -42, 10)
    f.statusBottom:SetWidth(360)

    local close = W.Button(header, "X", 24, 24, C.text2)
    close:SetPoint("TOPRIGHT", -8, -8)
    close:HookScript("OnEnter", function(s) s:SetBackdropBorderColor(C.red[1], C.red[2], C.red[3], 1) s:SetAccent(C.red) end)
    close:HookScript("OnLeave", function(s) s:SetAccent(C.text2) end)
    close:SetScript("OnClick", function() f:Hide() end)

    -- Sidebar.
    local side = CreateFrame("Frame", nil, f, "BackdropTemplate")
    side:SetPoint("TOPLEFT", 16, -73)
    side:SetPoint("BOTTOMLEFT", 16, 17)
    side:SetWidth(SIDE_W)
    W.Backdrop(side, C.side, C.frame, 1)

    local placed = {}
    for _, sec in ipairs(NAV) do
        for _, id in ipairs(sec.ids) do placed[id] = true end
    end
    for _, id in ipairs(self.order) do
        if not placed[id] then table.insert(NAV[#NAV].ids, id) end
    end

    f.navButtons = {}
    local y = -12
    for _, sec in ipairs(NAV) do
        local any = false
        for _, id in ipairs(sec.ids) do if self.tabs[id] then any = true end end
        if any then
            local h = W.Heading(side, sec.heading, 10)
            h:SetPoint("TOPLEFT", 14, y)
            y = y - 17
            for _, id in ipairs(sec.ids) do
                local tab = self.tabs[id]
                if tab then
                    local b = navTab(side, id, tab.label)
                    b:SetPoint("TOPLEFT", 11, y)
                    f.navButtons[id] = b
                    y = y - 30
                end
            end
            y = y - 10
        end
    end

    local foot = W.FS(side, 10, C.text3, "CENTER")
    foot:SetPoint("BOTTOM", 0, 12)
    foot:SetText("/pgm  -  v" .. PGM.VERSION)
    f.foot = foot
    local footLine = W.Divider(side)
    footLine:SetPoint("BOTTOMLEFT", 14, 30)
    footLine:SetPoint("BOTTOMRIGHT", -14, 30)

    -- The page well.
    local main = CreateFrame("Frame", nil, f, "BackdropTemplate")
    main:SetPoint("TOPLEFT", side, "TOPRIGHT", 13, 0)
    main:SetPoint("BOTTOMRIGHT", -16, 17)
    W.Backdrop(main, C.panel, C.frame, 1)
    f.main = main
    f.content = CreateFrame("Frame", nil, main)
    f.content:SetPoint("TOPLEFT", 12, -12)
    f.content:SetPoint("BOTTOMRIGHT", -12, 12)

    -- Corner grabber: drag to scale the window.
    local grab = CreateFrame("Button", nil, f)
    grab:SetSize(16, 16)
    grab:SetPoint("BOTTOMRIGHT", -3, 3)
    grab:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grab:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grab:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grab:SetScript("OnMouseDown", function(s, button)
        if button ~= "LeftButton" then return end
        UI:HideSecure()
        local x, yy = GetCursorPosition()
        s.dragging, s.x, s.y, s.scale = true, x, yy, f:GetScale()
    end)
    grab:SetScript("OnUpdate", function(s)
        if not s.dragging then return end
        local x, yy = GetCursorPosition()
        local delta = ((x - s.x) - (yy - s.y)) / (2 * UIParent:GetEffectiveScale())
        f:SetScale(math.max(0.6, math.min(1.6, s.scale + delta / 800)))
    end)
    grab:SetScript("OnMouseUp", function(s)
        if not s.dragging then return end
        s.dragging = false
        local scale = math.floor(f:GetScale() * 20 + 0.5) / 20
        f:SetScale(scale)
        PGM.setOpt("scale", scale)
        UI:Fire("MOVED")
    end)

    f:SetScript("OnShow", function()
        PGM:RequestRoster()
        UI:Refresh()
    end)
    -- Closing the window closes the profile too, or the after-combat refresh
    -- would put the secure buttons back on screen with no window behind them.
    f:SetScript("OnHide", function() UI:HideProfile() end)
    return f
end

-- ============================================================
-- PAGES
-- ============================================================

function UI:Show(id)
    local f = self:Create()
    id = (id and self.tabs[id]) and id or self.current or "overview"
    for tid, tab in pairs(self.tabs) do
        if tab.panel then tab.panel:SetShown(tid == id) end
        f.navButtons[tid]:SetSelected(tid == id)
    end
    local tab = self.tabs[id]
    if not tab.panel then
        tab.panel = CreateFrame("Frame", nil, f.content)
        tab.panel:SetAllPoints()
        tab.build(tab.panel)
    end
    tab.panel:Show()
    if self.current ~= id then
        UI:HideProfile()
        UI:HideSecure()
    end
    self.current = id
    f:Show()
    self:Refresh()
end

function UI:Toggle()
    local f = self:Create()
    if f:IsShown() then f:Hide() else self:Show() end
end

function UI:Refresh()
    local f = self.frame
    if not (f and f:IsShown()) then return end
    local key, name = PGM.GuildKey()
    local realm = key and key:match("%-(.+)$")
    f.guildName:SetText(name and (PGM.Hex(C.text) .. "<" .. name .. ">|r" .. (realm and ("  " .. realm) or ""))
        or "Not in a guild on this character")
    local g = PGM.GuildDB()
    if g and g.lastScan then
        local total, online = PGM:CountMembers()
        f.statusTop:SetText(("%s%d|r members   %s%d online|r"):format(PGM.Hex(C.text), total, PGM.Hex(C.jade), online))
        f.statusBottom:SetText("Roster read " .. PGM.AgoText(g.lastScan))
    else
        f.statusTop:SetText(key and "Reading the roster..." or "")
        f.statusBottom:SetText("")
    end
    local newer = PGM.UpdateAvailable and PGM:UpdateAvailable()
    if f.foot then
        f.foot:SetText("/pgm  -  v" .. PGM.VERSION
            .. (newer and ("  " .. PGM.Hex(C.amber) .. "(v" .. newer .. " is out)|r") or ""))
    end
    local tab = self.tabs[self.current]
    if tab and tab.panel and tab.refresh then tab.refresh(tab.panel) end
    if self.profile and self.profile:IsVisible() and self.RefreshProfile then self:RefreshProfile() end
end

-- Roster scans can arrive every few seconds; repaint at most once a second.
local refreshQueued = false
local function queueRefresh()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0.5, function()
        refreshQueued = false
        UI:Refresh()
    end)
end
PGM:On("ROSTER", queueRefresh)
PGM:On("RAIDS", queueRefresh)
PGM:On("TEAMS", queueRefresh)
PGM:On("SYNC", queueRefresh)
PGM:On("ACTIVITY", queueRefresh)
PGM:On("LOG", queueRefresh)

-- UI-only messages (window moved, and so on).
local uiListeners = {}
function UI:On(msg, fn)
    uiListeners[msg] = uiListeners[msg] or {}
    table.insert(uiListeners[msg], fn)
end
function UI:Fire(msg, ...)
    for _, fn in ipairs(uiListeners[msg] or {}) do fn(...) end
end

-- ============================================================
-- SECURE BUTTONS
-- ============================================================

-- Promote, demote and remove are protected: an addon can only offer a secure
-- button that runs Blizzard's own /gpromote when you click it. A protected
-- frame inside our window would make the whole window protected, and then it
-- couldn't be closed in combat. So the secure buttons live in their own
-- holder parented to UIParent and are placed over the profile page by
-- position, never anchored to it.
function UI:SecureHolder()
    if self.secure then return self.secure end
    local h = CreateFrame("Frame", "PandyGuildManagementSecure", UIParent)
    h:SetSize(330, 26)
    h:SetFrameStrata("DIALOG")
    h:Hide()
    self.secure = h
    return h
end

function UI:PlaceSecure(anchor)
    if InCombatLockdown() then return false end
    local left, bottom = anchor:GetLeft(), anchor:GetBottom()
    if not left or not bottom then return false end
    local h = self:SecureHolder()
    local f = self.frame
    h:SetScale(f:GetEffectiveScale() / UIParent:GetEffectiveScale())
    h:ClearAllPoints()
    h:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
    h:Show()
    return true
end

-- Hiding also disarms Remove, so it can never come back already armed.
function UI:HideSecure()
    if self.secure and not InCombatLockdown() then
        if self.DisarmRemove then self:DisarmRemove() end
        if self.secure:IsShown() then self.secure:Hide() end
    end
end

-- Combat lockdown starts right after this event, while it still allows it:
-- tuck the secure buttons away so they can't be left floating mid-fight.
PGM:RegisterEvent("PLAYER_REGEN_DISABLED", function() UI:HideSecure() end)
PGM:RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if UI.profile and UI.profile:IsVisible() and UI.RefreshProfile then UI:RefreshProfile() end
end)

-- The holder is placed by screen position, so a UI scale or resolution
-- change leaves it in the wrong spot. Put it back where it belongs.
local function replaceSecure()
    if InCombatLockdown() then return end
    UI:HideSecure()
    if UI.profile and UI.profile:IsVisible() and UI.RefreshProfile then UI:RefreshProfile() end
    UI:Fire("MOVED")   -- anything else placed by position goes back too
end
PGM:RegisterEvent("UI_SCALE_CHANGED", replaceSecure)
PGM:RegisterEvent("DISPLAY_SIZE_CHANGED", replaceSecure)
