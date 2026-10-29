-- Chat.lua (UI): LFG chat, on WoW Forever only. Group and trade lines from
-- the channels you're in, under each dungeon and raid (lowest level first),
-- then quests and other groups, then trade. Click to whisper, shift-click
-- for /who, ctrl-click to invite, right-click for all of it.

local _, NS = ...
local G = NS.G
local PGM = G.PGM
if not (PGM.IS_FOREVER and G.ReadChatLine) then return end

local C = PGM.C
local UI = PGM.UI
local W = UI.W
local GU = G.UI

local KIND_TAG = { M = { "LFM", C.jade }, G = { "LFG", C.gold }, T = { "Trade", C.text2 } }

-- The filter chips: { option, label, tip }.
local CHIPS = {
    { "dungeons", "Dungeons" },
    { "raids", "Raids" },
    { "other", "Quests and other", "Groups for no dungeon or raid: quests, elites, world bosses..." },
    { "trade", "Trade", "WTS, WTB, and looking for a crafter." },
    { "lfg", "Players looking", "LFG lines too: players looking for a group, not just groups looking for more." },
    { "fits", "My level", "Only dungeons within two levels of yours." },
}

local function age(s)
    s = math.max(0, math.floor(s))
    if s < 60 then return "now" end
    return math.floor(s / 60) .. "m"
end

local function whisper(l) UI:Whisper({ name = l.name }) end
local function invite(l) UI:Invite({ name = l.name }) end
local function who(l)
    if C_FriendList and C_FriendList.SendWho then pcall(C_FriendList.SendWho, 'n-"' .. l.short .. '"') end
end

