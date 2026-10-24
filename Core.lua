-- Core.lua: namespace, saved data, the "G" sync record, and the small
-- helpers every other file uses.
--
-- This is a module of Pandy Guild Management (PGM): it uses PGM's roster,
-- alts, teams, scores, window and guild sync, through the functions PGM's
-- README lists as stable. All guild traffic is one PGM record letter, "G",
-- with a sub-type in the second field (see DESIGN.md for the table).
--
-- Everything the game hands us goes through PGM.Plain first, as in PGM: a
-- Secret Value becomes nil, and nothing secret is compared or saved.

local ADDON, NS = ...
local PGM = PandyGuildManagement

local G = {}
NS.G = G
PandyGuildGroups = G

G.NAME = "Pandy Guild Groups"
G.VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata(ADDON, "Version")) or "dev"
G.PGM = PGM

-- An older PGM without module support (or a newer API than ours): stay off.
G.ok = PGM ~= nil and PGM.RegisterModule ~= nil and PGM.SyncRegister ~= nil
    and PGM.RegisterModule({ name = G.NAME, version = G.VERSION, api = 1, slash = "/pgg" })
if not G.ok then
    if PGM and not PGM.RegisterModule then
        print("|cff55d194Pandy|r Guild Groups needs Pandy Guild Management 0.9.0 or newer.")
    end
    return
end

local P = PGM.Plain
local SEP = "\031"

-- Roles, as one letter on the wire and PGM's role names on screen.
G.ROLES = { "T", "H", "D" }
G.ROLE_KEY = { T = "TANK", H = "HEALER", D = "DPS" }
G.ROLE_OF = { TANK = "T", HEALER = "H", DAMAGER = "D", DPS = "D" }

-- What a post can be, with the size and roles it starts from.
G.KINDS = { "M", "R", "D", "O" }
G.KIND_LABEL = { M = "Mythic+", R = "Raid", D = "Delve", O = "Other" }
G.KIND_ICON = {
    M = "Interface\\Icons\\INV_Relics_Hourglass",
    R = "Interface\\Icons\\Achievement_Boss_Ragnaros",
    D = "Interface\\Icons\\INV_Misc_Map_01",
    O = "Interface\\Icons\\INV_Misc_GroupNeedMore",
}
G.KIND_SIZE = { M = 5, R = 20, D = 5, O = 5 }
G.KIND_NEED = { M = { T = 1, H = 1, D = 3 }, R = { T = 2, H = 4, D = 14 }, D = { T = 1, H = 1, D = 3 },
                O = { T = 1, H = 1, D = 3 } }

local DEFAULTS = {
    ping = true,
    pingKinds = { M = true, R = true, D = true, O = true },
    roles = {},             -- roles I'll play; empty means "my spec's"
    guildFirst = 5,         -- minutes before Find PuGs lights up
    shareListing = true,    -- post my Group Finder listing to the guild
    looking = false,        -- "I'm up for a group"
    lookingKinds = { M = true, R = false, D = true, O = false },
    freeMaxOnly = true,
    freeAddonOnly = false,
    keysSort = "level",
    keysReverse = false,
    keysOnline = true,
    keysPinMine = false,    -- Mine first (was keysMineFirst, on by default)
    -- Tell the guild: {key} is the keystone link (or what the group is),
    -- {needs} the roles still open, {name} your character.
    announce = "{key} - needs {needs}. Whisper me to join!",
    -- The Groups page's Browse filters (playstyle unset means any).
    board = {
        guildFirst = true, guildOnly = false, scheduled = true, sort = "newest",
        keys = "", minRating = 0, skip = {},   -- skip: dungeons unticked in the list
        fitsMe = false, hideDeclined = true, brez = false, lust = false,
        needTank = false, needHealer = false, needDps = false, hasTank = false, hasHealer = false,
    },
}

local function fillDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            fillDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

-- ============================================================
-- SAVED DATA
-- ============================================================

