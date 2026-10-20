-- Export.lua (UI): a copy box. Addons can't write files, so exports are text
-- you select and copy (Ctrl+C) into a spreadsheet.

local _, NS = ...
local PGM = NS.PGM
local C = PGM.C
local UI = PGM.UI
local W = UI.W

local function create()
    local f = CreateFrame("Frame", "PandyGuildManagementExport", UIParent, "BackdropTemplate")
    f:SetSize(640, 420)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    W.Backdrop(f, C.bg, C.frame, 1)
    tinsert(UISpecialFrames, f:GetName())

    f.title = W.FS(f, 14, C.text)
    f.title:SetPoint("TOPLEFT", 14, -12)
    f.hint = W.FS(f, 11, C.text3)
    f.hint:SetPoint("TOPLEFT", 14, -32)
    f.hint:SetText("Press Ctrl+C to copy, then paste into a spreadsheet.")

    local close = W.Button(f, "Close", 70, 22, C.text2)
    close:SetPoint("TOPRIGHT", -12, -12)
    close:SetScript("OnClick", function() f:Hide() end)

    local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 14, -54)
    sf:SetPoint("BOTTOMRIGHT", -34, 14)
    local edit = CreateFrame("EditBox", nil, sf)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFont(STANDARD_TEXT_FONT, 11, "")
    edit:SetTextColor(C.text[1], C.text[2], C.text[3])
    edit:SetWidth(580)
    edit:SetScript("OnEscapePressed", function() f:Hide() end)
    -- Read-only: typing puts the original text back.
    edit:SetScript("OnTextChanged", function(s, user)
        if user and f.text then
            s:SetText(f.text)
            s:HighlightText()
        end
    end)
    sf:SetScrollChild(edit)
    f.edit = edit
    return f
end

function UI:ShowExport(title, text)
    self.export = self.export or create()
    local f = self.export
    f.title:SetText(title)
    f.text = text
    f.edit:SetText(text)
    f:Show()
    f.edit:SetFocus()
    f.edit:HighlightText()
end
