-- GuildFrame.lua (UI): quick buttons on Blizzard's Guild & Communities
-- window: open Pandy Guild & Groups, jump to History, and (for officers)
-- Bulk Actions. They sit just under the window's bottom-right corner, and
-- show only while the guild itself is the community being viewed.
--
-- They're plain buttons parented to the window, so they show and hide with
-- it; nothing of Blizzard's is changed or re-anchored.

local _, NS = ...
local PGM = NS.PGM
local UI = PGM.UI
local W = UI.W

local bar

local function guildSelected(cf)
    if not IsInGuild() then return false end
    local ok, selected = pcall(function() return cf:GetSelectedClubId() end)
    local okG, guild = pcall(function() return C_Club and C_Club.GetGuildClubId() end)
    selected, guild = ok and PGM.Plain(selected), okG and PGM.Plain(guild)
    -- If either is unknown, err on showing them.
    return not (selected and guild) or selected == guild
end

-- Right-aligned: lay the shown buttons out from the right edge, so hiding
-- Bulk Actions for a non-officer leaves no gap.
local function layout()
    local prev
    for i = #bar.buttons, 1, -1 do
        local b = bar.buttons[i]
        b:ClearAllPoints()
        if b:IsShown() then
            if prev then b:SetPoint("RIGHT", prev, "LEFT", -4, 0) else b:SetPoint("RIGHT") end
            prev = b
        end
    end
end

local function sync()
    if not bar then return end
    local cf = CommunitiesFrame
    bar:SetShown(cf ~= nil and guildSelected(cf))
    bar.bulk:SetShown(PGM.CanEdit ~= nil and PGM:CanEdit() or false)
    layout()
end

local function build()
    local cf = CommunitiesFrame
    if bar or not cf then return end
    bar = CreateFrame("Frame", nil, cf)
    bar:SetSize(1, 22)
    bar:SetPoint("TOPRIGHT", cf, "BOTTOMRIGHT", -4, -2)
    bar.buttons = {}
    local function add(label, w, page)
        local b = W.Button(bar, label, w, 22)
        b:SetScript("OnClick", function() UI:Show(page) end)
        bar.buttons[#bar.buttons + 1] = b
        return b
    end
    bar.main = add("Pandy Guild", 104)
    bar.history = add("History", 72, "log")
    bar.bulk = add("Bulk Actions", 104, "bulk")
    cf:HookScript("OnShow", sync)
    if cf.SelectClub then hooksecurefunc(cf, "SelectClub", sync) end
    sync()
end

-- Blizzard's Communities window loads on demand.
if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_Communities") then
    build()
else
    PGM:RegisterEvent("ADDON_LOADED", function(_, name)
        if name == "Blizzard_Communities" then build() end
    end)
end
-- Officer status can change with a roster read (a promotion, say).
PGM:On("ROSTER", sync)
