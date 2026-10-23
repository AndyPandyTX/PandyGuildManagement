-- Groups.lua (UI): the Groups page, in three views.
--   Browse: guild posts and Blizzard's Group Finder in one list, guild first,
--           with guild options on top and OAK-style filters under them.
--   My group: your group and everyone asking to join, one row each, with
--           their character's, main's and warband's M+ scores in columns.
--   Post a group: the form, for guild-first or scheduled groups, and the
--           Group Finder and ping settings.

local _, NS = ...
local G = NS.G
if not G.ok then return end
local PGM = G.PGM
local C = PGM.C
local UI = PGM.UI
local W = UI.W
local GU = G.UI

local LEFT_W = 330
local state = { editing = false }

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
    state.view = "post"
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
    state.view = (p.start or 0) > 0 and "board" or "mine"
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

    defaults("M")
end

-- ============================================================
-- SETTINGS (beside the form)
-- ============================================================

local function buildSettings(card)
    local x = 14
    form.share = W.Check(card, "Post my Group Finder listing to the guild",
        function() return G.opt("shareListing") end, function(v) G.setOpt("shareListing", v) end)
    form.share:SetPoint("TOPLEFT", x, -46)
    form.share:SetPoint("RIGHT", -12, 0)
    form.ping = W.Check(card, "Ping me when a guild group needs my role",
        function() return G.opt("ping") end, function(v) G.setOpt("ping", v) end)
    form.ping:SetPoint("TOPLEFT", x, -72)
    form.ping:SetPoint("RIGHT", -12, 0)
    label(card, "I play", x, -106)
    form.roleChips = {}
    local prev
    for _, r in ipairs(G.ROLES) do
        local chip = W.Chip(card, PGM.ROLE_LABEL[G.ROLE_KEY[r]], function(s)
            local t = G.opt("roles")
            t[r] = not t[r] or nil
            s:SetActive(t[r] == true)
            G:SendStatus()
            UI:Refresh()
        end)
        chip.tip = "None ticked: whatever your spec is. Used for pings, Fits my role and Apply."
        if prev then chip:SetPoint("LEFT", prev, "RIGHT", 6, 0) else chip:SetPoint("TOPLEFT", x + 50, -102) end
        form.roleChips[r] = chip
        prev = chip
    end
    label(card, "Ping for", x, -136)
    form.pingChips = {}
    prev = nil
    for _, k in ipairs(G.KINDS) do
        local chip = W.Chip(card, G.KIND_LABEL[k], function(s)
            local t = G.opt("pingKinds")
            t[k] = not t[k]
            s:SetActive(t[k])
        end)
        if prev then chip:SetPoint("LEFT", prev, "RIGHT", 4, 0) else chip:SetPoint("TOPLEFT", x + 50, -132) end
        form.pingChips[k] = chip
        prev = chip
    end
    local help = W.FS(card, 11, C.text3)
    help:SetPoint("TOPLEFT", x, -172)
    help:SetPoint("RIGHT", -12, 0)
    help:SetWordWrap(true)
    help:SetJustifyV("TOP")
    help:SetText("Listing in Blizzard's Group Finder posts the group here by itself. Use this form for a group "
        .. "you'd rather keep in the guild first, or one that starts later: type a start like 20:30, Sat 20:30 "
        .. "or +30 and guildies sign up instead.")

    -- Tell the guild: the chat line, as a template.
    local h = W.Heading(card, "Tell the guild")
    h:SetPoint("TOPLEFT", x, -246)
    form.announce = W.EditBox(card, 10, 22, "{key} - needs {needs}. Whisper me to join!")
    form.announce:SetPoint("TOPLEFT", x, -262)
    form.announce:SetPoint("RIGHT", -12, 0)
    form.announce:SetMaxLetters(200)
    form.announce.onChange = function(s)
        G.setOpt("announce", s:GetText())
        UI:Refresh()
    end
    form.preview = W.FS(card, 11, C.text2)
    form.preview:SetPoint("TOPLEFT", x, -292)
    form.preview:SetPoint("RIGHT", -12, 0)
    form.preview:SetWordWrap(true)
    form.preview:SetJustifyV("TOP")
end

-- ============================================================
-- MY GROUP
-- ============================================================

local mineUI = {}

-- Applicant columns: { label, x, width }.
local COLS = {
    { "Name", 8, 180 }, { "Roles", 192, 50 }, { "Spec", 246, 84 }, { "ilvl", 334, 36 },
    { "Character", 374, 78 }, { "Main", 456, 78 }, { "Warband", 538, 78 },
}