function G.opt(key)
    return PandyGuildGroupsDB and PandyGuildGroupsDB.settings[key]
end

function G.setOpt(key, value)
    PandyGuildGroupsDB.settings[key] = value
end

-- This guild's saved table, filed under PGM's guild key.
function G.DB()
    local key = PGM.GuildKey()
    if not (key and PandyGuildGroupsDB) then return nil end
    local d = PandyGuildGroupsDB.guilds[key]
    if not d then
        d = { keys = {}, sched = {}, closed = {} }
        PandyGuildGroupsDB.guilds[key] = d
    end
    return d
end

-- ============================================================
-- HELPERS
-- ============================================================

-- Text from another player, safe to show and to send: no separators, no
-- escape codes (a "|T" in a note would draw a texture), trimmed to fit.
function G.Clean(text, max)
    text = tostring(text or ""):gsub("[%z\031|]", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if max and #text > max then text = text:sub(1, max) end
    return text
end

-- "Player-1234-0ABCDEF0" -> "1234-0ABCDEF0": post ids start with it.
function G.GuidTail(guid)
    return guid and guid:match("^Player%-(.+)$")
end

function G.MyName()
    local name, realm = UnitFullName("player")
    name, realm = P(name), P(realm)
    if not name then return nil end
    return name .. "-" .. (realm or (GetNormalizedRealmName and GetNormalizedRealmName()) or "")
end

function G.MyRec()
    local g = PGM.GuildDB()
    return g and g.members[PGM:MyGuid() or ""]
end

-- The roster record for "Name-Realm" (or a bare name on our realm).
local byName
PGM:On("ROSTER", function() byName = nil end)
function G.RecByName(name)
    local g = PGM.GuildDB()
    if not (g and name) then return nil end
    if not byName then
        byName = {}
        for _, rec in pairs(g.members) do
            if rec.name then byName[PGM.SyncNorm(rec.name)] = rec end
        end
    end
    if not name:find("-", 1, true) then
        name = name .. "-" .. ((GetNormalizedRealmName and GetNormalizedRealmName()) or "")
    end
    return byName[PGM.SyncNorm(name)]
end

-- A member's name, and "alt of Main" when we know it.
function G.WhoText(rec)
    if not rec then return "?" end
    local text = PGM.ColorName(rec)
    local main = PGM:KnownMain(rec.guid)
    local g = PGM.GuildDB()
    local m = main and g and g.members[main]
    if m then text = text .. PGM.Hex(PGM.C.text3) .. "  alt of |r" .. PGM.ColorName(m) end
    return text
end

-- ============================================================
-- M+ SCORES
-- ============================================================

-- Role icons from the game's role sheet, dimmed for a role that only
-- partly earned a score (RaiderIO's "partial").
local ROLE_COORDS = { T = "0:19:22:41", H = "20:39:1:20", D = "20:39:22:41" }
function G.RoleIcon(r, dim)
    local coords = ROLE_COORDS[r]
    if not coords then return "" end
    return "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:13:13:0:0:64:64:" .. coords
        .. (dim and ":110:110:110" or "") .. "|t"
end

local RIO_ROLE = { tank = "T", healer = "H", dps = "D" }

-- RaiderIO's roles list ({ {"dps","full"}, {"healer","partial"} }) as icons.
local function rioRoles(list)
    local out = ""
    for _, it in ipairs(type(list) == "table" and list or {}) do
        local r = type(it) == "table" and RIO_ROLE[it[1]]
        if r then out = out .. G.RoleIcon(r, it[2] ~= "full") end
    end
    return out
end

local function rioProfile(name, realm)
    if PGM.IS_FOREVER or not (name and RaiderIO and RaiderIO.GetProfile) then return nil end
    realm = ((realm and realm ~= "") and realm or (GetNormalizedRealmName and GetNormalizedRealmName()) or ""):gsub("%s+", "")
    local ok, profile = pcall(RaiderIO.GetProfile, name, realm)
    local mp = ok and type(profile) == "table" and profile.mythicKeystoneProfile
    return type(mp) == "table" and mp or nil
end

-- A character's M+ scores, like RaiderIO shows them: their own, their
-- main's and their warband's, each with the roles it was earned on.
-- live: the score the game itself gives (roster, applicant), preferred.
-- { char = { score, roles }, main = {...}, warband = {...} }; parts may be nil.
function G.Scores(name, realm, live)
    local mp = rioProfile(name, realm)
    local function part(t, fallback)
        local score = tonumber(fallback) or (type(t) == "table" and tonumber(t.score)) or 0
        if score <= 0 then return nil end
        return { score = math.floor(score + 0.5), roles = type(t) == "table" and rioRoles(t.roles) or "" }
    end
    live = tonumber(live)
    return {
        char = part(mp and mp.mplusCurrent, (live and live > 0) and live or nil),
        main = part(mp and mp.mplusMainCurrent),
        warband = part(mp and mp.mplusWarbandCurrent),
    }
end

-- "2650 [D][h]   Main 2900 [T]   Warband 3146 [D]". Main and warband show
-- only when they're higher than the character's own.
function G.ScoreLine(s)
    local own = s.char and s.char.score or 0
    local function piece(label, p)
        return (label and (PGM.Hex(PGM.C.text3) .. label .. "|r ") or "")
            .. PGM.Hex(PGM:ScoreColor(p.score)) .. p.score .. "|r" .. (p.roles ~= "" and (" " .. p.roles) or "")
    end
    local parts = {}
    parts[#parts + 1] = s.char and piece(nil, s.char) or (PGM.Hex(PGM.C.text3) .. "No M+ score|r")
    if s.main and s.main.score > own then parts[#parts + 1] = piece("Main", s.main) end
    if s.warband and s.warband.score > own then parts[#parts + 1] = piece("Warband", s.warband) end
    return table.concat(parts, "   ")
end

-- The score line for a guild member.
function G.ScoreText(rec)
    if not rec then return nil end
    return G.ScoreLine(G.Scores(rec.short, rec.realm, PGM:MPlusScore(rec)))
end

-- Score lines in a tooltip, one per kind, for hovering.
function G.AddScoreLines(tooltip, s)
    local function line(label, p)
        if p then
            tooltip:AddDoubleLine(label, PGM.Hex(PGM:ScoreColor(p.score)) .. p.score .. "|r " .. p.roles,
                0.7, 0.73, 0.77, 1, 1, 1)
        end
    end
    line("M+ score", s.char)
    line("Main's", s.main)
    line("Warband's", s.warband)
end

-- My spec's role letter (T, H or D), or D when the game won't say.
function G.SpecRole()
    if not (GetSpecialization and GetSpecializationRole) then return "D" end
    local ok, spec = pcall(GetSpecialization)
    spec = ok and P(spec) or nil
    if not spec then return "D" end
    local ok2, role = pcall(GetSpecializationRole, spec)
    return G.ROLE_OF[ok2 and P(role) or ""] or "D"
end

function G.SpecID()
    if not (GetSpecialization and GetSpecializationInfo) then return 0 end
    local ok, spec = pcall(GetSpecialization)
    spec = ok and P(spec) or nil
    if not spec then return 0 end
    local ok2, id = pcall(GetSpecializationInfo, spec)
    return (ok2 and P(id)) or 0
end

-- The roles I'll play: ticked in settings, or my spec's.
function G.MyRoles()
    local set, any = {}, false
    for _, r in ipairs(G.ROLES) do
        if G.opt("roles")[r] then set[r] = true any = true end
    end
    if not any then set[G.SpecRole()] = true end
    return set
end

function G.MyIlvl()
    if not GetAverageItemLevel then return 0 end
    local ok, _, equipped = pcall(GetAverageItemLevel)
    equipped = ok and P(equipped) or nil
    return equipped and math.floor(equipped) or 0
end

function G.InGroup()
    return P(IsInGroup()) and true or false
end

function G.GroupSize()
    if not G.InGroup() then return 1 end
    return P(GetNumGroupMembers()) or 1
end

function G.IsLeader()
    if not G.InGroup() then return true end
    return P(UnitIsGroupLeader("player")) and true or false
end

-- "Name-Realm" for each other member of my group.
function G.GroupNames()
    local out = {}
    if not G.InGroup() then return out end
    local raid = P(IsInRaid())
    local n = G.GroupSize()
    local myRealm = (GetNormalizedRealmName and GetNormalizedRealmName()) or ""
    for i = 1, raid and n or (n - 1) do
        local unit = (raid and "raid" or "party") .. i
        local name, realm = UnitName(unit)
        name, realm = P(name), P(realm)
        if name and not P(UnitIsUnit(unit, "player")) then
            local role = P(UnitGroupRolesAssigned(unit))
            out[#out + 1] = { name = name .. "-" .. ((realm and realm ~= "") and realm or myRealm),
                              role = G.ROLE_OF[role or ""] }
        end
    end
    return out
end

-- Role icons inline in text, when the client has them.
local ROLE_ICON = {
    T = INLINE_TANK_ICON, H = INLINE_HEALER_ICON, D = INLINE_DAMAGER_ICON,
}
function G.RoleText(r, withLabel)
    local key = G.ROLE_KEY[r]
    local col = PGM.ROLE_COLOR[key] or PGM.C.text
    local label = PGM.Hex(col) .. (PGM.ROLE_LABEL[key] or r) .. "|r"
    if ROLE_ICON[r] then return withLabel and (ROLE_ICON[r] .. " " .. label) or ROLE_ICON[r] end
    return label
end

-- "1 Tank  1 Healer  2 DPS" (only what's still needed), or "Full".
function G.NeedText(need, highlight)
    local parts = {}
    for _, r in ipairs(G.ROLES) do
        local n = need and need[r] or 0
        if n > 0 then
            local key = G.ROLE_KEY[r]
            local col = (highlight and highlight[r]) and PGM.C.text or (PGM.ROLE_COLOR[key] or PGM.C.text)
            local icon = ROLE_ICON[r] and (ROLE_ICON[r] .. " ") or ""
            parts[#parts + 1] = icon .. PGM.Hex(col) .. n .. " " .. PGM.ROLE_LABEL[key] .. "|r"
        end
    end
    if #parts == 0 then return PGM.Hex(PGM.C.text3) .. "Full|r" end
    return table.concat(parts, "  ")
end

-- Can anything reach the guild right now?
function G.CanTalk()
    return IsInGuild() and PGM.opt("syncEnabled") ~= false and not PGM.SyncBlocked()
end

function G.WhyNot()
    if not IsInGuild() then return "You're not in a guild." end
    if PGM.opt("syncEnabled") == false then return "Guild sync is off (Pandy Guild Management > Settings)." end
    return "Addons can't talk to the guild from inside an instance. Try again once you're out."
end

-- Send a "G" record now, or say why it can't go. quiet: don't say.
function G.Send(quiet, sub, ...)
    if not G.CanTalk() then
        if not quiet then PGM.Print(G.WhyNot()) end
        return false
    end
    PGM.SyncSend(false, "1G", sub, ...)
    return true
end

-- Many small rows of one sub-type, packed into as few messages as fit.
function G.SendPacked(bulk, sub, rows)
    if not G.CanTalk() then return end
    local head = "1G" .. SEP .. sub
    local parts, size = {}, #head
    local function flush()
        if #parts > 0 then PGM.SyncSend(bulk, "1G", sub, table.concat(parts, SEP)) end
        parts, size = {}, #head
    end
    for _, row in ipairs(rows) do
        local piece = table.concat(row, SEP)
        if size + #SEP + #piece > 245 then flush() end
        parts[#parts + 1] = piece
        size = size + #SEP + #piece
    end
    flush()
end

-- Seconds since the weekly reset (keystones from before it are gone).
function G.LastReset()
    local now = PGM.Now()
    local fn = C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset
    local ok, left = false, nil
    if fn then ok, left = pcall(fn) end
    left = ok and P(left) or nil
    if type(left) ~= "number" then return now - 7 * 86400 end
    return now + left - 7 * 86400
end

-- ============================================================
-- MESSAGES
-- ============================================================

-- Inbound "G" records: handlers[sub](f, sender, rec), with f[3] the first
-- field after the sub-type. Only from guild members in our roster.
G.handlers = {}
PGM.SyncRegister("G", function(f, sender, rec)
    if not (rec and G.DB()) then return end
    local h = G.handlers[f[2] or ""]
    if h then h(f, sender, rec) end
end)

local listeners = {}
function G:On(msg, fn)
    listeners[msg] = listeners[msg] or {}
    table.insert(listeners[msg], fn)
end

-- Something changed: tell our files, then repaint PGM's window soon.
function G:Fire(msg, ...)
    for _, fn in ipairs(listeners[msg] or {}) do
        local ok, err = pcall(fn, ...)
        if not ok then geterrorhandler()(err) end
    end
    PGM.UI:QueueRefresh()
end

local frame = CreateFrame("Frame")
local events = {}
function G:RegisterEvent(event, fn)
    if not events[event] then
        events[event] = {}
        frame:RegisterEvent(event)
    end
    table.insert(events[event], fn)
end
frame:SetScript("OnEvent", function(_, event, ...)
    for _, fn in ipairs(events[event]) do
        local ok, err = pcall(fn, event, ...)
        if not ok then geterrorhandler()(err) end
    end
end)

G:RegisterEvent("ADDON_LOADED", function(_, name)
    if name ~= ADDON then return end
    PandyGuildGroupsDB = PandyGuildGroupsDB or {}
    local db = PandyGuildGroupsDB
    db.guilds = db.guilds or {}
    db.chars = db.chars or {}
    db.settings = db.settings or {}
    db.settings.keysMineFirst = nil   -- replaced by keysPinMine, which starts off
    fillDefaults(db.settings, DEFAULTS)
    G:Fire("LOADED")
end)

-- PGM's first full roster read: everyone's rank and online state are known.
local started = false
PGM:On("ROSTER", function()
    local g = PGM.GuildDB()
    if started or not (g and g.seeded and PandyGuildGroupsDB) then return end
    started = true
    G:Fire("READY")
end)

-- ============================================================
-- SLASH COMMAND
-- ============================================================

SLASH_PANDYGUILDGROUPS1 = "/pgg"
SlashCmdList.PANDYGUILDGROUPS = function(input)
    local cmd = strtrim((input or ""):lower())
    if cmd == "" or cmd == "groups" then
        PGM.UI:Show("groups")
    elseif cmd == "mine" or cmd == "my" or cmd == "post" then
        G.UI.ShowView(cmd == "post" and "post" or "mine")
    elseif cmd == "free" or cmd == "who" then
        PGM.UI:Show("free")
    elseif cmd == "keys" or cmd == "key" then
        PGM.UI:Show("keys")
    elseif cmd == "close" and G.CloseMine then
        G:CloseMine("c")
    elseif cmd == "tell" or cmd == "announce" then
        G:Announce()
    elseif cmd == "list" then
        G:ListMyKey()
    else
        PGM.Print("Guild Groups v" .. G.VERSION .. ":")
        PGM.Print("  /pgg - guild groups")
        PGM.Print("  /pgg mine | post - your group, or the post form")
        PGM.Print("  /pgg free - who's free")
        PGM.Print("  /pgg keys - everyone's keystone")
        PGM.Print("  /pgg close - close your post")
        PGM.Print("  /pgg tell - tell guild chat about your group")
        PGM.Print("  /pgg list - list your keystone in the Group Finder")
    end
end
