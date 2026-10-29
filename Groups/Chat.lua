-- Chat.lua: Looking for Group from chat, on WoW Forever only. Classic
-- players group in chat more than in the Group Finder, so this reads the
-- channels you're in (LookingForGroup, General, Trade, World...) and guild
-- chat for LFM, LFG and WTS / WTB lines, works out the dungeon or raid, and
-- keeps each person's newest line for a while. Nothing is sent or saved.

local _, NS = ...
local G = NS.G
local PGM = G.PGM

if not PGM.IS_FOREVER then return end

-- Forever's dungeons and raids, lowest first: { key, name, lo, hi, words },
-- raids with their size. Words are what people type for it, lower case,
-- without apostrophes; "dm" is the Deadmines, "dm e" (and friends) Dire Maul.
-- Scarlet Monastery's wings count only with "sm" in front ("sm gy"): alone,
-- "graveyard" or "library" is just talk.
G.CHAT_PLACES = {
    { "rfc", "Ragefire Chasm", 10, 16, { "rfc", "ragefire" } },
    { "thanes", "Hall of Thanes", 13, 18, { "hall of thanes", "thanes" } },
    { "rol", "Ruins of Lordaeron", 15, 20, { "ruins of lordaeron", "lordaeron", "rol" } },
    { "dm", "The Deadmines", 13, 20, { "deadmines", "deadmine", "vc", "dm" } },
    { "wc", "Wailing Caverns", 14, 21, { "wailing caverns", "wailing", "wc" } },
    { "sfk", "Shadowfang Keep", 16, 22, { "shadowfang", "sfk" } },
    { "bfd", "Blackfathom Deeps", 20, 27, { "blackfathom", "bfd" } },
    { "stocks", "The Stockade", 21, 27, { "stockade", "stocks", "stock" } },
    { "rfk", "Razorfen Kraul", 22, 30, { "razorfen kraul", "kraul", "rfk" } },
    { "gnomer", "Gnomeregan", 22, 30, { "gnomeregan", "gnomer" } },
    { "dig", "Excavation Site: Wetlands", 24, 31, { "excavation site", "excavation", "dig site" } },
    { "dal", "City of Dalaran", 28, 33, { "city of dalaran", "dalaran", "dal" } },
    { "sm", "Scarlet Monastery", 26, 45, { "scarlet monastery", "scarlet", "sm gy", "sm lib", "sm arm", "sm cath",
        "sm graveyard", "sm library", "sm armory", "sm armoury", "sm cathedral", "sm" } },
    { "rfd", "Razorfen Downs", 33, 40, { "razorfen downs", "downs", "rfd" } },
    { "ulda", "Uldaman", 35, 45, { "uldaman", "ulda", "uld" } },
    { "drowned", "The Drowned City", 35, 40, { "drowned city", "drowned" } },
    { "kroldok", "Krol'dok Stronghold", 40, 45, { "kroldok", "krol dok", "krol" } },
    { "zf", "Zul'Farrak", 42, 48, { "zulfarrak", "zul farrak", "farrak", "zf" } },
    { "mara", "Maraudon", 42, 50, { "maraudon", "mara", "princess run" } },
    { "st", "Sunken Temple", 45, 52, { "sunken temple", "atalhakkar", "atal hakkar", "sunken", "st" } },
    { "brd", "Blackrock Depths", 48, 56, { "blackrock depths", "brd" } },
    { "alcaz", "Alcaz Prison", 48, 53, { "alcaz island", "alcaz prison", "alcaz" } },
    { "lbrs", "Lower Blackrock Spire", 53, 60, { "lower blackrock", "lbrs" } },
    { "ubrs", "Upper Blackrock Spire", 55, 60, { "upper blackrock", "ubrs" } },
    { "diremaul", "Dire Maul", 54, 60, { "dire maul", "diremaul", "dme", "dmw", "dmn", "dm e", "dm w", "dm n",
        "dm east", "dm west", "dm north", "dm tribute", "dm trib", "tribute" } },
    { "strat", "Stratholme", 55, 60, { "stratholme", "strath", "strat", "baron run" } },
    { "blackmaw", "Blackmaw Hold", 55, 60, { "blackmaw hold", "blackmaw", "bmh" } },
    { "scholo", "Scholomance", 57, 60, { "scholomance", "scholo" } },
    { "shapers", "Shaper's Terrace", 58, 60, { "shapers terrace", "shapers", "shaper", "terrace" } },
    { "barrow", "Barrow Deeps", 60, 60, { "barrow deeps", "barrow" }, 10 },
    { "hyjal", "Hyjal Summit", 60, 60, { "hyjal summit", "mount hyjal", "hyjal" }, 20 },
    { "ony", "Onyxia's Lair", 60, 60, { "onyxias lair", "onyxia", "ony" }, 40 },
}
G.CHAT_PLACE = {}
for i, p in ipairs(G.CHAT_PLACES) do
    G.CHAT_PLACE[p[1]] = { key = p[1], name = p[2], lo = p[3], hi = p[4], raid = p[6], order = i }
