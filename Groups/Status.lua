-- Status.lua: who's free. Each copy says what its player is up to: free,
-- looking for a group (and which kinds), or in a group of some size. It says
-- so when that changes (at most once a minute) and every 10 minutes. Inside
-- an instance it can't say anything, so a status that's gone quiet for 15
-- minutes reads as "busy or away" rather than staying "free" for ever.
--
-- WIRE (inside "1G"):
--   S state size kinds role ilvl    state: f free, l looking, g in a group;
--                                   kinds: letters of G.KINDS; role: T/H/D

local _, NS = ...
local G = NS.G
local PGM = G.PGM

local GAP = 60
local EVERY = 10 * 60
local STALE = 15 * 60

G.status = {}   -- [guid] = { state, size, kinds, role, ilvl, at }

-- What I'd say about myself right now.
local function mine()
    local state, size = "f", 1
    if G.InGroup() then
        state, size = "g", G.GroupSize()
    elseif G.opt("looking") then
        state = "l"
    end
    local kinds = ""
    for _, k in ipairs(G.KINDS) do
        if G.opt("lookingKinds")[k] then kinds = kinds .. k end
    end
    local role = ""
    for _, r in ipairs(G.ROLES) do
        if G.MyRoles()[r] then role = role .. r end
    end
    return state, size, kinds, role, G.MyIlvl()
end

local lastSent, lastAt, timer = nil, 0, nil

local function send()
    local state, size, kinds, role, ilvl = mine()
    if G.Send(true, "S", state, size, kinds, role, ilvl) then
        lastSent, lastAt = table.concat({ state, size, kinds, role }, ","), GetTime()
    end
end

-- Say it if it changed, no more than once a minute.
function G:SendStatus(force)
    local state, size, kinds, role = mine()
    local now = table.concat({ state, size, kinds, role }, ",")
    if not force and now == lastSent then return end
    if timer then return end
    local wait = math.max(0, GAP - (GetTime() - lastAt))
    timer = C_Timer.NewTimer(wait, function()
        timer = nil
        send()
    end)
end

function G:SetLooking(on)
    G.setOpt("looking", on and true or false)
    G:SendStatus()
    G:Fire("STATUS")
end

function G:ToggleLookingKind(kind)
    local t = G.opt("lookingKinds")
    t[kind] = not t[kind]
    G:SendStatus()
    G:Fire("STATUS")
end

function G.handlers.S(f, sender, rec)
    local state = f[3]
    if state ~= "f" and state ~= "l" and state ~= "g" then return end
    G.status[rec.guid] = {
        state = state,
        size = tonumber(f[4]) or 1,
        kinds = G.Clean(f[5], 4),
        role = G.Clean(f[6], 3),
        ilvl = tonumber(f[7]) or 0,
        at = GetTime(),
    }
    G:Fire("STATUS")
end

-- A newcomer asked what's going on ("Q", see Posts.lua): answer with my
-- status too, after a random wait, at most once every two minutes.
local answered = -1000
function G:AnswerStatus()
    if GetTime() - answered < 120 then return end
    answered = GetTime()
    C_Timer.After(2 + math.random() * 10, send)
end

-- ============================================================
-- WHO'S FREE
-- ============================================================

-- The order states sort in, and their names.
G.STATE_ORDER = { l = 1, f = 2, g = 3, b = 4, n = 5 }
G.STATE_LABEL = { l = "Looking", f = "Free", g = "In a group", b = "Busy or away", n = "No addon" }

-- Online guildies other than me: { guid, rec, state, st (their status) }.
function G:WhoList()
    local g = PGM.GuildDB()
    local out = {}
    if not g then return out end
    local me = PGM:MyGuid()
    local max = PGM.MaxLevel()
    local users = g.users or {}
    for guid, rec in pairs(g.members) do
        if rec.online and not rec.mobile and guid ~= me then
            local st = G.status[guid]
            local state
            if st and GetTime() - st.at < STALE then
                state = st.state
            elseif st or users[guid] then
                state = "b"
            else
                state = "n"
            end
            local keep = (not G.opt("freeMaxOnly") or (rec.level or 0) >= max)
                and (not G.opt("freeAddonOnly") or state ~= "n")
            if keep then
                out[#out + 1] = { guid = guid, rec = rec, state = state, st = st }
            end
        end
    end
    table.sort(out, function(a, b)
        local oa, ob = G.STATE_ORDER[a.state], G.STATE_ORDER[b.state]
        if oa ~= ob then return oa < ob end
        return PGM.NameLess(a.rec.short, b.rec.short)
    end)
    return out
end

-- ============================================================
-- WHEN
-- ============================================================

G:On("READY", function()
    C_Timer.After(12, function() G:SendStatus(true) end)
    G.Every(EVERY, function() G:SendStatus(true) end)
end)

G:RegisterEvent("GROUP_ROSTER_UPDATE", function() G:SendStatus() end)
G:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", function(_, unit)
    if unit == "player" then G:SendStatus() end
end)
G:RegisterEvent("PLAYER_ENTERING_WORLD", function()
    C_Timer.After(6, function() G:SendStatus(true) end)
end)
-- Offline guildies drop off the list.
G:OnPGM("ROSTER", function()
    local g = PGM.GuildDB()
    for guid in pairs(G.status) do
        local rec = g and g.members[guid]
        if not (rec and rec.online) then G.status[guid] = nil end
    end
end)
