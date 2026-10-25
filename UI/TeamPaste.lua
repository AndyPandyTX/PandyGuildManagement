-- TeamPaste.lua (UI): paste a roster into a raid team. Copy the cells from a
-- spreadsheet (a wowaudit sheet, say), or paste CSV or a bot's JSON, and see
-- what it would do before anything changes. Teams.lua does the reading.

local _, NS = ...
local PGM = NS.PGM
local C = PGM.C
local UI = PGM.UI
local W = UI.W

local frame

local function names(list, fmt)
    local g = PGM.GuildDB()
    local parts = {}
    for _, it in ipairs(list) do
        local rec = g and g.members[it.guid]
        if rec then parts[#parts + 1] = fmt(it, rec) end
    end
    return table.concat(parts, ", ")
end

local function spot(role, status)
    local bits = {}
    if role then bits[#bits + 1] = PGM.Hex(PGM.ROLE_COLOR[role]) .. PGM.ROLE_LABEL[role] .. "|r" end
    if status then bits[#bits + 1] = PGM.Hex(PGM.STATUS_COLOR[status]) .. PGM.STATUS_LABEL[status] .. "|r" end
    return table.concat(bits, " ")
end

local function preview()
    local f = frame
    local plan = PGM:PlanTeamPaste(f.teamId, f.edit:GetText())
    f.plan = plan
    local lines = {}
    if #plan.add + #plan.change + plan.same + #plan.unknown == 0 then
        f.preview:SetText(PGM.Hex(C.text3) .. "Nothing to import yet.|r")
        f.import:Hide()
        return
    end
    lines[#lines + 1] = ("%sAdds %d|r   %sUpdates %d|r   %s%d already on the team|r"):format(
        PGM.Hex(C.jade), #plan.add, PGM.Hex(C.accent), #plan.change, PGM.Hex(C.text2), plan.same)
    if #plan.add > 0 then
        lines[#lines + 1] = PGM.Hex(C.text2) .. "Adds:|r " .. names(plan.add, function(it, rec)
            return PGM.ColorName(rec) .. " (" .. spot(it.role, it.status) .. ")"
        end)
    end
    if #plan.change > 0 then
        lines[#lines + 1] = PGM.Hex(C.text2) .. "Updates:|r " .. names(plan.change, function(it, rec)
            return PGM.ColorName(rec) .. " to " .. spot(it.role, it.status)
        end)
    end
    if #plan.unknown > 0 then
        lines[#lines + 1] = PGM.Hex(C.amber) .. "Not in the guild, skipped:|r " .. table.concat(plan.unknown, ", ")
    end
    f.preview:SetText(table.concat(lines, "\n\n"))
    f.import:SetShown(#plan.add + #plan.change > 0)
end

local function create()
    local f = CreateFrame("Frame", "PandyGuildManagementTeamPaste", UIParent, "BackdropTemplate")
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
    local hint = W.FS(f, 11, C.text3)
    hint:SetPoint("TOPLEFT", 14, -32)
    hint:SetPoint("TOPRIGHT", -14, -32)
    hint:SetWordWrap(true)
    hint:SetText("One character per line. Copy the cells from a spreadsheet (name, and optionally role and Core / Trial / Bench), or paste CSV. Only adds and updates; nobody is taken off the team.")

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
        local t = PGM:TeamById(f.teamId)
        if not (t and f.plan) then return end
        local added, changed = PGM:ApplyTeamPaste(t.id, f.plan)
        PGM.Print(("%s: added %d, updated %d from the pasted list."):format(t.name, added, changed))
        f:Hide()
    end)
    return f
end

function UI:ShowTeamPaste(team)
    frame = frame or create()
    frame.teamId = team.id
    frame.title:SetText("Paste a list into " .. team.name)
    frame.edit:SetText("")
    frame.plan = nil
    frame:Show()
    preview()
    frame.edit:SetFocus()
end