end

-- Every word, longest first, so "dm e" is read before "dm" and a matched
-- word is blanked out before the shorter ones look.
local WORDS = {}
for _, p in ipairs(G.CHAT_PLACES) do
    for _, w in ipairs(p[5]) do WORDS[#WORDS + 1] = { " " .. w .. " ", p[1] } end
end
table.sort(WORDS, function(a, b) return #a[1] > #b[1] end)

local TRADE = { wts = true, wtb = true, wtt = true, selling = true, buying = true }
local CRAFTER = { crafter = true, ench = true, enchanter = true, enchant = true, alch = true, alchemist = true,
                  bs = true, blacksmith = true, lw = true, leatherworker = true, tailor = true, engi = true,
                  engineer = true }
local ROLE_WORD = { tank = "T", tanks = "T", heal = "H", heals = "H", healer = "H", healers = "H", healz = "H",
                    dps = "D", dd = "D" }
local CLASS_WORD = { warrior = true, warr = true, priest = true, mage = true, rogue = true, druid = true,
                     paladin = true, pally = true, shaman = true, sham = true, shammy = true, hunter = true,
                     warlock = true, lock = true }
-- "dm me", "pm me": a private message, not the Deadmines.
local DM_PHRASES = { " dm me ", " pm me ", " dms ", " pms ", " dm if ", " dm pls ", " dm please ", " dm or " }

-- The word after "lf" or "looking for" at i, or nil.
local function afterLf(words, i)
    if words[i] == "lf" then return i + 1 end
    if words[i] == "looking" and words[i + 1] == "for" then return i + 2 end
end

-- Is what's at i something a group asks for: a role, a class or "more",
-- maybe after a count ("lf 2 dps", "need 1 more"), or "1m"? After "a" it
-- has to be a player ("need a tank"): "need a heal" is someone hurt.
local function wants(words, i)
    local w = words[i]
    if w == "a" or w == "an" then
        w = words[i + 1]
        return w ~= nil and w ~= "heal" and (ROLE_WORD[w] or CLASS_WORD[w]) and true or false
    end
    if w and w:match("^%d+$") then w = words[i + 1] end
    return w ~= nil and (ROLE_WORD[w] or CLASS_WORD[w] or w == "more" or w:match("^%d+m$")) and true or false
end

-- A chat line as plain text: colours, textures and links down to their names.
local function plain(text)
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", ""))
end

-- What a chat line is: { kind = "M" (group wants more) / "G" (player wants a
-- group) / "T" (trade), places = { keys }, roles = "THD" }, or nil when it's
-- just talk.
function G.ReadChatLine(text)
    if type(text) ~= "string" or text == "" then return nil end
    local low = plain(text):lower():gsub("'", "")
    local padded = " " .. low:gsub("[^%w%+]", " "):gsub("%s+", " ") .. " "
    local words, roles, seen = {}, {}, {}
    for w in padded:gmatch("%S+") do words[#words + 1] = w end
    local kind, asks
    for i, w in ipairs(words) do
        local after = afterLf(words, i)
        if TRADE[w] or (after and CRAFTER[words[after] or ""]) then kind = "T" break end
    end
    if not kind then
        -- The first that says what it is wins: "LFG, need SM gy" stays LFG.
        -- A bare "need" is just talk ("need a summon"): it counts before a
        -- role, a class or a count, or (below) in a line naming a place.
        for i, w in ipairs(words) do
            local after = afterLf(words, i)
            local need = (w == "need" or w == "needs") and i + 1 or nil
            if not kind then
                if w == "lfm" or w:match("^lf%dm$") or (after and wants(words, after)) or (need and wants(words, need)) then
                    kind = "M"
                elseif w == "lfg" or (after and (words[after] == "group" or words[after] == "grp")) then
                    kind = "G"
                end
            end
            if after or need then asks = asks or (need and "M" or "G") end
            local r = ROLE_WORD[w]
            if r and not seen[r] then seen[r], roles[#roles + 1] = true, r end
        end
    end
    -- Nothing that asks for anything: talk, so the places needn't be read.
    if not (kind or asks) then return nil end
    for _, ph in ipairs(DM_PHRASES) do
        local s, e = padded:find(ph, 1, true)
        while s do
            padded = padded:sub(1, s) .. padded:sub(e)
            s, e = padded:find(ph, 1, true)
        end
    end
    local places, got = {}, {}
    for _, wd in ipairs(WORDS) do
        local s, e = padded:find(wd[1], 1, true)
        while s do
            if not got[wd[2]] then got[wd[2]], places[#places + 1] = true, wd[2] end
            padded = padded:sub(1, s) .. (" "):rep(e - s - 1) .. padded:sub(e)
            s, e = padded:find(wd[1], 1, true)
        end
    end
    -- "Strat, need anyone?" is a group; "LF strat" a player looking. Without
    -- a place either is just talk.
    if not kind and #places > 0 then kind = asks end
    if not kind then return nil end
    table.sort(places, function(a, b) return G.CHAT_PLACE[a].order < G.CHAT_PLACE[b].order end)
    return { kind = kind, places = places, roles = table.concat(roles) }
end

-- ============================================================
-- WHAT'S BEEN SAID
-- ============================================================

local lines = {}   -- [full name] = the newest line from them

local KEEP = 15 * 60
local MAX_LINES = 300

local function prune()
    local now, n, oldest, oldestAt = GetTime(), 0, nil, math.huge
    for name, l in pairs(lines) do
        if now - l.at > KEEP then
            lines[name] = nil
        else
            n = n + 1
            if l.at < oldestAt then oldest, oldestAt = name, l.at end
        end
    end
    if n > MAX_LINES and oldest then lines[oldest] = nil end
end

local function secret(v)
    return issecretvalue and issecretvalue(v)
end

-- Repaint, but only while LFG Chat is the page showing: busy Trade chat
-- mustn't keep redrawing whatever else is open.
local function changed()
    if PGM.UI.current == "chat" then PGM.UI:QueueRefresh() end
end

-- One chat message: kept when it's a group or trade line.
function G:OnChatLine(text, sender, channel, guid)
    if secret(text) or secret(sender) or type(sender) ~= "string" or sender == "" then return end
    if guid and not secret(guid) and guid == UnitGUID("player") then return end
    local read = G.ReadChatLine(text)
    if not read then return end
    local short = sender:match("^([^-]+)") or sender
    local class
    if guid and not secret(guid) and GetPlayerInfoByGUID then
        local ok, _, cls = pcall(GetPlayerInfoByGUID, guid)
        class = ok and cls or nil
    end
    read.name, read.short, read.class, read.guid = sender, short, class, guid
    read.text, read.channel, read.at = text, channel, GetTime()
    read.rec = G.RecByName(sender)
    lines[sender] = read
    prune()
    changed()
end

-- The channel's short name: "Trade - City" is "Trade", "4. World" "World".
local function channelName(name, base)
    local n = (type(base) == "string" and base ~= "" and base) or (type(name) == "string" and name) or ""
    return (n:gsub("^%d+%.%s*", ""):gsub("%s+%-.*$", ""))
end

G:RegisterEvent("CHAT_MSG_CHANNEL", function(_, text, sender, _, name, _, _, _, _, base, _, _, guid)
    if secret(name) or secret(base) then return end
    G:OnChatLine(text, sender, channelName(name, base), guid)
end)
G:RegisterEvent("CHAT_MSG_GUILD", function(_, text, sender, _, _, _, _, _, _, _, _, _, guid)
    G:OnChatLine(text, sender, "Guild", guid)
end)
-- Ages tick on, and old lines go, even with no guild roster yet.
G.Every(30, function()
    if next(lines) then
        prune()
        changed()
    end
end)

-- ============================================================
-- THE BOARD
-- ============================================================

local function newestFirst(a, b)
    if a.at ~= b.at then return a.at > b.at end
    return a.name < b.name
end

-- Does a place suit this level? Within two levels of its range.
local function fits(place, level)
    return level >= place.lo - 2 and level <= place.hi + 2
end

-- The lines to show, under headings: each dungeon or raid lowest first,
-- then everything else that's a group, then trade. f: { dungeons, raids,
-- other, trade, fits (my level only), lfg (players looking, too), search }.
-- Rows are { head = text, count, place } or a line.
function G:ChatList(f)
    f = f or {}
    prune()
    local level = UnitLevel and UnitLevel("player") or 60
    local search = strtrim((f.search or ""):lower())
    local byPlace, other, trade = {}, {}, {}
    for _, l in pairs(lines) do
        local keep = (l.kind ~= "G" or f.lfg ~= false)
            and (search == "" or plain(l.text):lower():find(search, 1, true) or l.short:lower():find(search, 1, true))
        if keep and l.kind == "T" then
            if f.trade ~= false then trade[#trade + 1] = l end
        elseif keep and #l.places == 0 then
            if f.other ~= false then other[#other + 1] = l end
        elseif keep then
            for _, key in ipairs(l.places) do
                local p = G.CHAT_PLACE[key]
                local want = (p.raid and f.raids ~= false or not p.raid and f.dungeons ~= false)
                    and (not f.fits or fits(p, level))
                if want then
                    byPlace[key] = byPlace[key] or {}
                    table.insert(byPlace[key], l)
                end
            end
        end
    end
    local rows = {}
    local function section(head, list, place)
        if #list == 0 then return end
        table.sort(list, newestFirst)
        rows[#rows + 1] = { head = head, count = #list, place = place }
        for _, l in ipairs(list) do rows[#rows + 1] = l end
    end
    for _, p in ipairs(G.CHAT_PLACES) do
        local place = G.CHAT_PLACE[p[1]]
        section(place.name, byPlace[p[1]] or {}, place)
    end
    section("Quests and other groups", other)
    section("Trade", trade)
    return rows
end

-- ============================================================
-- POSTING
-- ============================================================

-- The channels you're in: { id = 4, name = "LookingForGroup" }, by number.
function G:ChatChannels()
    local out = {}
    if not GetChannelList then return out end
    local t = { GetChannelList() }
    for i = 1, #t, 3 do
        local id, name, disabled = t[i], t[i + 1], t[i + 2]
        if type(id) == "number" and type(name) == "string" and not secret(name) and not disabled then
            out[#out + 1] = { id = id, name = name }
        end
    end
    return out
end

-- The channel to post in: the one picked (kept by name, as its number can
-- change), else LookingForGroup, else World; nil when you're in neither.
function G:ChatPostChannel()
    local want = G.opt("chat").channel
    local list = G:ChatChannels()
    for _, pick in ipairs({ want, "LookingForGroup", "World" }) do
        for _, c in ipairs(list) do
            if pick ~= "" and c.name:lower() == pick:lower() then return c end
        end
    end
end

local POST_GAP = 5      -- seconds between posts, against a double click
local postedAt = -100

-- Send the saved line to the channel. From a click or Enter only: the game
-- won't send to a channel without one. True, or false and why not.
function G:SendChatPost()
    local text = strtrim(G.opt("chat").post or "")
    if text == "" then return false, "Type your message first." end
    local c = G:ChatPostChannel()
    if not c then return false, "Pick a channel you're in (join LookingForGroup or World)." end
    if GetTime() - postedAt < POST_GAP then return false, "Just sent: wait a few seconds." end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if not send then return false, "The game can't send chat right now." end
    local ok, err = pcall(send, text:sub(1, 255), "CHANNEL", nil, c.id)
    if not ok then return false, tostring(err) end
    postedAt = GetTime()
    return true
end
