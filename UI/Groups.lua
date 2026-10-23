-- Groups.lua (UI): the board. On the left, the form to post a group, or,
-- while you have one up, your group and who's asking to join. On the right,
-- the guild's groups, live ones first, then the scheduled ones.

local _, NS = ...
local G = NS.G
if not G.ok then return end
local PGM = G.PGM
local C = PGM.C
local UI = PGM.UI
local W = UI.W
local GU = G.UI

local LEFT_W = 300
local state = { kinds = {}, myRole = false, editing = false }

local WHAT_HINT = { M = "Dungeon", R = "Raid", D = "Delve", O = "What you're doing" }
local LEVEL_HINT = { M = "Key", R = "N/H/M", D = "Tier", O = "" }

-- ============================================================
-- THE FORM
-- ============================================================

local form = {}

local function setKind(kind)
    form.kind = kind
    for k, chip in pairs(form.kindChips) do chip:SetActive(k == kind) end
    form.what.hint:SetText(WHAT_HINT[kind])
    form.level.hint:SetText(LEVEL_HINT[kind])
end

-- Fresh defaults for a kind: its size, and its roles minus my own.
local function defaults(kind)
    setKind(kind)
    form.size:SetText(G.KIND_SIZE[kind])
    local mine = G.SpecRole()
    for _, r in ipairs(G.ROLES) do
        local n = G.KIND_NEED[kind][r] - (r == mine and 1 or 0)
        form.need[r]:Set(n)
    end
    if kind == "M" then
        local map, level = G.ReadMyKey()
        form.what:SetText(map and G.DungeonName(map) or "")
        form.level:SetText(level or "")
    else
        form.what:SetText("")
        form.level:SetText("")
    end
end

-- Fill the form from a post (to edit it) or a keystone (to post it).
function G.UI.FillForm(p)
    if not form.card then return end   -- the page isn't built yet
    defaults(p.kind or "M")
    state.editing = p.id ~= nil
    form.editId = p.id
    form.what:SetText(p.what or "")
    form.level:SetText(p.level or "")
    form.size:SetText(p.size or G.KIND_SIZE[form.kind])
    if p.need then
        for _, r in ipairs(G.ROLES) do form.need[r]:Set(p.need[r]) end
    end
    form.note:SetText(p.note or "")
    form.when:SetText((p.start or 0) > 0 and G.StartText(p.start):gsub("^Today ", "") or "")
    form.team:SetValue(p.team or "")
    form.err:SetText("")
end

local function teamChoices()
    local list = { { "", "Everyone" } }
    local mine = {}
    for _, it in ipairs(PGM:TeamsOf(PGM:MyGuid() or "")) do mine[it.team.id] = true end
    for _, t in ipairs(PGM:Teams()) do
        if mine[t.id] or PGM:CanEdit() then list[#list + 1] = { t.id, t.name } end
    end
    return list
end

local function submit()
    local start = G.ParseWhen(form.when:GetText())
    if not start then
        form.err:SetText(PGM.Hex(C.red) .. "Start: leave empty for now, or 20:30, Sat 20:30, +30.|r")
        return
    end
    local need = {}
    for _, r in ipairs(G.ROLES) do need[r] = form.need[r].n end
    if G.NeedTotal(need) == 0 then
        form.err:SetText(PGM.Hex(C.red) .. "Pick at least one role you need.|r")
        return
    end
    local p, why = G:Post({
        id = form.editId, kind = form.kind, what = form.what:GetText(), level = form.level:GetText(),
        size = form.size:GetText(), need = need, team = form.team:Value(), start = start,
        guildFirst = form.first:Value(), note = form.note:GetText(),
    })
    if not p then
        form.err:SetText(PGM.Hex(C.red) .. (why or "Couldn't post that.") .. "|r")
        return
    end
    form.err:SetText("")
    state.editing, form.editId = false, nil
    for _, e in ipairs({ form.what, form.level, form.note, form.when }) do e:ClearFocus() end
    UI:Refresh()
end

local function label(parent, text, x, y)
    local fs = W.FS(parent, 11, C.text2)
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text)
    return fs
end