local function specName(id)
    if not (id and id > 0 and GetSpecializationInfoByID) then return nil end
    local ok, _, name = pcall(GetSpecializationInfoByID, id)
    return ok and PGM.Plain(name) or nil
end

-- "3084 [D][h]", in the score's colour, or a dash.
local function scoreCell(p)
    if not p then return PGM.Hex(C.text3) .. "-|r" end
    return PGM.Hex(PGM:ScoreColor(p.score)) .. p.score .. "|r" .. (p.roles ~= "" and (" " .. p.roles) or "")
end

local function askRow(list)
    local r = W.Row(list)
    local function cell(i, size, col)
        local fs = W.FS(r, size or 12, col or C.text)
        fs:SetPoint("LEFT", COLS[i][2], 0)
        fs:SetWidth(COLS[i][3])
        return fs
    end
    r.edge = W.Solid(r, "ARTWORK", C.jade)
    r.edge:SetPoint("TOPLEFT")
    r.edge:SetPoint("BOTTOMLEFT")
    r.edge:SetWidth(3)
    r.name = W.FS(r, 12, C.text)
    r.name:SetPoint("TOPLEFT", COLS[1][2], -4)
    r.name:SetWidth(COLS[1][3])
    r.tag = W.FS(r, 10, C.text3)
    r.tag:SetPoint("BOTTOMLEFT", COLS[1][2], 4)
    r.tag:SetWidth(COLS[1][3])
    r.roles = cell(2)
    r.spec = cell(3, 12, C.text2)
    r.ilvl = cell(4, 12, C.text2)
    r.char = cell(5)
    r.main = cell(6)
    r.warband = cell(7)
    r.invite = W.Button(r, "Invite", 50, 20, C.jade)
    r.invite:SetPoint("RIGHT", -62, 0)
    r.invite:SetScript("OnClick", function(s) G:InviteAsk(s:GetParent().it.key) end)
    r.decline = W.Button(r, "Decline", 56, 20, C.red)
    r.decline:SetPoint("RIGHT", -4, 0)
    r.decline:SetScript("OnClick", function(s) G:DeclineAsk(s:GetParent().it.key) end)
    r.done = W.FS(r, 12, C.jade, "RIGHT")
    r.done:SetPoint("RIGHT", -8, 0)
    r:SetScript("OnClick", function(s, button)
        local rec = s.it.rec
        if rec and button == "RightButton" then UI:MemberMenu(s, rec.guid)
        elseif rec then UI:OpenProfile(rec.guid) end
    end)
    r.onEnter = function(s)
        local it = s.it
        local a = it.ask
        GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
        GameTooltip:SetText(a.name or "?")
        if a.note ~= "" then GameTooltip:AddLine(a.note, 0.85, 0.85, 0.85, true) end
        G.AddScoreLines(GameTooltip, it.scores or {})
        if (a.members or 1) > 1 then
            GameTooltip:AddLine(("Applied as a group of %d: Invite brings them all."):format(a.members), 0.6, 0.6, 0.6, true)
        end
        GameTooltip:Show()
    end
    return r
end

local function askUpdate(r, it)
    r.it = it
    local a, rec = it.ask, it.rec
    if rec then
        r.name:SetText(PGM.ColorName(rec))
        local main = PGM:KnownMain(rec.guid)
        local g = PGM.GuildDB()
        local m = main and g and g.members[main]
        r.tag:SetText(PGM.Hex(C.jade) .. "Guild|r" .. (m and ("  alt of " .. PGM.ColorName(m)) or "")
            .. (it.app and "  -  Group Finder" or "  -  asked here"))
    else
        r.name:SetText(PGM.ClassHex(a.class) .. (a.short or a.name or "?") .. "|r")
        r.tag:SetText((a.realm or "") .. ((a.members or 1) > 1 and ("  -  group of " .. a.members) or ""))
    end
    r.edge:SetShown(rec ~= nil)

    local roles = ""
    if a.offers then
        for _, role in ipairs(G.ROLES) do
            if a.offers[role] then roles = roles .. G.RoleIcon(role, role ~= a.role) end
        end
    end
    r.roles:SetText(roles ~= "" and roles or G.RoleIcon(a.role))
    r.spec:SetText(specName(a.spec) or "")
    r.ilvl:SetText(a.ilvl > 0 and a.ilvl or "")

    if it.app then
        it.scores = G.Scores(a.short, a.realm, a.score)
    else
        it.scores = rec and G.Scores(rec.short, rec.realm, PGM:MPlusScore(rec)) or {}
    end
    r.char:SetText(scoreCell(it.scores.char))
    r.main:SetText(scoreCell(it.scores.main))
    r.warband:SetText(scoreCell(it.scores.warband))

    local open = a.state == "new"
    r.invite:SetShown(open)
    r.decline:SetShown(open)
    r.done:SetShown(not open)
    r.done:SetText(a.state == "joined" and "Joined" or "Invited")
