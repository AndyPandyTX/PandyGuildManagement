-- Minimap.lua (UI): the panda button on the minimap, and the same launcher
-- for other addons.
--
-- It's a LibDataBroker object, so broker displays (Titan Panel,
-- ChocolateBar, ElvUI's data texts and the like) can show it, with the
-- number of guildies online as its text. LibDBIcon puts it on the minimap:
-- drag it around the edge to move it, and minimap button collectors pick it
-- up like any other. Where it sits and whether it shows are saved in
-- PandyGuildDB.minimap, LibDBIcon's own format.

local _, NS = ...
local PGM = NS.PGM
local UI = PGM.UI

local NAME = "PandyGuildManagement"
local ICON = "Interface\\AddOns\\PandyGuildManagement\\Media\\Logo"

local ldb = LibStub and LibStub("LibDataBroker-1.1", true)
local icon = LibStub and LibStub("LibDBIcon-1.0", true)
if not ldb then return end

local function onlineText()
    if not (IsInGuild() and PGM.GuildDB() and PGM.CountMembers) then return "" end
    local _, online = PGM:CountMembers()
    return online .. " online"
end

local launcher = ldb:NewDataObject(NAME, {
    type = "data source",
    label = "Pandy Guild",
    text = "",
    icon = ICON,
    OnClick = function(_, button)
        if button == "RightButton" then
            UI:Show("settings")
        else
            UI:Toggle()
        end
    end,
    OnTooltipShow = function(tt)
        tt:AddLine(PGM.NAME)
        local g = PGM.GuildDB()
        if g and PGM.CountMembers then
            local total, online = PGM:CountMembers()
            tt:AddLine(("%d members, %d online"):format(total, online), 1, 1, 1)
        end
        tt:AddLine("Click to open, right-click for settings", 0.6, 0.6, 0.6)
        if icon then tt:AddLine("Drag to move it around the minimap", 0.6, 0.6, 0.6) end
    end,
})

local function refresh()
    if launcher then launcher.text = onlineText() end
end
PGM:On("ROSTER", refresh)

-- Show or hide the minimap button (broker displays keep theirs).
function PGM:MinimapShown()
    return not (PandyGuildDB and PandyGuildDB.minimap and PandyGuildDB.minimap.hide)
end

function PGM:SetMinimapShown(show)
    if not (icon and PandyGuildDB) then return false end
    PandyGuildDB.minimap = PandyGuildDB.minimap or {}
    PandyGuildDB.minimap.hide = not show or nil
    if show then icon:Show(NAME) else icon:Hide(NAME) end
    return true
end

function PGM:HasMinimapButton()
    return icon ~= nil
end

PGM:On("LOGIN", function()
    refresh()
    if not (icon and launcher) then return end
    PandyGuildDB.minimap = PandyGuildDB.minimap or {}
    icon:Register(NAME, launcher, PandyGuildDB.minimap)
end)