local function buildForm(card)
    form.card = card
    local x = 14
    form.kindChips = {}
    local prev
    for _, k in ipairs(G.KINDS) do
        local chip = W.Chip(card, G.KIND_LABEL[k], function() defaults(k) end)
        if prev then chip:SetPoint("LEFT", prev, "RIGHT", 6, 0) else chip:SetPoint("TOPLEFT", x, -46) end
        form.kindChips[k] = chip
        prev = chip
    end

    label(card, "What", x, -78)
    form.what = W.EditBox(card, LEFT_W - 28, 22, "")
    form.what:SetPoint("TOPLEFT", x, -92)
    form.what:SetMaxLetters(40)

    label(card, "Level", x, -122)
    form.level = W.EditBox(card, 70, 22, "")
    form.level:SetPoint("TOPLEFT", x, -136)
    form.level:SetMaxLetters(8)
    label(card, "Size", x + 84, -122)
    form.size = W.EditBox(card, 50, 22, "")
    form.size:SetPoint("TOPLEFT", x + 84, -136)
    form.size:SetNumeric(true)
    form.size:SetMaxLetters(2)

    label(card, "Still need", x, -168)
    form.need = {}
    for i, r in ipairs(G.ROLES) do
        local key = G.ROLE_KEY[r]
        local s = GU.Stepper(card, PGM.ROLE_LABEL[key], PGM.ROLE_COLOR[key])
        s:SetPoint("TOPLEFT", x + (i - 1) * 92, -184)
        form.need[r] = s
    end

    label(card, "Note", x, -226)
    form.note = W.EditBox(card, LEFT_W - 28, 22, "Weekly, timing it, learning...")
    form.note:SetPoint("TOPLEFT", x, -240)
    form.note:SetMaxLetters(70)

    label(card, "Start", x, -270)
    form.when = W.EditBox(card, LEFT_W - 28, 22, "Now, or 20:30, Sat 20:30, +30")
    form.when:SetPoint("TOPLEFT", x, -284)
    form.when:SetMaxLetters(16)

    form.team = GU.Cycle(card, "Show to: ", teamChoices())
    form.team:SetPoint("TOPLEFT", x, -318)
    form.first = GU.Cycle(card, "Guild first: ", {
        { 5, "5 min" }, { 10, "10 min" }, { 15, "15 min" }, { 0, "off" },
    }, function(s) G.setOpt("guildFirst", s:Value()) end)
    form.first:SetPoint("LEFT", form.team, "RIGHT", 6, 0)
    form.first:SetValue(G.opt("guildFirst"))
    form.first.tip = "How long only guildies can join before Find PuGs lights up."

    form.post = W.Button(card, "Post", 90, 26)
    form.post:SetPoint("TOPLEFT", x, -354)
    form.post:SetScript("OnClick", submit)
    form.cancel = W.Button(card, "Cancel", 80, 26, C.text2)
    form.cancel:SetPoint("LEFT", form.post, "RIGHT", 6, 0)
    form.cancel:SetScript("OnClick", function()
        state.editing, form.editId = false, nil
        defaults(form.kind)
        UI:Refresh()
    end)
    form.err = W.FS(card, 11, C.text2)
    form.err:SetPoint("TOPLEFT", x, -388)
    form.err:SetPoint("TOPRIGHT", -12, -388)
    form.err:SetWordWrap(true)

    -- Pings.
    local div = W.Divider(card)
    div:SetPoint("TOPLEFT", x, -420)
    div:SetPoint("TOPRIGHT", -12, -420)
    local h = W.Heading(card, "Pings")
    h:SetPoint("TOPLEFT", x, -430)
    form.ping = W.Check(card, "Ping me when a group needs my role",
        function() return G.opt("ping") end, function(v) G.setOpt("ping", v) end)
    form.ping:SetPoint("TOPLEFT", x, -444)
    form.ping:SetWidth(LEFT_W - 28)
    label(card, "I play", x, -474)
    form.roleChips = {}
    prev = nil
    for _, r in ipairs(G.ROLES) do
        local chip = W.Chip(card, PGM.ROLE_LABEL[G.ROLE_KEY[r]], function(s)
            local t = G.opt("roles")
            t[r] = not t[r] or nil
            s:SetActive(t[r] == true)
            G:SendStatus()
            UI:Refresh()
        end)
        chip.tip = "None ticked: whatever your spec is."
        if prev then chip:SetPoint("LEFT", prev, "RIGHT", 6, 0) else chip:SetPoint("TOPLEFT", x + 44, -470) end
        form.roleChips[r] = chip
        prev = chip
    end
    label(card, "For", x, -502)
    form.pingChips = {}
    prev = nil
    for _, k in ipairs(G.KINDS) do
        local chip = W.Chip(card, G.KIND_LABEL[k], function(s)
            local t = G.opt("pingKinds")
            t[k] = not t[k]
            s:SetActive(t[k])
        end)
        if prev then chip:SetPoint("LEFT", prev, "RIGHT", 4, 0) else chip:SetPoint("TOPLEFT", x + 44, -498) end
        form.pingChips[k] = chip
        prev = chip
    end
    defaults("M")
