-- Multi-client simulation of PandyGuildManagement's guild sync.
-- Each simulated player loads the real addon files into its own environment
-- with stubbed WoW APIs; addon messages travel over a shared fake guild channel.

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
    step = step or 0.05
    local stop = T + seconds
    while T < stop do
        T = T + step
        -- deliver addon messages
        local due = {}
        for i = #bus, 1, -1 do
            if bus[i].at <= T then table.insert(due, 1, table.remove(bus, i)) end
        end
        for _, m in ipairs(due) do
            for _, c in pairs(clients) do
                c.fire("CHAT_MSG_ADDON", m.prefix, m.msg, m.chan, m.from)
            end
        end
        -- run timers
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

-- ---------- the guild ----------
local REALM = "MalGanis"
local function gid(n) return ("Player-3676-%08X"):format(n) end
local ROSTER = {
    { gid(1),  "Deathsquaad", "Guild Master",    0, "PALADIN", "", "" },
    { gid(10), "Nattypandy",  "Officer",         1, "DRUID",   "VA/Main/325/DPS/Heal/Pandy", "" },
    { gid(11), "Magicpayne",  "Officer",         1, "MAGE",    "HO/Main/308/DPS/Payne", "" },
    { gid(12), "Tamarynn",    "Raid Leadership", 2, "MAGE",    "H&M raidlead/Tam", "" },
    { gid(13), "Codiex",      "Member",          5, "DEMONHUNTER", "", "M+ / Social / Fill-in" },
    { gid(14), "Anvar",       "Raider",          4, "HUNTER",  "VA/Main/312/DPS/Anvar", "Team Valor" },
    { gid(15), "Demonpandy",  "Officer Alt",     3, "DEMONHUNTER", "NattyPandy", "" },
    { gid(21), "Atlasqt",     "Raider",          4, "DEATHKNIGHT", "VA/Main/311/DPS+Tank/Atlas.xd", "Team Valor" },
    { gid(22), "Funkyshade",  "Raider",          4, "PRIEST",  "VA/Main/323/HLS/Funky", "" },
    { gid(23), "Selwyne",     "Raider",          4, "DRUID",   "Valor/Main/DPS/317/Reed", "" },
    { gid(24), "Triclops",    "Raid Leadership", 2, "DEATHKNIGHT", "VA/Main/310/Tank/Triclops", "" },
    { gid(25), "Tiferis",     "Raider",          4, "PALADIN", "", "Holy. Valor. 3/12" },
    { gid(26), "Yinsane",     "Trial",           6, "SHAMAN",  "", "Valor Trial" },
    { gid(30), "Codiexalt",   "Member",          5, "WARRIOR", "", "" },
    { gid(40), "Trollboi",    "Member",          5, "ROGUE",   "", "" },
}
local function memberTable()
    local m = {}
    for _, r in ipairs(ROSTER) do
        m[r[1]] = { guid = r[1], name = r[2] .. "-" .. REALM, short = r[2], realm = REALM, rank = r[3],
                    rankIndex = r[4], level = 90, class = r[5], note = r[6], onote = r[7], online = true,
                    lastOnline = BASE }
    end
    return m
end

