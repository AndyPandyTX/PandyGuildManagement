-- Posts.lua: guild groups. A leader posts what they're running and the
-- roles they still need; guildies ask to join; the leader invites with a
-- click (the game only invites from a real click, so nothing here invites on
-- its own). A post can start later instead: guildies sign up with a role, and
-- at start time the leader invites them, one click each.
--
-- CLEANUP: the leader's copy closes the post when the group fills, when
-- they stop being leader, or when they close it. Every other copy drops a
-- post when PGM's roster shows its leader offline, or when it's gone 10
-- minutes without the leader's heartbeat (they went into an instance, where
-- addons can't talk). Scheduled posts stay until two hours after they start.
--
-- WHO MAY SAY WHAT: a post's id starts with its leader's GUID, and P, X and
-- Y count only from that character. A, C and U are about the sender only.
--
-- WIRE (inside "1G"):
--   P id u kind what level size needT needH needD have team start pugAt lfg note
--   X id u why            closed: f full, c closed, l no longer the leader
--   Q                     what's posted? (each leader answers with their own)
--   A id leader role ilvl spec note        ask to join
--   C id leader                            take an ask back
--   Y id asker answer                      i invited, d declined
--   U id u role state                      scheduled signup: i in, x out

local _, NS = ...
local G = NS.G
if not G.ok then return end
local PGM = G.PGM

local TTL = 10 * 60
local HEARTBEAT = 4 * 60
local SKEW = 300
local SCHED_KEEP = 2 * 3600
local MAX_ASKS = 40
local PING_GAP = 60

G.posts = {}    -- [id] = post, everyone's (mine too)
G.mine = nil    -- my live post, with its asks
G.asked = {}    -- [id] = { state = "asked" | "invited" | "declined" | "closed", role, at }

local function leaderTail(id)
    return type(id) == "string" and id:match("^([^%.]+)%.%d+$") or nil
end

-- Did this sender write this post?
local function isLeader(id, rec)
    local tail = leaderTail(id)
    return tail ~= nil and rec ~= nil and tail == G.GuidTail(rec.guid)
end

local function clampU(u)
    u = tonumber(u)
    if not u or u <= 0 then return nil end
    return math.floor(math.min(u, PGM.Now() + SKEW))
end

local function validRole(r)
    return (r == "T" or r == "H" or r == "D") and r or nil
end

local function sound()
    local kit = SOUNDKIT and (SOUNDKIT.UI_GROUP_FINDER_RECEIVE_APPLICATION or SOUNDKIT.TELL_MESSAGE)
    if kit then pcall(PlaySound, kit) end
end

function G.PostTitle(p)
    local what, level = p.what or "", p.level or ""
    if p.kind == "M" then
        return (level ~= "" and ("+" .. level .. " ") or "") .. (what ~= "" and what or "Mythic+")
    elseif p.kind == "R" then
        return (what ~= "" and what or "Raid") .. (level ~= "" and (" (" .. level .. ")") or "")
    elseif p.kind == "D" then
        return (what ~= "" and what or "Delve") .. (level ~= "" and (" tier " .. level) or "")
    end
    return what ~= "" and what or "Group"
end

function G.NeedTotal(need)
    return (need.T or 0) + (need.H or 0) + (need.D or 0)
end

-- Can I see this post? Team-only posts show only to that team (and the
-- leader). The rest of the guild's copies hold them but keep them hidden.
function G:Visible(p)
    if not p.team or p.team == "" or p.mine then return true end
    for _, it in ipairs(PGM:TeamsOf(PGM:MyGuid() or "")) do
        if it.team.id == p.team then return true end
    end
    return false
end

function G.TeamName(id)
    local t = id and id ~= "" and PGM:TeamById(id)
    return t and t.name or nil
end

-- ============================================================
-- SENDING
-- ============================================================

local function sendPost(p, quiet)
    return G.Send(quiet, "P", p.id, p.u, p.kind, G.Clean(p.what, 40), G.Clean(p.level, 8), p.size,
        p.need.T, p.need.H, p.need.D, p.have or 1, p.team or "", p.start or 0, p.pugAt or 0,
        p.lfg and 1 or 0, G.Clean(p.note, 70))
end

G.SendPost = sendPost

local counter = 0
local function newId()
    counter = counter + 1
    return G.GuidTail(PGM:MyGuid()) .. "." .. (PGM.Now() * 10 + counter % 10)
