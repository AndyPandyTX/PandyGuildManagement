-- Sync.lua: shares raid teams, raid nights and hand-made alt links with
-- everyone in the guild running the addon, over hidden guild addon messages.
-- Private notes and settings are never sent.
--
-- WHO MAY WRITE: officers only, and that is checked by every receiver, not
-- just the sender's UI. A record is applied only if its sender is an officer
-- in the receiver's own guild roster, so an edited copy of the addon on a
-- member's PC can't push changes. The guild master decides which ranks count
-- as officers (Settings); until then, ranks named like "Officer", "Leader" or
-- "Guild Master" do. One exception: anyone may say which of their own
-- characters is their main (record B), but only about the character sending
-- it; officers may relay everyone's during a catch-up.
--
-- HOW IT MERGES: every record carries the time it was made, and newest wins,
-- record by record (one team member, one alt link). A raid night's attendees
-- only ever grow, so those just merge. Seeing a record twice changes nothing,
-- so sending too much is always safe.
--
-- THE BUDGET: an addon gets about 10 messages, refilling one a second, shared
-- by everyone in the guild using it, 255 bytes each. So: one queue, one
-- message every 1.1s; small records; and catch-up is elected. A player who
-- logs in says how current they are ("H"); officers with newer data offer
-- ("O") after a random wait, standing down if someone else already has; the
-- player picks one ("R"); that officer sends the newer records on the guild
-- channel, where every listener merges them, then "E".
--
-- MIDNIGHT: addon messages don't work inside instances, so the queue simply
-- waits until you're out. Inbound fields that arrive secret are dropped.
--
-- WIRE: fields joined by \031; the first is protocol "1" + record type.
--   H newest version             I'm here, this is how current I am
--   V version                    I'm here too (an answer to H, so everyone
--                                learns who runs the addon and which version)
--   O target newest              I can catch target up
--   R target since               target: send me everything newer than since
--   E target count newest        end of that catch-up; target is now this current
--   T id u name schedule tags auto                  team details
--   K id u                                          team deleted
--   M team guid u state role status                 one team spot (i = on, x = removed)
--   A guid u main [guid u main ...]                 alt links ("0" = not an alt, "" = none)
--   S id u start stop instance diff team teamU name bosses   raid night
--   P id guid,guid,...                              raid night attendees (merged in)
--   D id u                                          raid night deleted
--   C u officerRank                                 guild master's officer cut-off
--   J guid u joined [guid u joined ...]             join dates (e.g. from GRM)
--   B guid u main [guid u main ...]                 "this character's main is main"
--                                                   (itself, if it's the main)

local _, NS = ...
local PGM = NS.PGM
local P = PGM.Plain

local PREFIX = "PandyGuildMgmt"
local SEP = "\031"
local SEND_GAP = 1.1
local SKEW = 300            -- most a record's clock may run ahead of ours
local OVERLAP = 3600        -- catch-up re-asks this much before our newest
local HELLO_GAP = 120
local HELLO_EVERY = 20 * 60
local MAX_DUMP_RAIDS = 30   -- a first-time catch-up brings this many recent raid nights

local Sync = { queue = {}, sent = 0, recv = 0, applied = 0, officers = {}, helloAt = 0 }
PGM.Sync = Sync

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
end

-- ============================================================
-- SMALL PIECES
-- ============================================================

local function store()
    local g = PGM.GuildDB(true)
    if not g then return nil end
    g.sync = g.sync or {}
    local s = g.sync
    s.newest = s.newest or 0
    s.teamDel = s.teamDel or {}
    s.raidDel = s.raidDel or {}
    s.alias = s.alias or {}
    s.joinU = s.joinU or {}
    g.linkU = g.linkU or {}
    g.users = g.users or {}
    g.claims = g.claims or {}
    g.claimU = g.claimU or {}
    return g, s
end

local function enabled()
    return IsInGuild() and PGM.opt("syncEnabled") ~= false
        and C_ChatInfo and C_ChatInfo.SendAddonMessage ~= nil
end

-- Our clock is the server's, so everyone agrees; a record from the future
-- (a bad clock, or a hostile one) is pulled back so it can't win forever.
local function clampU(u)
    u = tonumber(u)
    if not u or u <= 0 then return nil end
    return math.floor(math.min(u, PGM.Now() + SKEW))
end

local function bump(u)
    local _, s = store()
    if s and u and u > s.newest then s.newest = u end
end

local function clean(text)
    return ((text or ""):gsub("[%z\031]", ""))
end

local function isGuid(v)
    return type(v) == "string" and v:match("^Player%-%d+%-%x+$") ~= nil
end

-- "Name-Realm" made comparable: no spaces or punctuation, lower case.
local function norm(full)
    return ((full or ""):gsub("[%s%p]", "")):lower()
end

local function myFullName()
    local name, realm = UnitFullName("player")
    name, realm = P(name), P(realm)
    if not name then return nil end
    realm = realm or (GetNormalizedRealmName and GetNormalizedRealmName()) or ""
    return name .. "-" .. realm
end

-- The roster record of whoever sent a message, or nil. The name index is
-- rebuilt after each roster read.
local byName
PGM:On("ROSTER", function() byName = nil end)
local function senderRec(sender)
    local g = PGM.GuildDB()
    if not (g and sender) then return nil end
    if not byName then
        byName = {}
        for _, rec in pairs(g.members) do
            if rec.name then byName[norm(rec.name)] = rec end
        end
    end
    if not sender:find("-", 1, true) then
        sender = sender .. "-" .. ((GetNormalizedRealmName and GetNormalizedRealmName()) or "")
    end
    return byName[norm(sender)]
end

-- ============================================================
-- OFFICERS
-- ============================================================

local OFFICER_WORDS = { "officer", "leader", "guild master", "gm" }

-- Does this member's rank count as an officer?
function PGM:IsOfficerRec(rec)
    if not (rec and rec.rankIndex) then return false end
    if rec.rankIndex == 0 then return true end
    local g = PGM.GuildDB()
    local cut = g and g.sync and g.sync.officerRank
    if cut then return rec.rankIndex <= cut end
    local name = (rec.rank or ""):lower()
    for _, w in ipairs(OFFICER_WORDS) do
        if name:find(w, 1, true) then return true end
    end
    return false
end

-- May I edit shared things (raid teams, raid nights, alt links)?
function PGM:CanEdit()
    local g = PGM.GuildDB()
    local me = g and g.members[PGM:MyGuid() or ""]
    return PGM:IsOfficerRec(me)
end

function PGM:IsGuildMaster()
    local g = PGM.GuildDB()
    local me = g and g.members[PGM:MyGuid() or ""]
    return me ~= nil and me.rankIndex == 0
end

-- ============================================================
-- OUTBOUND
-- ============================================================

-- Inside an instance (or any chat lockdown) messages can't go out; they wait.
local function blocked()
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
        local ok, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
        if ok and P(locked) then return true end
    end
    local inInstance, kind = IsInInstance()
    return P(inInstance) and (P(kind) == "raid" or P(kind) == "party") or false
end

-- Two queues: live edits go first; bulk work (an import, a catch-up) only
-- uses the gaps, so an officer's change never waits behind 300 join dates.
Sync.bulk = {}

local ticker
local function pump()
    if blocked() then return end
    local q = #Sync.queue > 0 and Sync.queue or Sync.bulk
    local msg = table.remove(q, 1)
    if not msg then
        if ticker then ticker:Cancel() ticker = nil end
        return
    end
    local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, "GUILD")
    if ok and Enum and Enum.SendAddonMessageResult
        and result == Enum.SendAddonMessageResult.AddonMessageThrottle then
        table.insert(q, 1, msg)   -- the allowance refills; try again next tick
        return
    end
    if ok then Sync.sent = Sync.sent + 1 end