-- ---------- a client ----------
local function newClient(guid, name)
    local frames = {}
    local env = setmetatable({}, { __index = _G })
    local c = { env = env, name = name .. "-" .. REALM, guid = guid }
    function c.fire(event, ...)
        for _, f in ipairs(frames) do
            if f.events[event] and f.scripts.OnEvent then
                local ok, err = pcall(f.scripts.OnEvent, f, event, ...)
                if not ok then print("EVENT ERROR [" .. name .. "] " .. event .. ": " .. tostring(err)) failures = failures + 1 end
            end
        end
    end
    env.CreateFrame = function()
        local f = { events = {}, scripts = {} }
        function f:RegisterEvent(e) self.events[e] = true end
        function f:UnregisterEvent(e) self.events[e] = nil end
        function f:SetScript(k, fn) self.scripts[k] = fn end
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
    env.geterrorhandler = function() return function(e) print("ERROR: " .. tostring(e)) failures = failures + 1 end end
    env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) c.chat = (c.chat or "") .. m .. "\n" end }
    env.C_AddOns = { GetAddOnMetadata = function() return "sim" end }
    env.SlashCmdList = {}
    env.IsInGuild = function() return true end
    env.GetGuildInfo = function() return "For Honor and Mercy", "x", 1, REALM end
    env.GetNormalizedRealmName = function() return REALM end
    env.UnitGUID = function(u) if u == "player" then return guid end end
    env.UnitFullName = function() return name, REALM end
    env.UnitClass = function() return "Druid", "DRUID" end
    env.UnitLevel = function() return 90 end
    env.GetServerTime = function() return BASE + math.floor(T) end
    env.GetTime = function() return T end
    env.InCombatLockdown = function() return false end
    env.IsInInstance = function() return false, "none" end
    env.IsInRaid = function() return false end
    env.GetNumGroupMembers = function() return 0 end
    env.GetInstanceInfo = function() return "Town", "none", 0, "" end
    env.GetNumGuildMembers = function() return 0 end
    env.GetMaxLevelForLatestExpansion = function() return 90 end
    env._G = env
    env.ERR_GUILD_PROMOTE_SSS = "%s has promoted %s to %s."
    env.ERR_GUILD_DEMOTE_SSS = "%s has demoted %s to %s."
    env.ERR_GUILD_REMOVE_SS = "%s has been kicked out of the guild by %s."
    env.ERR_GUILD_LEAVE_S = "%s has left the guild."
    env.GetNumGuildEvents = function() return #(GUILD_EVENTS or {}) end
    env.GetGuildEventInfo = function(i) return table.unpack(GUILD_EVENTS[i]) end
    env.QueryGuildEventLog = function() end
    if FOREVER then
        -- WoW Forever: interface 16001, and the engine's latest expansion
        -- still says 90 while the player's cap is 60.
        env.GetBuildInfo = function() return "1.60.1", "70000", "", 16001 end
        env.GetMaxLevelForPlayerExpansion = function() return 60 end
    end
    env.C_GuildInfo = {
        GuildRoster = function() end,
        QueryGuildMembersForRecipe = function(line, recipe) LAST_RECIPE_QUERY = { line, recipe } end,
    }
    env.GetGuildRecipeInfoPostQuery = function()
        local a = RECIPE_ANSWER
        if not a then return nil end
        return a.line, a.recipe, #a.members
    end
    env.GetGuildRecipeMember = function(i)
        local m = RECIPE_ANSWER and RECIPE_ANSWER.members[i]
        return m, m
    end
    env.C_TradeSkillUI = {
        IsTradeSkillReady = function() return true end,
        GetAllRecipeIDs = function() return TRADE and TRADE.ids or {} end,
        GetRecipeInfo = function(id) return TRADE.info[id] end,
        GetProfessionInfoByRecipeID = function(id) return TRADE.prof[id] end,
        GetRecipeOutputItemData = function(id) return { itemID = TRADE.item[id] } end,
    }
    env.Enum = { SendAddonMessageResult = { AddonMessageThrottle = 3 } }
    env.C_ChatInfo = {
        RegisterAddonMessagePrefix = function() end,
        InChatMessagingLockdown = function() return false end,
        SendAddonMessage = function(prefix, msg, chan)
            assert(#msg <= 255, "message over 255 bytes: " .. #msg)
            table.insert(bus, { at = T + 0.05, prefix = prefix, msg = msg, chan = chan, from = c.name })
            c.sent = (c.sent or 0) + 1
            KINDS = KINDS or {}
            local k = msg:sub(2, 2)
            KINDS[k] = (KINDS[k] or 0) + 1
            return 0
        end,
    }
    local NS = {}
    for _, f in ipairs({ "Core.lua", "Club.lua", "Roster.lua", "GuildEvents.lua", "Alts.lua", "Attendance.lua", "Teams.lua", "Sync.lua", "Grm.lua", "Activity.lua", "Bulk.lua", "Crafters.lua" }) do
        local fn, err = load(FILES[f], "@" .. f, "t", env)
        if not fn then error(err) end
        fn("PandyGuildManagement", NS)
    end
    c.NS = NS
    c.fire("ADDON_LOADED", "PandyGuildManagement")
    c.fire("PLAYER_LOGIN")
    c.PGM = env.PandyGuildManagement
    local g = c.PGM.GuildDB(true)
    g.members = memberTable()
    g.seeded = BASE
    c.g = g
    c.PGM:Fire("ROSTER")
    clients[name] = c
    return c
end

local function teamNamed(c, name)
    for _, t in ipairs(c.g.teams or {}) do if t.name == name then return t end end
end

-- ================== SCENARIO ==================
local A = newClient(gid(10), "Nattypandy")   -- officer
local B = newClient(gid(11), "Magicpayne")   -- officer
local C = newClient(gid(13), "Codiex")       -- member
local RL = newClient(gid(12), "Tamarynn")    -- raid leadership
local GM = newClient(gid(1), "Deathsquaad")  -- guild master
run(15)

print("-- who has the addon")
run(30)
local users = A.PGM:AddonUsers()
check(#users == 5, "officer sees all 5 copies running (got " .. #users .. ")")
local cUsers = C.PGM:AddonUsers()
check(#cUsers == 5, "member sees all 5 copies running (got " .. #cUsers .. ")")

print("-- permissions")
check(A.PGM:CanEdit(), "officer can edit")
check(RL.PGM:CanEdit(), "raid leadership can edit by default")
check(not C.PGM:CanEdit(), "member cannot edit")
check(C.PGM:CreateTeam("Hack") == nil, "member CreateTeam refused")

print("-- officer creates a team")
local t = A.PGM:CreateTeam("Team Valor")
A.PGM:AddToTeam(t.id, gid(14))
A.PGM:AddToTeam(t.id, gid(21))
A.PGM:CycleRole(t.id, gid(21))          -- DPS -> TANK
run(20)
for _, cl in ipairs({ B, C, RL, GM }) do
    local tt = teamNamed(cl, "Team Valor")
    check(tt ~= nil, cl.name .. " got the team")
    check(tt and tt.members[gid(14)] ~= nil and tt.members[gid(21)] ~= nil, cl.name .. " got both members")
    check(tt and tt.members[gid(21)] and tt.members[gid(21)].role == "TANK", cl.name .. " got the role change")
end

print("-- member forges a write")
C.env.C_ChatInfo.SendAddonMessage("PandyGuildMgmt", table.concat({ "1T", "999-1", tostring(BASE + 100), "Hacked", "", "", "0" }, "\031"), "GUILD")
run(3)
check(teamNamed(A, "Hacked") == nil, "officer ignored member's forged team")
check(teamNamed(B, "Hacked") == nil, "other officer ignored forged team")

print("-- removal sticks through note import")
A.PGM:RemoveFromTeam(t.id, gid(14))     -- Anvar removed by hand
run(10)
local tb = teamNamed(B, "Team Valor")
check(tb and tb.members[gid(14)] == nil and tb.removed and tb.removed[gid(14)], "B sees Anvar removed")
tb.tags = "Valor, VA, V"
B.PGM:TouchTeam(tb)
local added = B.PGM:ImportTeamFromNotes(tb.id)
check(added == 6, "B imported 6 tagged mains (got " .. tostring(added) .. ")")
check(tb.members[gid(14)] == nil, "import did not re-add removed Anvar")
check(tb.members[gid(15)] == nil, "import skipped the alt Demonpandy")
check(tb.members[gid(10)] ~= nil, "import added officer main Nattypandy (VA note)")
check(tb.members[gid(26)] and tb.members[gid(26)].status == "trial", "Yinsane imported as trial")
check(tb.members[gid(22)] and tb.members[gid(22)].role == "HEALER", "Funkyshade imported as healer (HLS)")
run(25)
local tc = teamNamed(C, "Team Valor")
check(tc and tc.tags == "Valor, VA, V", "member got tags")
local n = 0 for _ in pairs(tc and tc.members or {}) do n = n + 1 end
check(n == 7, "member sees 7 on team (got " .. n .. ")")
check(tc and tc.members[gid(14)] == nil, "member sees Anvar still removed")

print("-- two officers record the same raid night")
local function raid(cl, id, startOff, present, boss)
    local s = { id = id, start = BASE + startOff, stop = BASE + startOff + 3 * 3600, instance = 2810, diffID = 15,
                name = "Manaforge", present = {}, bosses = { boss } }
    for _, gu in ipairs(present) do s.present[gu] = true end
    cl.g.raids = cl.g.raids or { sessions = {} }
    cl.g.raids.sessions = cl.g.raids.sessions or {}
    table.insert(cl.g.raids.sessions, s)
    cl.PGM:SyncRaid(s)
end
raid(A, "r-A", 1000, { gid(10), gid(21), gid(22) }, "Boss One")
raid(B, "r-B", 1300, { gid(11), gid(23), gid(24) }, "Boss Two")
run(25)
for _, cl in ipairs({ A, B, C }) do
    local sessions = cl.g.raids and cl.g.raids.sessions or {}
    check(#sessions == 1, cl.name .. " has one merged raid night (got " .. #sessions .. ")")
    local s = sessions[1] or { present = {}, bosses = {} }
    local p = 0 for _ in pairs(s.present) do p = p + 1 end
    check(p == 6, cl.name .. " merged attendees = 6 (got " .. p .. ")")
    check(#s.bosses == 2, cl.name .. " merged both bosses")
end

print("-- alt link by hand")
A.PGM:LinkAlt(gid(26), gid(25))
run(5)
check(C.g.links[gid(26)] == gid(25), "member got hand-made alt link")
check(C.PGM:KnownMain(gid(26)) == gid(25), "member's alt view updated")
check(not C.PGM:LinkAlt(gid(24), gid(25)), "member can't link alts")

print("-- late joiner catches up")
local D = newClient(gid(14), "Anvar")
run(90)
local td = teamNamed(D, "Team Valor")
check(td ~= nil, "late joiner got the team")
local nd = 0 for _ in pairs(td and td.members or {}) do nd = nd + 1 end
check(nd == 7, "late joiner got 7 members (got " .. nd .. ")")
check(td and td.removed and td.removed[gid(14)], "late joiner knows Anvar was removed")
check(D.g.raids and #D.g.raids.sessions == 1, "late joiner got the raid night")
check(D.g.links[gid(26)] == gid(25), "late joiner got the alt link")

print("-- guild master sets the officer cut-off")
C.env.C_ChatInfo.SendAddonMessage("PandyGuildMgmt", table.concat({ "1C", tostring(BASE + 5000), "5" }, "\031"), "GUILD")
run(3)
check(A.g.sync.officerRank == nil, "member's cut-off message ignored")
GM.PGM:SyncOfficerRank(1)
run(5)
check(RL.g.sync.officerRank == 1, "raid leader received GM cut-off")
check(not RL.PGM:CanEdit(), "raid leadership lost edit after cut-off to rank 2")
check(A.PGM:CanEdit(), "officer keeps edit")
GM.PGM:SyncOfficerRank(nil)
run(5)
check(RL.PGM:CanEdit(), "raid leadership back after GM resets")

print("-- remove then re-add in the same second")
A.PGM:RemoveFromTeam(t.id, gid(21))
A.PGM:AddToTeam(t.id, gid(21))
run(8)
check(teamNamed(C, "Team Valor").members[gid(21)] ~= nil, "member sees the re-add, not the removal")

print("-- inside an instance, messages wait")
A.env.IsInInstance = function() return true, "raid" end
A.PGM:CycleStatus(t.id, gid(21))         -- core -> trial
run(10)
check(teamNamed(C, "Team Valor").members[gid(21)].status == "core", "nothing sent while in the instance")
A.env.IsInInstance = function() return false, "none" end
run(10)
check(teamNamed(C, "Team Valor").members[gid(21)].status == "trial", "sent once out of the instance")

print("-- a member's own recording merges with the officer's")
local mine = { id = "r-C", start = BASE + 90000, stop = BASE + 99000, instance = 2900, name = "Abyss",
               present = { [gid(13)] = true }, bosses = {} }
table.insert(C.g.raids.sessions, mine)
local s2 = { id = "r-A2", start = BASE + 90300, stop = BASE + 99300, instance = 2900, diffID = 16, name = "Abyss",
             present = { [gid(10)] = true, [gid(13)] = true, [gid(21)] = true }, bosses = { "Ula'tek" } }
table.insert(A.g.raids.sessions, s2)
A.PGM:SyncRaid(s2)
run(10)
local abyss = 0
for _, s in ipairs(C.g.raids.sessions) do if s.instance == 2900 then abyss = abyss + 1 end end
check(abyss == 1, "member's own night merged with the officer's (got " .. abyss .. ")")

print("-- team deletion")
A.PGM:DeleteTeam(t.id)
run(5)
check(teamNamed(C, "Team Valor") == nil, "member's team deleted")
check(teamNamed(D, "Team Valor") == nil, "late joiner's team deleted")

print("-- play-time activity")
-- Everyone's roster: four people in game, one on the mobile app.
local onlineSet = { [gid(10)] = true, [gid(11)] = true, [gid(21)] = true, [gid(22)] = true }
local function rosterTick()
    for _, cl in pairs(clients) do
        for guid, rec in pairs(cl.g.members) do
            rec.online = onlineSet[guid] or guid == gid(23)
            rec.mobile = guid == gid(23)
        end
        cl.g.lastComplete = BASE + math.floor(T)
        cl.PGM:Fire("ROSTER")
    end
end
local sentBefore = 0
for _, cl in pairs(clients) do sentBefore = sentBefore + (cl.sent or 0) end
local wBefore = (KINDS and KINDS.W) or 0
for i = 1, 3 * 60 do rosterTick() run(60, 1) end   -- three hours
local sentDuring = 0
for _, cl in pairs(clients) do sentDuring = sentDuring + (cl.sent or 0) end
print("  messages sent by all copies over 3 hours:", sentDuring - sentBefore)
local oA = A.PGM:ComputeActivity(7, false)
check(oA.observed >= 3, "officer observed 3+ hours (got " .. oA.observed .. ")")
check(oA.peak == 4, "peak online is 4, mobile not counted (got " .. oA.peak .. ")")
local natty
for _, p in ipairs(oA.people) do if p.guid == gid(10) then natty = p end end
check(natty and natty.hours >= 3, "Nattypandy has 3+ hours played")
local wSent = ((KINDS and KINDS.W) or 0) - wBefore
print("  of which activity hours:", wSent)
check(wSent <= 6, "each finished hour shared about once (got " .. wSent .. " for 3 hours)")

-- A copy that logs in now catches up on the hours it missed.
local E = newClient(gid(25), "Tiferis")
for i = 1, 3 do rosterTick() run(60, 1) end
local oE = E.PGM:ComputeActivity(7, false)
check(oE.observed >= 3, "late copy caught up on missed hours (got " .. oE.observed .. ")")
local mainsView = A.PGM:ComputeActivity(7, true)
local alt
for _, p in ipairs(mainsView.people) do if p.guid == gid(15) then alt = p end end
check(alt == nil, "mains-only view doesn't list the alt separately")

print("-- players linking their own characters")
-- Codiex's account also has Codiexalt. Codiex is the main (same rank and
-- level, so the name decides).
local function shareAccount(c, guids)
    local key = c.env.PandyGuildDB.chars[c.guid].guild
    for _, g2 in ipairs(guids) do
        local r = c.g.members[g2]
        c.env.PandyGuildDB.chars[g2] = c.env.PandyGuildDB.chars[g2] or { name = r.short, class = r.class, guild = key, t = 0 }
    end
end
shareAccount(C, { gid(30) })
C.PGM:SyncMyMain()
run(5)
local CA = newClient(gid(30), "Codiexalt")
shareAccount(CA, { gid(13) })
run(40)
check(A.PGM:KnownMain(gid(30)) == gid(13), "officer sees Codiexalt as Codiex's alt")
check(A.PGM:AltSource(gid(30)) == "player", "...marked as set by the player")
check(D.PGM:KnownMain(gid(30)) == gid(13), "another member sees it too")

-- A troll claims Anvar as their alt, and their own character as an alt of
-- Funkyshade (who never ran the addon, so never claimed to be a main).
local TR = newClient(gid(40), "Trollboi")
run(20)
TR.PGM.SyncSend(false, "1B", gid(14), BASE + math.floor(T), gid(40))
TR.PGM.SyncSend(false, "1B", gid(40), BASE + math.floor(T), gid(22))
run(10)
check(A.PGM:KnownMain(gid(14)) == nil, "a claim about someone else's character is ignored")
check(A.PGM:KnownMain(gid(40)) == nil, "a claim onto a main that never claimed itself doesn't count")
check(A.PGM:MainOf(gid(13)) == gid(13), "Codiex is still a main")
-- The known weak spot: attaching your own character to a main that did
-- claim itself. It can only ever move the troll's character.
TR.PGM.SyncSend(false, "1B", gid(40), BASE + math.floor(T) + 1, gid(10))
run(10)
check(A.PGM:KnownMain(gid(40)) == gid(10), "a troll can attach only their own character")
check(A.PGM:KnownMain(gid(15)) == gid(10) and A.PGM:MainOf(gid(10)) == gid(10), "...and Nattypandy's group is otherwise untouched")
A.PGM:UnlinkAlt(gid(40))
run(10)
check(D.PGM:KnownMain(gid(40)) == nil, "an officer's Not an alt undoes it")

-- Someone logging in fresh gets the claims in their catch-up.
local LJ = newClient(gid(26), "Yinsane")
run(90)
check(LJ.PGM:KnownMain(gid(30)) == gid(13), "a late joiner learns the link in catch-up")

-- An officer's "Not an alt" beats the player's claim, for everyone.
A.PGM:UnlinkAlt(gid(30))
run(10)
check(A.PGM:KnownMain(gid(30)) == nil, "officer's Not an alt wins locally")
check(D.PGM:KnownMain(gid(30)) == nil, "...and for everyone else")

print("-- editing a team's details syncs")
local nt = A.PGM:CreateTeam()   -- default name, like "+ New raid team"
run(5)
check(C.PGM:TeamById(nt.id) ~= nil, "a new team reaches a member")
A.PGM:UpdateTeam(nt.id, { name = "Team Honor", schedule = "Tue 8pm", tags = "Honor, HO", autoSync = true })
run(10)
local ct = C.PGM:TeamById(nt.id)
check(ct and ct.name == "Team Honor", "a rename reaches a member (got " .. tostring(ct and ct.name) .. ")")
check(ct and ct.schedule == "Tue 8pm" and ct.tags == "Honor, HO", "schedule and tags reach a member")
check(ct and ct.autoSync == true, "Keep in sync reaches a member")
check(C.PGM:UpdateTeam(nt.id, { name = "Hax" }) == false, "a member can't rename a team")
check(A.PGM:TeamById(nt.id).name == "Team Honor", "...and the officer's copy is unchanged")

print("-- a change made just after one you have still arrives")
clients["Codiex"] = nil          -- Codiex steps away
A.PGM:UpdateTeam(nt.id, { name = "Team Honour" })
run(5)
clients["Codiex"] = C            -- and comes back, a few seconds behind
C.PGM.SyncNow()
run(60)
check(C.PGM:TeamById(nt.id).name == "Team Honour", "a small gap is caught up")
local before = C.sent or 0
run(1800)
check((C.sent or 0) - before < 10, "catch-up doesn't repeat (sent " .. ((C.sent or 0) - before) .. " in 30 min)")

print("-- unsent records survive a reload")
A.env.IsInInstance = function() return true, "raid" end
A.PGM:UpdateTeam(nt.id, { name = "Team Mercy" })
run(5)
A.fire("PLAYER_LOGOUT")
local pend = A.g.sync.pending
local hasT = false
for _, m in ipairs(pend or {}) do if m:sub(1, 2) == "1T" then hasT = true end end
check(hasT, "the rename is kept for next session")
local A2 = newClient(gid(10), "Nattypandy")   -- logs back in, out of the instance
A2.g.sync = A2.g.sync or {}
A2.g.sync.pending = pend
run(60)
check(C.PGM:TeamById(nt.id).name == "Team Mercy", "...and sent after logging back in")
A = A2

print("-- teams renamed before 0.7.1 get their names out")
-- The bug: the officer renamed a team, but only their own copy knew.
local ot = A.PGM:CreateTeam()
run(5)
A.PGM:TeamById(ot.id).name = "Team Zenith"          -- the old, unshared rename
local ph = A.PGM:CreateTeam()                        -- and one this copy never named
run(5)
check(C.PGM:TeamById(ot.id).name ~= "Team Zenith", "(setup: member has the placeholder)")
local A3 = newClient(gid(10), "Nattypandy")          -- the officer updates and logs in
A3.g.teams = A.g.teams
A3.g.sync = A3.g.sync or {}
run(60)
check(C.PGM:TeamById(ot.id).name == "Team Zenith", "a real name is re-shared once")
check(C.PGM:TeamById(ph.id).name == A.PGM:TeamById(ph.id).name, "a placeholder name isn't pushed over anyone")
A = A3

print("-- names sort with their plain letters")
local names = { "Zzivejr", "Ÿøu", "Ühtréd", "Ûzi", "Ôdin", "Ðonsÿ", "Ånonymous", "Ènso", "Ëdgard", "Zuluwest", "Codiex", "Anvar" }
table.sort(names, A.PGM.NameLess)
local got = table.concat(names, ", ")
print("  " .. got)
check(got == "Ånonymous, Anvar, Codiex, Ðonsÿ, Ëdgard, Ènso, Ôdin, Ühtréd, Ûzi, Ÿøu, Zuluwest, Zzivejr", "accented names sort among plain ones")
check(A.PGM.NameLess("Odin", "Ôdin") ~= A.PGM.NameLess("Ôdin", "Odin"), "an accent-only difference still has a fixed order")

print("-- bulk actions")
local P, g = A.PGM, A.g
local now = BASE + math.floor(T)
local function away(guid, days) local r = g.members[guid] r.online = false r.lastOnline = now - days * 86400 end
away(gid(30), 100)   -- Codiexalt: member, gone a long time
away(gid(40), 100)   -- Trollboi: same
away(gid(15), 100)   -- Demonpandy: Nattypandy's alt, and Nattypandy is online
away(gid(14), 100)   -- Anvar: on a raid team
P:Teams()[1].members[gid(14)] = { role = "DPS", status = "core" }
P:RebuildAlts()
away(gid(11), 100)   -- Magicpayne: an officer, same rank as me
away(gid(1), 400)    -- the guild master
local kr = P:BulkNewRule("kick")   -- away 60+, skip teams, keep if an alt or main is on
local m = P:BulkMatches("kick")
local names = {}
for _, it in ipairs(m) do names[#names + 1] = it.rec.short end
print("  kick picks: " .. table.concat(names, ", "))
check(table.concat(names, ",") == "Codiexalt,Trollboi", "kick rule picks only the right people")

-- A big run: twenty more long-gone members.
for i = 1, 20 do
    local guid = gid(100 + i)
    g.members[guid] = { guid = guid, name = ("Inactivechar%02d-%s"):format(i, REALM), short = ("Inactivechar%02d"):format(i),
        realm = REALM, rank = "Member", rankIndex = 5, level = 90, class = "MAGE", note = "", onote = "",
        online = false, lastOnline = now - 200 * 86400 }
end
P:BulkSetIgnored("kick", gid(40), true)
check(P:BulkStart("kick") == 21, "an ignored member is left out of the run (got " .. P:BulkProgress().total .. ")")
local text, items = P:BulkBatch()
print(("  first batch: %d people, %d characters"):format(#items, #text))
check(#text <= 255 and #items >= 6, "a batch fills one macro and does several people")
check(text:find("^/gremove Codiexalt%-MalGanis\n"), "commands use the full name")
P:BulkSent(items)
for _, it in ipairs(items) do g.members[it.guid] = nil end
P:Fire("ROSTER")
check(P:BulkProgress().done == #items, "people gone from the roster count as done")
check(P:BulkKicked(gid(30)), "...and History will say they were removed")
local text2, items2 = P:BulkBatch()
check(items2 and items2[1].guid ~= items[1].guid, "the next batch moves on")
P:BulkSent(items2)
run(25)   -- nobody leaves: tried again
check(P:BulkState(items2[1].guid) == nil, "a batch that didn't take is queued again")
local _, again = P:BulkBatch()
P:BulkSent(again)
run(25)
check(P:BulkState(items2[1].guid) == "failed", "...and fails after a second try")
P:BulkStop()

print("-- bulk promote")
local yin = g.members[gid(26)]
yin.rankIndex, yin.rank, yin.online = 6, "Trial", true
local pr = P:BulkNewRule("promote")
pr.ranks, pr.toRank, pr.skipTeams = { [6] = true }, 4, nil
check(P:BulkRuleCount("promote", pr) == 1, "promote rule picks the trial")
P:BulkStart("promote")
local pt, pi = P:BulkBatch()
check(pt == "/gpromote Yinsane-MalGanis\n/gpromote Yinsane-MalGanis", "two ranks up is two commands")
P:BulkSent(pi)
yin.rankIndex = 5
P:Fire("ROSTER")
check(P:BulkState(gid(26)) == nil, "partway there: queued for the rest")
local pt2 = P:BulkBatch()
check(pt2 == "/gpromote Yinsane-MalGanis", "...which is one more command")
yin.rankIndex = 4
P:BulkSent(select(2, P:BulkBatch()))
P:Fire("ROSTER")
check(P:BulkState(gid(26)) == "done", "reaching the target rank is done")
P:BulkStop()
pr.toRank = 1
check(P:BulkRuleCount("promote", pr) == 0, "nobody can be moved to your own rank")

print("-- bulk actions are officers only")
check(C.PGM:BulkNewRule("kick") == nil, "a member can't make a bulk rule")
check(C.PGM:BulkStart("kick") == 0, "...or start a run")
check(C.PGM:BulkAllowed().officer == false, "...and the page knows it")

print("-- who made each change")
local P, g = A.PGM, A.g
A.fire("CHAT_MSG_SYSTEM", "Nattypandy has demoted Codiex to Trial.")
local e1 = P:AddLog(g, "demote", g.members[gid(13)], { from = "Member", to = "Trial" })
check(e1.by == "Nattypandy", "a system message credits a demotion")
check(P.LogText(e1):find("demoted by Nattypandy: Member > Trial", 1, true), "...and History says so: " .. P.LogText(e1))
A.fire("CHAT_MSG_SYSTEM", "Trollboi-MalGanis has been kicked out of the guild by Magicpayne-MalGanis.")
local e2 = P:AddLog(g, "leave", { guid = gid(40), short = "Trollboi", class = "ROGUE" })
check(e2.removed and e2.by == "Magicpayne", "a kick message credits a removal, realm dropped")
A.fire("CHAT_MSG_SYSTEM", "Someoneelse has left the guild.")
local e2b = P:AddLog(g, "leave", { guid = gid(41), short = "Someoneelse", class = "ROGUE" })
check(not e2b.removed and P.LogText(e2b):find("left the guild", 1, true), "a leave message means they left")
-- No message for this one: the guild event log (newest last) credits it.
GUILD_EVENTS = {
    { "promote", "Magicpayne-MalGanis", "Tiferis-MalGanis", "Trial", 0, 0, 2, 0 },   -- an older one
    { "invite", "Deathsquaad", "Freshface", nil, 0, 0, 0, 1 },
    { "promote", "Dazibanu-MalGanis", "Tiferis-MalGanis", "Raider", 0, 0, 0, 0 },
}
local e3 = P:AddLog(g, "promote", g.members[gid(25)], { from = "Trial", to = "Raider" })
local e4 = P:AddLog(g, "join", { guid = gid(42), short = "Freshface", class = "MONK" })
check(not e3.by and not e4.by, "(no messages for these)")
A.fire("GUILD_EVENT_LOG_UPDATE")
check(e3.by == "Dazibanu", "the event log credits the newest matching promotion")
check(P.LogText(e4):find("(invited by Deathsquaad)", 1, true), "...and who invited a new member")
-- A Guild Finder join has only a "join" event: settled, nobody credited.
GUILD_EVENTS[#GUILD_EVENTS + 1] = { "join", "Finderjoin", nil, nil, 0, 0, 0, 0 }
GUILD_EVENTS[#GUILD_EVENTS + 1] = { "join", "Freshface", nil, nil, 0, 0, 0, 0 }
local e5 = P:AddLog(g, "join", { guid = gid(43), short = "Finderjoin", class = "MAGE" })
A.fire("GUILD_EVENT_LOG_UPDATE")
check(e5.credited and not e5.by, "a Guild Finder join is settled without an inviter")
check(e4.by == "Deathsquaad", "...and an invited join keeps its inviter")

print("-- leaving lists the characters still here")
local snap = {}
for guid, rec in pairs(g.members) do
    if guid ~= gid(15) then
        local c = {}
        for k, v in pairs(rec) do c[k] = v end
        snap[guid] = c
    end
end
P:ApplyRoster(snap, true)
local last = g.log[#g.log]
check(last.kind == "leave" and last.name == "Demonpandy", "Demonpandy's leave is logged")
check(P.LogText(last):find("left the guild. Still here: Nattypandy", 1, true), "her main still here is listed: " .. P.LogText(last))

print("-- raid nights: no duplicates, no wrong merges, deletes stick")
do
    local now = BASE + math.floor(T)
    local function night(id, startOff, diff, present)
        local n = { id = id, start = now + startOff, stop = now + startOff + 7200, instance = 4242, diffID = diff,
                    name = "Abyss", present = {}, bosses = {} }
        for _, gu in ipairs(present) do n.present[gu] = true end
        return n
    end
    local function abyss(cl)
        local list = {}
        for _, x in ipairs(cl.g.raids and cl.g.raids.sessions or {}) do
            if x.instance == 4242 then list[#list + 1] = x end
        end
        return list
    end
    -- B saves and shares first; A's own record of the night is still open.
    A.g.raids = A.g.raids or { sessions = {} }
    A.g.raids.open = night("open-A", -7300, 16, { gid(10), gid(21) })
    A.g.raids.open.last = now - 100
    local bn = night("n-B", -7000, 16, { gid(11), gid(22) })
    table.insert(B.g.raids.sessions, bn)
    B.PGM:SyncRaid(bn)
    run(10)
    A.PGM:CloseRaid(true)
    run(15)
    check(#abyss(A) == 1, "an open record merges into the night that arrived (A has " .. #abyss(A) .. ")")
    check(#abyss(C) == 1, "...and nobody else gets a second copy (C has " .. #abyss(C) .. ")")
    local p = 0 for _ in pairs((abyss(C)[1] or { present = {} }).present) do p = p + 1 end
    check(p == 4, "...with everyone from both records (got " .. p .. ")")

    -- Heroic, starting while the Normal one was on: a different night.
    local hn = night("n-B-heroic", -6500, 15, { gid(11) })
    table.insert(B.g.raids.sessions, hn)
    B.PGM:SyncRaid(hn)
    run(10)
    check(#abyss(C) == 2, "a Heroic night doesn't merge with the Normal one (C has " .. #abyss(C) .. ")")

    -- A deletes the Normal night: gone everywhere, and stays gone.
    local an
    for _, x in ipairs(abyss(A)) do if x.diffID == 16 then an = x end end
    A.PGM:DeleteRaid(an)
    run(15)
    local function normals(cl) local n = 0 for _, x in ipairs(abyss(cl)) do if x.diffID == 16 then n = n + 1 end end return n end
    check(normals(A) == 0 and normals(B) == 0 and normals(C) == 0, "a deleted night is gone for everyone")
    B.PGM.SyncSend(false, "1S", "n-B", now - 50, now - 7000, now + 200, 4242, 16, "", 0, "Abyss", "")
    run(5)
    check(normals(C) == 0, "a stale copy re-sent under another id doesn't bring it back")
    check(#abyss(C) == 1, "...and the Heroic night is untouched")
end

print("-- sync hardening")
do
    -- "gm" only as its own word (checked without the GM's cut-off).
    local cut = A.g.sync.officerRank
    A.g.sync.officerRank = nil
    check(not A.PGM:IsOfficerRec({ rankIndex = 5, rank = "Sigma" }), "a rank called Sigma isn't an officer rank")
    check(A.PGM:IsOfficerRec({ rankIndex = 3, rank = "GM Alt" }), "...but GM Alt is")
    A.g.sync.officerRank = cut

    -- A member asking for full catch-ups nobody offered gets nothing.
    local before = B.sent or 0
    for _ = 1, 3 do C.PGM.SyncSend(false, "1R", "Magicpayne-MalGanis", 0) end
    C.PGM.SyncSend(false, "1R", "", 0)
    run(40)
    check((B.sent or 0) - before < 5, "unrequested catch-up requests are ignored (officer sent " .. ((B.sent or 0) - before) .. ")")

    -- Two players logging in together both get caught up.
    local X = newClient(gid(23), "Selwyne")
    local Y = newClient(gid(22), "Funkyshade")
    check(not X.PGM:SyncSettled(), "a fresh login isn't settled before its catch-up")
    run(150)
    local function names(cl) local t = {} for _, x in ipairs(cl.g.teams or {}) do t[#t + 1] = x.name end return table.concat(t, "/") end
    check(names(X) == names(A) and names(Y) == names(A), "two logins at once are both caught up (" .. names(X) .. ")")
    check(X.PGM:SyncSettled(), "...and settled after it")

    -- An officer who edits right after logging in is still caught up.
    local G = newClient(gid(1), "Deathsquaad")
    G.PGM:CreateTeam("Scratch")
    run(150)
    check(teamNamed(G, "Team Mercy") ~= nil and teamNamed(G, "Team Zenith") ~= nil, "an edit right after login doesn't skip the catch-up")

    -- Wild activity numbers are kept within what's possible.
    local hour = math.floor((BASE + T) / 3600) - 3
    C.PGM.SyncSend(false, "1W", hour, 4000, 99999, 99999, "")
    C.PGM.SyncSend(false, "1W", hour + 10, 5, 50, 12, "")
    run(5)
    local ha = A.g.activity and A.g.activity.hours or {}
    check(not (ha[hour] and (ha[hour].p or 0) >= 4000), "a peak bigger than the guild is ignored")
    check(not ha[hour + 10], "an hour in the future is ignored")
end

print("-- professions by player")
do
    local fn = load(FILES["Stats.lua"], "@Stats.lua", "t", A.env)
    fn("PandyGuildManagement", A.NS)
    local P, g = A.PGM, A.g
    local now = BASE + math.floor(T)
    local function member(n, name, note, online, daysAgo, profs)
        local guid = gid(n)
        local prof = {}
        for _, id in ipairs(profs) do prof[#prof + 1] = { id = id } end
        g.members[guid] = { guid = guid, name = name .. "-" .. REALM, short = name, realm = REALM, rank = "Member",
            rankIndex = 5, level = 90, class = "MAGE", note = note, onote = "", online = online,
            lastOnline = now - daysAgo * 86400, prof = prof }
        return guid
    end
    -- One player: a main (offline 2 days) and an alt (online), both enchanters;
    -- the main is also the only scribe. Another player, gone 20 days.
    local main = member(200, "Crafterone", "", false, 2, { 333, 444 })
    local alt = member(201, "Crafteralt", "alt of Crafterone", true, 0, { 333 })
    local lone = member(202, "Loneone", "", false, 20, { 333 })
    P:RebuildAlts()
    local st = P:ProfessionStats()[333]
    check(st and st.chars == 3 and st.players == 2, "enchanting: 3 characters, 2 players")
    check(st and st.activePlayers == 1 and st.onlinePlayers == 1 and st.onlineChars == 1, "...1 active, 1 online")
    check(st and st.thin, "...which is thin")
    local list = P:ProfessionCrafters(333, true)
    check(#list == 2 and list[1].guid == alt, "by player: the online alt stands for its player")
    check(list[1] and #list[1].others == 1 and list[1].others[1].short == "Crafterone", "...with the main as another crafter")
    check(#P:ProfessionCrafters(333, false) == 3, "by character: everyone listed")
    local scribe = P:ProfessionCrafters(444, true)[1]
    check(scribe and scribe.guid == main and scribe.onlineAs and scribe.onlineAs.short == "Crafteralt",
        "an offline crafter whose player is online shows who to ask")
    for _, guid in ipairs({ main, alt, lone }) do g.members[guid] = nil end
    P:RebuildAlts()
end

print("-- telling you when your copy is out of date")
do
    local P = A.PGM
    local saved = P.VERSION
    P.VERSION = "0.8.2"
    A.chat = ""
    C.PGM.SyncSend(false, "1V", "0.8.1")
    run(3)
    check(not A.chat:find("is out", 1, true) and not P:UpdateAvailable(), "an older guildie's copy says nothing")
    C.PGM.SyncSend(false, "1V", "0.9.0")
    run(3)
    check(A.chat:find("v0.9.0 is out (you have v0.8.2)", 1, true) ~= nil, "a newer copy is mentioned in chat")
    check(P:UpdateAvailable() == "0.9.0", "...and kept for the footer")
    A.chat = ""
    C.PGM.SyncSend(false, "1V", "0.9.1")
    run(3)
    check(not A.chat:find("is out", 1, true), "...but only once a session")
    check(P:UpdateAvailable() == "0.9.1", "...while the footer shows the newest")
    C.PGM.SyncSend(false, "1V", "dev")
    run(3)
    check(P:UpdateAvailable() == "0.9.1", "a dev build is never compared")
    P.VERSION = saved
end

print("-- who can craft a recipe")
do
    local P = A.PGM
    -- Two Midnight Alchemy recipes and an older one, as a profession window lists them.
    TRADE = {
        ids = { 1001, 1002, 900 },
        info = { [1001] = { name = "Light's Potential" }, [1002] = { name = "Silvermoon Health Potion" }, [900] = { name = "Old Elixir" } },
        prof = { [1001] = { professionID = 2906, parentProfessionID = 171 }, [1002] = { professionID = 2906, parentProfessionID = 171 },
                 [900] = { professionID = 2871, parentProfessionID = 171 } },
        item = { [1001] = 5001, [1002] = 5002, [900] = 4900 },
    }
    check(P:LearnOpenRecipes() == 2 and P:RecipeCount() == 2, "an open profession window teaches its newest expansion's recipes")
    local byName = P:FindRecipes("light")
    check(byName[1] and byName[1].recipe == 1001 and byName[1].line == 171, "recipes are found by name")
    local byItem = P:FindRecipes("|cffffffff|Hitem:5002::::::::90:::::|h[Silvermoon Health Potion]|h|r")
    check(#byItem == 1 and byItem[1].recipe == 1002, "...and by item link")
    check(#P:FindRecipes("old elixir") == 0, "older expansions' recipes aren't kept")

    -- Asking the guild who knows one.
    LAST_RECIPE_QUERY, RECIPE_ANSWER = nil, nil
    local got
    P:RecipeCrafters(171, 1001, function(list) got = list end)
    check(LAST_RECIPE_QUERY and LAST_RECIPE_QUERY[1] == 171 and LAST_RECIPE_QUERY[2] == 1001, "the game is asked about the recipe")
    RECIPE_ANSWER = { line = 171, recipe = 1001, members = { "Magicpayne-MalGanis", "Nattypandy-MalGanis", "Stranger-Elsewhere" } }
    A.fire("GUILD_RECIPE_KNOWN_BY_MEMBERS")
    check(got and #got == 2, "the answer lists the guildies who know it (" .. (got and #got or "none") .. ")")
    check(P:KnownCrafters(171, 1001) == got, "...and is kept")
    LAST_RECIPE_QUERY = nil
    local again
    P:RecipeCrafters(171, 1001, function(list) again = list end)
    check(again == got and LAST_RECIPE_QUERY == nil, "asking again soon uses the kept answer")
    -- No event: the answer is read after a moment anyway.
    RECIPE_ANSWER = { line = 171, recipe = 1002, members = { "Magicpayne-MalGanis" } }
    local late
    P:RecipeCrafters(171, 1002, function(list) late = list end)
    run(4)
    check(late and #late == 1, "an answer without the event is still read")
    TRADE, RECIPE_ANSWER = nil, nil
end

print("-- pasting a list into a team")
do
    local P = A.PGM
    local pt = P:CreateTeam("Paste Test")
    P:AddToTeam(pt.id, gid(22))   -- Funkyshade, on it as DPS
    local function addOf(plan, guid)
        for _, a in ipairs(plan.add) do if a.guid == guid then return a end end
    end
    local sheet = "Name\tRole\tStatus\n"
        .. "Anvar\tRanged DPS\tCore\n"
        .. "Funkyshade-MalGanis\tHealer\tCore\n"
        .. "Tiferis\tHoly\tTrial\n"
        .. "Yinsane\t\t\n"
        .. "Notinguild\tTank\tBench\n"
        .. "anvar\tTank\tBench\n"
    local plan = P:PlanTeamPaste(pt.id, sheet)
    check(#plan.add == 3, "spreadsheet paste adds 3 (got " .. #plan.add .. ")")
    check(#plan.change == 1 and plan.change[1].role == "HEALER" and plan.change[1].status == nil,
        "Funkyshade's role changes to Healer, status untouched")
    check(#plan.unknown == 1 and plan.unknown[1] == "Notinguild", "the stranger is listed, the header isn't")
    local an, ti, yi = addOf(plan, gid(14)), addOf(plan, gid(25)), addOf(plan, gid(26))
    check(an and an.role == "DPS" and an.status == "core", "Anvar as DPS Core (first line wins over the duplicate)")
    check(ti and ti.role == "HEALER" and ti.status == "trial", "a spec word (Holy) reads as Healer")
    check(yi and yi.status == "trial", "no status given: Yinsane's Trial rank counts")
    check(pt.members[gid(14)] == nil, "planning changes nothing")
    local added, changed = P:ApplyTeamPaste(pt.id, plan)
    check(added == 3 and changed == 1, "applied: 3 added, 1 updated")
    check(pt.members[gid(22)].role == "HEALER", "Funkyshade is a healer now")

    local csv = P:PlanTeamPaste(pt.id, 'Triclops,Tank,Bench\n"Selwyne", Resto, Core')
    local tr, se = addOf(csv, gid(24)), addOf(csv, gid(23))
    check(#csv.add == 2 and tr and tr.role == "TANK" and tr.status == "bench", "CSV: Triclops Tank Bench")
    check(se and se.role == "HEALER" and se.status == "core", "CSV with quotes: Selwyne Resto Core")
    local json = P:PlanTeamPaste(pt.id, '{"characters":[{"name":"Atlasqt","realm":"MalGanis","role":"Tank","rank":"Trial"}]}')
    local at = addOf(json, gid(21))
    check(#json.add == 1 and at and at.role == "TANK" and at.status == "trial", "JSON: Atlasqt Tank Trial")
    local plain = P:PlanTeamPaste(pt.id, "Codiex\nTrollboi\n")
    check(#plain.add == 2, "one name per line works")
    local realm = P:PlanTeamPaste(pt.id, "Codiex-Stormrage")
    check(#realm.add == 0 and #realm.unknown == 1, "a name on another realm isn't a guild member")
    local again = P:PlanTeamPaste(pt.id, sheet)
    check(#again.add == 0 and #again.change == 0 and again.same == 4, "pasting it again changes nothing")

    local cTeam = teamNamed(C, "Paste Test")
    run(30)
    cTeam = teamNamed(C, "Paste Test")
    check(cTeam and cTeam.members[gid(25)] and cTeam.members[gid(25)].status == "trial", "the guild gets the pasted spots")
    check(cTeam and cTeam.members[gid(22)] and cTeam.members[gid(22)].role == "HEALER", "...and the role change")
    local cAdded = C.PGM:ApplyTeamPaste(cTeam.id, C.PGM:PlanTeamPaste(cTeam.id, "Codiex"))
    check(cAdded == 0, "a member can't import a list")
    P:DeleteTeam(pt.id)
    run(10)
end

print("-- game version: " .. (FOREVER and "WoW Forever" or "retail"))
for _, f in ipairs({ "Stats.lua", "Progress.lua" }) do
    local fn, err = load(FILES[f], "@" .. f, "t", A.env)
    if not fn then error(err) end
    fn("PandyGuildManagement", A.NS)
end
local P = A.PGM
local cap = FOREVER and 60 or 90
check(P.IS_FOREVER == (FOREVER and true or false), "detects the game version")
check(P.MaxLevel() == cap, "level cap is " .. cap .. " (got " .. tostring(P.MaxLevel()) .. ")")
local ov = P:ComputeOverview("all", false)
local labels = {}
for _, l in ipairs(ov.levels) do labels[#labels + 1] = l.label end
print("  level bands: " .. table.concat(labels, ", "))
local wantBands = FOREVER and "60 (max), 50-59, 40-49, 20-39, 10-19, 1-9" or "90 (max), 80-89, 70-79, 50-69, 10-49, 1-9"
check(table.concat(labels, ", ") == wantBands, "level bands fit the cap")
local scored = { score = 2400, short = "Someone" }
if FOREVER then
    check(P:MPlusScore(scored) == nil, "no M+ score on Forever")
    check(P:RaidProgress(scored) == nil, "no raid progress on Forever")
else
    check(P:MPlusScore(scored) == 2400, "M+ score still shows on retail")
end

print(("\n%d passed, %d failed"):format(passes, failures))