end

-- Post a group, or change mine. spec: { kind, what, level, size, need,
-- team, start, guildFirst, note, id }. A start in the future makes it a
-- scheduled group. Returns the post, or nil and why not.
function G:Post(spec)
    if not G.CanTalk() then return nil, G.WhyNot() end
    if not PGM:MyGuid() then return nil, "Your character isn't ready yet." end
    local now = PGM.Now()
    local scheduled = (spec.start or 0) > now + 60
    if not scheduled and G.InGroup() and not G.IsLeader() then
        return nil, "Only your group's leader can post it."
    end
    local d = G.DB()
    local old = spec.id and G.posts[spec.id]
    if old and not old.mine then old = nil end
    if not scheduled and G.mine and not (old and old.id == G.mine.id) then
        return nil, "You already have a group posted. Close it first."
    end
    local p = old or { id = newId(), mine = true, leader = PGM:MyGuid() }
    if old and (old.start or 0) > 0 ~= scheduled then
        return nil, "A scheduled group stays scheduled. Close it and post again."
    end
    p.u = PGM.Stamp(p.u)
    p.kind = G.KIND_LABEL[spec.kind] and spec.kind or "O"
    p.what = G.Clean(spec.what, 40)
    p.level = G.Clean(spec.level, 8)
    p.size = math.max(2, math.min(40, tonumber(spec.size) or G.KIND_SIZE[p.kind]))
    p.need = {}
    for _, r in ipairs(G.ROLES) do
        p.need[r] = math.max(0, math.min(p.size, tonumber(spec.need and spec.need[r]) or 0))
    end
    p.team = spec.team or ""
    p.note = G.Clean(spec.note, 70)
    p.start = scheduled and math.floor(spec.start) or 0
    p.leaderName = G.MyName()
    if scheduled then
        p.signups = p.signups or {}
        p.invited = p.invited or {}
        d.sched[p.id] = p
    else
        p.have = G.GroupSize()
        if spec.lfg ~= nil then p.lfg = spec.lfg end
        p.fromLFG = spec.fromLFG or p.fromLFG
        if not old then
            p.pugAt = now + 60 * (tonumber(spec.guildFirst) or G.opt("guildFirst") or 0)
            p.asks, p.counted, p.base = {}, {}, {}
            for _, m in ipairs(G.GroupNames()) do p.base[PGM.SyncNorm(m.name)] = true end
        end
        G.mine = p
    end
    G.posts[p.id] = p
    sendPost(p)
    G:Fire("POSTS")
    return p
end

-- Close my live post. why: f full, c closed, l no longer the leader.
function G:CloseMine(why)
    local p = G.mine
    if not p then return end
    G.mine = nil
    G.posts[p.id] = nil
    local d = G.DB()
    local u = PGM.Stamp(p.u)
    if d then d.closed[p.id] = u end
    G.Send(true, "X", p.id, u, why or "c")
    G:Fire("POSTS")
end

function G:CloseScheduled(id)
    local p = G.posts[id]
    if not (p and p.mine and (p.start or 0) > 0) then return end
    if not G.CanTalk() then
        PGM.Print(G.WhyNot())
        return
    end
    local d = G.DB()
    G.posts[id] = nil
    d.sched[id] = nil
    local u = PGM.Stamp(p.u)
    d.closed[id] = u
    G.Send(true, "X", id, u, "c")
    G:Fire("POSTS")
end

