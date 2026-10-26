-- PasteBox.lua (UI): a window to paste text into, with a live preview of
-- what importing it would do and an Import button, so nothing changes until
-- you've seen it. Raid teams' Paste list and the Loot page's import use it.
--
--   UI:ShowPasteBox({ title, hint,
--       preview = function(text) return previewText, canImport end,
--       import = function(text) end })

local _, NS = ...
local PGM = NS.PGM
local C = PGM.C
local UI = PGM.UI
local W = UI.W

local frame

local function preview()
    local f = frame
    local text, ok = f.opts.preview(f.edit:GetText() or "")
    f.preview:SetText(text or "")
    f.import:SetShown(ok and true or false)
end

local function create()
    local f = CreateFrame("Frame", "PandyGuildManagementPasteBox", UIParent, "BackdropTemplate")
    f:SetSize(640, 500)
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
    f.hint:SetPoint("TOPRIGHT", -14, -32)
    f.hint:SetWordWrap(true)

    local close = W.Button(f, "Cancel", 70, 22, C.text2)
    close:SetPoint("TOPRIGHT", -12, -10)
    close:SetScript("OnClick", function() f:Hide() end)

    local box = CreateFrame("Frame", nil, f, "BackdropTemplate")
    box:SetPoint("TOPLEFT", 14, -64)
    box:SetPoint("TOPRIGHT", -14, -64)
    box:SetHeight(220)
    W.Backdrop(box, C.panel, C.frame, 1)
    local sf = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 6, -6)
    sf:SetPoint("BOTTOMRIGHT", -26, 6)
    local edit = CreateFrame("EditBox", nil, sf)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFont(STANDARD_TEXT_FONT, 11, "")
    edit:SetTextColor(C.text[1], C.text[2], C.text[3])
    edit:SetWidth(570)
    edit:SetScript("OnEscapePressed", function() f:Hide() end)
    -- A tab key press would leave the box; pasted tabs still come through.
    edit:SetScript("OnTabPressed", function(s) s:Insert("\t") end)
    -- Clicking anywhere in the box puts the cursor in it.
    box:EnableMouse(true)
    box:SetScript("OnMouseDown", function() edit:SetFocus() end)
    local pending
    edit:SetScript("OnTextChanged", function(_, user)
        if not user or pending then return end
        pending = true
        C_Timer.After(0.3, function()
            pending = false
            if f:IsShown() then preview() end
        end)
    end)
    sf:SetScrollChild(edit)
    f.edit = edit

    f.preview = W.FS(f, 12, C.text)
    f.preview:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -12)
    f.preview:SetPoint("BOTTOMRIGHT", -14, 48)
    f.preview:SetJustifyV("TOP")
    f.preview:SetWordWrap(true)

    f.import = W.Button(f, "Import", 100, 26)
    f.import:SetPoint("BOTTOMRIGHT", -14, 14)
    f.import:SetScript("OnClick", function()
        f.opts.import(f.edit:GetText() or "")
        f:Hide()
    end)
    return f
end

function UI:ShowPasteBox(opts)
    frame = frame or create()
    frame.opts = opts
    frame.title:SetText(opts.title or "Paste")
    frame.hint:SetText(opts.hint or "")
    frame.edit:SetText("")
    frame:Show()
    preview()
    frame.edit:SetFocus()
end
