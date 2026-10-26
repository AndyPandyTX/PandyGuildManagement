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
    env.UnitName = function() return name end
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
-- Not before B's catch-up is in (it could undo a removal B hasn't heard of).
check(B.PGM:ImportTeamFromNotes(tb.id) == nil, "importing from notes waits for the catch-up")
B.PGM.Sync.settled = true
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
    check(#(P:KnownCrafters(171, 1001) or {}) == 2, "...and is kept")
    LAST_RECIPE_QUERY = nil
    local again
    P:RecipeCrafters(171, 1001, function(list) again = list end)
    check(again and #again == 2 and LAST_RECIPE_QUERY == nil, "asking again soon uses the kept answer")
    -- Who's online is read fresh, not kept with the answer.
    local g = A.g
    local wasOnline = g.members[gid(11)].online
    g.members[gid(11)] = setmetatable({ online = not wasOnline }, { __index = g.members[gid(11)] })
    local fresh
    for _, it in ipairs(P:KnownCrafters(171, 1001)) do if it.guid == gid(11) then fresh = it end end
    check(fresh and fresh.rec.online == not wasOnline, "the kept answer shows who's online now")
    g.members[gid(11)] = getmetatable(g.members[gid(11)]).__index
    -- The server never answers: the question is dropped, so asking again asks again.
    RECIPE_ANSWER = { line = 171, recipe = 1001, members = {} }   -- an old answer, for another recipe
    P:RecipeCrafters(171, 1003, function() end)
    check(P:CraftersAsking(171, 1003), "while waiting, it's asking")
    run(4)
    check(not P:CraftersAsking(171, 1003) and P:KnownCrafters(171, 1003) == nil, "no answer: it stops waiting")
    LAST_RECIPE_QUERY = nil
    P:RecipeCrafters(171, 1003, function() end)
    check(LAST_RECIPE_QUERY and LAST_RECIPE_QUERY[2] == 1003, "...and picking it again asks the server again")
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

print("-- two teams in the same raid at the same time")
do
    local now = BASE + math.floor(T)
    local function night(id, startOff, present, leaders)
        local n = { id = id, start = now + startOff, stop = now + startOff + 7200, instance = 5151, diffID = 15,
                    name = "Voidspire", present = {}, bosses = {} }
        for _, gu in ipairs(present) do n.present[gu] = true end
        if leaders then
            n.leaders = {}
            for _, gu in ipairs(leaders) do n.leaders[gu] = true end
        end
        return n
    end
    local function voidspire(cl)
        local list = {}
        for _, x in ipairs(cl.g.raids and cl.g.raids.sessions or {}) do
            if x.instance == 5151 then list[#list + 1] = x end
        end
        return list
    end
    local function share(cl, n)
        table.insert(cl.g.raids.sessions, n)
        cl.PGM:SyncRaid(n)
    end
    -- Mercy (led by Nattypandy) and Honor (led by Magicpayne), same raid,
    -- same difficulty, same start.
    share(A, night("mercy-A", -7200, { gid(10), gid(21), gid(22) }, { gid(10) }))
    share(B, night("honor-B", -7100, { gid(11), gid(23), gid(24) }, { gid(11) }))
    run(15)
    check(#voidspire(C) == 2, "two raids led by different people stay two nights (C has " .. #voidspire(C) .. ")")
    check(#voidspire(A) == 2 and #voidspire(B) == 2, "...for the officers too")
    -- RL recorded Mercy's raid as well: it joins Mercy's night.
    share(RL, night("mercy-RL", -7000, { gid(12), gid(25) }, { gid(10) }))
    run(15)
    check(#voidspire(C) == 2, "a second record of Mercy's raid merges (C has " .. #voidspire(C) .. ")")
    local mercy
    for _, x in ipairs(voidspire(C)) do if x.leaders and x.leaders[gid(10)] then mercy = x end end
    local p = 0 for _ in pairs(mercy and mercy.present or {}) do p = p + 1 end
    check(p == 5, "...into Mercy's night, not Honor's (got " .. p .. " there)")
    -- Deleting Honor's night leaves Mercy's alone.
    local honorA
    for _, x in ipairs(voidspire(A)) do if x.leaders and x.leaders[gid(11)] then honorA = x end end
    A.PGM:DeleteRaid(honorA)
    run(15)
    check(#voidspire(C) == 1 and voidspire(C)[1].leaders[gid(10)], "deleting one team's night keeps the other")
    check(#voidspire(B) == 1, "...for the officer who recorded it too")

    -- Records from older copies (no leaders): two full raids with nobody in
    -- common stay apart; small ones still merge as before.
    for _, cl in ipairs({ A, B, C, RL }) do
        for i = #cl.g.raids.sessions, 1, -1 do
            if cl.g.raids.sessions[i].instance == 5151 then table.remove(cl.g.raids.sessions, i) end
        end
    end
    local older = night("old-1", -3600, { gid(1), gid(10), gid(12), gid(13), gid(14) })
    local other = night("old-2", -3500, { gid(11), gid(21), gid(22), gid(23), gid(24) })
    check(not A.PGM:SameRaidNight(older, other), "older records: two full raids with nobody shared are two nights")
    local small = night("old-3", -3500, { gid(11), gid(21), gid(22) })
    check(A.PGM:SameRaidNight(older, small), "...but a small record still merges")
    local sameRaid = night("old-4", -3500, { gid(10), gid(25), gid(26), gid(30), gid(40) })
    check(A.PGM:SameRaidNight(older, sameRaid), "...and records sharing someone are one night")
end

print("-- which team a raid night belongs to")
do
    local P, g = A.PGM, A.g
    for n = 300, 325 do
        g.members[gid(n)] = { guid = gid(n), name = ("Teamer%02d-%s"):format(n, REALM), short = ("Teamer%02d"):format(n),
            realm = REALM, rank = "Raider", rankIndex = 4, level = 90, class = "WARRIOR", note = "", onote = "" }
    end
    local big = P:CreateTeam("Night Big")
    for n = 300, 311 do P:AddToTeam(big.id, gid(n)) end            -- 12 members
    P:CycleStatus(big.id, gid(311)) P:CycleStatus(big.id, gid(311)) -- one on the bench
    local other = P:CreateTeam("Night Other")
    for n = 312, 325 do P:AddToTeam(other.id, gid(n)) end          -- 14 members
    local small = P:CreateTeam("Night Small")
    for _, n in ipairs({ 1, 13, 30, 40 }) do P:AddToTeam(small.id, gid(n)) end -- 4 members
    local function guess(list)
        local s = { present = {} }
        for _, n in ipairs(list) do s.present[gid(n)] = true end
        return P:GuessTeam(s)
    end
    local function range(a, b, extra)
        local out = {}
        for n = a, b do out[#out + 1] = n end
        for _, n in ipairs(extra or {}) do out[#out + 1] = n end
        return out
    end
    check(guess(range(300, 309)) == big.id, "10 of a team's members make it their night")
    check(guess(range(300, 308)) == nil, "9 isn't enough")
    check(guess(range(302, 311)) == big.id, "a benched member who shows up counts")
    check(guess(range(300, 310, range(312, 323))) == other.id, "with two teams there, the one with more members wins")
    check(guess(range(300, 310, range(312, 322))) == big.id, "...and a tie goes to the team with more of its roster there")
    check(guess({ 1, 13, 30, 40 }) == small.id, "a team under 10 needs all of its members")
    check(guess({ 1, 13, 30 }) == nil, "...not just most of them")
    for _, t in ipairs({ big, other, small }) do P:DeleteTeam(t.id) end
    for n = 300, 325 do g.members[gid(n)] = nil end
    run(10)
end

print("-- loot tracking")
do
    -- Items: 268256 a helm, 268300 a trinket, 268400 a tier token, 999 a reagent.
    local ITEMS = {
        [268256] = { 4, 4, "INVTYPE_HEAD" }, [268300] = { 4, 0, "INVTYPE_TRINKET" }, [268400] = { 15, 0, "" },
        [270000] = { 2, 7, "INVTYPE_WEAPON" }, [270001] = { 4, 1, "INVTYPE_FINGER" }, [271875] = { 4, 2, "INVTYPE_CHEST" },
        [251115] = { 4, 1, "INVTYPE_FINGER" }, [272000] = { 4, 3, "INVTYPE_LEGS" }, [999] = { 7, 0, "" },
        [268650] = { 15, 0, "" },   -- "junk" that isn't a tier token (an upgrade shard)
    }
    local function link(id, q) return ("|cnIQ%d:|Hitem:%d::::::::90:102::::::::|h[Item %d]|h|r"):format(q or 4, id, id) end
    local function setup(cl)
        local e = cl.env
        e.C_Item = { GetItemInfoInstant = function(id)
            local it = ITEMS[tonumber(id)]
            if not it then return nil end
            return id, "", "", it[3], 0, it[1], it[2]
        end }
        e.GetClassInfo = function(n) local f = { [5] = "PRIEST", [11] = "DRUID" } return "x", f[n], n end
        -- Tooltips: a tier token says which classes may use it.
        e.ITEM_CLASSES_ALLOWED = "Classes: %s"
        e.C_TooltipInfo = { GetItemByID = function(id)
            if id == 268400 then return { lines = { { leftText = "Token" }, { leftText = "Classes: Druid, Priest" } } } end
            return { lines = { { leftText = "Item" }, { leftText = "Use: something" } } }
        end }
        e.LOOT_ITEM_BONUS_ROLL = "%s receives bonus loot: %s."
        e.LOOT_ITEM_BONUS_ROLL_MULTIPLE = "%s receives bonus loot: %sx%d."
        e.C_LootHistory = {
            GetSortedDropsForEncounter = function() return LOOT_DROPS end,
            GetSortedInfoForDrop = function(_, id) return LOOT_INFO and LOOT_INFO[id] end,
        }
        local fn, err = load(FILES["Loot.lua"], "@Loot.lua", "t", e)
        if not fn then error(err) end
        fn("PandyGuildManagement", cl.NS)
    end
    setup(A)
    setup(B)
    local P = A.PGM
    local function count(cl) return #cl.PGM:LootItems() end
    local function find(cl, who, id, how)
        for _, r in ipairs(cl.PGM:LootItems()) do
            if r.who == who and r.id == id and (not how or r.how == how) then return r end
        end
    end
    local function town() return "Town", "none", 0, "" end

    A.env.GetInstanceInfo = function() return "Voidspire", "raid", 15, "Heroic", 20, 0, false, 3004 end
    A.fire("ENCOUNTER_END", 3429, "Boss A", 15, 20, 1)
    LOOT_DROPS = {
        { itemHyperlink = link(268256), winner = { playerName = "Funkyshade", playerClass = "PRIEST", state = 0 } },
        { itemHyperlink = link(268300), winner = { playerName = "Selwyne-MalGanis", playerClass = "DRUID", state = 3 } },
        { itemHyperlink = link(272000) },   -- still being rolled for
        -- The summary doesn't say how Vdovdr rolled; the full list does.
        { itemHyperlink = link(271875), lootListID = 7, winner = { playerName = "Vdovdr", playerClass = "PRIEST" } },
    }
    LOOT_INFO = { [7] = { rollInfos = {
        { playerName = "Anvar", state = 0, roll = 40, isWinner = false },
        { playerName = "Vdovdr", state = 2, roll = 77, isWinner = true },
    } } }
    A.fire("LOOT_HISTORY_UPDATE_ENCOUNTER", 3429)
    check(count(A) == 3, "group loot: the three decided drops are kept (got " .. count(A) .. ")")
    local vd = find(A, "Vdovdr-MalGanis", 271875)
    check(vd and vd.how == "tmog" and vd.roll == 77, "how the winner rolled, from the full roll list, with the roll")
    local fh = find(A, "Funkyshade-MalGanis", 268256)
    check(fh and fh.how == "need" and fh.boss == "Boss A" and fh.diff == 15 and fh.kind == "raid", "a Need win, with boss and difficulty")
    check(find(A, "Selwyne-MalGanis", 268300, "greed") ~= nil, "a Greed win")
    A.fire("LOOT_HISTORY_UPDATE_DROP", 3429, 1)
    A.fire("ENCOUNTER_LOOT_RECEIVED", 3429, 268256, link(268256), 1, "Funkyshade", "PRIEST")
    check(count(A) == 3 and fh.how == "need", "the same drop reported again is one record, still a Need")
    A.fire("ENCOUNTER_LOOT_RECEIVED", 3429, 268400, link(268400), 1, "Tiferis", "PALADIN")
    check(find(A, "Tiferis-MalGanis", 268400, "personal") ~= nil, "personal loot is kept")
    A.fire("ENCOUNTER_LOOT_RECEIVED", 3429, 999, link(999, 4), 3, "Tiferis", "PALADIN")
    A.fire("ENCOUNTER_LOOT_RECEIVED", 3429, 272000, link(272000, 3), 1, "Tiferis", "PALADIN")
    check(count(A) == 4, "reagents and blue items aren't kept (got " .. count(A) .. ")")

    -- Bonus rolls: ours from the game, everyone else's from loot chat.
    A.fire("BONUS_ROLL_RESULT", "item", link(270000), 1, 102)
    local mine = find(A, "Nattypandy-MalGanis", 270000, "bonus")
    check(mine and mine.boss == "Boss A" and mine.kind == "raid", "my bonus roll, for the boss just killed")
    A.fire("CHAT_MSG_LOOT", "Anvar receives bonus loot: " .. link(270001) .. ".")
    A.fire("CHAT_MSG_LOOT", "Atlasqt-Stormrage receives bonus loot: " .. link(268256) .. "x2.")
    A.fire("CHAT_MSG_LOOT", "Anvar receives loot: " .. link(268300) .. ".")
    check(find(A, "Anvar-MalGanis", 270001, "bonus") ~= nil, "someone else's bonus roll from chat")
    check(find(A, "Atlasqt-Stormrage", 268256, "bonus") ~= nil, "...and the several-of-it line, cross-realm")
    check(count(A) == 7, "ordinary loot lines aren't bonus rolls (got " .. count(A) .. ")")

    A.env.GetInstanceInfo = town
    A.fire("ENCOUNTER_LOOT_RECEIVED", 0, 268300, link(268300), 1, "Codiex", "DEMONHUNTER")
    check(count(A) == 7, "outside a raid, drops aren't recorded")

    -- Back in the raid: junk, stacks and a winner from another realm.
    A.env.GetInstanceInfo = function() return "Voidspire", "raid", 15, "Heroic", 20, 0, false, 3004 end
    A.fire("ENCOUNTER_LOOT_RECEIVED", 3429, 268650, link(268650), 1, "Tiferis", "PALADIN")
    A.fire("ENCOUNTER_LOOT_RECEIVED", 3429, 268400, link(268400), 2, "Anvar", "HUNTER")
    check(count(A) == 7, "miscellany that isn't a tier token, and stacks, aren't kept")
    A.env.GetNumGroupMembers = function() return 2 end
    A.env.GetRaidRosterInfo = function(i) return ({ "Speedyjosh-Hyjal", "Nattypandy" })[i] end
    LOOT_DROPS = { { itemHyperlink = link(272000), lootListID = 9,
        winner = { playerName = "Speedyjosh", playerClass = "MAGE", state = 3 } } }
    A.fire("ENCOUNTER_END", 3445, "Entombed Sentinels", 15, 20, 1)
    A.fire("LOOT_HISTORY_UPDATE_ENCOUNTER", 3445)
    A.fire("LOOT_HISTORY_UPDATE_ENCOUNTER", 3445)
    check(find(A, "Speedyjosh-Hyjal", 272000, "greed") ~= nil, "a winner from another realm gets their own realm, from the raid group")
    check(count(A) == 8, "...and reading the drop again doesn't add it twice")
    A.env.GetNumGroupMembers = function() return 0 end
    A.env.GetInstanceInfo = town

    -- Pulled in from MRT and VoidcoreAdvisor.
    local now = BASE + math.floor(T)
    A.env.VMRT = { LootHistory = { bossNames = { [3430] = "Boss B", [2000] = "Dungeon Boss" },
        instanceNames = { [2813] = "Ruby Life Pools" }, list = {
        ("%d#3429#3004#15#Funkyshade#5#1#item:268256::::::::90:102:::::::::#1"):format(now - 60),   -- already here
        ("%d#3430#3004#16#Codiex#12#1#item:272000::::::::90:102:::::::::"):format(now - 86400),      -- new
        ("%d#2000#2813#8#Codiex#12#1#item:268300::::::::90:102:::::::::"):format(now - 3600),        -- M+
        ("%d#3430#3004#16#Codiex#12#3#item:999::::::::90:102:::::::::"):format(now - 3600),          -- reagent
        -- MRT's roll type is how this account rolled: right for our own win,
        -- not for someone else's.
        ("%d#3429#3004#15#Nattypandy#11#1#item:268300::::::::90:102:::::::::#2"):format(now - 200000),
        ("%d#3429#3004#15#Codiex#12#1#item:270000::::::::90:102:::::::::#1"):format(now - 300000),
        -- No realm in MRT's line; the records say Speedyjosh is from Hyjal.
        ("%d#3429#3004#15#Speedyjosh#8#1#item:268256::::::::90:102:::::::::#1"):format(now - 500000),
        -- Stacks aren't kept.
        ("%d#3429#3004#15#Codiex#12#3#item:268400::::::::90:102:::::::::"):format(now - 600000),
    } } }
    A.env.VoidcoreAdvisorCharDB = { bonusRollLog = {
        { itemID = 270000, itemLink = link(270000), timestamp = now + 2, difficultyID = 15, raidInstanceID = 1314 },
        { itemID = 271875, itemLink = link(271875), timestamp = now - 7 * 86400, difficultyID = 15, raidInstanceID = 1314 },
        -- Rolled just after Boss B's drops (MRT's line above): which boss is filled in.
        { itemID = 270001, itemLink = link(270001), timestamp = now - 86400 + 40, difficultyID = 16, raidInstanceID = 1314 },
        { itemID = 251115, itemLink = link(251115), timestamp = now - 2 * 86400, difficultyID = 23, sourceType = "MYTHIC_PLUS" },
    } }
    local fromMRT, fromVCA = P:PullLoot()
    check(fromMRT == 5, "MRT: four raid items and an M+ item new; the repeat, reagent and stack skipped (got " .. tostring(fromMRT) .. ")")
    check(find(A, "Speedyjosh-Hyjal", 268256) ~= nil and find(A, "Speedyjosh-MalGanis", 268256) == nil,
        "MRT: a name without a realm gets the one the other records say")
    check((find(A, "Nattypandy-MalGanis", 268300) or {}).how == "greed", "MRT: our own win shows how we rolled")
    check((find(A, "Codiex-MalGanis", 270000) or {}).how == "roll", "MRT: someone else's win stays just a won roll")
    check(fromVCA == 3, "VoidcoreAdvisor: three new bonus rolls, the live one not counted twice (got " .. tostring(fromVCA) .. ")")
    check((find(A, "Nattypandy-MalGanis", 251115, "bonus") or {}).diff == 8, "an M+ bonus roll is Mythic Keystone, as MRT says it")
    local mp = find(A, "Codiex-MalGanis", 268300)
    check(mp and mp.kind == "mplus" and mp.where == "Ruby Life Pools", "MRT's M+ loot is kept as M+, with the dungeon")
    local filled = find(A, "Nattypandy-MalGanis", 270001, "bonus")
    check(filled and filled.boss == "Boss B" and filled.enc == 3430, "a bonus roll without a boss gets the kill it came after")
    check((find(A, "Nattypandy-MalGanis", 271875, "bonus") or {}).boss == nil, "...and one with no kill near it stays unknown")
    local cb = find(A, "Codiex-MalGanis", 272000)
    check(cb and cb.boss == "Boss B" and cb.diff == 16 and cb.src == "mrt", "MRT's record keeps boss and difficulty")
    check((find(A, "Nattypandy-MalGanis", 251115, "bonus") or {}).kind == "mplus", "an M+ bonus roll is marked M+")
    local again1, again2 = P:PullLoot()
    check(again1 == 0 and again2 == 0, "pulling again brings nothing new")

    -- What kind of item.
    check(P.LootType(268400) == "token", "a tier token")
    check(P.LootType(268300) == "trinket" and P.LootType(270000) == "weapon"
        and P.LootType(270001) == "jewelry" and P.LootType(268256) == "armor", "trinket, weapon, ring, armor")

    -- Export, and import on another copy.
    local all = P:LootItems()
    local text = P:LootExportText(all)
    check(text:sub(1, 8) == "PGMLOOT1", "export without the game's packer is plain text")
    local parsed = B.PGM:ParseLootExport(text)
    check(parsed and #parsed == #all, "the export reads back whole (" .. tostring(parsed and #parsed) .. " of " .. #all .. ")")
    check(not B.PGM:LootKnown(parsed[1]), "before importing, B doesn't have it")
    local added = B.PGM:ImportLoot(parsed)
    check(added == #all and count(B) == #all, "B imports every record")
    local fb = find(B, "Funkyshade-MalGanis", 268256)
    check(fb and fb.how == "need" and fb.boss == "Boss A" and fb.diff == 15, "...with how, boss and difficulty")
    check(B.PGM:ImportLoot(B.PGM:ParseLootExport(text)) == 0, "importing it twice adds nothing")
    check(B.PGM:ParseLootExport("hello") == nil, "random text isn't an export")
    check(P:LootCSV(all):match("^Date,Player,Item") ~= nil, "CSV has a header row")

    -- Which raid night, and so which team.
    A.g.raids = A.g.raids or { sessions = {} }
    local mercy = { id = "loot-night-1", start = now - 3600, stop = now + 3600, instance = 3004, diffID = 15,
        present = { [gid(22)] = true }, bosses = {}, team = "team-mercy" }
    local honor = { id = "loot-night-2", start = now - 3600, stop = now + 3600, instance = 3004, diffID = 15,
        present = { [gid(23)] = true }, bosses = {}, team = "team-honor" }
    table.insert(A.g.raids.sessions, mercy)
    table.insert(A.g.raids.sessions, honor)
    P:Fire("RAIDS")
    check(P:LootNight(fh) == mercy, "Funkyshade's drop is on the night Funkyshade attended")
    check(P:LootNight(find(A, "Selwyne-MalGanis", 268300)) == honor, "...and Selwyne's on the other team's night")
    check(P:LootNight(cb) == nil, "an item from a night not recorded has no night")
    local sj = find(A, "Speedyjosh-Hyjal", 272000)
    sj.t = now
    P:Fire("RAIDS")
    check(P:LootNight(sj) == nil, "a non-guildie's drop when two teams raid at once is on neither night")
    for i = #A.g.raids.sessions, 1, -1 do
        local s = A.g.raids.sessions[i]
        if s == mercy or s == honor then table.remove(A.g.raids.sessions, i) end
    end
    -- The Loot page draws, under every filter choice and in both views. The
    -- window is stand-ins that take any call (as in simgroups.lua), so the
    -- page's own code runs: building, filtering, every row and its tooltip.
    -- Buttons keep their click handlers and menus their entries, so the
    -- test can click through them.
    do
        local MockMT = {}
        local function Mock() return setmetatable({}, MockMT) end
        MockMT.__index = function() return Mock() end
        MockMT.__call = function() return Mock() end
        MockMT.__concat = function(a, b) return (type(a) == "string" and a or "") .. (type(b) == "string" and b or "") end
        MockMT.__len = function() return 0 end
        local function clickable()
            local b = Mock()
            rawset(b, "SetScript", function(self, k, f) rawset(self, k, f) end)
            rawset(b, "HasFocus", function() return false end)
            rawset(b, "GetText", function() return "" end)
            return b
        end
        local W = setmetatable({}, { __index = function() return function() return Mock() end end })
        local rows, lastMenu = 0, nil
        rawset(W, "List", function(_, _, buildRow, updateRow)
            local l = Mock()
            rawset(l, "SetData", function(self, data)
                for i, d in ipairs(data or {}) do
                    local r = buildRow(self, i)
                    updateRow(r, d, i)
                    if rawget(r, "onEnter") then r.onEnter(r) end
                    rows = rows + 1
                end
            end)
            return l
        end)
        rawset(W, "Button", function() return clickable() end)
        rawset(W, "EditBox", function() return clickable() end)
        rawset(W, "Chip", function(_, _, onClick)
            local c = clickable()
            rawset(c, "OnClick", onClick)
            return c
        end)
        rawset(W, "Menu", function(_, _, entries) lastMenu = entries end)
        local UI = { W = W, tabs = {} }
        function UI:AddTab(t) self.tabs[t.id] = t end
        function UI:QueueRefresh() end
        function UI:Refresh() end
        local exported = {}
        function UI:ShowExport(title, text) exported[#exported + 1] = text end
        local realUI, realCreate = P.UI, A.env.CreateFrame
        P.UI = UI
        A.env.CreateFrame = function() return Mock() end
        A.env.GameTooltip = Mock()
        local fn, err = load(FILES["UI/Loot.lua"], "@UI/Loot.lua", "t", A.env)
        if not fn then error(err) end
        local ok, why = pcall(fn, "PandyGuildManagement", A.NS)
        check(ok, "the Loot page loads (" .. tostring(why) .. ")")
        local tab = UI.tabs.loot
        local page = Mock()
        local choices = 0
        ok, why = pcall(function()
            tab.build(page)
            tab.refresh(page)
            for _, chip in ipairs({ "viewItems", "viewPlayers" }) do
                rawget(page, chip).OnClick(rawget(page, chip))
                tab.refresh(page)
                for _, b in ipairs(rawget(page, "menus")) do
                    b.OnClick(b)
                    for _, e in ipairs(lastMenu or {}) do
                        if e.toggle then
                            e.toggle()
                            tab.refresh(page)
                            choices = choices + 1
                        end
                    end
                    rawget(page, "clear").OnClick(rawget(page, "clear"))
                end
                for _, name in ipairs({ "mine", "myBonus", "tokens", "alts" }) do
                    local c = rawget(page, name)
                    c.OnClick(c)
                    tab.refresh(page)
                    c.OnClick(c)
                end
                local ex = rawget(page, "export")
                ex.OnClick(ex)
                for _, e in ipairs(lastMenu or {}) do if e[2] then e[2]() end end
            end
        end)
        check(ok, "the Loot page builds and refreshes under every filter (" .. tostring(why) .. ")")
        -- The Boss menu, by tier: Boss A (3429) is in the current tier, Boss B
        -- (3430) in none, so it's under Older raids.
        ok, why = pcall(function()
            local bossButton = rawget(page, "menus")[4]
            bossButton.OnClick(bossButton)
            local labels, older = {}, nil
            for _, e in ipairs(lastMenu or {}) do
                if e[1] then labels[e[1]] = e end
                if e[1] == "Older raids" then older = e.sub end
            end
            check(labels["Midnight Season 2"] and labels["Midnight Season 2"].title, "the current tier heads the Boss menu")
            check(labels["Boss A"] ~= nil and labels["Boss B"] == nil, "...with its bosses right there, older ones not")
            local inOlder = false
            for _, e in ipairs(older or {}) do if e[1] == "Boss B" then inOlder = true end end
            check(inOlder, "a boss in no tier is under Older raids")
            labels["All of Midnight Season 2"].toggle()
            tab.refresh(page)
            local items, wrong = rawget(page, "items") or {}, 0
            for _, rec in ipairs(items) do if P.LootTierOf(rec.enc) ~= 1 then wrong = wrong + 1 end end
            check(#items > 0 and wrong == 0, "All of Midnight Season 2 shows only that tier (" .. #items .. " items)")
            rawget(page, "clear").OnClick(rawget(page, "clear"))
        end)
        check(ok, "the Boss menu works (" .. tostring(why) .. ")")
        check(#exported == 4 and exported[1]:sub(1, 7) == "PGMLOOT", "export from the page gives PGM text and CSV")
        check(choices >= 20 and rows > 0, "...through " .. choices .. " menu choices, drawing " .. rows .. " rows")
        P.UI, A.env.CreateFrame, A.env.GameTooltip = realUI, realCreate, nil
    end

    -- Old records under a realm we added: fixed, and repeats merged.
    local before = #P:LootItems()
    table.insert(P:LootItems(), { t = sj.t + 30, who = "Speedyjosh-MalGanis", id = 272000, link = "item:272000",
        how = "greed", kind = "raid", src = "pgm" })
    check(P:FixLootNames() >= 1 and #P:LootItems() == before, "a name we gave the wrong realm is fixed, and the repeat merged")
    -- Deleting sticks: pulling MRT again doesn't bring it back.
    P:DeleteLoot(cb)
    P:PullLoot(true)
    check(find(A, "Codiex-MalGanis", 272000) == nil, "a deleted entry stays deleted when MRT is read again")
    P:DeleteLoot(fh)
    check(find(A, "Funkyshade-MalGanis", 268256) == nil, "a record can be deleted")
end

print("-- raid teams: no duplicates from a copy still catching up, and who made each")
do
    local E = newClient(gid(24), "Triclops")   -- raid leadership, just installed
    check(E.PGM:CanEdit(), "the new copy can edit teams")
    check(E.PGM:FindTeamsInNotes() == nil, "before catching up, Find teams in notes doesn't run")
    run(100)
    check(E.PGM:FindTeamsInNotes() ~= nil, "after catching up, it does")
    local made = A.PGM:CreateTeam("Made By Test")
    run(10)
    local bt = teamNamed(B, "Made By Test")
    check(made.by == "Nattypandy" and bt and bt.by == "Nattypandy", "a team says who made it, on every copy")
    A.PGM:DeleteTeam(made.id)
    run(10)
end

print("-- review fixes: purges, alt ranks, rank names with spaces, the closest event")
do
    -- A purge while we were away: the first read that's missing a third of
    -- the guild is held back; a read a minute later missing the same people
    -- is believed.
    local F = newClient(gid(23), "Selwyne")
    local g = F.g
    local purged = {}
    for n = 500, 539 do
        local guid = gid(n)
        purged[guid] = true
        g.members[guid] = { guid = guid, name = ("Purged%03d-%s"):format(n, REALM), short = ("Purged%03d"):format(n),
            realm = REALM, rank = "Member", rankIndex = 5, level = 90, class = "MAGE", note = "", onote = "" }
    end
    local function read(withPurged)
        local snap = {}
        for guid, rec in pairs(g.members) do
            if withPurged or not purged[guid] then
                local c = {}
                for k, v in pairs(rec) do c[k] = v end
                snap[guid] = c
            end
        end
        F.PGM:ApplyRoster(snap, true)
    end
    local function members() local n = 0 for _ in pairs(g.members) do n = n + 1 end return n end
    local before = members()
    read(false)
    check(members() == before, "a read missing a third of the guild is held back")
    read(true)
    check(members() == before, "...and a full read after it is fine")
    read(false)
    run(30)
    read(false)
    check(members() == before, "...still held half a minute later")
    run(40)
    read(false)
    check(members() == before - 40, "the same people still missing a minute later: they're gone (" .. members() .. ")")
    local leaves = 0
    for _, e in ipairs(g.log) do if e.kind == "leave" and (e.name or ""):find("^Purged") then leaves = leaves + 1 end end
    check(leaves == 40, "...and History has their leaves (" .. leaves .. ")")

    -- Alt ranks are whole words.
    check(not F.PGM.IsAltRank({ rank = "Exalted" }), "a rank called Exalted isn't an alt rank")
    check(F.PGM.IsAltRank({ rank = "Raider Alts" }) and F.PGM.IsAltRank({ rank = "Alt" })
        and F.PGM.IsAltRank({ rank = "Officer Alt" }), "...but Alt, Officer Alt and Raider Alts are")

    -- A rank name with spaces doesn't swallow the member's name.
    local P, ag = A.PGM, A.g
    A.fire("CHAT_MSG_SYSTEM", "Magicpayne has promoted Codiex to Ready to Raid.")
    local e = P:AddLog(ag, "promote", ag.members[gid(13)], { from = "Trial", to = "Ready to Raid" })
    check(e.by == "Magicpayne", "a promotion to a rank with spaces is credited")

    -- Kicked three days ago, re-invited, quit now: the quit explains today's leave.
    GUILD_EVENTS = {
        -- ("" not nil: a nil would end the row early when unpacked)
        { "remove", "Magicpayne-MalGanis", "Bouncer-MalGanis", "", 0, 0, 3, 0 },
        { "quit", "Bouncer-MalGanis", "", "", 0, 0, 0, 0 },
    }
    local leave = P:AddLog(ag, "leave", { guid = gid(44), short = "Bouncer", class = "ROGUE" })
    A.fire("GUILD_EVENT_LOG_UPDATE")
    check(leave.credited and not leave.removed, "today's leave is today's quit, not an old kick")
end

print("-- review fixes: deleted nights stay deleted, older copies, catch-up traffic, re-tagging")
do
    local now = BASE + math.floor(T)
    local function count(cl, inst)
        local n = 0
        for _, x in ipairs(cl.g.raids and cl.g.raids.sessions or {}) do
            if x.instance == inst then n = n + 1 end
        end
        return n
    end
    local function night(id, startOff, inst, present, leaders)
        local n = { id = id, start = now + startOff, stop = now + startOff + 7200, instance = inst, diffID = 15,
                    name = "Voidspire", present = {}, bosses = {} }
        for _, gu in ipairs(present) do n.present[gu] = true end
        if leaders then
            n.leaders = {}
            for _, gu in ipairs(leaders) do n.leaders[gu] = true end
        end
        return n
    end

    -- A deletes a night; a copy that missed the delete sends it again under
    -- its own id later: it stays deleted everywhere.
    local wed = night("wed-A", -7200, 6161, { gid(10), gid(21), gid(22) }, { gid(10) })
    table.insert(A.g.raids.sessions, wed)
    A.PGM:SyncRaid(wed)
    run(10)
    check(count(C, 6161) == 1, "the night arrived")
    A.PGM:DeleteRaid(wed)
    run(10)
    check(count(A, 6161) == 0 and count(C, 6161) == 0, "...and is deleted")
    B.PGM.SyncSend(false, "1S", "wed-B", now, now - 7100, now + 300, 6161, 15, "", 0, "Voidspire", "", gid(10))
    run(5)
    check(count(A, 6161) == 0 and count(C, 6161) == 0, "the same night under another id stays deleted")

    -- Older copies send nights without leaders, and attendees after.
    local mercy = night("mercy-new", -3600, 7171, { gid(10), gid(21), gid(22), gid(25), gid(26) }, { gid(10) })
    table.insert(A.g.raids.sessions, mercy)
    A.PGM:SyncRaid(mercy)
    run(10)
    -- Another team's raid at the same time, from an older copy: two nights.
    B.PGM.SyncSend(false, "1S", "honor-old", now - 50, now - 3500, now + 3700, 7171, 15, "", 0, "Voidspire", "")
    B.PGM.SyncSend(false, "1P", "honor-old", table.concat({ gid(1), gid(11), gid(12), gid(13), gid(14) }, ","))
    run(10)
    check(count(C, 7171) == 2, "an older copy's record of another team's raid stays its own night (" .. count(C, 7171) .. ")")
    -- The same raid as Mercy's, from an older copy: one night.
    B.PGM.SyncSend(false, "1S", "mercy-old", now - 40, now - 3400, now + 3600, 7171, 15, "", 0, "Voidspire", "")
    B.PGM.SyncSend(false, "1P", "mercy-old", table.concat({ gid(10), gid(23) }, ","))
    run(10)
    check(count(C, 7171) == 2, "...and its record of Mercy's raid joins Mercy's night (" .. count(C, 7171) .. ")")
    local m
    for _, x in ipairs(C.g.raids.sessions) do if x.instance == 7171 and x.present[gid(10)] then m = x end end
    check(m and m.present[gid(23)] and m.present[gid(25)], "...with everyone from both")

    -- Overhearing someone else's catch-up counts as my own, when it started
    -- no later than I'd caught up to and I heard all of it.
    local H = C.PGM.SyncHandlers
    local cs = C.g.sync
    local officer = A.g.members[gid(10)]
    local function overhear(since, newest, zone)
        cs.caught = 1000
        H.R({ "1R", "Nattypandy-MalGanis", tostring(since) }, "Selwyne-MalGanis")
        if zone then C.fire("PLAYER_ENTERING_WORLD") end
        H.E({ "1E", "Selwyne-MalGanis", "3", tostring(newest) }, "Nattypandy-MalGanis", officer)
        return cs.caught
    end
    local edge = BASE + math.floor(T)
    check(overhear(900, edge) == edge, "overhearing a catch-up from before mine catches me up too")
    check(overhear(1100, edge) == 1000, "...not one that started after what I have")
    run(1)
    check(overhear(900, edge, true) == 1000, "...nor one I may have missed part of (a loading screen)")
    cs.caught = math.max(cs.caught, cs.newest)
    -- An officer's own edit, made while caught up, keeps them caught up.
    local as = A.g.sync
    as.caught = math.max(as.caught, as.newest)
    local t = A.PGM:CreateTeam("Traffic Test")
    check(as.caught == as.newest and as.caught >= t.u, "my own edit while caught up doesn't need a catch-up")
    A.PGM:DeleteTeam(t.id)

    -- Match past raids: not a night untagged by hand, but yes one whose team went.
    local P, g = A.PGM, A.g
    local team = P:CreateTeam("Retag Test")
    for _, n in ipairs({ 10, 21, 22 }) do P:AddToTeam(team.id, gid(n)) end
    local byHand = night("untagged-by-hand", -1800, 8181, { gid(10), gid(21), gid(22) })
    local freed = night("freed-by-delete", -900, 8282, { gid(10), gid(21), gid(22) })
    table.insert(g.raids.sessions, byHand)
    table.insert(g.raids.sessions, freed)
    P:AssignRaid(byHand, team.id)
    P:AssignRaid(byHand, nil)
    local gone = P:CreateTeam("Gone Team")
    P:AssignRaid(freed, gone.id)
    P:DeleteTeam(gone.id)
    P:AutoAssignRaids()
    check(byHand.team == nil, "Match past raids leaves a night you untagged alone")
    check(freed.team == team.id, "...but tags a night whose team was deleted")
    P:DeleteTeam(team.id)
    for i = #g.raids.sessions, 1, -1 do
        local s = g.raids.sessions[i]
        if s == byHand or s == freed then table.remove(g.raids.sessions, i) end
    end
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