-- ============================================================
-- ASKING (the guildie's side)
-- ============================================================

function G:Ask(id, role, note)
    local p = G.posts[id]
    if not p or p.mine then return end
    if not G.CanTalk() then PGM.Print(G.WhyNot()) return end
    if G.InGroup() then
        PGM.Print("Leave your group first: an invite can't reach you while you're in one.")
        return
    end
    role = validRole(role) or G.SpecRole()
    G.asked[id] = { state = "asked", role = role, at = GetTime() }
    G.Send(false, "A", id, p.leaderName or "", role, G.MyIlvl(), G.SpecID(), G.Clean(note, 60))
    G:Fire("POSTS")
end

function G:Withdraw(id)
    local p = G.posts[id]
    G.asked[id] = nil
    if p then G.Send(true, "C", id, p.leaderName or "") end
    G:Fire("POSTS")
end

function G:SignUp(id, role)
    local p = G.posts[id]
    local me = PGM:MyGuid()
    if not (p and me and (p.start or 0) > 0) or p.mine then return end
    if not G.CanTalk() then PGM.Print(G.WhyNot()) return end
    p.signups = p.signups or {}
    local cur = p.signups[me]
    local s = { role = validRole(role) or G.SpecRole(), u = PGM.Stamp(cur and cur.u), state = "i" }
    p.signups[me] = s
    G.Send(false, "U", id, s.u, s.role, "i")
    G:Fire("POSTS")
end

function G:SignOff(id)
    local p = G.posts[id]
    local me = PGM:MyGuid()
    local cur = p and p.signups and p.signups[me or ""]
    if not cur then return end
    if not G.CanTalk() then PGM.Print(G.WhyNot()) return end
    cur.state, cur.u = "x", PGM.Stamp(cur.u)
    G.Send(false, "U", id, cur.u, cur.role, "x")
    G:Fire("POSTS")
end

-- ============================================================
-- ANSWERING (the leader's side)
-- ============================================================

-- Everyone asking to join, oldest first with guildies ahead of the rest:
-- asks on my post through the guild ({ key, ask, rec }), and applicants to
-- my Group Finder listing ({ key, ask, rec, app = true }, from
-- GroupFinder.lua). Someone who did both is listed once, as an applicant.
function G:Asks()
    local out, seen = {}, {}
    for _, it in ipairs(G.Applicants and G:Applicants() or {}) do
        out[#out + 1] = it
        seen[PGM.SyncNorm(it.ask.name)] = true
    end
    local p = G.mine
    for key, a in pairs(p and p.asks or {}) do
        if a.state ~= "declined" and not seen[key] then
            out[#out + 1] = { key = key, ask = a, rec = G.RecByName(a.name) }
        end
    end
    table.sort(out, function(a, b)
        if (a.rec ~= nil) ~= (b.rec ~= nil) then return a.rec ~= nil end
        return (a.ask.at or 0) < (b.ask.at or 0)
    end)
    return out
end

-- From a click: the game invites only from one. A Group Finder applicant
-- is invited through the Group Finder (their whole application at once).
function G:InviteAsk(key)
    if G.InviteApplicant and G:InviteApplicant(key) then return end
    local p = G.mine
    local a = p and p.asks[key]
    if not a then return end
    if C_PartyInfo and C_PartyInfo.InviteUnit then C_PartyInfo.InviteUnit(a.name) end
    a.state = "invited"
    G.Send(true, "Y", p.id, a.name, "i")
    G:Fire("POSTS")
end

function G:DeclineAsk(key)
    if G.DeclineApplicant and G:DeclineApplicant(key) then return end
    local p = G.mine
    local a = p and p.asks[key]
    if not a then return end
    a.state = "declined"
    G.Send(true, "Y", p.id, a.name, "d")
    G:Fire("POSTS")
end

-- A scheduled group's signups: { guid, rec, s }, in the order they came.
function G:Signups(p)
    local g = PGM.GuildDB()
    local out = {}
    for guid, s in pairs(p.signups or {}) do
        local rec = g and g.members[guid]
        if rec and s.state == "i" then out[#out + 1] = { guid = guid, rec = rec, s = s } end
    end
    table.sort(out, function(a, b) return (a.s.u or 0) < (b.s.u or 0) end)
    return out
end

-- Invite the next signup who's online and not in my group yet. From a
-- click, one invite per click. Returns their name, or nil.
function G:InviteNextSignup(id)
    local p = G.posts[id]
    if not (p and p.mine) then return nil end
    local inGroup = {}
    for _, m in ipairs(G.GroupNames()) do inGroup[PGM.SyncNorm(m.name)] = true end
    for _, it in ipairs(G:Signups(p)) do
        local key = PGM.SyncNorm(it.rec.name)
        if it.rec.online and not inGroup[key] and not p.invited[it.guid] then
            p.invited[it.guid] = true
            if C_PartyInfo and C_PartyInfo.InviteUnit then C_PartyInfo.InviteUnit(it.rec.name) end
            G:Fire("POSTS")
            return it.rec.short
        end
    end
end

function G:SignupsLeft(p)
    local inGroup, n = {}, 0
    for _, m in ipairs(G.GroupNames()) do inGroup[PGM.SyncNorm(m.name)] = true end
    for _, it in ipairs(G:Signups(p)) do
        if it.rec.online and not inGroup[PGM.SyncNorm(it.rec.name)] and not p.invited[it.guid] then n = n + 1 end
    end
    return n
end

-- After the guild-first wait: open Blizzard's Group Finder. Listing a group
-- needs a real click on its own List Group button, so that part is theirs.
local FINDER_CATEGORY = { M = "Dungeons", R = "Raids", D = "Delves", O = "Custom" }
function G:FindPugs()
    local p = G.mine
    if PVEFrame_ShowFrame then
        pcall(PVEFrame_ShowFrame, "GroupFinderFrame", "LFGListPVEStub")
    elseif PVEFrame_ToggleFrame then
        pcall(PVEFrame_ToggleFrame)
    end
    PGM.Print(("Group Finder: pick %s, then Start a Group. Guildies can still ask here."):format(
        FINDER_CATEGORY[p and p.kind or "O"]))
end

-- ============================================================
-- RECEIVING
-- ============================================================

local pinged, lastPing = {}, -1000

-- One chat line and a soft sound when a post needs a role I play.
local function maybePing(p)
    if not G.opt("ping") or p.mine or (p.start or 0) > 0 or pinged[p.id] then return end
    if InCombatLockdown() or PGM.SyncBlocked() or G.InGroup() then return end
    if not G.opt("pingKinds")[p.kind] or not G:Visible(p) then return end
    if GetTime() - lastPing < PING_GAP then return end
    local roles, want = G.MyRoles(), nil
    for _, r in ipairs(G.ROLES) do
        if roles[r] and (p.need[r] or 0) > 0 then want = r break end
    end
    if not want then return end
    pinged[p.id], lastPing = true, GetTime()
    local g = PGM.GuildDB()
    local rec = g and g.members[p.leader]
    PGM.Print(("%s's %s needs a %s.  /pgg to ask."):format(rec and PGM.ColorName(rec) or "A guildie",
        G.PostTitle(p), G.RoleText(want, true)))
    sound()
end

function G.handlers.P(f, sender, rec)
    local id, u = f[3], clampU(f[4])
    if not (id and u and isLeader(id, rec)) then return end
    local d = G.DB()
    if (d.closed[id] or 0) >= u then return end
    local cur = G.posts[id]
    if cur and cur.u >= u then
        cur.seen = GetTime()   -- a heartbeat
        return
    end
    local p = cur or { id = id }
    p.u, p.leader, p.leaderName, p.seen = u, rec.guid, sender, GetTime()
    p.kind = G.KIND_LABEL[f[5]] and f[5] or "O"
    p.what, p.level = G.Clean(f[6], 40), G.Clean(f[7], 8)
    p.size = math.max(2, math.min(40, tonumber(f[8]) or 5))
    p.need = {}
    for i, r in ipairs(G.ROLES) do p.need[r] = math.max(0, math.min(40, tonumber(f[8 + i]) or 0)) end
    p.have = tonumber(f[12]) or 1
    p.team = G.Clean(f[13], 40)
    p.start = tonumber(f[14]) or 0
    p.pugAt = tonumber(f[15]) or 0
    p.lfg = f[16] == "1"
    p.note = G.Clean(f[17], 70)
    G.posts[id] = p
    if p.start > 0 then
        p.signups = p.signups or {}
        d.sched[id] = p
    end
    if not cur then maybePing(p) end
    G:Fire("POSTS")
end

function G.handlers.X(f, sender, rec)
    local id, u = f[3], clampU(f[4])
    if not (id and u and isLeader(id, rec)) then return end
    local d = G.DB()
    if (d.closed[id] or 0) >= u then return end
    d.closed[id] = u
    G.posts[id] = nil
    d.sched[id] = nil
    if G.asked[id] then G.asked[id].state = "closed" end
    G:Fire("POSTS")
end

function G.handlers.Q()
    G:AnswerStatus()
    if not G.CanTalk() then return end
    local mine = {}
    for _, p in pairs(G.posts) do
        if p.mine then mine[#mine + 1] = p end
    end
    if #mine == 0 then return end
    C_Timer.After(1 + math.random() * 4, function()
        for _, p in ipairs(mine) do
            if G.posts[p.id] == p then sendPost(p, true) end
        end
    end)
end

function G.handlers.A(f, sender, rec)
    local p = G.mine
    local id = f[3]
    if not (p and p.id == id and PGM.SyncIsMe(f[4])) then return end
    local key = PGM.SyncNorm(sender)
    local a = p.asks[key]
    if not a then
        local n = 0
        for _ in pairs(p.asks) do n = n + 1 end
        if n >= MAX_ASKS then return end
    end
    if a and (a.state == "invited" or a.state == "joined") then return end
    p.asks[key] = {
        name = sender, guid = rec.guid, role = validRole(f[5]) or "D",
        ilvl = tonumber(f[6]) or 0, spec = tonumber(f[7]) or 0, note = G.Clean(f[8], 60),
        at = GetTime(), state = "new",
    }
    local score = G.ScoreText(rec)
    PGM.Print(("%s asks to join as %s%s%s."):format(G.WhoText(rec), G.RoleText(p.asks[key].role, true),
        p.asks[key].ilvl > 0 and (", " .. p.asks[key].ilvl .. " ilvl") or "",
        score and (", " .. score) or ""))
    sound()
    G:Fire("POSTS")
end

function G.handlers.C(f, sender)
    local p = G.mine
    if not (p and p.id == f[3] and PGM.SyncIsMe(f[4])) then return end
    local key = PGM.SyncNorm(sender)
    if p.asks[key] and p.asks[key].state == "new" then
        p.asks[key] = nil
        G:Fire("POSTS")
    end
end

function G.handlers.Y(f, sender, rec)
    local id = f[3]
    local a = G.asked[id]
    if not (a and isLeader(id, rec) and PGM.SyncIsMe(f[4])) then return end
    local p = G.posts[id]
    local title = p and G.PostTitle(p) or "the group"
    if f[5] == "i" then
        a.state = "invited"
        PGM.Print(("%s invited you to %s."):format(PGM.ColorName(rec), title))
    elseif f[5] == "d" then
        a.state, a.declinedAt = "declined", GetTime()
        PGM.Print(("%s's %s is going ahead without you this time."):format(PGM.ColorName(rec), title))
    end
    G:Fire("POSTS")
end

function G.handlers.U(f, sender, rec)
    local id, u, role, state = f[3], clampU(f[4]), validRole(f[5]), f[6]
    local p = G.posts[id]
    if not (p and u and role and (p.start or 0) > 0) or (state ~= "i" and state ~= "x") then return end
    p.signups = p.signups or {}
    local cur = p.signups[rec.guid]
    if cur and (cur.u or 0) >= u then return end
    p.signups[rec.guid] = { role = role, u = u, state = state }
    if p.mine then
        PGM.Print(("%s %s %s as %s."):format(G.WhoText(rec), state == "i" and "signed up for" or "dropped out of",
            G.PostTitle(p), G.RoleText(role, true)))
    end
    G:Fire("POSTS")
end

-- ============================================================
-- MY GROUP CHANGING
-- ============================================================

-- Count who joined since I posted, take their roles off what's needed,
-- and close the post once it's full.
local function recount()
    local p = G.mine
    if not p then return end
    if G.InGroup() and not G.IsLeader() then
        PGM.Print("You're not the group leader any more, so your guild post closed.")
        G:CloseMine("l")
        return
    end
    local changed = false
    local here = {}
    for _, m in ipairs(G.GroupNames()) do
        local key = PGM.SyncNorm(m.name)
        here[key] = true
        if not p.base[key] and not p.counted[key] then
            local a = p.asks[key]
            local role = m.role or (a and a.role) or "?"
            p.counted[key] = role
            if validRole(role) and (p.need[role] or 0) > 0 then p.need[role] = p.need[role] - 1 end
            if a then a.state = "joined" end
            changed = true
        end
    end
    -- Someone who joined and left again: their spot is open again.
    for key, role in pairs(p.counted) do
        if not here[key] then
            p.counted[key] = nil
            if validRole(role) then p.need[role] = (p.need[role] or 0) + 1 end
            changed = true
        end
    end
    for key in pairs(p.base) do
        if not here[key] then p.base[key] = nil end
    end
    local have = G.GroupSize()
    if have ~= p.have then p.have, changed = have, true end
    if have >= p.size or G.NeedTotal(p.need) == 0 then
        PGM.Print(("Your %s is full, so its guild post closed."):format(G.PostTitle(p)))
        G:CloseMine("f")
        return
    end
    if changed then
        p.u = PGM.Stamp(p.u)
        sendPost(p, true)
        G:Fire("POSTS")
    end
end

local recountTimer
G:RegisterEvent("GROUP_ROSTER_UPDATE", function()
    if not G.mine or recountTimer then return end
    recountTimer = C_Timer.NewTimer(1, function()
        recountTimer = nil
        recount()
    end)
end)

-- ============================================================
-- CLEANUP
-- ============================================================

local reminded = {}

local function sweep()
    local d = G.DB()
    if not d then return end
    local g = PGM.GuildDB()
    local now, t = PGM.Now(), GetTime()
    local me = PGM:MyGuid()
    local changed = false
    for id, p in pairs(G.posts) do
        local scheduled = (p.start or 0) > 0
        local rec = g and g.members[p.leader or ""]
        local drop
        if p.mine then
            drop = scheduled and p.start + SCHED_KEEP < now
        elseif scheduled then
            drop = p.start + SCHED_KEEP < now or not rec
        else
            drop = t - (p.seen or 0) > TTL or not (rec and rec.online)
        end
        if drop then
            G.posts[id] = nil
            d.sched[id] = nil
            if G.asked[id] then G.asked[id].state = "closed" end
            changed = true
        elseif scheduled and p.start <= now and not reminded[id] then
            reminded[id] = true
            local mineSignup = me and p.signups and p.signups[me]
            if p.mine then
                PGM.Print(("Your %s starts now: /pgg, then Invite next for each signup."):format(G.PostTitle(p)))
                sound()
            elseif mineSignup and mineSignup.state == "i" then
                PGM.Print(("%s's %s starts now. Watch for the invite."):format(
                    rec and PGM.ColorName(rec) or "The", G.PostTitle(p)))
                sound()
            end
        end
    end
    for id, u in pairs(d.closed) do
        if u < now - 2 * 86400 then d.closed[id] = nil end
    end
    if changed then G:Fire("POSTS") end
end

G:OnPGM("ROSTER", sweep)

-- Everyone's posts I can see: live first (newest first), then scheduled
-- ones by start time.
function G:PostList()
    local out = {}
    for _, p in pairs(G.posts) do
        if G:Visible(p) then out[#out + 1] = p end
    end
    table.sort(out, function(a, b)
        local sa, sb = (a.start or 0) > 0, (b.start or 0) > 0
        if sa ~= sb then return sb end
        if sa then return a.start < b.start end
        return (a.u or 0) > (b.u or 0)
    end)
    return out
end

-- ============================================================
-- SESSION
-- ============================================================

G:On("READY", function()
    local d = G.DB()
    if not d then return end
    -- Scheduled groups saved from before, mine and others'.
    local myTail = G.GuidTail(PGM:MyGuid())
    for id, p in pairs(d.sched) do
        if (p.start or 0) + SCHED_KEEP < PGM.Now() or (d.closed[id] or 0) >= (p.u or 0) then
            d.sched[id] = nil
        else
            p.mine = leaderTail(id) == myTail or nil
            p.invited = p.invited or {}
            G.posts[id] = p
        end
    end
    -- A live post from just before a /reload: carry on with it.
    local saved = d.mine
    d.mine = nil
    if saved and saved.savedAt and PGM.Now() - saved.savedAt < TTL and leaderTail(saved.id) == myTail
        and G.IsLeader() then
        saved.savedAt = nil
        G.mine = saved
        G.posts[saved.id] = saved
        C_Timer.After(14, function()
            if G.mine == saved then
                saved.u = PGM.Stamp(saved.u)
                sendPost(saved, true)
                recount()
            end
        end)
    end
    C_Timer.After(16, function() G.Send(true, "Q") end)
    G.Every(30, sweep)
    G.Every(HEARTBEAT, function()
        if G.mine and G.CanTalk() then sendPost(G.mine, true) end
    end)
    G:Fire("POSTS")
end)

G:RegisterEvent("PLAYER_LOGOUT", function()
    local d = G.DB()
    if not d then return end
    if G.mine then
        G.mine.savedAt = PGM.Now()
        d.mine = G.mine
    end
end)