end

-- ============================================================
-- MY GROUP
-- ============================================================

local mineUI = {}

local function askRow(list)
    local r = W.Row(list)
    r.name = W.FS(r, 12, C.text)
    r.name:SetPoint("TOPLEFT", 8, -5)
    r.name:SetPoint("TOPRIGHT", -8, -5)
    r.info = W.FS(r, 11, C.text2)
    r.info:SetPoint("BOTTOMLEFT", 8, 5)
    r.info:SetPoint("BOTTOMRIGHT", -124, 5)
    r.invite = W.Button(r, "Invite", 56, 20, C.jade)
    r.invite:SetPoint("BOTTOMRIGHT", -64, 3)
    r.invite:SetScript("OnClick", function(s) G:InviteAsk(s:GetParent().it.key) end)
    r.decline = W.Button(r, "Decline", 56, 20, C.red)
    r.decline:SetPoint("BOTTOMRIGHT", -4, 3)
    r.decline:SetScript("OnClick", function(s) G:DeclineAsk(s:GetParent().it.key) end)
    r.done = W.FS(r, 11, C.jade, "RIGHT")
    r.done:SetPoint("BOTTOMRIGHT", -8, 6)
    r:SetScript("OnClick", function(s, button)
        local rec = s.it.rec
        if rec and button == "RightButton" then UI:MemberMenu(s, rec.guid)
        elseif rec then UI:OpenProfile(rec.guid) end
    end)
    r.onEnter = function(s)
        local a = s.it.ask
        if a.note == "" then return end
        GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
        GameTooltip:SetText(a.note, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end
    return r
end

local function specName(id)
    if not (id and id > 0 and GetSpecializationInfoByID) then return nil end
    local ok, _, name = pcall(GetSpecializationInfoByID, id)
    return ok and PGM.Plain(name) or nil
end

local function askUpdate(r, it)
    r.it = it
    local a, rec = it.ask, it.rec
    r.name:SetText(rec and G.WhoText(rec) or (a.name or "?"))
    local parts = { G.RoleText(a.role, true) }
    local spec = specName(a.spec)
    if spec then parts[#parts + 1] = spec end
    if a.ilvl > 0 then parts[#parts + 1] = a.ilvl .. " ilvl" end
    local score = rec and PGM:MPlusScore(rec)
    if score then parts[#parts + 1] = PGM.Hex(PGM:ScoreColor(score)) .. score .. "|r M+" end
    if a.note ~= "" then parts[#parts + 1] = PGM.Hex(C.text3) .. a.note .. "|r" end
    r.info:SetText(table.concat(parts, "   "))
    local open = a.state == "new"
    r.invite:SetShown(open)
    r.decline:SetShown(open)
    r.done:SetShown(not open)
    r.done:SetText(a.state == "joined" and "Joined" or "Invited")
end

local function buildMine(card)
    mineUI.card = card
    mineUI.needs = W.FS(card, 12, C.text)
    mineUI.needs:SetPoint("TOPLEFT", 14, -48)
    mineUI.needs:SetPoint("TOPRIGHT", -12, -48)
    mineUI.info = W.FS(card, 11, C.text2)
    mineUI.info:SetPoint("TOPLEFT", 14, -68)
    mineUI.info:SetPoint("TOPRIGHT", -12, -68)
    mineUI.info:SetWordWrap(true)

    mineUI.edit = W.Button(card, "Edit", 60, 24, C.text2)
    mineUI.edit:SetPoint("TOPLEFT", 14, -96)
    mineUI.edit:SetScript("OnClick", function()
        if G.mine then G.UI.FillForm(G.mine) UI:Refresh() end
    end)
    mineUI.close = W.Button(card, "Close", 60, 24, C.red)
    mineUI.close:SetPoint("LEFT", mineUI.edit, "RIGHT", 6, 0)
    mineUI.close:SetScript("OnClick", function() G:CloseMine("c") end)
    mineUI.pugs = W.Button(card, "Find PuGs", 90, 24)
    mineUI.pugs:SetPoint("LEFT", mineUI.close, "RIGHT", 6, 0)
    mineUI.pugs:SetScript("OnClick", function() G:FindPugs() end)
    mineUI.pugs.tip = "Opens Blizzard's Group Finder. Listing the group there needs your own click."

    local h = W.Heading(card, "Asking to join")
    h:SetPoint("TOPLEFT", 14, -134)
    mineUI.list = W.List(card, 40, askRow, askUpdate)
    mineUI.list:SetPoint("TOPLEFT", 10, -150)
    mineUI.list:SetPoint("BOTTOMRIGHT", -8, 10)
    mineUI.empty = W.FS(card, 11, C.text3)
    mineUI.empty:SetPoint("TOPLEFT", 14, -154)
    mineUI.empty:SetPoint("TOPRIGHT", -12, -154)
    mineUI.empty:SetWordWrap(true)
    mineUI.empty:SetText("Nobody yet. Guildies running Pandy Guild Groups see your post and can ask in one click.")
end

local function refreshMine()
    local p = G.mine
    mineUI.card.title:SetText(G.PostTitle(p))
    mineUI.card.sub:SetText(G.KIND_LABEL[p.kind] .. ((G.TeamName(p.team) and ("  -  " .. G.TeamName(p.team) .. " only")) or ""))
    mineUI.needs:SetText(G.NeedText(p.need) .. PGM.Hex(C.text3) .. ("   %d/%d|r"):format(p.have or 1, p.size))
    local left = (p.pugAt or 0) - PGM.Now()
    local info
    if left > 0 then
        info = "Guild only for " .. G.Clock(left) .. ", then Find PuGs lights up."
    elseif p.lfg then
        info = "Listed in Group Finder too."
    else
        info = "Guild first is over: Find PuGs to fill the rest."
    end
    if p.note ~= "" then info = info .. "  " .. PGM.Hex(C.text3) .. p.note .. "|r" end
    mineUI.info:SetText(info)
    mineUI.pugs:SetEnabled(left <= 0)
    mineUI.pugs:SetAlpha(left <= 0 and 1 or 0.45)
    local asks = G:Asks()
    mineUI.list:SetData(asks, true)
    mineUI.empty:SetShown(#asks == 0)
end

-- ============================================================
-- THE BOARD
-- ============================================================

local function postAction(p)
    local now = PGM.Now()
    if p.mine then
        if (p.start or 0) > 0 then
            local n = G:SignupsLeft(p)
            return ("Invite next (%d)"):format(n), n > 0 and p.start - now < 1800
        end
        return "Yours", false
    end
    if (p.start or 0) > 0 then
        local s = p.signups and p.signups[PGM:MyGuid() or ""]
        if s and s.state == "i" then return "Signed up", true end
        return "Sign up", true
    end
    local a = G.asked[p.id]
    if not a then return "Ask to join", true end
    if a.state == "asked" then return "Asked...", true end
    if a.state == "invited" then return "Invited", false end
    if a.state == "declined" then return "Declined", false end
    return "Closed", false
end

local function onAction(p, role)
    if p.mine then
        if (p.start or 0) > 0 then
            local who = G:InviteNextSignup(p.id)
            if not who then PGM.Print("Nobody left to invite: everyone signed up is in your group or offline.") end
        end
        return
    end
    if (p.start or 0) > 0 then
        local s = p.signups and p.signups[PGM:MyGuid() or ""]
        if s and s.state == "i" and not role then G:SignOff(p.id) else G:SignUp(p.id, role) end
        return
    end
    local a = G.asked[p.id]
    if a and a.state == "asked" and not role then G:Withdraw(p.id) else G:Ask(p.id, role) end
end

-- The first needed role I play, for the one-click ask.
local function bestRole(p)
    local roles = G.MyRoles()
    for _, r in ipairs(G.ROLES) do
        if roles[r] and (p.need[r] or 0) > 0 then return r end
    end
    return G.SpecRole()
end

local function postMenu(owner, p)
    local g = PGM.GuildDB()
    local rec = g and g.members[p.leader or ""]
    local entries = {}
    if p.mine then
        if (p.start or 0) > 0 then
            entries[#entries + 1] = { "Edit", function() G.UI.FillForm(p) UI:Refresh() end }
            entries[#entries + 1] = { "Cancel this group", function() G:CloseScheduled(p.id) end }
        else
            entries[#entries + 1] = { "Close", function() G:CloseMine("c") end }
        end
    else
        local verb = (p.start or 0) > 0 and "Sign up as " or "Ask as "
        for _, r in ipairs(G.ROLES) do
            entries[#entries + 1] = { verb .. PGM.ROLE_LABEL[G.ROLE_KEY[r]], function() onAction(p, r) end }
        end
        if rec then
            entries[#entries + 1] = { divider = true }
            entries[#entries + 1] = { "Whisper " .. (rec.short or "leader"), function() UI:Whisper(rec) end }
            entries[#entries + 1] = { "Open profile", function() UI:OpenProfile(rec.guid) end }
        end
    end
    W.Menu(owner, G.PostTitle(p), entries)
end

local function postRow(list)
    local r = W.Row(list)
    r.icon = W.FramedIcon(r, 30)
    r.icon:SetPoint("LEFT", 6, 0)
    r.title = W.FS(r, 13, C.text)
    r.title:SetPoint("TOPLEFT", 44, -6)
    r.title:SetPoint("TOPRIGHT", -150, -6)
    r.info = W.FS(r, 11, C.text2)
    r.info:SetPoint("BOTTOMLEFT", 44, 6)
    r.info:SetPoint("BOTTOMRIGHT", -112, 6)
    r.when = W.FS(r, 10, C.text3, "RIGHT")
    r.when:SetPoint("TOPRIGHT", -8, -6)
    r.when:SetWidth(140)
    r.action = W.Button(r, "", 100, 20)
    r.action:SetPoint("BOTTOMRIGHT", -6, 4)
    r.action:SetScript("OnClick", function(s)
        local p = s:GetParent().p
        local a = G.asked[p.id]
        local signedUp = p.signups and p.signups[PGM:MyGuid() or ""]
        local undo = (a and a.state == "asked") or (signedUp and signedUp.state == "i")
        onAction(p, (not p.mine and not undo) and bestRole(p) or nil)
    end)
    r:SetScript("OnClick", function(s, button)
        if button == "RightButton" then postMenu(s, s.p)
        elseif s.p.leader and not s.p.mine then UI:OpenProfile(s.p.leader) end
    end)
    r.onEnter = function(s)
        local p = s.p
        GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
        GameTooltip:SetText(G.PostTitle(p))
        if p.note ~= "" then GameTooltip:AddLine(p.note, 0.85, 0.85, 0.85, true) end
        if (p.start or 0) > 0 then
            local list = G:Signups(p)
            GameTooltip:AddLine(("%d signed up"):format(#list), 1, 1, 1)
            for _, it in ipairs(list) do
                GameTooltip:AddLine(G.RoleText(it.s.role) .. " " .. PGM.ColorName(it.rec))
            end
        end
        GameTooltip:AddLine("Right-click for more", 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end
    return r
end

local function postUpdate(r, p)
    r.p = p
    r.icon.icon:SetTexture(G.KIND_ICON[p.kind])
    local g = PGM.GuildDB()
    local rec = g and g.members[p.leader or ""]
    r.title:SetText(G.PostTitle(p) .. "   " .. (rec and G.WhoText(rec) or ""))
    local parts = { G.NeedText(p.need, not p.mine and G.MyRoles() or nil) }
    if G.TeamName(p.team) then parts[#parts + 1] = PGM.Hex(C.gold) .. G.TeamName(p.team) .. " only|r" end
    if p.lfg then parts[#parts + 1] = PGM.Hex(C.text3) .. "also in Group Finder|r" end
    if p.note ~= "" then parts[#parts + 1] = PGM.Hex(C.text3) .. p.note .. "|r" end
    r.info:SetText(table.concat(parts, "   "))
    if (p.start or 0) > 0 then
        r.when:SetText(PGM.Hex(C.accent) .. G.StartText(p.start) .. "|r")
    else
        r.when:SetText(("%d/%d  -  %s"):format(p.have or 1, p.size, p.mine and "yours" or "live"))
    end
    local text, enabled = postAction(p)
    r.action:SetLabel(text)
    r.action:SetEnabled(enabled)
    r.action:SetAlpha(enabled and 1 or 0.5)
    local a = G.asked[p.id]
    r.action:SetAccent((a and a.state == "invited") and C.jade or ((a and a.state == "declined") and C.text3 or C.accent))
end

-- ============================================================
-- PAGE
-- ============================================================

local function build(p)
    local left = W.Card(p, "Post a group", "Guildies running the module see it and ask in one click.")
    left:SetPoint("TOPLEFT")
    left:SetPoint("BOTTOMLEFT")
    left:SetWidth(LEFT_W)
    p.formCard = left
    buildForm(left)

    local mine = W.Card(p, "", "")
    mine:SetPoint("TOPLEFT")
    mine:SetPoint("BOTTOMLEFT")
    mine:SetWidth(LEFT_W)
    p.mineCard = mine
    buildMine(mine)

    local right = CreateFrame("Frame", nil, p)
    right:SetPoint("TOPLEFT", LEFT_W + 12, 0)
    right:SetPoint("BOTTOMRIGHT")
    GU.Title(right)
    right.sub:SetText("")

    p.kindChips = {}
    local prev
    for _, k in ipairs(G.KINDS) do
        local chip = W.Chip(right, G.KIND_LABEL[k], function(s)
            state.kinds[k] = not state.kinds[k] or nil
            s:SetActive(state.kinds[k] == true)
            UI:Refresh()
        end)
        if prev then chip:SetPoint("LEFT", prev, "RIGHT", 4, 0) else chip:SetPoint("TOPLEFT", 0, -44) end
        p.kindChips[k] = chip
        prev = chip
    end
    p.roleChip = W.Chip(right, "Needs my role", function(s)
        state.myRole = not state.myRole
        s:SetActive(state.myRole)
        UI:Refresh()
    end)
    p.roleChip:SetPoint("LEFT", prev, "RIGHT", 10, 0)

    p.list = W.List(right, 46, postRow, postUpdate)
    p.list:SetPoint("TOPLEFT", 0, -74)
    p.list:SetPoint("BOTTOMRIGHT")
    p.empty = W.FS(right, 12, C.text3)
    p.empty:SetPoint("TOPLEFT", 0, -82)
    p.empty:SetPoint("TOPRIGHT", 0, -82)
    p.empty:SetWordWrap(true)
    p.right = right

    -- The guild-first countdown ticks while the page is open.
    p.ticker = 0
    p:SetScript("OnUpdate", function(s, elapsed)
        s.ticker = s.ticker + elapsed
        if s.ticker >= 1 and G.mine and s.mineCard:IsShown() then
            s.ticker = 0
            refreshMine()
        end
    end)
end

local function refresh(p)
    local showMine = G.mine ~= nil and not state.editing
    p.mineCard:SetShown(showMine)
    p.formCard:SetShown(not showMine)
    if showMine then refreshMine() end
    p.formCard.title:SetText(state.editing and "Edit your group" or "Post a group")
    form.cancel:SetShown(state.editing)
    form.team:SetChoices(teamChoices())
    for r, chip in pairs(form.roleChips) do chip:SetActive(G.opt("roles")[r] == true) end
    for k, chip in pairs(form.pingChips) do chip:SetActive(G.opt("pingKinds")[k] and true or false) end
    form.ping:Sync()

    local anyKind = next(state.kinds) ~= nil
    local roles = G.MyRoles()
    local list = {}
    for _, post in ipairs(G:PostList()) do
        local ok = not anyKind or state.kinds[post.kind]
        if ok and state.myRole and not post.mine then
            ok = false
            for r in pairs(roles) do
                if (post.need[r] or 0) > 0 then ok = true end
            end
        end
        if ok then list[#list + 1] = post end
    end
    local live = 0
    for _, post in ipairs(list) do if (post.start or 0) == 0 then live = live + 1 end end
    p.right.title:SetText(("Guild groups: %d live, %d coming up"):format(live, #list - live))
    if PGM.SyncBlocked() then
        p.right.sub:SetText(PGM.Hex(C.amber) .. "In an instance: posts and asks wait until you're out.|r")
    else
        p.right.sub:SetText("Click Ask to join; the leader sees your role, item level and M+ score.")
    end
    p.list:SetData(list, true)
    if #list > 0 then
        p.empty:SetText("")
    elseif anyKind or state.myRole then
        p.empty:SetText("Nothing matches. Turn a filter off to see every group.")
    else
        p.empty:SetText("No guild groups right now. Post one, or see who's free.")
    end
end

UI:AddTab({ id = "groups", label = "Groups", build = build, refresh = refresh, module = true,
            icon = "Interface\\Icons\\INV_Misc_GroupNeedMore" })
