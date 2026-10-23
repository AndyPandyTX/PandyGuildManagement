-- Bulk.lua (UI): kick, promote or demote by rules, a batch per press.
--
-- Left: the rules for the chosen action, and the selected rule's editor.
-- Right: everyone the rules pick (untick to leave someone alone, which is
-- remembered), then the run controls. Starting asks for confirmation, then
-- arms a secure button and a hotkey; each press runs the next batch.
--
-- Like the profile's rank buttons, the run button is a secure button in
-- its own holder on UIParent, placed over the page by position, so the
-- window itself never becomes protected. It's disarmed (no commands, no
-- hotkey) whenever you leave the page, close the window or enter combat.

local _, NS = ...
local PGM = NS.PGM
local C = PGM.C
local UI = PGM.UI
local W = UI.W

local LABEL = { kick = "Kick", promote = "Promote", demote = "Demote" }
local VERB_ING = { kick = "kick", promote = "promote", demote = "demote" }
local DEFAULT_HOTKEY = "CTRL-SHIFT-K"
local LEFT_W = 290

local state = { action = "kick", rule = nil }
local page, holder, runBtn
local armed, wantArmed = false, false

StaticPopupDialogs.PANDYGUILD_BULK_START = {
    text = "%s",
    button1 = "Start", button2 = CANCEL,
    OnAccept = function() UI:BulkArm(true) end,
    timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true, preferredIndex = 3,
}

local function hotkey()
    local k = PGM.opt("bulkHotkey")
    return (k and k ~= "") and k or DEFAULT_HOTKEY
end

local function rankName(i)
    local n = GuildControlGetRankName and PGM.Plain(GuildControlGetRankName(i + 1))
    return (n and n ~= "") and n or ("Rank " .. (i + 1))
end

-- The ranks below yours: the only ones you can act on or move people to.
local function ranksBelowMe()
    local out = {}
    local my = PGM:MyRankIndex()
    local num = GuildControlGetNumRanks and PGM.Plain(GuildControlGetNumRanks()) or 0
    if not my then return out end
    for i = my + 1, (num or 0) - 1 do out[#out + 1] = i end
    return out
end

local function selectedRule()
    for _, r in ipairs(PGM:BulkRules(state.action)) do
        if r.id == state.rule then return r end
    end
end

local function changed()
    PGM:Fire("BULK")
end

-- ============================================================
-- THE SECURE RUN BUTTON
-- ============================================================

local function buildSecure()
    if holder then return end
    holder = CreateFrame("Frame", "PandyGuildManagementBulk", UIParent)
    holder:SetSize(260, 30)
    holder:SetFrameStrata("DIALOG")
    holder:Hide()
    runBtn = W.Button(holder, "", 260, 30, C.red, "SecureActionButtonTemplate", "PandyGuildManagementBulkRun")
    runBtn:SetAllPoints()
    -- Both edges, as with the profile buttons: the game acts on the edge the
    -- "ActionButtonUseKeyDown" setting picks and ignores the other.
    runBtn:RegisterForClicks("AnyUp", "AnyDown")
    runBtn:SetAttribute("type", "macro")
    -- PostClick runs after the secure action, for both edges; only the edge
    -- that acted counts. Then load the next batch.
    runBtn:SetScript("PostClick", function(s, _, down)
        if InCombatLockdown() then return end
        if (down and true or false) ~= GetCVarBool("ActionButtonUseKeyDown") then return end
        if s.batch then PGM:BulkSent(s.batch) end
        UI:BulkLoad()
    end)
end

-- Put the next batch on the button, or nothing when nobody is waiting.
function UI:BulkLoad()
    if not (runBtn and armed) or InCombatLockdown() then return end
    local text, items = PGM:BulkBatch()
    runBtn.batch = items
    runBtn:SetAttribute("macrotext", text)
    local action = PGM:BulkRunning()
    if text then
        local names = {}
        for i, it in ipairs(items) do
            if i > 2 then break end
            names[#names + 1] = it.rec.short
        end
        local more = #items > 2 and (" +" .. (#items - 2)) or ""
        runBtn:SetLabel(("%s %s%s"):format(LABEL[action] or "Run", table.concat(names, ", "), more))
    else
        local p = PGM:BulkProgress()
        runBtn:SetLabel(p.pending > 0 and "Waiting for the roster..." or "All done")
    end
end

local function place()
    if not (holder and page and page:IsVisible() and page.spot) or InCombatLockdown() then return false end
    local left, bottom = page.spot:GetLeft(), page.spot:GetBottom()
    if not left or not bottom then return false end
    holder:SetScale(UI.frame:GetEffectiveScale() / UIParent:GetEffectiveScale())
    holder:ClearAllPoints()
    holder:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
    holder:Show()
    return true
end

-- Arm: commands on the button, the hotkey bound to it. `fresh` starts a new
-- run from the rules; otherwise the run in progress resumes.
function UI:BulkArm(fresh)
    if InCombatLockdown() then return end
    if fresh then PGM:BulkStart(state.action) end
    if not PGM:BulkRunning() then return end
    buildSecure()
    armed, wantArmed = true, true
    if not place() then
        C_Timer.After(0, function() if armed then place() end end)
    end
    ClearOverrideBindings(holder)
    SetOverrideBindingClick(holder, true, hotkey(), "PandyGuildManagementBulkRun", "LeftButton")
    UI:BulkLoad()
    UI:Refresh()
end

-- Disarm: no commands, no hotkey, out of sight. The run itself is kept, so
-- it can be resumed. Out of combat only; PLAYER_REGEN_DISABLED comes just
-- before the lock, so a fight never starts with it armed.
function UI:BulkDisarm()
    armed = false
    if not holder or InCombatLockdown() then return end
    runBtn.batch = nil
    runBtn:SetAttribute("macrotext", nil)
    ClearOverrideBindings(holder)
    holder:Hide()
end

-- Everything that hides the profile's secure buttons (switching pages,
-- dragging or scaling the window) disarms this too.
hooksecurefunc(UI, "HideSecure", function() UI:BulkDisarm() end)
PGM:RegisterEvent("PLAYER_REGEN_DISABLED", function()
    wantArmed = false
    UI:BulkDisarm()
end)
-- After a drag or scale, put it back where it was, if it was armed.
UI:On("MOVED", function()
    if wantArmed and PGM:BulkRunning() and page and page:IsVisible() then UI:BulkArm(false) end
end)
PGM:On("BULK", function()
    if armed then UI:BulkLoad() end
    UI:Refresh()
end)

-- ============================================================
-- PAGE
-- ============================================================

local function label(parent, text, x, y, col)
    local fs = W.FS(parent, 12, col or C.text2)
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text)
    return fs