end

local function buildMine(v)
    local card = W.Card(v, "", "")
    card:SetPoint("TOPLEFT")
    card:SetPoint("TOPRIGHT")
    card:SetHeight(94)
    mineUI.card = card
    mineUI.needs = W.FS(card, 13, C.text)
    mineUI.needs:SetPoint("TOPLEFT", 14, -48)
    mineUI.needs:SetPoint("TOPRIGHT", -240, -48)
    mineUI.info = W.FS(card, 11, C.text2)
    mineUI.info:SetPoint("TOPLEFT", 14, -70)
    mineUI.info:SetPoint("TOPRIGHT", -12, -70)

    mineUI.pugs = W.Button(card, "Find PuGs", 90, 24)
    mineUI.pugs:SetPoint("TOPRIGHT", -12, -12)
    mineUI.pugs:SetScript("OnClick", function() G:FindPugs() end)
    mineUI.pugs.tip = "Opens Blizzard's Group Finder. Listing the group there needs your own click."
    mineUI.close = W.Button(card, "Close", 64, 24, C.red)
    mineUI.close:SetPoint("RIGHT", mineUI.pugs, "LEFT", -6, 0)
    mineUI.close:SetScript("OnClick", function() G:CloseMine("c") end)
    mineUI.edit = W.Button(card, "Edit", 56, 24, C.text2)
    mineUI.edit:SetPoint("RIGHT", mineUI.close, "LEFT", -6, 0)
    mineUI.edit:SetScript("OnClick", function()
        if G.mine then
            state.view = "post"
            G.UI.FillForm(G.mine)
            UI:Refresh()
        end
    end)
    mineUI.status = W.FS(card, 11, C.jade, "RIGHT")
    mineUI.status:SetPoint("TOPRIGHT", -12, -48)
    mineUI.status:SetWidth(220)
    mineUI.tell = W.Button(card, "Tell the guild", 104, 24, C.jade)
    mineUI.tell:SetScript("OnClick", function() G:Announce() end)
    mineUI.listKey = W.Button(card, "List my key", 96, 24)
    mineUI.listKey:SetScript("OnClick", function() G:ListMyKey() end)
    mineUI.listKey.tip = "Opens the Group Finder. Click Dungeons, then Start a Group: it fills in your keystone. Then List Group."

    local cols = {}
    for i, c in ipairs(COLS) do cols[i] = { c[1], c[2] } end
    GU.Header(v, -104, cols)
    mineUI.list = W.List(v, 36, askRow, askUpdate)
    mineUI.list:SetPoint("TOPLEFT", 0, -126)
    mineUI.list:SetPoint("BOTTOMRIGHT")
    mineUI.empty = W.FS(v, 12, C.text3)
    mineUI.empty:SetPoint("TOPLEFT", 8, -136)
    mineUI.empty:SetPoint("TOPRIGHT", -8, -136)
    mineUI.empty:SetWordWrap(true)
end