local function menu(owner, l)
    local entries = {
        { "Whisper", function() whisper(l) end },
        { "Invite", function() invite(l) end },
        { "Who is this?", function() who(l) end },
    }
    if l.rec and l.rec.guid then
        entries[#entries + 1] = { "Profile", function() UI:OpenProfile(l.rec.guid) end }
    end
    W.Menu(owner, l.short, entries)
end

local function onEnter(r)
    local l = r.it
    if not l or l.head then return end
    GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
    GameTooltip:SetText(l.rec and G.WhoText(l.rec) or l.short)
    GameTooltip:AddLine(l.text, 1, 1, 1, true)
    local places = {}
    for _, key in ipairs(l.places) do places[#places + 1] = G.CHAT_PLACE[key].name end
    if #places > 0 then GameTooltip:AddLine(table.concat(places, ", "), 0.7, 0.73, 0.77, true) end
    local ago = GetTime() - l.at < 60 and "just now" or (age(GetTime() - l.at) .. " ago")
    GameTooltip:AddLine(("%s, %s"):format(l.channel ~= "" and l.channel or "Chat", ago), 0.5, 0.52, 0.56)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Click: whisper.  Shift-click: who.  Ctrl-click: invite.  Right-click: more.", 0.5, 0.52, 0.56, true)
    GameTooltip:Show()
end

local function buildRow(list)
    local r = W.Row(list)
    r.head = W.FS(r, 11, C.accent)
    r.head:SetPoint("LEFT", 6, 0)
    r.range = W.FS(r, 11, C.text3)
    r.range:SetPoint("LEFT", r.head, "RIGHT", 10, 0)
    r.age = W.FS(r, 11, C.text3)
    r.age:SetPoint("LEFT", 6, 0)
    r.age:SetWidth(34)
    r.tag = W.FS(r, 11, C.text)
    r.tag:SetPoint("LEFT", 42, 0)
    r.tag:SetWidth(40)
    r.name = W.FS(r, 12, C.text)
    r.name:SetPoint("LEFT", 84, 0)
    r.name:SetWidth(120)
    r.roles = W.FS(r, 12, C.text)
    r.roles:SetPoint("LEFT", 206, 0)
    r.roles:SetWidth(54)
    r.text = W.FS(r, 12, C.text2)
    r.text:SetPoint("LEFT", 262, 0)
    r.text:SetPoint("RIGHT", -6, 0)
    r.text:SetWordWrap(false)
    r:SetScript("OnClick", function(s, button)
        local l = s.it
        if not l or l.head then return end
        if button == "RightButton" then
            menu(s, l)
        elseif IsShiftKeyDown() then
            who(l)
        elseif IsControlKeyDown() then
            invite(l)
        else
            whisper(l)
        end
    end)
    r.onEnter = onEnter
    return r
end

local function updateRow(r, it)
    r.it = it
    local isHead = it.head ~= nil
    for _, k in ipairs({ "age", "tag", "name", "roles", "text" }) do r[k]:SetShown(not isHead) end
    r.head:SetShown(isHead)
    r.range:SetShown(isHead)
    if isHead then
        r.stripe:SetColorTexture(C.side[1], C.side[2], C.side[3], 1)
        r.head:SetText(it.head:upper())
        local p = it.place
        local range = p and (p.raid and (p.raid .. " players") or (p.lo .. "-" .. p.hi)) or ""
        r.range:SetText(range .. (range ~= "" and "   " or "") .. it.count)
        return
    end
    r.age:SetText(age(GetTime() - it.at))
    local tag = KIND_TAG[it.kind]
    r.tag:SetText(PGM.Hex(tag[2]) .. tag[1] .. "|r")
    local name = it.short
    if it.rec then
        name = G.WhoText(it.rec)
    elseif it.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[it.class] then
        local c = RAID_CLASS_COLORS[it.class]
        name = PGM.Hex({ c.r, c.g, c.b }) .. name .. "|r"
    end
    r.name:SetText(name)
    local roles = {}
    for l in it.roles:gmatch(".") do roles[#roles + 1] = G.RoleIcon(l) end
    r.roles:SetText(table.concat(roles, ""))
    r.text:SetText(it.text)
end

local function build(p)
    GU.Title(p)
    p.chips = {}
    local prev
    for _, c in ipairs(CHIPS) do
        local chip = W.Chip(p, c[2], function()
            local f = G.opt("chat")
            f[c[1]] = not f[c[1]]
            UI:Refresh()
        end)
        chip.tip = c[3]
        if prev then chip:SetPoint("LEFT", prev, "RIGHT", 4, 0) else chip:SetPoint("TOPLEFT", 0, -46) end
        p.chips[c[1]] = chip
        prev = chip
    end
    p.search = W.EditBox(p, 160, 22, "Search")
    p.search:SetPoint("TOPRIGHT", 0, -46)
    p.search.onChange = function() UI:Refresh() end

    -- Your own line along the bottom: a channel, the text (kept, so an LFM
    -- needn't be typed again or made a macro), and Send. Enter sends too.
    p.channel = W.Button(p, "", 170, 24, C.text2)
    p.channel:SetPoint("BOTTOMLEFT", 0, 0)
    p.channel.tip = "The channel your line goes to. Only channels you're in are listed."
    p.channel:SetScript("OnClick", function(s)
        local cur = G:ChatPostChannel()
        local entries = {}
        for _, c in ipairs(G:ChatChannels()) do
            entries[#entries + 1] = { ("/%d %s"):format(c.id, c.name),
                checked = function() return cur ~= nil and cur.id == c.id end,
                toggle = function()
                    G.opt("chat").channel = c.name
                    UI:Refresh()
                end }
        end
        if #entries == 0 then entries[1] = { "You're in no chat channels", title = true } end
        W.Menu(s, "Send to", entries)
    end)
    p.send = W.Button(p, "Send", 70, 24, C.jade)
    p.send:SetPoint("BOTTOMRIGHT", 0, 0)
    local function send()
        local ok, why = G:SendChatPost()
        if not ok then PGM.Print(why) end
    end
    p.send:SetScript("OnClick", send)
    p.post = W.EditBox(p, 200, 24, "Your LFM or LFG line. It's kept for next time.")
    p.post:SetPoint("LEFT", p.channel, "RIGHT", 6, 0)
    p.post:SetPoint("RIGHT", p.send, "LEFT", -6, 0)
    p.post:SetMaxLetters(255)
    p.post.onChange = function(s) G.opt("chat").post = s:GetText() end
    p.post.onEnter = send

    p.list = W.List(p, 22, buildRow, updateRow)
    p.list:SetPoint("TOPLEFT", 0, -78)
    p.list:SetPoint("BOTTOMRIGHT", 0, 32)
    p.empty = W.FS(p, 12, C.text3)
    p.empty:SetPoint("TOPLEFT", 6, -86)
    p.empty:SetPoint("RIGHT", -6, 0)
    p.empty:SetWordWrap(true)
end

local function refresh(p)
    if GU.Off(p) then return end
    local f = G.opt("chat")
    for k, chip in pairs(p.chips) do chip:SetActive(f[k] and true or false) end
    local rows = G:ChatList({ dungeons = f.dungeons, raids = f.raids, other = f.other, trade = f.trade,
                              lfg = f.lfg, fits = f.fits, search = p.search:GetText() })
    local n = 0
    for _, r in ipairs(rows) do if not r.head then n = n + 1 end end
    p.title:SetText(("LFG chat: %d %s"):format(n, n == 1 and "line" or "lines"))
    p.sub:SetText("Group and trade lines from your chat channels and guild chat in the last 15 minutes, each person's newest. Join LookingForGroup, Trade or World to see more.")
    p.list:SetData(rows, true)
    p.empty:SetText(#rows == 0 and "Nothing yet. Lines show up here as people post them, from when you logged in." or "")
    local c = G:ChatPostChannel()
    p.channel:SetLabel((c and ("/%d %s"):format(c.id, c.name) or "Pick a channel") .. "  v")
    if not p.post:HasFocus() then p.post:SetText(f.post or "") end
end

UI:AddTab({ id = "chat", label = "LFG Chat", build = build, refresh = refresh, module = true, hidden = GU.Hidden,
            icon = "Interface\\Icons\\INV_Letter_15" })