end

local function enqueue(msg, bulk)
    if not enabled() then return end
    if #msg > 255 then
        PGM.Debug("sync: oversized record dropped", #msg)
        return
    end
    local q = bulk and Sync.bulk or Sync.queue
    q[#q + 1] = msg
    if not ticker then
        ticker = C_Timer.NewTicker(SEND_GAP, pump)
        pump()
    end
end

-- While a catch-up is being sent, everything it sends is bulk too.
local bulkMode = false
-- For other modules: queue a record (fields joined like every other record).
function PGM.SyncSend(bulk, ...)
    enqueue(table.concat({ ... }, SEP), bulk)
end
PGM.SyncNorm = norm
function PGM.SyncIsMe(name)
    return norm(name) == norm(myFullName())
end

local function send(...)
    enqueue(table.concat({ ... }, SEP), bulkMode)
end

-- Packs many small records of one kind into as few messages as fit:
-- { {a, b, c}, {a, b, c} } -> "1A" a b c a b c ..., each under 250 bytes.
local function sendPacked(kind, rows, bulk)
    local parts, size = { kind }, #kind
    for _, row in ipairs(rows) do
        local piece = table.concat(row, SEP)
        if #parts > 1 and size + #SEP + #piece > 250 then
            enqueue(table.concat(parts, SEP), bulk)
            parts, size = { kind }, #kind
        end
        parts[#parts + 1] = piece
        size = size + #SEP + #piece
    end
    if #parts > 1 then enqueue(table.concat(parts, SEP), bulk) end
end

function PGM:SyncQueued()
    return #Sync.queue + #Sync.bulk
end

-- Fits text into what's left of the 255 bytes after the other fields.
local function fit(text, used)
    text = clean(text)
    local room = 250 - used
    if room <= 0 then return "" end
    return #text > room and text:sub(1, room) or text
end

-- ---- record senders ----

local function sendTeam(t)
    -- Fixed fields, the separators still to come, and the 1-byte auto flag.
    local used = #table.concat({ "1T", t.id, t.u or 0 }, SEP) + 4 * #SEP + 1
    local name = fit(t.name, used)
    local schedule = fit(t.schedule, used + #name)
    local tags = fit(t.tags, used + #name + #schedule)
    send("1T", t.id, t.u or 0, name, schedule, tags, t.autoSync and "1" or "0")
end

local function sendSpot(t, guid)
    local e = t.members[guid]
    if e then
        send("1M", t.id, guid, e.u or 0, "i", e.role or "DPS", e.status or "core")
    elseif t.removed and t.removed[guid] then
        send("1M", t.id, guid, t.removed[guid], "x", "", "")
    end
end

local function linkRow(g, guid)
    local v = g.links[guid]
    return { guid, g.linkU[guid] or 0, v == false and "0" or (v or "") }
end

local function sendLink(g, guid)
    sendPacked("1A", { linkRow(g, guid) }, bulkMode)
end

local function sendRaid(s)
    local fixed = table.concat({ "1S", s.id, s.u or 0, s.start or 0, s.stop or 0, s.instance or 0,
        s.diffID or 0, s.team or "", s.teamU or 0 }, SEP)
    local name = fit(s.name or "Raid", #fixed + 2)
    local bosses = fit(table.concat(s.bosses or {}, ";"), #fixed + #name + 2)
    send("1S", s.id, s.u or 0, s.start or 0, s.stop or 0, s.instance or 0, s.diffID or 0,
        s.team or "", s.teamU or 0, name, bosses)
    -- Attendees in as many records as it takes; each one only adds.
    local batch, size = {}, #("1P" .. SEP .. s.id .. SEP)
    for guid in pairs(s.present or {}) do
        if size + #guid + 1 > 250 then
            send("1P", s.id, table.concat(batch, ","))
            batch, size = {}, #("1P" .. SEP .. s.id .. SEP)
        end
        batch[#batch + 1] = guid
        size = size + #guid + 1
    end
    if #batch > 0 then send("1P", s.id, table.concat(batch, ",")) end
end

local function teamById(id)
    local g = PGM.GuildDB()
    for _, t in ipairs(g and g.teams or {}) do
        if t.id == id then return t end
    end
end

-- ---- what the rest of the addon calls when an officer changes something ----

function PGM:SyncTeam(t)
    t.u = PGM.Stamp(t.u)
    bump(t.u)
    sendTeam(t)
end

-- The spot's stamp moves past whatever it was last (its add or its removal).
function PGM:SyncSpot(t, guid)
    local u
    if t.members[guid] then
        u = PGM.Stamp(t.members[guid].u)
        t.members[guid].u = u
    elseif t.removed and t.removed[guid] then
        u = PGM.Stamp(t.removed[guid])
        t.removed[guid] = u
    end
    if not u then return end
    bump(u)
    sendSpot(t, guid)
end

function PGM:SyncTeamDeleted(id)
    local _, s = store()
    if not s then return end
    local t = teamById(id)
    local now = PGM.Stamp(t and t.u)
    s.teamDel[id] = now
    bump(now)
    send("1K", id, now)
end

function PGM:SyncLink(guid)
    local g = store()
    if not g then return end
    g.linkU[guid] = PGM.Stamp(g.linkU[guid])
    bump(g.linkU[guid])
    sendLink(g, guid)
end

-- Many links at once (an import): stamped, packed, sent at low priority.
function PGM:SyncLinks(guids)
    local g = store()
    if not g then return end
    local rows = {}
    for _, guid in ipairs(guids) do
        g.linkU[guid] = PGM.Stamp(g.linkU[guid])
        bump(g.linkU[guid])
        rows[#rows + 1] = linkRow(g, guid)
    end
    sendPacked("1A", rows, true)
end

function PGM:SyncRaid(s)
    s.u = PGM.Stamp(s.u)
    bump(s.u)
    sendRaid(s)
end

function PGM:SyncRaidDeleted(id)
    local _, s = store()
    if not s then return end
    local now = PGM.Now()
    s.raidDel[id] = now
    bump(now)
    send("1D", id, now)
end

-- Join dates an officer knows (from GRM, say) go to everyone: stamped,
-- packed, sent at low priority.
function PGM:SyncJoins(guids)
    local g, s = store()
    if not g then return end
    local rows = {}
    for _, guid in ipairs(guids) do
        local rec = g.members[guid]
        if rec and rec.joined then
            s.joinU[guid] = PGM.Stamp(s.joinU[guid])
            bump(s.joinU[guid])
            rows[#rows + 1] = { guid, s.joinU[guid], rec.joined }
        end
    end
    sendPacked("1J", rows, true)
end

-- Tell the guild which character is this account's main. Each character
-- speaks only for itself, so every alt needs logging in once; a main says
-- it's a main, which is what lets its alts' claims count. Sent once a
-- session and whenever the main changes. Claims don't move `newest`: every
-- character repeats its own each login, so they never need a catch-up.
function PGM:SyncMyMain()
    local g = store()
    local me = PGM:MyGuid()
    if not (g and me and g.members[me] and enabled()) then return end
    local main = PGM:AccountMain(g.members) or me
    if g.claims[me] ~= main or not g.claimU[me] then
        g.claims[me] = main
        g.claimU[me] = PGM.Stamp(g.claimU[me])
        PGM:RebuildAlts()
    end
    sendPacked("1B", { { me, g.claimU[me], main } }, false)
end

function PGM:SyncOfficerRank(rank)
    local _, s = store()
    if not s then return end
    s.officerRank = rank
    s.cfgU = PGM.Stamp(s.cfgU)
    bump(s.cfgU)
    send("1C", s.cfgU, rank or "")
end

-- ============================================================
-- CATCH-UP
-- ============================================================

local function sendHello()
    local _, s = store()
    if not (s and enabled()) then return end
    Sync.helloAt = GetTime()
    Sync.versionAt = GetTime()
    send("1H", s.newest, PGM.VERSION)
end
PGM.SyncNow = sendHello

-- Everything newer than `since`, onto the guild channel, then "E".
local function dump(target, since)
    local g, s = store()
    if not g then return end
    bulkMode = true
    local n = 0
    if (s.cfgU or 0) > since then send("1C", s.cfgU, s.officerRank or "") n = n + 1 end
    for _, t in ipairs(g.teams or {}) do
        if (t.u or 0) > since then sendTeam(t) n = n + 1 end
        for guid, e in pairs(t.members) do
            if (e.u or 0) > since then sendSpot(t, guid) n = n + 1 end
        end
        for guid, u in pairs(t.removed or {}) do
            if type(u) == "number" and u > since then sendSpot(t, guid) n = n + 1 end
        end
    end
    for id, u in pairs(s.teamDel) do
        if u > since then send("1K", id, u) n = n + 1 end
    end
    local links = {}
    for guid, u in pairs(g.linkU) do
        if u > since and g.links[guid] ~= nil then links[#links + 1] = linkRow(g, guid) n = n + 1 end
    end
    sendPacked("1A", links, true)
    local sessions = g.raids and g.raids.sessions or {}
    local sent = 0
    for i = #sessions, 1, -1 do
        local r = sessions[i]
        if sent >= MAX_DUMP_RAIDS then break end
        if r.id and (r.u or 0) > since then
            sendRaid(r)
            sent, n = sent + 1, n + 1
        end
    end
    for id, u in pairs(s.raidDel) do
        if u > since then send("1D", id, u) n = n + 1 end
    end
    local joins = {}
    for guid, u in pairs(s.joinU) do
        local rec = g.members[guid]
        if u > since and rec and rec.joined then joins[#joins + 1] = { guid, u, rec.joined } n = n + 1 end
    end
    sendPacked("1J", joins, true)
    local claims = {}
    for guid, u in pairs(g.claimU) do
        if u > since and g.claims[guid] then claims[#claims + 1] = { guid, u, g.claims[guid] } n = n + 1 end
    end
    sendPacked("1B", claims, true)
    send("1E", target, n, s.newest)   -- bulk too, so it arrives after what it follows
    bulkMode = false
end

-- ============================================================
-- INBOUND
-- ============================================================

local dirty = {}
local function changed(what)
    if dirty[what] then return end
    dirty[what] = true
    C_Timer.After(1, function()
        dirty[what] = nil
        if what == "ROSTER" and PGM.RebuildAlts then PGM:RebuildAlts() end
        PGM:Fire(what)
    end)
end

local function applied(u)
    Sync.applied = Sync.applied + 1
    Sync.lastApplied = PGM.Now()
    bump(u)
end

-- A team we hear about before its details: a placeholder they'll fill.
local function ensureTeam(id)
    local g, s = store()
    if not g or (s.teamDel[id]) then return nil end
    local t = teamById(id)
    if not t then
        g.teams = g.teams or {}
        t = { id = id, name = "Raid team", schedule = "", tags = "", members = {}, removed = {}, u = 0 }
        table.insert(g.teams, t)
    end
    t.removed = t.removed or {}
    return t
end

-- The local raid night a remote one is: same id, a known alias, or the same
-- instance within three hours (two officers recorded the same night).
local function findRaid(id, instance, start)
    local g, s = store()
    local sessions = g.raids and g.raids.sessions or {}
    local localId = s.alias[id] or id
    for _, r in ipairs(sessions) do
        if r.id == localId then return r end
    end
    if instance and start then
        for _, r in ipairs(sessions) do
            if r.instance and r.instance == instance and math.abs((r.start or 0) - start) < 3 * 3600 then
                if r.id ~= id then s.alias[id] = r.id end
                return r
            end
        end
    end
end

local handlers = {}
-- Other modules (Activity.lua) add their own record types here. Records they
-- add aren't in WRITES, so any guild member's copy may send them.
PGM.SyncHandlers = handlers

function handlers.T(f)
    local id, u = f[2], clampU(f[3])
    local _, s = store()
    if not (id and u) or (s.teamDel[id] or 0) >= u then return end
    local t = ensureTeam(id)
    if t and u > (t.u or 0) then
        t.u, t.name, t.schedule, t.tags = u, f[4] ~= "" and f[4] or t.name, f[5] or "", f[6] or ""
        t.autoSync = f[7] == "1" or nil
        applied(u)
        changed("TEAMS")
    end
end

function handlers.K(f)
    local id, u = f[2], clampU(f[3])
    local g, s = store()
    if not (id and u) or (s.teamDel[id] or 0) >= u then return end
    local t = teamById(id)
    if t and (t.u or 0) > u then return end   -- recreated after that deletion
    s.teamDel[id] = u
    for i, tt in ipairs(g.teams or {}) do
        if tt.id == id then table.remove(g.teams, i) break end
    end
    for _, r in ipairs(g.raids and g.raids.sessions or {}) do
        if r.team == id then r.team = nil end
    end
    applied(u)
    changed("TEAMS")
end

function handlers.M(f)
    local id, guid, u, state = f[2], f[3], clampU(f[4]), f[5]
    local g = PGM.GuildDB()
    if not (id and isGuid(guid) and u) or not (g.members[guid] or g.former[guid]) then return end
    local t = ensureTeam(id)
    if not t then return end
    local cur = (t.members[guid] and t.members[guid].u) or (type(t.removed[guid]) == "number" and t.removed[guid]) or 0
    if u <= cur then return end
    if state == "i" then
        local role = PGM.ROLE_LABEL[f[6]] and f[6] or "DPS"
        local status = PGM.STATUS_LABEL[f[7]] and f[7] or "core"
        t.members[guid] = { role = role, status = status, added = (t.members[guid] and t.members[guid].added) or u, u = u }
        t.removed[guid] = nil
    elseif state == "x" then
        t.members[guid] = nil
        t.removed[guid] = u
    else
        return
    end
    applied(u)
    changed("TEAMS")
end

local function applyLink(g, guid, u, main)
    u = clampU(u)
    main = main or ""
    if not (isGuid(guid) and u) or not g.members[guid] then return end
    if u <= (g.linkU[guid] or 0) then return end
    if main == "0" then
        g.links[guid] = false
    elseif main == "" then
        g.links[guid] = nil
    elseif isGuid(main) and g.members[main] and main ~= guid then
        g.links[guid] = main
    else
        return
    end
    g.linkU[guid] = u
    applied(u)
    changed("ROSTER")
end

function handlers.A(f)
    local g = store()
    for i = 2, #f, 3 do applyLink(g, f[i], f[i + 1], f[i + 2]) end
end

function handlers.S(f)
    local id, u = f[2], clampU(f[3])
    local start, stop = tonumber(f[4]), tonumber(f[5])
    local instance, diffID = tonumber(f[6]), tonumber(f[7])
    local team, teamU = f[8] ~= "" and f[8] or nil, clampU(f[9]) or 0
    if not (id and u and start and stop) then return end
    local g, s = store()
    if (s.raidDel[id] or 0) >= u then return end
    g.raids = g.raids or { sessions = {} }
    g.raids.sessions = g.raids.sessions or {}
    local r = findRaid(id, instance, start)
    if not r then
        r = { id = id, start = start, stop = stop, instance = instance, diffID = diffID,
              name = f[10] ~= "" and f[10] or "Raid", present = {}, bosses = {}, u = 0, teamU = 0 }
        -- Keep the list in time order.
        local at = #g.raids.sessions + 1
        for i, other in ipairs(g.raids.sessions) do
            if (other.start or 0) > start then at = i break end
        end
        table.insert(g.raids.sessions, at, r)
    end
    r.start = math.min(r.start or start, start)
    r.stop = math.max(r.stop or stop, stop)
    r.instance = r.instance or instance
    for boss in (f[11] or ""):gmatch("[^;]+") do
        if not tContains(r.bosses, boss) then table.insert(r.bosses, boss) end
    end
    if teamU > (r.teamU or 0) then r.team, r.teamU = team, teamU end
    r.u = math.max(r.u or 0, u)
    applied(u)
    changed("RAIDS")
end

function handlers.P(f)
    local id = f[2]
    local g, s = store()
    local localId = s.alias[id] or id
    local r
    for _, x in ipairs(g.raids and g.raids.sessions or {}) do
        if x.id == localId then r = x break end
    end
    if not r then return end
    local added = 0
    for guid in (f[3] or ""):gmatch("[^,]+") do
        if isGuid(guid) and (g.members[guid] or g.former[guid]) and not r.present[guid] then
            r.present[guid] = true
            added = added + 1
        end
    end
    if added > 0 then
        local n = 0
        for _ in pairs(r.present) do n = n + 1 end
        r.count = n
        changed("RAIDS")
    end
end

function handlers.D(f)
    local id, u = f[2], clampU(f[3])
    local g, s = store()
    if not (id and u) or (s.raidDel[id] or 0) >= u then return end
    s.raidDel[id] = u
    local localId = s.alias[id] or id
    for i, r in ipairs(g.raids and g.raids.sessions or {}) do
        if r.id == localId then table.remove(g.raids.sessions, i) break end
    end
    applied(u)
    changed("RAIDS")
end

function handlers.J(f)
    local g, s = store()
    for i = 2, #f, 3 do
        local guid, u, joined = f[i], clampU(f[i + 1]), tonumber(f[i + 2])
        local rec = isGuid(guid) and g.members[guid]
        -- A join date can't be in the future.
        if rec and u and joined and u > (s.joinU[guid] or 0) and joined <= PGM.Now() + SKEW then
            rec.joined = joined
            s.joinU[guid] = u
            applied(u)
            changed("ROSTER")
        end
    end
end

-- A player about their own character, or an officer relaying claims in a
-- catch-up. Anything else about someone else's character is ignored.
function handlers.B(f, sender, rec)
    if not rec then return end
    local g = store()
    local relay = PGM:IsOfficerRec(rec)
    for i = 2, #f, 3 do
        local guid, u, main = f[i], clampU(f[i + 1]), f[i + 2]
        if (guid == rec.guid or relay) and isGuid(guid) and isGuid(main) and u
            and g.members[guid] and g.members[main] and u > (g.claimU[guid] or 0) then
            g.claims[guid] = main
            g.claimU[guid] = u
            Sync.applied = Sync.applied + 1
            Sync.lastApplied = PGM.Now()
            changed("ROSTER")
        end
    end
end

function handlers.C(f, sender, rec)
    if not (rec and rec.rankIndex == 0) then return end   -- the guild master's call alone
    local u = clampU(f[2])
    local _, s = store()
    if not u or u <= (s.cfgU or 0) then return end
    s.officerRank = tonumber(f[3])
    s.cfgU = u
    applied(u)
    changed("ROSTER")
end

-- ---- catch-up choreography ----

local offerTimer, pickTimer
local offers = {}

-- Who runs the addon, and which version. Kept between sessions.
local function noteUser(rec, version)
    local g = PGM.GuildDB()
    if not (g and rec and rec.guid) then return end
    g.users = g.users or {}
    local u = g.users[rec.guid] or {}
    -- Versions before 0.4.0 didn't say theirs.
    u.v = (version and version ~= "") and clean(version):sub(1, 16) or u.v or "0.3"
    u.seen = PGM.Now()
    g.users[rec.guid] = u
    changed("SYNC")
end

-- Answer a hello with our version, at most once every five minutes and
-- after a random wait, so a crowded login doesn't become a flood.
local versionTimer
local function answerVersion()
    if versionTimer or GetTime() - (Sync.versionAt or -1000) < 300 then return end
    versionTimer = C_Timer.NewTimer(2 + math.random() * 10, function()
        versionTimer = nil
        Sync.versionAt = GetTime()
        send("1V", PGM.VERSION)
    end)
end

function handlers.V(f, sender, rec)
    noteUser(rec, f[2])
end

function handlers.H(f, sender, rec)
    local theirs = tonumber(f[2]) or 0
    local _, s = store()
    noteUser(rec, f[3])
    answerVersion()
    -- I'm behind them: say hello myself, so an officer catches me up. Any
    -- gap counts: the same data means the same newest, and a catch-up ends
    -- by bringing the two level (see E), so this can't repeat forever.
    if theirs > s.newest and GetTime() - Sync.helloAt > HELLO_GAP then
        C_Timer.After(2 + math.random() * 4, sendHello)
    end
    -- I'm an officer and ahead of them: offer, unless someone beats me to it.
    if PGM:CanEdit() and s.newest > theirs then
        if offerTimer then offerTimer:Cancel() end
        Sync.offerFor, Sync.offerNewest = sender, s.newest
        offerTimer = C_Timer.NewTimer(1 + math.random() * 4, function()
            offerTimer = nil
            send("1O", sender, s.newest)
        end)
    end
end

function handlers.O(f, sender, rec)
    local target, theirs = f[2], tonumber(f[3]) or 0
    -- Someone else offered the same player at least as much: stand down.
    if offerTimer and Sync.offerFor and norm(target) == norm(Sync.offerFor) and theirs >= (Sync.offerNewest or 0) then
        offerTimer:Cancel()
        offerTimer = nil
    end
    -- An offer to me, from an officer: gather them for a few seconds, take the best.
    if norm(target) == norm(myFullName()) and PGM:IsOfficerRec(rec) then
        offers[#offers + 1] = { sender = sender, newest = theirs }
        if not pickTimer then
            pickTimer = C_Timer.NewTimer(4, function()
                pickTimer = nil
                table.sort(offers, function(a, b) return a.newest > b.newest end)
                local best = offers[1]
                wipe(offers)
                local _, s = store()
                if best and s then send("1R", best.sender, math.max(0, s.newest - OVERLAP)) end
            end)
        end
    end
end

function handlers.R(f, sender)
    local target, since = f[2], tonumber(f[3]) or 0
    if norm(target) == norm(myFullName()) and PGM:CanEdit() then
        dump(sender, since)
    end
end

function handlers.E(f, sender, rec)
    if norm(f[2]) == norm(myFullName()) then
        -- I now hold everything that officer had (a record I couldn't use,
        -- like a spot for someone not in my roster, included), so I'm as
        -- current as they are. Otherwise we'd keep catching up forever.
        if PGM:IsOfficerRec(rec) then bump(clampU(f[4])) end
        Sync.lastCatchUp = PGM.Now()
        Sync.lastFrom = sender
        changed("SYNC")
    end
end

-- Records that write shared data: officers only. "C" is checked inside
-- (guild master only). H/O/R/E are control messages, open to everyone.
local WRITES = { T = true, K = true, M = true, A = true, S = true, P = true, D = true, J = true }

local frame = CreateFrame("Frame")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:SetScript("OnEvent", function(_, _, prefix, msg, channel, sender)
    prefix, msg, channel, sender = P(prefix), P(msg), P(channel), P(sender)
    if prefix ~= PREFIX or channel ~= "GUILD" or not (msg and sender) then return end
    if not enabled() then return end
    if norm(sender) == norm(myFullName()) then return end
    local g = PGM.GuildDB()
    if not (g and g.seeded) then return end
    Sync.recv = Sync.recv + 1
    local f = { strsplit(SEP, msg) }
    local head = f[1] or ""
    if head:sub(1, 1) ~= "1" then return end   -- a newer protocol than ours
    local kind = head:sub(2, 2)
    local h = handlers[kind]
    if not h then return end
    local rec = senderRec(sender)
    if rec then Sync.officers[sender] = PGM:IsOfficerRec(rec) and PGM.Now() or nil end
    if WRITES[kind] and not PGM:IsOfficerRec(rec) then
        PGM.Debug("sync: ignored", kind, "from non-officer", sender)
        return
    end
    local ok, err = pcall(h, f, sender, rec)
    if not ok then PGM.Debug("sync: error in", kind, err) end
end)

-- ============================================================
-- SESSION
-- ============================================================

-- Once the roster has been read (so we can tell who's an officer), say hello,
-- and again every 20 minutes in case anything was missed.
local started = false
PGM:On("ROSTER", function()
    if started then return end
    local g = PGM.GuildDB()
    if not (g and g.seeded) then return end
    started = true
    -- Count ourselves among the people running it.
    local me = g.members[PGM:MyGuid() or ""]
    if me then
        g.users = g.users or {}
        g.users[me.guid] = { v = PGM.VERSION, seen = PGM.Now() }
    end
    C_Timer.After(8, sendHello)
    C_Timer.NewTicker(HELLO_EVERY, sendHello)
    C_Timer.After(15, function() PGM:SyncMyMain() end)
    -- Before 0.7.1 a team's rename, schedule, tags and "Keep in sync" stayed
    -- on the officer's own copy, and didn't change the team's stamp. So once,
    -- the copy that created each team (only it has `created`) re-shares it
    -- one tick newer than that stamp: enough to beat everyone's placeholder,
    -- which has the same stamp, never enough to beat a real edit since.
    C_Timer.After(25, function()
        local _, s = store()
        if not s or s.resent071 or not PGM:CanEdit() then return end
        s.resent071 = true
        for _, t in ipairs(g.teams or {}) do
            if t.created then
                t.u = (t.u or 0) + 1
                bump(t.u)
                sendTeam(t)
            end
        end
    end)
    -- Re-announce the officer cut-off so newcomers get it.
    C_Timer.After(12, function()
        local _, s = store()
        if PGM:IsGuildMaster() and s and s.cfgU then send("1C", s.cfgU, s.officerRank or "") end
    end)
end)

-- Records still waiting to go out when the game closes or reloads (a big
-- import takes a minute or more to send) are kept and sent next session.
-- Only data records: hellos and catch-up chatter would be stale by then.
-- Seeing a record twice changes nothing, so resending is always safe.
local KEEP = { T = true, K = true, M = true, A = true, S = true, P = true, D = true, J = true, C = true, B = true }
local MAX_PENDING = 300
local logout = CreateFrame("Frame")
logout:RegisterEvent("PLAYER_LOGOUT")
logout:SetScript("OnEvent", function()
    local g = PGM.GuildDB()
    if not (g and g.sync) then return end
    local keep = {}
    for _, q in ipairs({ Sync.queue, Sync.bulk }) do
        for _, msg in ipairs(q) do
            if #keep < MAX_PENDING and KEEP[msg:sub(2, 2)] then keep[#keep + 1] = msg end
        end
    end
    g.sync.pending = #keep > 0 and keep or nil
end)

PGM:On("ROSTER", function()
    local g = PGM.GuildDB()
    if Sync.resumed or not (g and g.seeded) then return end
    Sync.resumed = true
    C_Timer.After(20, function()
        local _, s = store()
        local pending = s and s.pending
        if not pending then return end
        s.pending = nil
        for _, msg in ipairs(pending) do enqueue(msg, true) end
    end)
end)

-- How many officers with the addon we've heard from in the last hour.
function PGM:SyncPeers()
    local n, now = 0, PGM.Now()
    for _, t in pairs(Sync.officers) do
        if now - t < 3600 then n = n + 1 end
    end
    return n
end

-- ============================================================
-- WHO HAS THE ADDON
-- ============================================================

-- "0.10.2" as comparable numbers; anything odd sorts as oldest.
local function versionParts(v)
    local a, b, c = tostring(v or ""):match("^(%d+)%.(%d+)%.?(%d*)")
    return tonumber(a) or 0, tonumber(b) or 0, tonumber(c) or 0
end

function PGM.NewerVersion(a, b)
    local a1, a2, a3 = versionParts(a)
    local b1, b2, b3 = versionParts(b)
    if a1 ~= b1 then return a1 > b1 end
    if a2 ~= b2 then return a2 > b2 end
    return a3 > b3
end

-- Members known to run the addon: { guid, rec, v, seen, outdated }, newest
-- version first. "Latest" is the newest anyone in the guild has.
function PGM:AddonUsers()
    local g = PGM.GuildDB()
    local out, latest = {}, PGM.VERSION
    for guid, u in pairs(g and g.users or {}) do
        local rec = g.members[guid]
        if rec then
            out[#out + 1] = { guid = guid, rec = rec, v = u.v, seen = u.seen }
            if PGM.NewerVersion(u.v, latest) then latest = u.v end
        end
    end
    for _, it in ipairs(out) do it.outdated = PGM.NewerVersion(latest, it.v) end
    table.sort(out, function(a, b)
        if a.rec.online ~= b.rec.online then return a.rec.online end
        return PGM.NameLess(a.rec.short, b.rec.short)
    end)
    return out, latest
end

function PGM:AddonUserOf(guid)
    local g = PGM.GuildDB()
    return g and g.users and g.users[guid]
end