local function refreshMine()
    local p = G.mine
    local listed = G:IsListed()
    local shown = {}
    if not p then
        mineUI.card.title:SetText(listed and "Your Group Finder listing" or "No group up")
        mineUI.card.sub:SetText(listed and "Not on the guild board" or "")
        mineUI.needs:SetText("")
        if listed then
            mineUI.info:SetText(G.opt("shareListing") == false
                and "Tick Post my Group Finder listing to the guild (Post a group) to share it."
                or "Taken off the guild board. Delist and list again to post it.")
        else
            mineUI.info:SetText("List a group in the Group Finder, or Post a group, and who's asking shows here.")
        end
        mineUI.status:SetText("")
        shown.listKey = not listed and G.ReadMyKey() ~= nil
    else
        mineUI.card.title:SetText(G.PostTitle(p))
        mineUI.card.sub:SetText(G.KIND_LABEL[p.kind] .. (p.fromLFG and "  -  from your Group Finder listing" or "")
            .. ((G.TeamName(p.team) and ("  -  " .. G.TeamName(p.team) .. " only")) or ""))
        mineUI.needs:SetText(PGM.Hex(C.text2) .. "Needs:|r  " .. G.NeedText(p.need)
            .. PGM.Hex(C.text3) .. ("     %d/%d in the group|r"):format(p.have or 1, p.size))
        local left = (p.pugAt or 0) - PGM.Now()
        if p.lfg then
            mineUI.status:SetText("Listed in the Group Finder")
            mineUI.info:SetText("Guildies who apply, or ask here, are listed first."
                .. (p.note ~= "" and ("  " .. PGM.Hex(C.text3) .. p.note .. "|r") or ""))
        elseif left > 0 then
            mineUI.status:SetText(PGM.Hex(C.gold) .. "Guild only for " .. G.Clock(left) .. "|r")
            mineUI.info:SetText("Then Find PuGs lights up." .. (p.note ~= "" and ("  " .. PGM.Hex(C.text3) .. p.note .. "|r") or ""))
        else
            mineUI.status:SetText(PGM.Hex(C.text2) .. "Guild only|r")
            mineUI.info:SetText("Guild first is over: Find PuGs to fill the rest."
                .. (p.note ~= "" and ("  " .. PGM.Hex(C.text3) .. p.note .. "|r") or ""))
        end
        shown.edit, shown.close, shown.pugs, shown.tell = not p.fromLFG, true, not p.lfg, true
        mineUI.tell.tip = "Says in guild chat:\n" .. (G:AnnounceText(p) or "")
        local canFind = left <= 0
        mineUI.pugs:SetEnabled(canFind)
        mineUI.pugs:SetAlpha(canFind and 1 or 0.45)
        mineUI.close.tip = p.fromLFG and "Takes it off the guild board. Your Group Finder listing stays." or nil
    end
    -- Buttons pack to the right, whichever are shown.
    local anchor
    for _, key in ipairs({ "tell", "pugs", "close", "edit", "listKey" }) do
        local b = mineUI[key]
        b:SetShown(shown[key])
        if shown[key] then
            b:ClearAllPoints()
            if anchor then b:SetPoint("RIGHT", anchor, "LEFT", -6, 0) else b:SetPoint("TOPRIGHT", mineUI.card, "TOPRIGHT", -12, -12) end
            anchor = b
        end
    end
    local asks = G:Asks()
    mineUI.list:SetData(asks, true)
    mineUI.empty:SetText(#asks == 0 and (p or listed) and
        "Nobody yet. Group Finder applicants and guildies asking through Pandy Guild Groups show here, guildies first." or "")
end

-- ============================================================
-- THE BOARD
-- ============================================================

local board = {}

local function filters()
    local f = G.opt("board")
    f.kind = state.cat
    return f
end

-- "5m", "2h": how long ago a result was listed.
local function age(s)
    s = math.max(0, s or 0)
    if s < 3600 then return math.max(1, math.floor(s / 60)) .. "m" end
    return math.floor(s / 3600) .. "h"
end

local function rowAction(row)
    local p, res = row.post, row.result
    if p and p.mine then
        local n = G:SignupsLeft(p)
        return ("Invite next (%d)"):format(n), n > 0 and p.start - PGM.Now() < 1800
    end
    if res then
        local st = res.status
        if not st then return "Apply", true end
        if st == "applied" then return "Applied", true end
        if st == "invited" then return "Invited", false end
        if st == "inviteaccepted" then return "Joined", false end
        return "Declined", false
    end
    if (p.start or 0) > 0 then
        local s = p.signups and p.signups[PGM:MyGuid() or ""]
        if s and s.state == "i" then return "Signed up", true end
        return "Sign up", true
    end
    local a = G.asked[p.id]
    if not a then return "Ask to join", true end
    if a.state == "asked" then return "Asked", true end
    if a.state == "invited" then return "Invited", false end
    if a.state == "declined" then return "Declined", false end
    return "Closed", false
end

-- The first needed role I play.
local function bestRole(row)
    local roles = G.MyRoles()
    for _, r in ipairs(G.ROLES) do
        if roles[r] and (row.need[r] or 0) > 0 then return r end
    end
    return G.SpecRole()
end

-- Act on a row: role is a pick from the menu, or nil for the button.
local function act(row, role)
    local p, res = row.post, row.result
    if p and p.mine then
        if not G:InviteNextSignup(p.id) then
            PGM.Print("Nobody left to invite: everyone signed up is in your group or offline.")
        end
        return
    end
    if res then
        if res.status == "applied" and not role then G:CancelFinder(res.id) else G:ApplyFinder(res.id, role) end
        return
    end
    if (p.start or 0) > 0 then
        local s = p.signups and p.signups[PGM:MyGuid() or ""]
        if s and s.state == "i" and not role then G:SignOff(p.id) else G:SignUp(p.id, role or bestRole(row)) end
        return
    end
    local a = G.asked[p.id]
    if a and a.state == "asked" and not role then G:Withdraw(p.id) else G:Ask(p.id, role or bestRole(row)) end
end

