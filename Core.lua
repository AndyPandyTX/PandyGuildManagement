-- Core.lua: namespace, saved data, shared helpers, events and slash commands.
--
-- Everything the game hands us goes through PGM.Plain first. In Midnight a
-- roster row or a unit's identity can arrive as a Secret Value: addon code may
-- hold one but not compare, concatenate or save it, and one written to
-- SavedVariables corrupts the file. Plain turns a secret into nil, so the rest
-- of the addon only ever sees ordinary values or nothing.

local ADDON, NS = ...

local PGM = {}
NS.PGM = PGM
PandyGuildManagement = PGM

PGM.NAME = "Pandy Guild Management"
PGM.VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata(ADDON, "Version")) or "dev"

-- Modules (separate addons that list this one in ## Dependencies) build on
-- the functions in the README's "Modules" section. Within one API number
-- those keep their names, arguments and results; a change that breaks one
-- moves the number up, and a module asking for a newer one is told to update.
PGM.API = 1
PGM.Modules = {}

-- info: { name, version, api, slash }. False when this copy is too old.
function PGM.RegisterModule(info)
    if (info.api or 1) > PGM.API then
        PGM.Print(("%s needs a newer Pandy Guild Management. Please update it."):format(info.name or "A module"))
        return false
    end
    PGM.Modules[#PGM.Modules + 1] = info
    return true
end

-- WoW Forever (game version 1.60, "Camelot" in the game's own constants) runs
-- the same engine and API as Midnight with Classic content: level cap 60, no
-- Mythic+, and Classic raids. The project constant is the proper way to ask;
-- the interface number (16001 against 120105) covers a build without it.
do
    local camelot = WOW_PROJECT_CAMELOT
    local interface = GetBuildInfo and select(4, GetBuildInfo()) or 0
    PGM.IS_FOREVER = (camelot ~= nil and WOW_PROJECT_ID == camelot)
        or (type(interface) == "number" and interface > 0 and interface < 100000)
end

-- Clean and dark: neutral near-black panels, crisp one-pixel frames, bright
-- text, and a single accent colour for headings and whatever's selected.
-- The status colours (jade for "good", red, amber...) mean the same thing on
-- every theme. Jade is also the Pandy name.
PGM.C = {
    bg       = { 0.035, 0.037, 0.042 },  -- window
    panel    = { 0.055, 0.058, 0.066 },  -- content well, header
    side     = { 0.045, 0.048, 0.055 },  -- sidebar
    card     = { 0.078, 0.083, 0.095 },  -- cards and tiles
    button   = { 0.105, 0.112, 0.128 },
    hover    = { 0.15, 0.16, 0.18 },
    rowA     = { 0.062, 0.066, 0.075 },
    rowB     = { 0.080, 0.085, 0.096 },
    line     = { 0.17, 0.18, 0.21 },     -- quiet dividers
    frame    = { 0.25, 0.27, 0.31 },     -- panel and control frames
    cardLine = { 0.19, 0.205, 0.235 },
    accent   = { 0.35, 0.78, 1.00 },     -- set from the chosen accent at load
    text     = { 0.97, 0.97, 0.98 },
    text2    = { 0.70, 0.73, 0.77 },
    text3    = { 0.47, 0.50, 0.55 },
    jade    = { 0.33, 0.82, 0.58 },
    gold   = { 1.00, 0.80, 0.32 },
    amber  = { 1.00, 0.60, 0.24 },
    red    = { 0.95, 0.32, 0.30 },
    blue   = { 0.42, 0.68, 1.00 },
    purple = { 0.72, 0.54, 1.00 },
}

-- The accent choices (Settings > Look). Changing one needs a /reload,
-- because frames take their colours when they're built.
PGM.ACCENTS = {
    { id = "ice",    name = "Ice",    col = { 0.35, 0.78, 1.00 } },
    { id = "jade",   name = "Jade",   col = { 0.30, 0.90, 0.72 } },
    { id = "violet", name = "Violet", col = { 0.72, 0.56, 1.00 } },
    { id = "white",  name = "White",  col = { 0.95, 0.96, 0.98 } },
    { id = "ember",  name = "Ember",  col = { 1.00, 0.45, 0.36 } },
}

function PGM.ApplyAccent(id)
    for _, a in ipairs(PGM.ACCENTS) do
        if a.id == id then
            -- In place: other files hold on to this very table.
            PGM.C.accent[1], PGM.C.accent[2], PGM.C.accent[3] = a.col[1], a.col[2], a.col[3]
            return
        end
    end
end

-- Retail's thirteen, in the order the game's own class lists use.
PGM.CLASSES = {
    "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN",
    "MAGE", "WARLOCK", "MONK", "DRUID", "DEMONHUNTER", "EVOKER",
}

local DEFAULTS = {
    announce = { join = true, leave = true, rank = true, maxLevel = true, rename = true },
    raidMinGuildies = 5,
    scale = 1,
    accent = "ice",
    syncEnabled = true,
    overviewScope = "all",
    overviewMainsOnly = false,
    logCap = 3000,
}

-- ============================================================
-- HELPERS
-- ============================================================

function PGM.Now()
    return GetServerTime and GetServerTime() or time()
end

-- A time for a shared change that's always later than the last one to the
-- same thing, even two edits in the same second (newest wins when merging).
function PGM.Stamp(prev)
    local now = PGM.Now()
    prev = tonumber(prev) or 0
    return now > prev and now or prev + 1
end

-- A value from the game, or nil when the game is keeping it secret.
function PGM.Plain(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

function PGM.Print(...)
    local msg = strjoin(" ", tostringall(...))
    DEFAULT_CHAT_FRAME:AddMessage("|cff55d194Pandy|r " .. msg)
end

function PGM.Debug(...)
    if PandyGuildDB and PandyGuildDB.debug then PGM.Print("|cff888888[debug]|r", ...) end
end

-- "Name-Realm" -> "Name", "Realm". A bare name gets the player's own realm.
function PGM.SplitName(full)
    if not full then return nil, nil end
    local name, realm = full:match("^([^-]+)-(.+)$")
    if name then return name, realm end
    return full, GetNormalizedRealmName and GetNormalizedRealmName() or nil
end

-- Guild names are unique per realm, so name+realm files a guild across sessions.
-- Asked thousands of times a refresh (every GuildDB call), so the answer is
-- kept until the game says our guild changed, and at most 30 seconds.
local keyCache, nameCache, keyAt
function PGM.ForgetGuildKey()
    keyCache, nameCache, keyAt = nil, nil, nil
end

function PGM.GuildKey()
    if not IsInGuild() then return nil end
    if keyCache and GetTime() - keyAt < 30 then return keyCache, nameCache end
    local key, name = PGM.ReadGuildKey()
    if key then keyCache, nameCache, keyAt = key, name, GetTime() end
    return key, name
end

function PGM.ReadGuildKey()
    local name, _, _, realm = GetGuildInfo("player")
    name, realm = PGM.Plain(name), PGM.Plain(realm)
    if not name or name == "" then return nil end
    realm = realm or (GetNormalizedRealmName and GetNormalizedRealmName()) or "?"
    -- GetGuildInfo can say "Area 52" where the normalized name is "Area52";
    -- one guild must always file under one key.
    realm = realm:gsub("[%s%-]", "")
    return name .. "-" .. realm, name
end

-- The current guild's saved table. With create, makes it on first use.
function PGM.GuildDB(create)
    local key, name = PGM.GuildKey()
    if not key or not PandyGuildDB then return nil end
    local g = PandyGuildDB.guilds[key]
    if not g and create then
        g = { name = name, members = {}, former = {}, log = {}, notes = {}, links = {},
              raids = { sessions = {} } }
        PandyGuildDB.guilds[key] = g
    end
    return g
end

function PGM.opt(key)
    return PandyGuildDB and PandyGuildDB.settings[key]
end

function PGM.setOpt(key, value)
    PandyGuildDB.settings[key] = value
end

function PGM.MaxLevel()
    -- Retail: the game's cap, not this account's, or an account without
    -- Midnight would call everyone at 90 "above max". Forever: the latest
    -- expansion is the engine's, so ask for the player's cap there instead.
    local fn
    if PGM.IS_FOREVER then fn = GetMaxLevelForPlayerExpansion
    else fn = GetMaxLevelForLatestExpansion or GetMaxLevelForPlayerExpansion end
    local ok, cap = false, nil
    if fn then ok, cap = pcall(fn) end
    cap = ok and PGM.Plain(cap) or nil
    if type(cap) == "number" and cap > 1 then return cap end
    return PGM.IS_FOREVER and 60 or 90
end

-- Names sort as if accents weren't there, so "Ühtréd" sits among the U's
-- rather than after Z (byte order puts every accented letter past z). Covers
-- Latin-1 and Latin Extended-A, which is what character names can use.
local FOLD = {}
do
    local ranges = {
        { 0xC0, 0xC5, "a" }, { 0xC6, 0xC6, "ae" }, { 0xC7, 0xC7, "c" }, { 0xC8, 0xCB, "e" },
        { 0xCC, 0xCF, "i" }, { 0xD0, 0xD0, "d" }, { 0xD1, 0xD1, "n" }, { 0xD2, 0xD6, "o" },
        { 0xD8, 0xD8, "o" }, { 0xD9, 0xDC, "u" }, { 0xDD, 0xDD, "y" }, { 0xDE, 0xDE, "th" },
        { 0xDF, 0xDF, "ss" },
        { 0xE0, 0xE5, "a" }, { 0xE6, 0xE6, "ae" }, { 0xE7, 0xE7, "c" }, { 0xE8, 0xEB, "e" },
        { 0xEC, 0xEF, "i" }, { 0xF0, 0xF0, "d" }, { 0xF1, 0xF1, "n" }, { 0xF2, 0xF6, "o" },
        { 0xF8, 0xF8, "o" }, { 0xF9, 0xFC, "u" }, { 0xFD, 0xFD, "y" }, { 0xFE, 0xFE, "th" },
        { 0xFF, 0xFF, "y" },
        { 0x100, 0x105, "a" }, { 0x106, 0x10D, "c" }, { 0x10E, 0x111, "d" }, { 0x112, 0x11B, "e" },
        { 0x11C, 0x123, "g" }, { 0x124, 0x127, "h" }, { 0x128, 0x131, "i" }, { 0x132, 0x133, "ij" },
        { 0x134, 0x135, "j" }, { 0x136, 0x138, "k" }, { 0x139, 0x142, "l" }, { 0x143, 0x14B, "n" },
        { 0x14C, 0x151, "o" }, { 0x152, 0x153, "oe" }, { 0x154, 0x159, "r" }, { 0x15A, 0x161, "s" },
        { 0x162, 0x167, "t" }, { 0x168, 0x173, "u" }, { 0x174, 0x175, "w" }, { 0x176, 0x178, "y" },
        { 0x179, 0x17E, "z" },
    }
    for _, r in ipairs(ranges) do
        for cp = r[1], r[2] do
            FOLD[string.char(0xC0 + math.floor(cp / 64), 0x80 + cp % 64)] = r[3]
        end
    end
end

local sortKeys = {}
function PGM.SortKey(name)
    name = name or ""
    local key = sortKeys[name]
    if not key then
        key = name:lower():gsub("[\195-\197][\128-\191]", FOLD)
        sortKeys[name] = key
    end
    return key
end

-- For table.sort: by name ignoring accents, then exactly, so the order
-- never depends on the sort's mood.
function PGM.NameLess(a, b)
    local ka, kb = PGM.SortKey(a), PGM.SortKey(b)
    if ka ~= kb then return ka < kb end
    return (a or "") < (b or "")
end

function PGM.ClassColor(classFile)
    local c = classFile and C_ClassColor and C_ClassColor.GetClassColor(classFile)
    if c then return c.r, c.g, c.b end
    c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if c then return c.r, c.g, c.b end
    return 0.7, 0.7, 0.7
end

function PGM.ClassHex(classFile)
    local r, g, b = PGM.ClassColor(classFile)
    return ("|cff%02x%02x%02x"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

function PGM.ClassName(classFile)
    return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classFile]) or classFile or "?"
end

-- A member's short name in class colour. Cross-realm members keep a "*" so
-- two people called the same thing on different realms stay apart.
function PGM.ColorName(rec)
    if not rec then return "?" end
    local myRealm = GetNormalizedRealmName and GetNormalizedRealmName()
    local tag = (rec.realm and myRealm and rec.realm ~= myRealm) and "*" or ""
    return PGM.ClassHex(rec.class) .. (rec.short or rec.name or "?") .. tag .. "|r"
end

function PGM.Hex(col)
    return ("|cff%02x%02x%02x"):format(math.floor(col[1] * 255 + 0.5), math.floor(col[2] * 255 + 0.5),
        math.floor(col[3] * 255 + 0.5))
end

-- How long ago, compactly: "now", "5h", "3d", "2mo", "1y".
function PGM.Ago(t)
    if not t then return "?" end
    local s = PGM.Now() - t
    if s < 3600 then return "now" end
    if s < 86400 then return math.floor(s / 3600) .. "h" end
    if s < 86400 * 60 then return math.floor(s / 86400) .. "d" end
    if s < 86400 * 365 then return math.floor(s / (86400 * 30)) .. "mo" end
    return math.floor(s / (86400 * 365)) .. "y"
end

-- The same, as a phrase: "just now", "5h ago", "3d ago".
function PGM.AgoText(t)
    if not t then return "?" end
    local a = PGM.Ago(t)
    return a == "now" and "just now" or (a .. " ago")
end

function PGM.Date(t, withTime)
    if not t then return "?" end
    return date(withTime and "%b %d %H:%M" or "%b %d, %Y", t)
end

function PGM.DaysSince(t)
    if not t then return nil end
    return (PGM.Now() - t) / 86400
end

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
-- MESSAGES (addon-internal)
-- ============================================================

local listeners = {}

function PGM:On(msg, fn)
    listeners[msg] = listeners[msg] or {}
    table.insert(listeners[msg], fn)
end

function PGM:Fire(msg, ...)
    for _, fn in ipairs(listeners[msg] or {}) do
        local ok, err = pcall(fn, ...)
        if not ok then geterrorhandler()(err) end
    end
end

-- ============================================================
-- GAME EVENTS
-- ============================================================

local frame = CreateFrame("Frame")
local handlers = {}

function PGM:RegisterEvent(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        frame:RegisterEvent(event)
    end
    table.insert(handlers[event], fn)
end

frame:SetScript("OnEvent", function(_, event, ...)
    for _, fn in ipairs(handlers[event]) do
        local ok, err = pcall(fn, event, ...)
        if not ok then geterrorhandler()(err) end
    end
end)

-- Joining, leaving or changing guilds (or logging in) means a new key.
PGM:RegisterEvent("PLAYER_GUILD_UPDATE", function() PGM.ForgetGuildKey() end)
PGM:RegisterEvent("PLAYER_ENTERING_WORLD", function() PGM.ForgetGuildKey() end)

PGM:RegisterEvent("ADDON_LOADED", function(_, name)
    if name ~= ADDON then return end
    PandyGuildDB = PandyGuildDB or {}
    local db = PandyGuildDB
    db.version = 1
    db.guilds = db.guilds or {}
    db.chars = db.chars or {}
    db.settings = db.settings or {}
    fillDefaults(db.settings, DEFAULTS)
    PGM.ApplyAccent(db.settings.accent)
    PGM:Fire("LOADED")
end)

PGM:RegisterEvent("PLAYER_LOGIN", function()
    PGM:Fire("LOGIN")
end)

-- ============================================================
-- SLASH COMMANDS
-- ============================================================

local TAB_ALIASES = {
    overview = "overview", o = "overview",
    roster = "roster", r = "roster",
    log = "log", history = "log",
    professions = "professions", profs = "professions", prof = "professions",
    teams = "teams", team = "teams",
    raids = "raids", raid = "raids", attendance = "raids",
    settings = "settings", config = "settings", options = "settings",
}

SLASH_PANDYGUILD1 = "/pgm"
SLASH_PANDYGUILD2 = "/pandy"
SlashCmdList.PANDYGUILD = function(input)
    local cmd = strtrim((input or ""):lower())
    if cmd == "" then
        PGM.UI:Toggle()
    elseif TAB_ALIASES[cmd] then
        PGM.UI:Show(TAB_ALIASES[cmd])
    elseif PGM.UI.tabs[cmd] then
        PGM.UI:Show(cmd)   -- any page by its id, modules' included
    elseif cmd == "scan" then
        PGM:RequestRoster(true)
        PGM.Print("Asked the server for a fresh roster.")
    elseif cmd == "minimap" then
        if PGM.SetMinimapShown and PGM:SetMinimapShown(not PGM:MinimapShown()) then
            PGM.Print("Minimap button", PGM:MinimapShown() and "shown" or "hidden")
        end
    elseif cmd == "export" then
        PGM.UI:ShowExport("Roster CSV", PGM:RosterCSV())
    elseif cmd == "debug" then
        PandyGuildDB.debug = not PandyGuildDB.debug
        PGM.Print("Debug", PandyGuildDB.debug and "on" or "off")
    else
        PGM.Print("v" .. PGM.VERSION .. " commands:")
        PGM.Print("  /pgm - open or close the window")
        PGM.Print("  /pgm overview | roster | professions | teams | log | raids | settings - open a page")
        PGM.Print("  /pgm export - roster as CSV")
        PGM.Print("  /pgm scan - refresh the roster now")
        PGM.Print("  /pgm minimap - show or hide the minimap button")
        for _, m in ipairs(PGM.Modules) do
            if m.slash then PGM.Print("  " .. m.slash .. " - " .. (m.name or "module")) end
        end
    end
end

-- Blizzard's AddOns button on the minimap.
function PandyGuildManagement_OnCompartmentClick()
    PGM.UI:Toggle()
end

function PandyGuildManagement_OnCompartmentEnter(_, button)
    GameTooltip:SetOwner(button, "ANCHOR_LEFT")
    GameTooltip:AddLine(PGM.NAME)
    local g = PGM.GuildDB()
    if g and PGM.CountMembers then
        local total, online = PGM:CountMembers()
        GameTooltip:AddLine(("%d members, %d online"):format(total, online), 1, 1, 1)
    end
    GameTooltip:AddLine("Click to open", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

function PandyGuildManagement_OnCompartmentLeave()
    GameTooltip:Hide()
end