end

-- A number box: empty means "no limit".
local function numBox(parent, w)
    local e = W.EditBox(parent, w or 48, 22, "")
    e:SetNumeric(true)
    e:SetMaxLetters(4)
    e:SetJustifyH("CENTER")
    return e
end

local function setNumber(field)
    return function(s)
        local r = selectedRule()
        if not r then return end
        local v = tonumber(s:GetText() or "")
        if r[field] ~= v then
            r[field] = v
            changed()
        end
    end
end

local function showNumber(box, v)
    if not box:HasFocus() then box:SetText(v and tostring(v) or "") end
end

local function buildEditor(p, ed)
    local y = 0
    label(ed, "Name", 0, y - 4)
    ed.name = W.EditBox(ed, 200, 22, "Rule name")
    ed.name:SetPoint("TOPLEFT", 84, y)
    ed.name:SetMaxLetters(40)
    ed.name.onCommit = function(s)
        local r = selectedRule()
        local t = strtrim(s:GetText() or "")
        if r and t ~= "" and t ~= r.name then r.name = t changed() end
    end

    y = y - 28
    ed.daysLabel = label(ed, "Away at least", 0, y - 4)
    ed.days = numBox(ed)
    ed.days:SetPoint("TOPLEFT", 84, y)
    label(ed, "days", 140, y - 4, C.text3)
    ed.days.onCommit = function(s)
        local r = selectedRule()
        if not r then return end
        local v = tonumber(s:GetText() or "")
        local field = state.action == "promote" and "seenDays" or "awayDays"
        if r[field] ~= v then r[field] = v changed() end
    end

    y = y - 28
    label(ed, "Ranks", 0, y - 4)
    ed.ranks = W.Button(ed, "", 200, 22, C.text2)
    ed.ranks:SetPoint("TOPLEFT", 84, y)
    ed.ranks:SetScript("OnClick", function(s)
        local r = selectedRule()
        if not r then return end
        local entries = {}
        for _, i in ipairs(ranksBelowMe()) do
            entries[#entries + 1] = { rankName(i),
                checked = function() return r.ranks and r.ranks[i] end,
                toggle = function()
                    r.ranks = r.ranks or {}
                    r.ranks[i] = not r.ranks[i] or nil
                    if not next(r.ranks) then r.ranks = nil end
                    changed()
                end }
        end
        W.Menu(s, "Only these ranks (none = any below yours)", entries)
    end)

    y = y - 28
    label(ed, "Level", 0, y - 4)
    ed.minLevel = numBox(ed, 40)
    ed.minLevel:SetPoint("TOPLEFT", 84, y)
    ed.minLevel.onCommit = setNumber("minLevel")
    label(ed, "to", 130, y - 4, C.text3)
    ed.maxLevel = numBox(ed, 40)
    ed.maxLevel:SetPoint("TOPLEFT", 150, y)
    ed.maxLevel.onCommit = setNumber("maxLevel")

    y = y - 28
    label(ed, "In guild", 0, y - 4)
    ed.joined = numBox(ed)
    ed.joined:SetPoint("TOPLEFT", 84, y)
    ed.joined.onCommit = setNumber("joinedDays")
    label(ed, "days or more", 140, y - 4, C.text3)

    y = y - 28
    ed.toLabel = label(ed, "Move to", 0, y - 4)
    ed.toRank = W.Button(ed, "", 200, 22, C.accent)
    ed.toRank:SetPoint("TOPLEFT", 84, y)
    ed.toRank:SetScript("OnClick", function(s)
        local r = selectedRule()
        if not r then return end
        local entries = {}
        for _, i in ipairs(ranksBelowMe()) do
            entries[#entries + 1] = { rankName(i), function() r.toRank = i changed() end }
        end
        W.Menu(s, "Move them to", entries)
    end)
    ed.toY = y

    y = y - 28
    ed.noteLabel = label(ed, "Note has", 0, y - 4)
    ed.note = W.EditBox(ed, 200, 22, "Text in their notes (optional)")
    ed.note:SetPoint("TOPLEFT", 84, y)
    ed.note:SetMaxLetters(40)
    ed.note.onCommit = function(s)
        local r = selectedRule()
        local t = strtrim(s:GetText() or "")
        if r and t ~= (r.note or "") then r.note = t ~= "" and t or nil changed() end
    end

    y = y - 30
    ed.skipTeams = W.Check(ed, "Leave raid team members alone",
        function() local r = selectedRule() return r and r.skipTeams end,
        function(v) local r = selectedRule() if r then r.skipTeams = v or nil changed() end end)
    ed.skipTeams:SetPoint("TOPLEFT", 0, y)
    ed.skipTeams:SetWidth(LEFT_W)

    y = y - 24
    ed.keepGroup = W.Check(ed, "...or anyone whose alt or main was on",
        function() local r = selectedRule() return r and r.keepIfGroupActive end,
        function(v) local r = selectedRule() if r then r.keepIfGroupActive = v or nil changed() end end)
    ed.keepGroup:SetPoint("TOPLEFT", 0, y)
    ed.keepGroup:SetWidth(LEFT_W)
    ed.keepGroup:HookScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_TOP")
        GameTooltip:SetText("Leave them alone if any character in their group was online within the days above.", 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    ed.keepGroup:HookScript("OnLeave", function() GameTooltip:Hide() end)

    y = y - 32
    ed.delete = W.Button(ed, "Delete rule", 100, 22, C.red)
    ed.delete:SetPoint("TOPLEFT", 0, y)
    ed.delete:SetScript("OnClick", function()
        local r = selectedRule()
        if r then
            PGM:BulkDeleteRule(state.action, r.id)
            state.rule = nil
        end
    end)
end

local function ruleRow(list)
    local r = W.Row(list)
    r.check = W.Check(r, "", function() return r.rule and r.rule.on end,
        function(v) if r.rule then r.rule.on = v or nil changed() end end)
    r.check:SetPoint("LEFT", 4, 0)
    r.check:SetWidth(20)
    r.name = W.FS(r, 12, C.text)
    r.name:SetPoint("LEFT", 30, 0)
    r.name:SetPoint("RIGHT", -50, 0)
    r.count = W.FS(r, 11, C.text3, "RIGHT")
    r.count:SetPoint("RIGHT", -6, 0)
    r:SetScript("OnClick", function(s)
        UI:CommitBulkEdits()
        state.rule = s.rule.id
        UI:Refresh()
    end)
    return r
end

local function ruleUpdate(r, rule)
    r.rule = rule
    r.check:Sync()
    local sel = rule.id == state.rule
    r.name:SetText((sel and PGM.Hex(C.accent) or "") .. (rule.name or "Rule") .. (sel and "|r" or ""))
    r.count:SetText(rule.on and tostring(PGM:BulkRuleCount(state.action, rule)) or "off")
end

local STATE_TEXT = {
    pending = { "sent...", C.gold }, done = { "done", C.jade },
    failed = { "failed", C.red }, gone = { "left", C.text3 },
}

local function queueRow(list)
    local r = W.Row(list)
    r.tick = CreateFrame("Frame", nil, r, "BackdropTemplate")
    r.tick:SetSize(14, 14)
    r.tick:SetPoint("LEFT", 6, 0)
    W.Backdrop(r.tick, { 0.02, 0.02, 0.025 }, C.frame, 1)
    r.tick.fill = W.Solid(r.tick, "ARTWORK", C.accent)
    r.tick.fill:SetPoint("TOPLEFT", 3, -3)
    r.tick.fill:SetPoint("BOTTOMRIGHT", -3, 3)
    r.name = W.FS(r, 12, C.text)
    r.name:SetPoint("LEFT", 28, 0)
    r.name:SetWidth(140)
    r.rank = W.FS(r, 12, C.text2)
    r.rank:SetPoint("LEFT", 174, 0)
    r.rank:SetWidth(96)
    r.seen = W.FS(r, 12, C.text2)
    r.seen:SetPoint("LEFT", 276, 0)
    r.seen:SetWidth(64)
    r.right = W.FS(r, 12, C.text2, "RIGHT")
    r.right:SetPoint("RIGHT", -6, 0)
    r.right:SetWidth(66)
    r:SetScript("OnClick", function(s, button)
        local it = s.item
        if button == "RightButton" then
            UI:MemberMenu(s, it.guid)
        elseif not PGM:BulkRunning() then
            PGM:BulkSetIgnored(it.action, it.guid, not it.ignored)
        end
    end)
    r.onEnter = function(s)
        local it = s.item
        GameTooltip:SetOwner(s, "ANCHOR_CURSOR_RIGHT")
        GameTooltip:SetText(PGM.ColorName(it.rec))
        GameTooltip:AddLine("Picked by: " .. (it.rule and it.rule.name or "?"), 0.8, 0.8, 0.8)
        if it.rec.note and it.rec.note ~= "" then GameTooltip:AddLine("Note: " .. it.rec.note, 0.8, 0.8, 0.8, true) end
        local teams = PGM:TeamsText(it.guid)
        if teams ~= "" then GameTooltip:AddLine("Raid teams: " .. teams, 0.72, 0.54, 1) end
        if not PGM:BulkRunning() then
            GameTooltip:AddLine(it.ignored and "Click to include again" or "Click to leave them alone", 0.45, 0.45, 0.45)
        end
        GameTooltip:Show()
    end
    return r
end

local function queueUpdate(r, it)
    r.item = it
    -- The roster swaps in fresh records on every read; show the current one
    -- (so a finished demotion shows its new rank), or the last known if
    -- they've left.
    local g = PGM.GuildDB()
    local rec = (g and g.members[it.guid]) or it.rec
    local running = PGM:BulkRunning()
    r.tick.fill:SetShown(not it.ignored)
    r.tick:SetShown(not running)
    r.name:SetText(PGM.ColorName(rec))
    r.rank:SetText(rec.rank or "?")
    r.seen:SetText(rec.online and (PGM.Hex(C.jade) .. "Online|r") or PGM.AgoText(rec.lastOnline))
    local s = running and PGM:BulkState(it.guid)
    if s and STATE_TEXT[s] then
        r.right:SetText(PGM.Hex(STATE_TEXT[s][2]) .. STATE_TEXT[s][1] .. "|r")
    elseif it.action ~= "kick" and it.toRank then
        r.right:SetText(PGM.Hex(C.text3) .. "> |r" .. rankName(it.toRank))
    else
        r.right:SetText("")
    end
    local alpha = it.ignored and 0.45 or 1
    for _, fs in ipairs({ r.name, r.rank, r.seen, r.right }) do fs:SetAlpha(alpha) end
end

function UI:CommitBulkEdits()
    if not page then return end
    local ed = page.editor
    for _, box in ipairs({ ed.name, ed.days, ed.minLevel, ed.maxLevel, ed.joined, ed.note }) do box:ClearFocus() end
end

local function build(p)
    page = p
    p:SetScript("OnHide", function()
        wantArmed = false
        UI:BulkDisarm()
    end)

    p.chips = {}
    local prev
    for _, a in ipairs(PGM.BULK_ACTIONS) do
        local chip = W.Chip(p, LABEL[a], function()
            if PGM:BulkRunning() and PGM:BulkRunning() ~= a then
                PGM.Print("Finish or stop the current run first.")
                return
            end
            UI:CommitBulkEdits()
            state.action, state.rule = a, nil
            UI:Refresh()
        end)
        if prev then chip:SetPoint("LEFT", prev, "RIGHT", 6, 0) else chip:SetPoint("TOPLEFT", 0, 0) end
        p.chips[a] = chip
        prev = chip
    end
    p.perms = W.FS(p, 11, C.text3, "RIGHT")
    p.perms:SetPoint("TOPRIGHT", 0, -5)

    -- Left: rules.
    local rh = W.FS(p, 13, C.accent)
    rh:SetPoint("TOPLEFT", 0, -38)
    rh:SetText("Rules")
    p.newRule = W.Button(p, "+ New rule", 90, 22)
    p.newRule:SetPoint("TOPLEFT", LEFT_W - 90, -34)
    p.newRule:SetScript("OnClick", function()
        UI:CommitBulkEdits()
        local r = PGM:BulkNewRule(state.action)
        if r then state.rule = r.id end
        UI:Refresh()
    end)
    p.rules = W.List(p, 24, ruleRow, ruleUpdate)
    p.rules:SetPoint("TOPLEFT", 0, -62)
    p.rules:SetSize(LEFT_W, 24 * 4)
    p.noRules = W.FS(p, 11, C.text3)
    p.noRules:SetPoint("TOPLEFT", 4, -66)
    p.noRules:SetWidth(LEFT_W - 8)
    p.noRules:SetWordWrap(true)

    local ed = CreateFrame("Frame", nil, p)
    ed:SetPoint("TOPLEFT", 0, -172)
    ed:SetSize(LEFT_W, 330)
    p.editor = ed
    buildEditor(p, ed)

    local divider = W.Solid(p, "BORDER", C.line, 1)
    divider:SetPoint("TOPLEFT", LEFT_W + 14, -34)
    divider:SetPoint("BOTTOMLEFT", LEFT_W + 14, 0)
    divider:SetWidth(1)

    -- Right: who they pick, and the run.
    local x = LEFT_W + 30
    p.qHead = W.FS(p, 13, C.accent)
    p.qHead:SetPoint("TOPLEFT", x, -38)
    p.ignored = W.FS(p, 11, C.text3, "RIGHT")
    p.ignored:SetPoint("TOPRIGHT", -70, -40)
    p.clearIgnored = W.Button(p, "Clear", 60, 20, C.text2)
    p.clearIgnored:SetPoint("TOPRIGHT", 0, -36)
    p.clearIgnored.tip = "Include everyone you've left alone for this action again."
    p.clearIgnored:SetScript("OnClick", function() PGM:BulkClearIgnored(state.action) end)

    p.queue = W.List(p, 22, queueRow, queueUpdate)
    p.queue:SetPoint("TOPLEFT", x, -62)
    p.queue:SetPoint("BOTTOMRIGHT", 0, 96)
    p.empty = W.FS(p, 12, C.text3, "CENTER")
    p.empty:SetPoint("CENTER", p.queue, "CENTER")
    p.empty:SetWidth(360)
    p.empty:SetWordWrap(true)

    local bar = W.Divider(p)
    bar:SetPoint("BOTTOMLEFT", x, 88)
    bar:SetPoint("BOTTOMRIGHT", 0, 88)
    p.status = W.FS(p, 11, C.text2)
    p.status:SetPoint("BOTTOMLEFT", x, 66)
    p.status:SetPoint("BOTTOMRIGHT", -190, 66)
    p.status:SetWordWrap(true)

    -- The run button's spot: the secure button sits exactly here when armed;
    -- the plain Start / Resume button fills it otherwise.
    p.spot = CreateFrame("Frame", nil, p)
    p.spot:SetSize(260, 30)
    p.spot:SetPoint("BOTTOMLEFT", x, 26)
    p.start = W.Button(p, "Start", 260, 30, C.accent)
    p.start:SetAllPoints(p.spot)
    p.start:SetScript("OnClick", function()
        UI:CommitBulkEdits()
        if PGM:BulkRunning() then
            UI:BulkArm(false)
            return
        end
        local n = 0
        for _, it in ipairs(PGM:BulkMatches(state.action)) do if not it.ignored then n = n + 1 end end
        if n == 0 then return end
        local who = n == 1 and "member" or "members"
        local what = state.action == "kick" and ("Remove %d %s from the guild?"):format(n, who)
            or ("%s %d %s?"):format(LABEL[state.action], n, who)
        StaticPopup_Show("PANDYGUILD_BULK_START", what
            .. "\n\nNothing happens until you press the button or " .. hotkey()
            .. ". Each press does the next few.")
    end)
    p.stop = W.Button(p, "Stop", 80, 30, C.red)
    p.stop:SetPoint("LEFT", p.spot, "RIGHT", 8, 0)
    p.stop:SetScript("OnClick", function()
        wantArmed = false
        UI:BulkDisarm()
        PGM:BulkStop()
    end)

    p.keyText = W.FS(p, 11, C.text3, "RIGHT")
    p.keyText:SetPoint("BOTTOMRIGHT", -72, 64)
    p.keyBtn = W.Button(p, "Change", 64, 22, C.text2)
    p.keyBtn:SetPoint("BOTTOMRIGHT", 0, 60)
    p.keyBtn.tip = "The key that runs the next batch while a run is armed."
    -- Press the new key combination; Escape cancels.
    local capture = CreateFrame("Frame", nil, p)
    capture:SetAllPoints(p.keyBtn)
    capture:EnableKeyboard(false)
    local function endCapture()
        capture:EnableKeyboard(false)
        p.capturing = false
        UI:Refresh()
    end
    capture:SetScript("OnKeyDown", function(_, key)
        if key == "ESCAPE" then endCapture() return end
        if key:find("SHIFT") or key:find("CTRL") or key:find("ALT") or key:find("META") then return end
        local combo = (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "")
            .. (IsShiftKeyDown() and "SHIFT-" or "") .. key
        PGM.setOpt("bulkHotkey", combo)
        endCapture()
        if armed then UI:BulkArm(false) end
    end)
    p.keyBtn:SetScript("OnClick", function()
        if InCombatLockdown() then return end
        p.capturing = true
        capture:EnableKeyboard(true)
        capture:SetPropagateKeyboardInput(false)
        UI:Refresh()
    end)
end

local function refresh(p)
    local action = state.action
    local running = PGM:BulkRunning()
    local allowed = PGM:BulkAllowed()
    for a, chip in pairs(p.chips) do chip:SetActive(a == action) end
    -- Officers only: everyone else just sees why.
    p.newRule:SetShown(allowed.officer)
    p.keyBtn:SetShown(allowed.officer)
    if not allowed.officer then
        p.perms:SetText("")
        p.editor:Hide()
        p.rules:SetData({})
        p.noRules:SetText("")
        p.queue:SetData({})
        p.qHead:SetText("")
        p.ignored:SetText("")
        p.clearIgnored:Hide()
        p.empty:SetText("Bulk Actions is for officers: the same people who can edit raid teams.")
        p.status:SetText("")
        p.start:Hide()
        p.stop:Hide()
        p.keyText:SetText("")
        return
    end
    local can = {}
    for _, a in ipairs(PGM.BULK_ACTIONS) do if allowed[a] then can[#can + 1] = VERB_ING[a] end end
    p.perms:SetText(#can > 0 and ("Your rank can " .. table.concat(can, ", ") .. ". Only ranks below yours are listed.")
        or "Your rank can't kick, promote or demote.")

    -- Rules.
    local rules = PGM:BulkRules(action)
    if not selectedRule() then state.rule = rules[1] and rules[1].id or nil end
    p.rules:SetData(rules, true)
    p.noRules:SetText(#rules == 0 and ("No %s rules yet. Click + New rule to make one."):format(VERB_ING[action]) or "")

    local r = selectedRule()
    local ed = p.editor
    ed:SetShown(r ~= nil)
    if r then
        if not ed.name:HasFocus() then ed.name:SetText(r.name or "") end
        ed.daysLabel:SetText(action == "promote" and "Online within" or "Away at least")
        showNumber(ed.days, action == "promote" and r.seenDays or r.awayDays)
        local names = {}
        for i in pairs(r.ranks or {}) do names[#names + 1] = i end
        table.sort(names)
        for k, i in ipairs(names) do names[k] = rankName(i) end
        ed.ranks:SetLabel(#names > 0 and table.concat(names, ", ") or "Any rank below yours")
        showNumber(ed.minLevel, r.minLevel)
        showNumber(ed.maxLevel, r.maxLevel)
        showNumber(ed.joined, r.joinedDays)
        local moves = action ~= "kick"
        ed.toLabel:SetShown(moves)
        ed.toRank:SetShown(moves)
        ed.toRank:SetLabel(r.toRank and rankName(r.toRank) or "Pick a rank")
        if not ed.note:HasFocus() then ed.note:SetText(r.note or "") end
        ed.skipTeams:Sync()
        ed.keepGroup:Sync()
        ed.keepGroup:SetShown(action ~= "promote")
    end

    -- Queue: the run's own list while one is going, else a live preview.
    local items = running == action and PGM.Bulk.queue or PGM:BulkMatches(action)
    local included = 0
    for _, it in ipairs(items) do if not it.ignored then included = included + 1 end end
    p.queue:SetData(items, true)
    p.qHead:SetText(running == action and ("This run: %d"):format(#items)
        or ("%d to %s"):format(included, VERB_ING[action]))
    local ignoredN = PGM:BulkIgnoredCount(action)
    p.ignored:SetText(ignoredN > 0 and (ignoredN .. " left alone") or "")
    p.clearIgnored:SetShown(ignoredN > 0 and not running)
    if #items == 0 then
        p.empty:SetText(#rules == 0 and "Make a rule on the left, and everyone it picks shows up here."
            or "Nobody matches the rules that are on.")
    else
        p.empty:SetText("")
    end

    -- The run.
    local prog = PGM:BulkProgress()
    if running then
        local parts = { ("%d done"):format(prog.done) }
        if prog.pending > 0 then parts[#parts + 1] = ("%d sent"):format(prog.pending) end
        parts[#parts + 1] = ("%d to go"):format(prog.waiting)
        if prog.failed > 0 then parts[#parts + 1] = PGM.Hex(C.red) .. prog.failed .. " failed|r" end
        if prog.gone > 0 then parts[#parts + 1] = prog.gone .. " left on their own" end
        local finished = prog.waiting == 0 and prog.pending == 0
        p.status:SetText((finished and "Finished: " or "") .. table.concat(parts, "  ·  "))
        p.stop:SetLabel(finished and "Close" or "Stop")
        p.stop:Show()
        p.start:SetShown(not armed)
        p.start:SetLabel(("Resume (%d to go)"):format(prog.waiting + prog.pending))
        p.start:SetEnabled(true)
        p.start:SetAlpha(1)
    else
        p.status:SetText(allowed[action]
            and (included > 0 and "Each press of the button or hotkey does the next batch." or "")
            or ("Your rank can't %s."):format(VERB_ING[action]))
        p.stop:Hide()
        p.start:Show()
        p.start:SetLabel(("Start: %s %d"):format(VERB_ING[action], included))
        p.start:SetEnabled(allowed[action] and included > 0)
        p.start:SetAlpha((allowed[action] and included > 0) and 1 or 0.5)
    end
    if InCombatLockdown() then p.status:SetText("Paused for combat. Resume after.") end
    p.keyText:SetText(p.capturing and (PGM.Hex(C.accent) .. "Press a key, or Escape|r")
        or ("Hotkey: " .. PGM.Hex(C.text) .. hotkey() .. "|r"))
end

UI:AddTab({ id = "bulk", label = "Bulk Actions", build = build, refresh = refresh })
