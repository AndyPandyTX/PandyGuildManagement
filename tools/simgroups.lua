-- Multi-client simulation of Pandy Guild Groups (the group finder).
-- Each simulated player loads PGM's real non-UI files and the real Groups
-- files into its own environment, with stubbed WoW APIs, a stand-in for
-- PGM's window (widgets that accept anything; lists that draw every row so
-- the page code runs), and a fake Group Finder. Groups' records travel
-- through PGM's real Sync.lua over a shared fake guild channel.
--
-- Run by simrun.js with GROUPS = { [file] = source } (from Groups\).

local BASE = 1800000000
local T = 0
local timers, bus = {}, {}
local clients = {}
local failures, passes = 0, 0

local function check(cond, label)
    if cond then passes = passes + 1 else failures = failures + 1 print("FAIL: " .. label) end
end

-- ---------- scheduler ----------
local function schedule(at, fn, every)
    local t = { at = at, fn = fn, every = every }
    table.insert(timers, t)
    return t
end
local C_Timer = {
    After = function(d, fn) schedule(T + d, fn) end,
    NewTicker = function(d, fn)
        local t = schedule(T + d, fn, d)
        return { Cancel = function() t.cancelled = true end }
    end,
    NewTimer = function(d, fn)
        local t = schedule(T + d, fn)
        return { Cancel = function() t.cancelled = true end }
    end,
}

local function run(seconds, step)
    step = step or 0.1
    local stop = T + seconds
    while T < stop do
        T = T + step
        local due = {}
        for i = #bus, 1, -1 do
            if bus[i].at <= T then table.insert(due, 1, table.remove(bus, i)) end
        end
        for _, m in ipairs(due) do
            for _, c in pairs(clients) do
                c.fire("CHAT_MSG_ADDON", m.prefix, m.msg, m.chan, m.from)
            end
        end
        table.sort(timers, function(a, b) return a.at < b.at end)
        local i = 1
        while i <= #timers do
            local t = timers[i]
            if t.cancelled then
                table.remove(timers, i)
            elseif t.at <= T then
                if t.every then t.at = t.at + t.every else table.remove(timers, i) i = i - 1 end
                local ok, err = pcall(t.fn)
                if not ok then print("TIMER ERROR: " .. tostring(err)) failures = failures + 1 end
                i = i + 1
            else
                break
            end
        end
    end
end

-- ---------- a stand-in for PGM's window ----------
-- Anything can be called on these, and they answer with another one, so
-- page code that builds and lays out frames runs without a real UI.
local MockMT = {}
local function Mock() return setmetatable({}, MockMT) end
MockMT.__index = function() return Mock() end
MockMT.__call = function() return Mock() end
for _, m in ipairs({ "__add", "__sub", "__mul", "__div", "__mod", "__unm" }) do MockMT[m] = function() return 0 end end
MockMT.__concat = function(a, b) return (type(a) == "string" and a or "") .. (type(b) == "string" and b or "") end
MockMT.__lt = function() return false end
MockMT.__le = function() return false end
MockMT.__len = function() return 0 end
MockMT.__tostring = function() return "" end