local function rowMenu(owner, row)
    local p, rec = row.post, row.rec
    local entries = {}
    if p and p.mine then
        entries[#entries + 1] = { "Edit", function() state.view = "post" G.UI.FillForm(p) UI:Refresh() end }
        entries[#entries + 1] = { "Cancel this group", function() G:CloseScheduled(p.id) end }
    else
        local verb = row.result and "Apply as " or ((p and (p.start or 0) > 0) and "Sign up as " or "Ask as ")
        for _, r in ipairs(G.ROLES) do
            entries[#entries + 1] = { verb .. PGM.ROLE_LABEL[G.ROLE_KEY[r]], function() act(row, r) end }
        end
        if rec then
            entries[#entries + 1] = { divider = true }
            entries[#entries + 1] = { "Whisper " .. (rec.short or "leader"), function() UI:Whisper(rec) end }
            entries[#entries + 1] = { "Open profile", function() UI:OpenProfile(rec.guid) end }
        end
    end
    W.Menu(owner, G.PostTitle(row), entries)
end

local function boardRow(list)
    local r = W.Row(list)
    r.wash = W.Solid(r, "BORDER", C.jade, 0.06)
    r.wash:SetAllPoints()
    r.edge = W.Solid(r, "ARTWORK", C.jade)
    r.edge:SetPoint("TOPLEFT")
    r.edge:SetPoint("BOTTOMLEFT")
    r.edge:SetWidth(3)
    r.icon = W.FramedIcon(r, 30)
    r.icon:SetPoint("LEFT", 8, 0)
    r.title = W.FS(r, 13, C.text)
    r.title:SetPoint("TOPLEFT", 46, -6)
    r.title:SetPoint("TOPRIGHT", -190, -6)
    r.info = W.FS(r, 11, C.text2)
    r.info:SetPoint("BOTTOMLEFT", 46, 7)
    r.info:SetPoint("BOTTOMRIGHT", -116, 7)
    r.when = W.FS(r, 10, C.text3, "RIGHT")
    r.when:SetPoint("TOPRIGHT", -8, -6)
    r.when:SetWidth(180)
    r.action = W.Button(r, "", 102, 20)
    r.action:SetPoint("BOTTOMRIGHT", -6, 4)
    r.action:SetScript("OnClick", function(s) act(s:GetParent().row) end)
    r:SetScript("OnClick", function(s, button)
        if button == "RightButton" then rowMenu(s, s.row)
        elseif s.row.rec then UI:OpenProfile(s.row.rec.guid) end
    end)
    r.onEnter = function(s)
        local row = s.row
        GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
        GameTooltip:SetText(G.PostTitle(row))
        if row.rec then
            GameTooltip:AddLine(G.WhoText(row.rec))
            G.AddScoreLines(GameTooltip, G.Scores(row.rec.short, row.rec.realm, row.score))
        elseif row.result and row.result.leader then
            local short, realm = row.result.leader:match("^([^-]+)-(.+)$")
            GameTooltip:AddLine(row.result.leader, 1, 1, 1)
            G.AddScoreLines(GameTooltip, G.Scores(short or row.result.leader, realm, row.score))
        end
        if row.note ~= "" then GameTooltip:AddLine(row.note, 0.85, 0.85, 0.85, true) end
        local res = row.result
        if res and #res.classes > 0 then
            local parts = {}
            for _, class in ipairs(res.classes) do
                local name = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]) or class
                parts[#parts + 1] = PGM.ClassHex(class) .. name .. "|r"
            end
            GameTooltip:AddLine(table.concat(parts, ", "), 1, 1, 1, true)
        end
        if row.post and (row.post.start or 0) > 0 then
            local list = G:Signups(row.post)
            GameTooltip:AddLine(("%d signed up"):format(#list), 1, 1, 1)
            for _, it in ipairs(list) do GameTooltip:AddLine(G.RoleIcon(it.s.role) .. " " .. PGM.ColorName(it.rec)) end
        end
        GameTooltip:AddLine("Right-click to pick your role", 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end
    return r
end

local function boardUpdate(r, row)
    r.row = row
    r.wash:SetShown(row.guild)
    r.edge:SetShown(row.guild)
    r.icon.icon:SetTexture(G.KIND_ICON[row.kind])

    local leader
    if row.rec then
        leader = G.WhoText(row.rec) .. "  " .. PGM.Hex(C.jade) .. "Guild|r"
    elseif row.result and row.result.leader then
        local short, realm = row.result.leader:match("^([^-]+)-(.+)$")
        leader = PGM.Hex(C.text) .. (short or row.result.leader) .. "|r" .. (realm and (PGM.Hex(C.text3) .. "-" .. realm .. "|r") or "")
        if row.result.mates > 0 then leader = leader .. "  " .. PGM.Hex(C.jade) .. row.result.mates .. " guildie" .. (row.result.mates == 1 and "" or "s") .. "|r" end
    end
    r.title:SetText(G.PostTitle(row) .. (leader and ("   " .. leader) or ""))

    local parts = { PGM.Hex(C.text3) .. "Needs:|r " .. G.NeedText(row.need, G.MyRoles()) }
    if row.result then parts[#parts + 1] = PGM.Hex(C.text3) .. row.result.members .. "/" .. row.size .. "|r" end
    if row.score > 0 then parts[#parts + 1] = PGM.Hex(PGM:ScoreColor(row.score)) .. row.score .. "|r" end
    if row.playstyle then parts[#parts + 1] = PGM.Hex(C.text3) .. row.playstyle .. "|r" end
    if G.TeamName(row.post and row.post.team) then parts[#parts + 1] = PGM.Hex(C.gold) .. G.TeamName(row.post.team) .. " only|r" end
    if row.note ~= "" then parts[#parts + 1] = PGM.Hex(C.text3) .. row.note .. "|r" end
    r.info:SetText(table.concat(parts, "   "))

    local source = row.post and (row.result and "Guild post + Group Finder" or "Guild post") or "Group Finder"
    local when
    if row.scheduled then
        when = PGM.Hex(C.accent) .. G.StartText(row.post.start) .. "|r"
    elseif row.result then
        when = age(row.result.age)
    else
        when = "live"
    end
    r.when:SetText(source .. "  -  " .. when)

    local text, enabled = rowAction(row)
    r.action:SetLabel(text)
    r.action:SetEnabled(enabled)
    r.action:SetAlpha(enabled and 1 or 0.5)
    local good = text == "Invited" or text == "Joined" or text == "Applied" or text == "Asked" or text == "Signed up"
    r.action:SetAccent(good and C.jade or (enabled and C.accent or C.text3))
end

-- A chip bound to a board filter flag.
local function flagChip(parent, text, key, tip)
    local chip = W.Chip(parent, text, function(s)
        local f = G.opt("board")
        f[key] = not f[key]
        s:SetActive(f[key])
        UI:Refresh()
    end)
    chip.tip = tip
    chip.key = key
    board.flags[#board.flags + 1] = chip
    return chip
end

local function search()
    local ok, why = G:SearchFinder(state.cat)
    if not ok then PGM.Print(why) end
    UI:Refresh()
end

local function buildBoard(v)
    board.flags = {}
    local function heading(text, y)
        local h = W.Heading(v, text)
        h:SetPoint("TOPLEFT", 0, y - 6)
        return h
    end

    heading("Guild", 0)
    local prev = flagChip(v, "Guild first", "guildFirst", "Guild posts, and Group Finder groups with guildies, at the top.")
    prev:SetPoint("TOPLEFT", 96, 0)
    local chip = flagChip(v, "Guild only", "guildOnly", "Only guild groups.")
    chip:SetPoint("LEFT", prev, "RIGHT", 4, 0)
    prev = chip
    chip = flagChip(v, "Scheduled", "scheduled", "Show scheduled guild groups, to sign up for.")
    chip:SetPoint("LEFT", prev, "RIGHT", 4, 0)
    board.sort = GU.Cycle(v, "Sort: ", { { "newest", "Newest" }, { "level", "Key level" }, { "rating", "Leader rating" } },
        function(s)
            G.opt("board").sort = s:Value()
            UI:Refresh()
        end)
    board.sort:SetPoint("TOPRIGHT", 0, 0)

    heading("Group Finder", -28)
    board.cats = {}
    prev = nil
    for _, c in ipairs(G.FINDER_CATS) do
        chip = W.Chip(v, c.label, function()
            state.cat = c.id
            G.opt("board").dungeons = {}
            search()   -- a click, so the game lets us search
        end)
        if prev then chip:SetPoint("LEFT", prev, "RIGHT", 4, 0) else chip:SetPoint("TOPLEFT", 96, -28) end
        board.cats[c.id] = chip
        prev = chip
    end
    board.search = W.Button(v, "Search", 70, 22)
    board.search:SetPoint("LEFT", prev, "RIGHT", 10, 0)
    board.search:SetScript("OnClick", search)
    board.search.tip = "Search the Group Finder again (the game only allows it from a click)."
    board.searched = W.FS(v, 10, C.text3)
    board.searched:SetPoint("LEFT", board.search, "RIGHT", 8, 0)

    heading("Filters", -56)
    local keysLabel = W.FS(v, 11, C.text2)
    keysLabel:SetPoint("TOPLEFT", 96, -60)
    keysLabel:SetText("Keys")
    board.keys = W.EditBox(v, 64, 22, "10-15")
    board.keys:SetPoint("TOPLEFT", 126, -56)
    board.keys:SetMaxLetters(7)
    board.keys.onChange = function(s)
        G.opt("board").keys = s:GetText()
        UI:Refresh()
    end
    board.keys.tip = "A range (10-15), at least (15+), or exactly (15)."
    local ratingLabel = W.FS(v, 11, C.text2)
    ratingLabel:SetPoint("LEFT", board.keys, "RIGHT", 10, 0)
    ratingLabel:SetText("Leader rating")
    board.rating = W.EditBox(v, 56, 22, "0")
    board.rating:SetPoint("LEFT", ratingLabel, "RIGHT", 6, 0)
    board.rating:SetNumeric(true)
    board.rating:SetMaxLetters(4)
    board.rating.onChange = function(s)
        G.opt("board").minRating = tonumber(s:GetText()) or 0
        UI:Refresh()
    end
    board.playstyle = GU.Cycle(v, "Playstyle: ", { { false, "Any" } }, function(s)
        G.opt("board").playstyle = s:Value() or nil
        UI:Refresh()
    end)
    board.playstyle:SetPoint("LEFT", board.rating, "RIGHT", 10, 0)
    board.dungeons = W.Button(v, "Dungeons: all", 120, 22, C.text2)
    board.dungeons.fs:SetFont(STANDARD_TEXT_FONT, 11, "")
    board.dungeons:SetPoint("LEFT", board.playstyle, "RIGHT", 6, 0)
    board.dungeons:SetScript("OnClick", function(s)
        local f = G.opt("board")
        f.dungeons = f.dungeons or {}
        local entries = {}
        for _, name in ipairs(G:BoardActivities(state.cat)) do
            entries[#entries + 1] = { name, checked = function() return f.dungeons[name] == true end,
                toggle = function() f.dungeons[name] = not f.dungeons[name] or nil UI:Refresh() end }
        end
        if #entries == 0 then entries[1] = { "Search first", function() end, disabled = true } end
        entries[#entries + 1] = { divider = true }
        entries[#entries + 1] = { "Show all", function() f.dungeons = {} UI:Refresh() end }
        W.Menu(s, "Only these", entries)
    end)

    prev = flagChip(v, "Fits my role", "fitsMe", "Groups that still need a role you play.")
    prev:SetPoint("TOPLEFT", 96, -84)
    for _, it in ipairs({
        { "Has tank", "hasTank" }, { "Has healer", "hasHealer" }, { "Battle res", "brez", "Has a class with a battle res." },
        { "Lust", "lust", "Has a class with Bloodlust or the like." }, { "Hide declined", "hideDeclined" },
    }) do
        chip = flagChip(v, it[1], it[2], it[3])
        chip:SetPoint("LEFT", prev, "RIGHT", 4, 0)
        prev = chip
    end

    board.list = W.List(v, 46, boardRow, boardUpdate)
    board.list:SetPoint("TOPLEFT", 0, -116)
    board.list:SetPoint("BOTTOMRIGHT")
    board.empty = W.FS(v, 12, C.text3)
    board.empty:SetPoint("TOPLEFT", 8, -126)
    board.empty:SetPoint("TOPRIGHT", -8, -126)
    board.empty:SetWordWrap(true)
end

local function refreshBoard()
    local f = filters()
    for _, chip in ipairs(board.flags) do chip:SetActive(f[chip.key] and true or false) end
    for id, chip in pairs(board.cats) do chip:SetActive(id == state.cat) end
    board.sort:SetValue(f.sort)
    if not board.keys:HasFocus() then board.keys:SetText(f.keys or "") end
    if not board.rating:HasFocus() then board.rating:SetText((f.minRating or 0) > 0 and f.minRating or "") end
    local styles = { { false, "Any" } }
    for _, s in ipairs(G:BoardPlaystyles()) do styles[#styles + 1] = { s, s } end
    board.playstyle:SetChoices(styles)
    board.playstyle:SetValue(f.playstyle or false)
    local n = 0
    for _ in pairs(f.dungeons or {}) do n = n + 1 end
    local noun = state.cat == "R" and "Raids" or (state.cat == "D" and "Delves" or "Dungeons")
    board.dungeons:SetLabel(noun .. ": " .. (n > 0 and n or "all"))
    board.searched:SetText(G.searchedAt and ("Searched " .. age(GetTime() - G.searchedAt) .. " ago") or "Click a category to search")

    local rows = G:Board(f)
    board.list:SetData(rows, true)
    if #rows > 0 then
        board.empty:SetText("")
    elseif not G.resultsAt then
        board.empty:SetText("No guild groups right now. Click Mythic+, Raids, Delves or Custom to search the Group Finder too.")
    else
        board.empty:SetText("Nothing matches. Turn a filter off, or Search again.")
    end
end

-- ============================================================
-- PAGE
-- ============================================================

local VIEWS = { { "board", "Browse" }, { "mine", "My group" }, { "post", "Post a group" } }

-- Open the Groups page on one view: "board", "mine" or "post".
function G.UI.ShowView(view)
    state.view = view
    UI:Show("groups")
    UI:Refresh()
end

local function build(p)
    state.view = state.view or "board"
    state.cat = state.cat or "M"
    p.viewChips = {}
    local prev
    for _, v in ipairs(VIEWS) do
        local chip = W.Chip(p, v[2], function()
            state.view = v[1]
            UI:Refresh()
        end)
        if prev then chip:SetPoint("LEFT", prev, "RIGHT", 4, 0) else chip:SetPoint("TOPLEFT") end
        p.viewChips[v[1]] = chip
        prev = chip
    end
    p.status = W.FS(p, 11, C.text2, "RIGHT")
    p.status:SetPoint("TOPRIGHT", 0, -4)
    p.status:SetWidth(380)

    p.views = {}
    for _, v in ipairs(VIEWS) do
        local f = CreateFrame("Frame", nil, p)
        f:SetPoint("TOPLEFT", 0, -34)
        f:SetPoint("BOTTOMRIGHT")
        p.views[v[1]] = f
    end
    buildBoard(p.views.board)
    buildMine(p.views.mine)

    local formCard = W.Card(p.views.post, "Post a group", "Kept in the guild first, or scheduled for later.")
    formCard:SetPoint("TOPLEFT")
    formCard:SetPoint("BOTTOMLEFT")
    formCard:SetWidth(LEFT_W)
    p.formCard = formCard
    buildForm(formCard)
    local settings = W.Card(p.views.post, "Group Finder and pings", "")
    settings:SetPoint("TOPLEFT", LEFT_W + 12, 0)
    settings:SetPoint("BOTTOMRIGHT")
    buildSettings(settings)

    -- The guild-first countdown ticks while My group is open.
    p.ticker = 0
    p:SetScript("OnUpdate", function(s, elapsed)
        s.ticker = s.ticker + elapsed
        if s.ticker >= 1 and state.view == "mine" then
            s.ticker = 0
            refreshMine()
        end
    end)
end

local function refresh(p)
    if state.view == "post" and G.mine and not state.editing and G.mine.fromLFG then state.view = "mine" end
    for id, f in pairs(p.views) do f:SetShown(id == state.view) end
    local asks = 0
    for _, it in ipairs(G:Asks()) do
        if it.ask.state == "new" then asks = asks + 1 end
    end
    p.viewChips.mine:SetLabel(asks > 0 and ("My group (" .. asks .. ")") or "My group")
    p.viewChips.mine:SetWidth(p.viewChips.mine.fs:GetStringWidth() + 24)
    for id, chip in pairs(p.viewChips) do chip:SetActive(id == state.view) end
    p.viewChips.mine:SetAccent(asks > 0 and state.view ~= "mine" and C.jade or (state.view == "mine" and C.text or C.text2))

    if PGM.SyncBlocked() then
        p.status:SetText(PGM.Hex(C.amber) .. "In an instance: guild posts and asks wait until you're out.|r")
    elseif G.mine then
        p.status:SetText("Your group: " .. G.PostTitle(G.mine))
    else
        p.status:SetText("")
    end

    if state.view == "board" then
        refreshBoard()
    elseif state.view == "mine" then
        refreshMine()
    else
        p.formCard.title:SetText(state.editing and "Edit your group" or "Post a group")
        form.cancel:SetShown(state.editing)
        form.team:SetChoices(teamChoices())
        for r, chip in pairs(form.roleChips) do chip:SetActive(G.opt("roles")[r] == true) end
        for k, chip in pairs(form.pingChips) do chip:SetActive(G.opt("pingKinds")[k] and true or false) end
        form.ping:Sync()
        form.share:Sync()
        if not form.announce:HasFocus() then form.announce:SetText(G.opt("announce") or "") end
        local sample = G:AnnounceText(G.mine or { kind = "M", what = "The Blinding Vale", level = "14",
            need = { T = 1, H = 0, D = 2 } })
        form.preview:SetText("{key}, {needs} and {name} are filled in. Right now it would say:\n"
            .. PGM.Hex(C.text) .. (sample or "") .. "|r")
    end
end

UI:AddTab({ id = "groups", label = "Groups", build = build, refresh = refresh, module = true,
            icon = "Interface\\Icons\\INV_Misc_GroupNeedMore" })