local function mockUI(c)
    local W = setmetatable({}, { __index = function() return function() return Mock() end end })
    -- Lists build and update a row for every item, and hover it, so the
    -- row code (and its tooltips) runs too.
    rawset(W, "List", function(_, _, buildRow, updateRow)
        local l = Mock()
        rawset(l, "SetData", function(self, data)
            for i, d in ipairs(data or {}) do
                local r = buildRow(self, i)
                updateRow(r, d, i)
                if rawget(r, "onEnter") then r.onEnter(r) end
            end
        end)
        return l
    end)
    local UI = { W = W, tabs = {} }
    function UI:AddTab(t) self.tabs[t.id] = t end
    function UI:QueueRefresh() end
    function UI:Refresh() end
    function UI:Show(id) c.st.opened[#c.st.opened + 1] = id end
    function UI:MemberMenu() end
    function UI:OpenProfile() end
    function UI:Whisper() end
    function UI:Invite() end
    return UI
end

-- Build and refresh every Groups page, the way the window would.
local function drawPages(c)
    for _, tab in pairs(c.PGM.UI.tabs) do
        local p = Mock()
        rawset(p, "IsVisible", function() return true end)
        tab.build(p)
        tab.refresh(p)
    end
end

-- ---------- the guild ----------
local REALM = "MalGanis"
local function gid(n) return ("Player-3676-%08X"):format(n) end
local ROSTER = {
    { gid(1),  "Deathsquaad", "Guild Master", 0, "PALADIN" },
    { gid(10), "Nattypandy",  "Officer",      1, "DRUID" },
    { gid(11), "Magicpayne",  "Officer",      1, "MAGE" },
    { gid(13), "Codiex",      "Member",       5, "DEMONHUNTER" },
    { gid(15), "Demonpandy",  "Officer Alt",  3, "DEMONHUNTER" },
    { gid(22), "Funkyshade",  "Raider",       4, "PRIEST" },
}
local function memberTable()
    local m = {}
    for _, r in ipairs(ROSTER) do
        m[r[1]] = { guid = r[1], name = r[2] .. "-" .. REALM, short = r[2], realm = REALM, rank = r[3],
                    rankIndex = r[4], level = 90, class = r[5], note = "", onote = "", online = true,
                    lastOnline = BASE, score = 2000 + r[4] * 100 }
    end
    return m
end

-- RaiderIO's lookup, for every client: a few known profiles.
local RIO = {
    Funkyshade = { mplusCurrent = { score = 2500, roles = { { "healer", "full" }, { "dps", "partial" } } },
                   mplusMainCurrent = { score = 0, roles = {} },
                   mplusWarbandCurrent = { score = 3146.4, roles = { { "tank", "full" } } } },
}

-- ---------- a client ----------
local PGM_FILES = { "Core.lua", "Club.lua", "Roster.lua", "GuildEvents.lua", "Alts.lua", "Attendance.lua", "Teams.lua",
                    "Sync.lua", "Grm.lua", "Activity.lua", "Stats.lua", "Progress.lua", "Bulk.lua" }
local GROUP_FILES = { "Core.lua", "Keystone.lua", "Status.lua", "Posts.lua", "GroupFinder.lua",
                      "UI/Common.lua", "UI/Groups.lua", "UI/Free.lua", "UI/Keys.lua" }

local function newClient(guid, name, class, specRole)
    local frames = {}
    local env = setmetatable({}, { __index = _G })
    local c = { env = env, name = name .. "-" .. REALM, guid = guid, prints = {} }
    -- Everything about this player's game the tests poke at.
    local st = {
        group = {}, leader = true, blocked = false, key = { map = 0, level = 0 }, class = class, specRole = specRole,
        invites = {}, chat = {}, opened = {}, finder = {}, tip = {},
        lfg = { listed = false, activity = 1, apps = {}, invited = {}, declined = {}, results = {}, order = {},
                counts = {}, players = {}, appStatus = {}, applied = {}, searches = {} },
    }
    c.st = st
    function c.fire(event, ...)
        for _, f in ipairs(frames) do
            if f.events[event] and f.scripts.OnEvent then
                local ok, err = pcall(f.scripts.OnEvent, f, event, ...)
                if not ok then print("EVENT ERROR [" .. name .. "] " .. event .. ": " .. tostring(err)) failures = failures + 1 end
            end
        end
    end
    -- Frames listen for events and take any other call (the UI needs that).
    env.CreateFrame = function()
        local f = setmetatable({ events = {}, scripts = {} }, MockMT)
        rawset(f, "RegisterEvent", function(self, e) self.events[e] = true end)
        rawset(f, "UnregisterEvent", function(self, e) self.events[e] = nil end)
        rawset(f, "SetScript", function(self, k, fn) self.scripts[k] = fn end)
        table.insert(frames, f)
        return f
    end
    env.C_Timer = C_Timer
    env.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
    env.strjoin = function(sep, ...) return table.concat({ ... }, sep) end
    env.tostringall = function(...) local t = { ... } for i = 1, select("#", ...) do t[i] = tostring(t[i]) end return table.unpack(t, 1, select("#", ...)) end
    env.strsplit = function(sep, s)
        local out, from = {}, 1
        while true do
            local a, b = s:find(sep, from, true)
            if not a then out[#out + 1] = s:sub(from) break end
            out[#out + 1] = s:sub(from, a - 1)
            from = b + 1
        end
        return table.unpack(out)
    end
    env.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    env.tContains = function(t, v) for _, x in ipairs(t) do if x == v then return true end end return false end
    env.tIndexOf = function(t, v) for i, x in ipairs(t) do if x == v then return i end end end
    env.unpack = table.unpack
    env.date = os.date
    env.time = os.time
    env.geterrorhandler = function() return function(e) print("ERROR [" .. name .. "]: " .. tostring(e)) failures = failures + 1 end end
    env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) c.prints[#c.prints + 1] = m end }
    env.C_AddOns = { GetAddOnMetadata = function() return "sim" end }
    env.SlashCmdList = {}
    env.IsInGuild = function() return true end
    env.GetGuildInfo = function() return "For Honor and Mercy", "x", 1, REALM end
    env.GetNormalizedRealmName = function() return REALM end
    env.UnitGUID = function(u) if u == "player" then return guid end end
    env.UnitFullName = function() return name, REALM end
    env.UnitLevel = function() return 90 end
    env.GetServerTime = function() return BASE + math.floor(T) end
    env.GetTime = function() return T end
    env.InCombatLockdown = function() return false end
    env.IsInInstance = function() if st.blocked then return true, "party" end return false, "none" end
    env.IsInRaid = function() return false end
    env.GetInstanceInfo = function() return "Town", "none", 0, "" end
    env.GetNumGuildMembers = function() return 0 end
    env.GetMaxLevelForLatestExpansion = function() return 90 end
    env._G = env
    env.GetNumGuildEvents = function() return 0 end
    env.QueryGuildEventLog = function() end
    env.C_GuildInfo = { GuildRoster = function() end }
    env.Enum = { SendAddonMessageResult = { AddonMessageThrottle = 3 },
                 LFGListFilter = { PvE = 1, CurrentSeason = 0x40, Recommended = 4 } }
    env.C_ChatInfo = {
        RegisterAddonMessagePrefix = function() end,
        InChatMessagingLockdown = function() return st.blocked end,
        SendAddonMessage = function(prefix, msg, chan)
            assert(#msg <= 255, "message over 255 bytes: " .. #msg)
            table.insert(bus, { at = T + 0.05, prefix = prefix, msg = msg, chan = chan, from = c.name })
            return 0
        end,
    }

    -- The player's group: st.group = { { name = "X-Realm", assigned = "HEALER", class = "PRIEST" } }.
    env.IsInGroup = function() return #st.group > 0 end
    env.GetNumGroupMembers = function() return #st.group > 0 and #st.group + 1 or 0 end
    env.UnitIsGroupLeader = function() return st.leader end
    env.UnitIsUnit = function() return false end
    local function member(unit) return st.group[tonumber(unit:match("%d+") or "")] end
    env.UnitName = function(unit)
        if unit == "player" then return name end
        local m = member(unit)
        if m then return m.name:match("^(.-)%-(.+)$") end
    end
    env.UnitClass = function(unit)
        if unit == "player" then return "x", st.class end
        local m = member(unit)
        return m and "x", m and m.class
    end
    env.UnitGroupRolesAssigned = function(unit)
        if unit == "player" then return "NONE" end
        local m = member(unit)
        return m and m.assigned or "NONE"
    end
    env.C_PartyInfo = { InviteUnit = function(n) st.invites[#st.invites + 1] = n end }
    env.GetSpecialization = function() return 1 end
    env.GetSpecializationRole = function() return st.specRole end
    env.GetSpecializationInfo = function() return 105 end
    env.GetSpecializationInfoByID = function(id) return id, "Spec" .. id, "", 135940 end
    env.GetAverageItemLevel = function() return 651, 650.4 end
    env.C_MythicPlus = {
        GetOwnedKeystoneChallengeMapID = function() return st.key.map end,
        GetOwnedKeystoneLevel = function() return st.key.level end,
        RequestMapInfo = function() end,
        GetSeasonBestForMap = function(m) if m == 501 then return { level = 14 }, nil end end,
    }
    env.C_ChallengeMode = {
        GetMapUIInfo = function(m) return "Dungeon" .. m, m, 1800, "icon" .. m end,
        GetMapTable = function() return { 501, 502 } end,
    }
    env.C_DateAndTime = { GetSecondsUntilWeeklyReset = function() return 3 * 86400 end }
    env.C_Container = {
        GetContainerNumSlots = function(bag) return bag == 1 and 3 or 0 end,
        GetContainerItemID = function(_, slot) return slot == 2 and 180653 or 1 end,
        GetContainerItemLink = function() return "|cffa335ee|Hkeystone:180653:501:14|h[Keystone: Dungeon501 (14)]|h|r" end,
    }
    env.C_Item = { IsItemKeystoneByID = function(id) return id == 180653 and st.key.map > 0 end }
    env.SendChatMessage = function(text, ch) st.chat[#st.chat + 1] = ch .. ":" .. text end
    env.PlaySound = function() end
    env.SOUNDKIT = { TELL_MESSAGE = 1 }
    env.STANDARD_TEXT_FONT = "font"
    env.INLINE_TANK_ICON, env.INLINE_HEALER_ICON, env.INLINE_DAMAGER_ICON = "[T]", "[H]", "[D]"
    env.RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1 } end })
    env.LOCALIZED_CLASS_NAMES_MALE = setmetatable({}, { __index = function(_, k) return k end })
    env.bit = { bor = function(a, b) return a + b end }
    env.RaiderIO = { GetProfile = function(n) local p = RIO[n] return p and { mythicKeystoneProfile = p } end }
    env.PVEFrame_ShowFrame = function(a) st.finder[#st.finder + 1] = a end

    -- The Group Finder.
    local L = st.lfg
    env.C_LFGList = {
        HasActiveEntryInfo = function() return L.listed end,
        GetActiveEntryInfo = function()
            if not L.listed then return nil end
            return { activityIDs = { L.activity }, name = "|Ks1|k0000|k", comment = "" }
        end,
        GetActivityInfoTable = function(id)
            if id == 1 then return { fullName = "Dungeon501 (Mythic Keystone)", isMythicPlusActivity = true, maxNumPlayers = 5, categoryID = 2 } end
            if id == 2 then return { fullName = "Voidspire (Heroic)", isCurrentRaidActivity = true, maxNumPlayers = 30, categoryID = 3 } end
            if id == 11 then return { fullName = "Dungeon502 (Mythic Keystone)", isMythicPlusActivity = true, maxNumPlayers = 5, categoryID = 2 } end
        end,
        GetApplicants = function()
            local ids = {}
            for id in pairs(L.apps) do ids[#ids + 1] = id end
            table.sort(ids)
            return ids
        end,
        GetApplicantInfo = function(id)
            local a = L.apps[id]
            return a and { applicantID = id, applicationStatus = a.status, numMembers = #a.members, comment = a.comment or "" }
        end,
        GetApplicantMemberInfo = function(id, i)
            local m = L.apps[id] and L.apps[id].members[i]
            if not m then return nil end
            return m.name, m.class, "", 90, m.ilvl, 0, m.tank, m.healer, m.dps, m.assigned or "NONE", nil, m.score, 0, "", 0, m.spec
        end,
        InviteApplicant = function(id) L.invited[#L.invited + 1] = id end,
        DeclineApplicant = function(id) L.declined[#L.declined + 1] = id end,
        Search = function(cat, filters) L.searches[#L.searches + 1] = cat .. ":" .. filters end,
        GetSearchResults = function() return #L.order, L.order end,
        GetSearchResultInfo = function(id) return L.results[id] end,
        GetSearchResultMemberCounts = function(id) return L.counts[id] end,
        GetSearchResultPlayerInfo = function(id, i) return L.players[id] and L.players[id][i] end,
        GetApplicationInfo = function(id) return id, L.appStatus[id] or "none" end,
        ApplyToGroup = function(id, t, h, d)
            L.applied[#L.applied + 1] = id .. ":" .. tostring(t) .. tostring(h) .. tostring(d)
            L.appStatus[id] = "applied"
        end,
        CancelApplication = function(id) L.appStatus[id] = nil end,
        GetPlaystyleString = function(_, v) return ({ "Learning", "Relaxed", "Competitive" })[v] end,
        GetLanguageSearchFilter = function() return { enUS = true } end,
        ClearSearchTextFields = function() end,
    }
    -- Blizzard's Group Finder functions the addon hooks, and its search box.
    env.LFGListSearchEntry_Update = function() end
    env.LFGListUtil_SetSearchEntryTooltip = function() end
    env.LFGListApplicationViewer_UpdateApplicantMember = function() end
    env.hooksecurefunc = function(fname, fn)
        local orig = env[fname]
        env[fname] = function(...) orig(...) fn(...) end
    end
    -- A Blizzard frame: it records anchors, hooks and every SetScript made
    -- on it (addon code must never replace Blizzard's scripts).
    local function plainFrame()
        local f = { scripts = {}, children = {}, hooks = {}, setScripts = 0, anchors = { "home" } }
        function f:GetParent() return self.parent end
        function f:SetParent(p) self.parent = p end
        function f:GetPoint() return "TOPLEFT", "home", "TOPLEFT", 1, 2 end
        function f:GetNumPoints() return 1 end
        function f:ClearAllPoints() self.anchors = {} end
        function f:SetPoint(_, rel) self.anchors[#self.anchors + 1] = rel end
        function f:IsVisible() return true end
        function f:GetWidth() return 200 end
        function f:GetHeight() return 20 end
        function f:SetSize() end
        function f:GetFrameStrata() return "MEDIUM" end
        function f:SetFrameStrata() end
        function f:GetFrameLevel() return 3 end
        function f:SetFrameLevel() end
        function f:GetScript(n) return self.scripts[n] end
        function f:SetScript(n, fn) self.scripts[n] = fn self.setScripts = self.setScripts + 1 end
        function f:Show() end
        function f:ClearFocus() end
        function f:CreateTexture() return Mock() end
        function f:HookScript(n, fn) self.hooks[n] = self.hooks[n] or {} table.insert(self.hooks[n], fn) end
        -- What the game does on a key press or click: Blizzard's script, then the hooks.
        function f:Press(n)
            if self.scripts[n] then self.scripts[n](self) end
            for _, fn in ipairs(self.hooks[n] or {}) do fn(self) end
        end
        return f
    end
    local home, box = plainFrame(), plainFrame()
    box.parent, box.clearButton = home, plainFrame()
    -- Blizzard's Enter searches its own panel's category.
    box.scripts.OnEnterPressed = function() env.C_LFGList.Search(home.categoryID, 0) end
    home.SearchBox, home.AutoCompleteFrame, home.categoryID, home.preferredFilters = box, { name = "acf" }, 2, 1
    env.LFGListFrame = { SearchPanel = home }
    c.searchBox, c.searchHome, c.plainFrame = box, home, plainFrame
    env.GameTooltip = {
        SetOwner = function(self, o) self.owner = o end,
        GetOwner = function(self) return self.owner end,
        SetText = function(self, t) st.tip = { t } end,
        AddLine = function(self, t) st.tip[#st.tip + 1] = t end,
        AddDoubleLine = function(self, a, b) st.tip[#st.tip + 1] = a .. " = " .. b end,
        Show = function() end,
        Hide = function() end,
    }

    -- PGM itself (the non-UI files), its window stood in for, then Groups.
    local NS = {}
    for _, f in ipairs(PGM_FILES) do
        local fn, err = load(FILES[f], "@" .. f, "t", env)
        if not fn then error(err) end
        fn("PandyGuildManagement", NS)
    end
    c.PGM = env.PandyGuildManagement
    c.PGM.UI = mockUI(c)
    c.fire("ADDON_LOADED", "PandyGuildManagement")
    local GNS = {}
    for _, f in ipairs(GROUP_FILES) do
        local fn, err = load(GROUPS[f], "@Groups/" .. f, "t", env)
        if not fn then error(err) end
        fn("PandyGuildGroups", GNS)
    end
    c.G = env.PandyGuildGroups
    c.fire("ADDON_LOADED", "PandyGuildGroups")
    c.fire("PLAYER_LOGIN")
    local g = c.PGM.GuildDB(true)
    g.members = memberTable()
    g.seeded = BASE
    c.g = g
    c.PGM:Fire("ROSTER")
    clients[name] = c
    return c
end

local function said(c, text)
    for _, p in ipairs(c.prints) do
        if p:find(text, 1, true) then return true end
    end
    return false
end
local function npost(c, kind)
    local n = 0
    for _, p in pairs(c.G.posts) do if not kind or p.kind == kind then n = n + 1 end end
    return n
end
local function firstPost(c, kind)
    for _, p in pairs(c.G.posts) do if not kind or p.kind == kind then return p end end
end
local function board(c, kind, extra)
    local f = {}
    for k, v in pairs(c.G.opt("board")) do f[k] = v end
    f.kind = kind or "M"
    for k, v in pairs(extra or {}) do f[k] = v end
    local t = {}
    for _, row in ipairs(c.G:Board(f)) do t[#t + 1] = (row.guild and "G:" or "") .. (row.what or "?") .. (row.level ~= "" and ("+" .. row.level) or "") end
    return table.concat(t, ",")
end

-- ================== SCENARIO ==================
local A = newClient(gid(10), "Nattypandy", "DRUID", "TANK")       -- leader
local B = newClient(gid(22), "Funkyshade", "PRIEST", "HEALER")    -- healer
local C = newClient(gid(13), "Codiex", "DEMONHUNTER", "DAMAGER")  -- dps
A.st.key = { map = 501, level = 12 }
run(90)

print("-- login: keys and status")
local bobKeys = B.G:KeyList()
local gotKey = false
for _, k in ipairs(bobKeys) do if k.rec.short == "Nattypandy" and k.level == 12 then gotKey = true end end
check(gotKey, "my key reaches a guildie (K)")
check(C.G.status[gid(22)] and C.G.status[gid(22)].state == "f", "a guildie shows as free (S)")

print("-- post, ping, ask, invite")
A.st.key = { map = 501, level = 14 }
local p = A.G:Post({ kind = "M", what = "Dungeon501", level = "14", size = 5, need = { T = 0, H = 1, D = 3 }, note = "weekly" })
check(p ~= nil, "posting works")
run(10)
local seen = firstPost(B, "M")
check(seen and B.G.PostTitle(seen) == "+14 Dungeon501", "the post reaches guildies")
check(said(B, "needs a"), "a healer is pinged")
check(said(C, "needs a"), "a DPS is pinged")
B.G:Ask(seen.id, "H", "hi")
run(10)
check(said(A, "asks to join"), "the leader hears the ask")
local asks = A.G:Asks()
check(#asks == 1, "one ask (got " .. #asks .. ")")
A.G:InviteAsk(asks[1].key)
run(10)
check(A.st.invites[1] == "Funkyshade-" .. REALM, "the invite is sent")
check(B.G.asked[seen.id] and B.G.asked[seen.id].state == "invited", "the asker is told")

print("-- the group fills")
A.st.group = { { name = "Funkyshade-" .. REALM } }
A.fire("GROUP_ROSTER_UPDATE")
run(10)
local cs = firstPost(C, "M")
check(cs and cs.need.H == 0 and cs.have == 2, "the healer spot is taken")
A.st.group = { { name = "Funkyshade-" .. REALM }, { name = "Codiex-" .. REALM, assigned = "DAMAGER" },
               { name = "X-Other", assigned = "DAMAGER" }, { name = "Y-Other", assigned = "DAMAGER" } }
A.fire("GROUP_ROSTER_UPDATE")
run(10)
check(said(A, "is full"), "the leader is told it's full")
check(npost(C, "M") == 0, "a full post closes for everyone")
A.st.group = {}
A.fire("GROUP_ROSTER_UPDATE")
run(5)

print("-- scheduled group")
local sched = C.G:Post({ kind = "R", what = "Voidspire", level = "H", size = 20, need = { T = 2, H = 4, D = 13 },
                         start = C.PGM.Now() + 3600 })
check(sched ~= nil, "scheduling works")
run(10)
check(firstPost(B, "R") ~= nil, "guildies see it")
B.G:SignUp(firstPost(B, "R").id, "H")
run(10)
check(said(C, "signed up"), "the leader hears the signup")
check(C.G:SignupsLeft(firstPost(C, "R")) == 1, "one signup to invite")
C.G:InviteNextSignup(firstPost(C, "R").id)
check(C.st.invites[1] == "Funkyshade-" .. REALM, "Invite next invites them")
run(3700, 1)
check(said(B, "starts now"), "the signup is reminded")
check(said(C, "starts now"), "the leader is reminded")
run(7300, 2)
check(npost(B, "R") == 0, "a scheduled group expires")

print("-- a scheduled group closed while you were away")
local away = C.G:Post({ kind = "R", what = "Voidspire", level = "M", size = 20, need = { T = 2, H = 4, D = 14 },
                        start = C.PGM.Now() + 7200 })
run(10)
check(firstPost(B, "R") ~= nil, "a guildie holds it")
clients.Funkyshade = nil   -- away: hears nothing
C.G:CloseScheduled(away.id)
run(10)
clients.Funkyshade = B
check(firstPost(B, "R") ~= nil, "still held after missing the close")
B.G.Send(true, "Q")        -- back: what's posted?
run(10)
check(firstPost(B, "R") == nil, "the leader says it's closed when asked")

print("-- editing a scheduled group that has begun")
local begun = C.G:Post({ kind = "O", what = "Mounts", size = 5, need = { D = 4 }, start = C.PGM.Now() + 120 })
local begunAt = begun.start   -- (the post itself changes when edited)
run(200, 1)
local keep = { text = "20:30", start = begunAt }   -- as the form shows it
local again = C.G.ParseWhen("20:30", keep)
check(again == begunAt, "Start left alone keeps the start")
check(C.G.ParseWhen("21:00", keep) ~= begunAt, "a changed Start is read afresh")
local edited, editWhy = C.G:Post({ id = begun.id, kind = "O", what = "Mounts", size = 5, need = { D = 3 }, start = again })
check(edited and edited.start == begunAt and edited.need.D == 3,
      "the edit keeps it scheduled at its start (" .. tostring(editWhy) .. ")")
C.G:CloseScheduled(begun.id)
run(5)

print("-- cleanup")
A.G:Post({ kind = "D", what = "Delve", level = "8", size = 5, need = { T = 1, H = 1, D = 2 } })
run(10)
check(npost(C, "D") == 1, "the delve reaches guildies")
C.g.members[gid(10)].online = false
C.PGM:Fire("ROSTER")
check(npost(C, "D") == 0, "dropped when the leader logs off")
C.g.members[gid(10)].online = true
A.st.blocked = true
run(700, 1)
check(npost(B, "D") == 0, "dropped after going quiet (in an instance)")
local _, why = A.G:Post({ kind = "O", need = { D = 1 } })
check(why ~= nil, "no posting from an instance")
A.st.blocked = false
run(300, 1)
check(npost(B, "D") == 1, "back with the next heartbeat")
-- A forged close from someone else is ignored.
C.env.C_ChatInfo.SendAddonMessage("PandyGuildMgmt", table.concat({ "1G", "X", firstPost(B, "D").id, tostring(C.PGM.Now() + 10), "c" }, "\031"), "GUILD")
run(3)
check(npost(B, "D") == 1, "a forged close is ignored")
A.G:CloseMine("c")
run(5)

print("-- LibKeystone")
local before = #bus
A.G:RequestLibKeystone()
check(#bus > before and bus[#bus].prefix == "LibKS", "asks the guild on LibKS")
A.fire("CHAT_MSG_ADDON", "LibKS", "15,502,3100", "GUILD", "Codiex-" .. REALM)
local ck = A.G:Keys()[gid(13)]
check(ck and ck.level == 15 and ck.map == 502, "a LibKeystone reply is a key")
A.fire("CHAT_MSG_ADDON", "LibKS", "-1,-1,3100", "GUILD", "Magicpayne-" .. REALM)
check(A.G:Keys()[gid(11)] == nil, "a hidden key stays hidden")
A.fire("CHAT_MSG_ADDON", "LibKS", "9,501,3100", "PARTY", "Deathsquaad-" .. REALM)
check(A.G:Keys()[gid(1)] == nil, "party replies are ignored")

print("-- keys catch-up and relays")
local vs, send = {}, A.G.Send
A.G.Send = function(quiet, sub, ...)
    if sub == "V" then vs[#vs + 1] = (...) end
    return send(quiet, sub, ...)
end
A.G.handlers.W({ "1G", "W", "0" }, "Funkyshade-" .. REALM)
A.G.handlers.W({ "1G", "W", "0" }, "Magicpayne-" .. REALM)
run(10)
A.G.Send = send
check(#vs == 2, "two askers at once both get keys (got " .. #vs .. ")")
local soon = A.PGM.Now() + 300
A.G.handlers.K({ "1G", "K", gid(22), tostring(soon), "502", "2" }, "Codiex-" .. REALM, A.g.members[gid(13)])
run(10)
A.G.handlers.K({ "1G", "K", gid(22), tostring(A.PGM.Now()), "502", "20" }, "Funkyshade-" .. REALM, A.g.members[gid(22)])
check(A.G:Keys()[gid(22)].level == 20, "a relayed key stamped ahead can't beat its owner's")

print("-- scores")
local line = A.G.ScoreText(A.g.members[gid(22)])
check(line:find("2400", 1, true) and line:find("Warband", 1, true) and line:find("3146", 1, true), "character and warband scores, warband higher")
check(line:find("1:20|t", 1, true) and line:find("22:41:110:110:110", 1, true), "roles: healer full, dps partial")
check(not line:find("Main", 1, true), "no main when it's zero")

print("-- Group Finder listing becomes a guild post")
A.st.key = { map = 501, level = 14 }
A.st.lfg.listed = true
A.fire("LFG_LIST_ACTIVE_ENTRY_UPDATE")
run(10)
check(A.G.mine and A.G.mine.fromLFG and A.G.PostTitle(A.G.mine) == "+14 Dungeon501", "listing posts it")
check(A.G.mine and A.G.mine.need.T .. A.G.mine.need.H .. A.G.mine.need.D == "013", "needs less my own role")
check(A.st.opened[#A.st.opened] == "groups", "listing opens the Groups page")
check(firstPost(B, "M") and firstPost(B, "M").lfg, "guildies see it's in the Group Finder")

print("-- a listing's needs follow the group, each member counted once")
local function lfgNeeds() return A.G.mine and (A.G.mine.need.T .. A.G.mine.need.H .. A.G.mine.need.D) or "none" end
-- The listing's update reaches us before the roster's (the order that counted twice).
A.st.group = { { name = "Codiex-" .. REALM, assigned = "DAMAGER", class = "DEMONHUNTER" } }
A.fire("LFG_LIST_ACTIVE_ENTRY_UPDATE")
run(0.5)
A.fire("GROUP_ROSTER_UPDATE")
run(5)
check(lfgNeeds() == "012", "a joiner comes off the needs once (got " .. lfgNeeds() .. ")")
A.st.group = {}
A.fire("LFG_LIST_ACTIVE_ENTRY_UPDATE")
run(0.5)
A.fire("GROUP_ROSTER_UPDATE")
run(5)
check(lfgNeeds() == "013", "a leaver's place opens once (got " .. lfgNeeds() .. ")")
-- And the other way round: the roster first.
A.st.group = { { name = "Codiex-" .. REALM, assigned = "DAMAGER", class = "DEMONHUNTER" } }
A.fire("GROUP_ROSTER_UPDATE")
run(0.5)
A.fire("LFG_LIST_ACTIVE_ENTRY_UPDATE")
run(5)
check(lfgNeeds() == "012", "the roster first counts once too (got " .. lfgNeeds() .. ")")
A.st.group = {}
A.fire("GROUP_ROSTER_UPDATE")
run(5)
check(lfgNeeds() == "013", "back to the listing's own needs (got " .. lfgNeeds() .. ")")

print("-- applicants")
A.st.lfg.apps[7] = { status = "applied", comment = "lfg", members = { { name = "Pug-Other", class = "MAGE", ilvl = 655, dps = true, score = 2100, spec = 63 } } }
A.st.lfg.apps[8] = { status = "applied", members = { { name = "Funkyshade", class = "PRIEST", ilvl = 650, healer = true, dps = true, score = 2500, spec = 257 } } }
A.fire("LFG_LIST_APPLICANT_LIST_UPDATED")
run(1)
check(said(A, "applied through the Group Finder"), "a guildie applying is announced")
local order = {}
for _, it in ipairs(A.G:Asks()) do order[#order + 1] = it.ask.short end
check(table.concat(order, ",") == "Funkyshade,Pug", "guildies first (got " .. table.concat(order, ",") .. ")")
B.G:Ask(firstPost(B, "M").id, "H")
run(10)
local n = 0
for _, it in ipairs(A.G:Asks()) do if it.ask.short == "Funkyshade" or it.ask.name == "Funkyshade-" .. REALM then n = n + 1 end end
check(n == 1, "asked both ways, listed once")
A.G:InviteAsk(A.G:Asks()[2].key)
check(A.st.lfg.invited[1] == 7, "Invite goes through the Group Finder")
drawPages(A)

print("-- listing closes")
A.G:CloseMine("c")
A.fire("LFG_LIST_ACTIVE_ENTRY_UPDATE")
run(5)
check(A.G.mine == nil, "closed by hand stays closed")
A.st.lfg.listed = false
A.fire("LFG_LIST_ACTIVE_ENTRY_UPDATE")
run(5)
A.st.lfg.listed, A.st.lfg.activity = true, 2
A.fire("LFG_LIST_ACTIVE_ENTRY_UPDATE")
run(5)
check(A.G.mine and A.G.PostTitle(A.G.mine) == "Voidspire (H)", "relisting posts again")
A.st.lfg.listed = false
A.fire("LFG_LIST_ACTIVE_ENTRY_UPDATE")
run(10)
check(A.G.mine == nil and npost(B, "R") == 0, "delisting closes it everywhere")
A.st.lfg.activity = 1

print("-- searching the Group Finder")
local L = C.st.lfg
L.order = { 101, 102, 103, 104, 105 }
L.results[101] = { activityIDs = { 1 }, name = "+14 Relaxed", leaderName = "Stranger-Other", numMembers = 2, leaderOverallDungeonScore = 3000, generalPlaystyle = 2, age = 300, numGuildMates = 0 }
L.counts[101] = { TANK = 1, HEALER = 0, DAMAGER = 1 }
L.players[101] = { { classFilename = "WARRIOR", assignedRole = "TANK", isLeader = true }, { classFilename = "MAGE", assignedRole = "DAMAGER" } }
L.results[102] = { activityIDs = { 11 }, name = "9", leaderName = "Nattypandy-" .. REALM, numMembers = 1, leaderOverallDungeonScore = 2900, generalPlaystyle = 1, age = 60, numGuildMates = 1 }
L.counts[102] = { TANK = 1, HEALER = 0, DAMAGER = 0 }
L.players[102] = { { classFilename = "DRUID", assignedRole = "TANK" } }
L.results[103] = { activityIDs = { 1 }, name = "20+", leaderName = "Pro-Other", numMembers = 4, leaderOverallDungeonScore = 3500, generalPlaystyle = 3, age = 30, numGuildMates = 0 }
L.counts[103] = { TANK = 1, HEALER = 1, DAMAGER = 2, TANK_REMAINING = 0, HEALER_REMAINING = 0, DAMAGER_REMAINING = 1 }
L.results[104] = { activityIDs = { 1 }, name = "|Ks12|k0000000000000000|k", leaderName = "Hidden-Other", numMembers = 1, age = 10 }
L.results[105] = { activityIDs = { 2 }, name = "|Ks5|k00|k", leaderName = "Raidlead-Other", numMembers = 29, numGuildMates = 2, age = 60 }
L.counts[105] = { TANK = 2, HEALER = 6, DAMAGER = 21, TANK_REMAINING = 28, HEALER_REMAINING = 24, DAMAGER_REMAINING = 9 }
local ok = C.G:SearchFinder("M")
check(ok and L.searches[1] == "2:65", "searches with the M+ filters")
C.fire("LFG_LIST_SEARCH_RESULTS_RECEIVED")
run(1)
local r = {}
for _, x in ipairs(C.G:FinderResults()) do r[x.id] = x end
check(r[101] and r[101].level == "14" and r[102].level == "9" and r[103].level == "20", "levels from readable titles")
check(r[104] and r[104].level == "" and r[104].title == "|Ks12|k0000000000000000|k", "a protected title is kept to draw, never read")
check(r[101].need.T .. r[101].need.H .. r[101].need.D == "012", "needs from who's in it")
check(r[103].need.D == 1, "remaining counts used for five-player groups")
check(r[101].lust and r[101].playstyle == "Relaxed", "lust and playstyle")
check(r[101].comp[1].class == "WARRIOR" and r[101].comp[1].role == "T", "the comp is read")
check(r[105].kind == "R" and r[105].has.T == 2 and r[105].diff == "Heroic" and r[105].mates == 2, "a raid: who's in, difficulty, guildies")

print("-- the board")
check(board(C) == "G:Dungeon502+9,Dungeon501,Dungeon501+20,Dungeon501+14", "guild first, then newest (got " .. board(C) .. ")")
check(board(C, "M", { guildOnly = true }) == "G:Dungeon502+9", "guild only")
check(board(C, "M", { minRating = 3100 }) == "Dungeon501+20", "leader rating")
check(board(C, "M", { playstyle = "Learning" }) == "G:Dungeon502+9", "playstyle")
check(board(C, "M", { skip = { Dungeon501 = true } }) == "G:Dungeon502+9", "an unticked dungeon is hidden")
check(board(C, "M", { hasHealer = true }) == "Dungeon501+20", "has a healer")
check(board(C, "M", { brez = true }) == "G:Dungeon502+9", "battle res (druid)")
check(board(C, "M", { guildFirst = false, sort = "rating" }):sub(1, 14) == "Dungeon501+20,", "sorted by leader rating")
check(board(C, "R") == "G:Voidspire+H", "raids are their own category, guild-marked (got " .. board(C, "R") .. ")")
local allSet = true
for _, row in ipairs(C.G:Board({ kind = "M" })) do
    if type(row.scheduled) ~= "boolean" then allSet = false end
end
check(allSet, "every row says whether it's scheduled")
local acts = C.G:BoardActivities("M")
check(#acts == 2 and acts[1].icon == "icon501" and acts[1].best == 14, "this season's dungeons, with icons and my best")

print("-- applying")
C.G:ApplyFinder(101)
check(L.applied[1] == "101:falsefalsetrue", "applies with the roles I play")
check(board(C):sub(1, 14) == "Dungeon501+14,", "my application goes to the top")
check(C.G:Board({ kind = "M", minRating = 9999 })[1].state == "pending", "pending shows past the filters")
C.G:CancelFinder(101)
check(board(C):sub(1, 6) == "G:Dung", "cancelling unpins it")
L.appStatus[103] = "declined"
C.fire("LFG_LIST_SEARCH_RESULT_UPDATED")
run(1)
check(board(C):sub(1, 14) == "Dungeon501+20,", "a fresh decline is pinned on top")
run(130, 1)
check(not board(C):find("+20", 1, true), "then Hide declined hides it")
C.fire("LFG_LIST_APPLICATION_STATUS_UPDATED", 101, "applied", "none")
check(C.st.opened[#C.st.opened] == "groups", "applying anywhere opens the Groups page")

print("-- Blizzard's search box")
C.G.UI.ShowView("board")
drawPages(C)
local box = C.searchBox
check(box.parent == C.searchHome and box.anchors[1] ~= "home", "moved into Browse, still Blizzard's child")
check(box.setScripts == 0 and box.clearButton.setScripts == 0, "Blizzard's scripts are never replaced")
check(box.hooks.OnEnterPressed and box.clearButton.hooks.OnClick, "ours are hooked on after them")
local searched = #L.searches
box:Press("OnEnterPressed")
check(#L.searches == searched + 1 and L.searches[#L.searches] == "2:0", "Enter is Blizzard's search, once")
C.searchHome.categoryID = 3
box:Press("OnEnterPressed")
check(#L.searches == searched + 3 and L.searches[#L.searches] == "2:65", "then Browse's category if Blizzard's was another")
C.searchHome.categoryID = 2
C.G.UI.ShowView("mine")
drawPages(C)
check(box.anchors[1] == "home", "given back on leaving Browse")
searched = #L.searches
box:Press("OnEnterPressed")
check(#L.searches == searched + 1, "given back, our hook stands aside")
box.parent = "oak"
C.G.UI.ShowView("board")
drawPages(C)
check(box.anchors[1] == "home", "left alone when another addon has it")
box.parent = C.searchHome
C.G.UI.ShowView("mine")
drawPages(C)

print("-- tell the guild, list my key")
check(A.G:Announce() == false, "nothing to tell without a group")
A.G:Post({ kind = "M", what = "Dungeon501", level = "14", size = 5, need = { T = 1, H = 0, D = 2 } })
local text = A.G:AnnounceText()
check(text:find("[Keystone: Dungeon501 (14)]", 1, true) and text:find("needs 1 Tank, 2 DPS", 1, true), "the chat line has the key link and needs")
check(A.G:Announce() and A.st.chat[1] == "GUILD:" .. text, "it goes to guild chat")
check(A.G:Announce() == false, "at most once a minute")
A.G:CloseMine("c")
A.G:ListMyKey()
check(A.st.finder[1] == "GroupFinderFrame", "List opens the Group Finder (and nothing protected)")

print("-- keystones page order")
A.st.key = { map = 501, level = 14 }
A.fire("BAG_UPDATE_DELAYED")
run(5)
local keys = A.G.DB().keys
keys[gid(22)] = { map = 502, level = 19, u = A.PGM.Now() - 10 }
keys[gid(13)] = { map = 502, level = 15, u = A.PGM.Now() - 5 }
local function korder()
    local t = {}
    for _, it in ipairs(A.G.UI.KeyRows()) do t[#t + 1] = it.rec.short .. "+" .. it.level end
    return table.concat(t, ",")
end
A.G.setOpt("keysSort", "level") A.G.setOpt("keysReverse", false) A.G.setOpt("keysOnline", true)
check(korder() == "Funkyshade+19,Codiex+15,Nattypandy+14", "highest first (got " .. korder() .. ")")
A.G.setOpt("keysReverse", true)
check(korder() == "Nattypandy+14,Codiex+15,Funkyshade+19", "reversed")
A.G.setOpt("keysReverse", false) A.G.setOpt("keysPinMine", true)
check(korder():sub(1, 13) == "Nattypandy+14", "Mine first pins mine")
A.G.setOpt("keysPinMine", false)
A.g.members[gid(13)].online = false
check(korder() == "Funkyshade+19,Nattypandy+14", "Online only hides offline keys")
A.g.members[gid(13)].online = true

print("-- the off switch")
A.G:Post({ kind = "M", what = "Dungeon501", level = "14", size = 5, need = { T = 1, H = 1, D = 2 } })
run(10)
check(firstPost(B, "M") ~= nil, "a post is up before switching off")
local navBuilt = 0
A.PGM.UI.frame = {}
A.PGM.UI.BuildNav = function() navBuilt = navBuilt + 1 end
A.G:SetEnabled(false)
run(10)
check(navBuilt == 1, "switching off lays the sidebar out again")
local gone = true
for _, pp in pairs(B.G.posts) do if pp.leader == gid(10) and pp.kind == "M" then gone = false end end
check(gone, "switching off closes my post for everyone")
check(not A.G:IsEnabled() and A.G.Send(true, "Q") == false, "no sends while off")
check(A.PGM.UI.tabs.groups.hidden(), "tabs say hidden while off")
A.env.SlashCmdList.PANDYGUILDGROUPS("")
check(said(A, "is off"), "/pgg says it's off")
drawPages(A)
A.env.SlashCmdList.PANDYGUILDGROUPS("on")
check(A.G:IsEnabled() and A.G.Send(true, "Q"), "/pgg on brings it back")
check(navBuilt == 2, "and lays the sidebar out again")
A.PGM.UI.frame, A.PGM.UI.BuildNav = nil, nil

print("-- every page and view draws")
for _, cl in ipairs({ A, B, C }) do
    for _, view in ipairs({ "board", "mine", "post" }) do
        cl.G.UI.ShowView(view)
        drawPages(cl)
    end
end
check(true, "pages build and refresh")

print(("\n%d passed, %d failed"):format(passes, failures))
