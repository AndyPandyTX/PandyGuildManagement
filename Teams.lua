-- Teams.lua: raid teams. A guild can run as many as it likes, each with its
-- own roster, roles, schedule note and attendance.
--
-- Raid nights are matched to a team on their own: when a raid is saved, the
-- team with the most of its members there gets it, if that's at least ten.
-- A wrong guess is one right-click to fix on the Raids page.

local _, NS = ...
local PGM = NS.PGM
local C = PGM.C

PGM.ROLES = { "TANK", "HEALER", "DPS" }
PGM.ROLE_LABEL = { TANK = "Tank", HEALER = "Healer", DPS = "DPS" }
PGM.ROLE_COLOR = { TANK = C.blue, HEALER = C.jade, DPS = C.red }
PGM.STATUSES = { "core", "trial", "bench" }
PGM.STATUS_LABEL = { core = "Core", trial = "Trial", bench = "Bench" }
PGM.STATUS_COLOR = { core = C.text, trial = C.gold, bench = C.text3 }

-- Raid-wide buffs and boss debuffs in Midnight, and the class that brings
-- each (Icy Veins' Midnight raid buff list; Hunter's Mark is the one that
-- changed from The War Within: now a flat 3% for the whole fight). Death
-- Knights and Warlocks bring utility rather than a throughput buff.
PGM.RAID_BUFFS = {
    { class = "MAGE",        name = "Arcane Intellect",      effect = "+3% Intellect" },
    { class = "PRIEST",      name = "Power Word: Fortitude", effect = "+5% Stamina" },
    { class = "WARRIOR",     name = "Battle Shout",          effect = "+5% attack power" },
    { class = "DRUID",       name = "Mark of the Wild",      effect = "+3% Versatility" },
    { class = "SHAMAN",      name = "Skyfury",               effect = "+2% Mastery, extra auto attacks" },
    { class = "EVOKER",      name = "Blessing of the Bronze", effect = "-15% movement cooldowns" },
    { class = "PALADIN",     name = "Devotion Aura",         effect = "-3% damage taken" },
    { class = "MONK",        name = "Mystic Touch",          effect = "boss takes +5% physical" },
    { class = "DEMONHUNTER", name = "Chaos Brand",           effect = "boss takes +3% magic" },
    { class = "HUNTER",      name = "Hunter's Mark",         effect = "boss takes +3% damage" },
    { class = "ROGUE",       name = "Atrophic Poison",       effect = "boss deals -3% damage" },
}

-- Utility a raid wants at least one of.
PGM.RAID_UTILITY = {
    { name = "Bloodlust", classes = { MAGE = true, SHAMAN = true, EVOKER = true, HUNTER = true } },
    { name = "Battle res", classes = { DEATHKNIGHT = true, DRUID = true, WARLOCK = true } },
}

-- The roster doesn't say anyone's spec, so new members start as DPS and one
-- click on their role fixes it.
local DEFAULT_ROLE = "DPS"

local function teams()
    local g = PGM.GuildDB(true)
    if not g then return nil end
    g.teams = g.teams or {}
    return g.teams
end

-- Shared editing: only officers change teams, and each change is sent to the
-- rest of the guild (Sync.lua, loaded after this file, so looked up at use).
local function canEdit()
    return PGM.CanEdit ~= nil and PGM:CanEdit()
end
local function share(fn, ...)
    if PGM[fn] and canEdit() then PGM[fn](PGM, ...) end
end

-- After a team's name, schedule, tags or sync setting changes.
function PGM:TouchTeam(t)
    share("SyncTeam", t)
end

-- Change a team's details: any of name, schedule, tags, autoSync. Shared
-- with the guild when anything actually changed. Returns true if it did.
-- (Every edit box goes through here, so nothing is changed locally only.)
function PGM:UpdateTeam(id, fields)
    local t = PGM:TeamById(id)
    if not t or not canEdit() then return false end
    local changed = false
    if fields.name then
        local name = strtrim(fields.name)
        if name ~= "" and name ~= t.name then t.name, changed = name, true end
    end
    for _, key in ipairs({ "schedule", "tags" }) do
        local v = fields[key]
        if v then
            v = strtrim(v)
            if v ~= (t[key] or "") then t[key], changed = v, true end
        end
    end
    if fields.autoSync ~= nil then
        local v = fields.autoSync and true or nil
        if v ~= t.autoSync then t.autoSync, changed = v, true end
    end
    if changed then
        PGM:TouchTeam(t)
        PGM:Fire("TEAMS")
    end
    return changed
end

function PGM:Teams()
    return teams() or {}
end

function PGM:TeamById(id)
    for _, t in ipairs(PGM:Teams()) do
        if t.id == id then return t end
    end
end

function PGM:CreateTeam(name)
    local list = teams()
    if not list or not canEdit() then return nil end
    name = strtrim(name or "")
    if name == "" then name = "Raid team " .. (#list + 1) end
    -- `by`: who made it (shared, so everyone can see it on the team).
    local ok, me = pcall(UnitName, "player")
    local t = { id = ("%d-%d"):format(PGM.Now(), math.random(1000, 9999)), name = name, schedule = "",
                members = {}, removed = {}, created = PGM.Now(), by = ok and PGM.Plain(me) or nil }
    table.insert(list, t)
    share("SyncTeam", t)
    PGM:Fire("TEAMS")
    return t
end

function PGM:DeleteTeam(id)
    local list = teams()
    if not list or not canEdit() then return end
    for i, t in ipairs(list) do
        if t.id == id then table.remove(list, i) break end
    end
    local g = PGM.GuildDB()
    for _, s in ipairs(g.raids and g.raids.sessions or {}) do
        if s.team == id then s.team = nil end
    end
    share("SyncTeamDeleted", id)
    PGM:Fire("TEAMS")
end

-- A new spot on a team, shared. Lifts an earlier removal by hand.
local function place(t, guid, role, status)
    -- Carry the removal's stamp over, so the re-add is stamped later than it.
    local prev = t.removed and tonumber(t.removed[guid]) or nil
    t.members[guid] = { role = role or DEFAULT_ROLE, status = status or "core", added = PGM.Now(), u = prev }
    if t.removed then t.removed[guid] = nil end
    share("SyncSpot", t, guid)
end

-- Adding by hand also lifts an earlier removal (see RemoveFromTeam). Role
-- and status are optional (DPS and Core).
function PGM:AddToTeam(id, guid, role, status)
    local t = PGM:TeamById(id)
    if not t or not guid or t.members[guid] or not canEdit() then return false end
    place(t, guid, role, status)
    PGM:Fire("TEAMS")
    return true
end

-- A removal by hand is remembered, so importing from notes never puts them
-- back. Adding them by hand again is the only way back in.
function PGM:RemoveFromTeam(id, guid)
    local t = PGM:TeamById(id)
    if t and t.members[guid] and canEdit() then
        local prev = t.members[guid].u
        t.members[guid] = nil
        t.removed = t.removed or {}
        t.removed[guid] = prev or PGM.Now()
        share("SyncSpot", t, guid)
        PGM:Fire("TEAMS")
    end
end

local function nextOf(list, current)
    for i, v in ipairs(list) do
        if v == current then return list[i % #list + 1] end
    end
    return list[1]
end

function PGM:CycleRole(id, guid)
    local t = PGM:TeamById(id)
    local e = t and t.members[guid]
    if e and canEdit() then
        e.role = nextOf(PGM.ROLES, e.role)
        share("SyncSpot", t, guid)
        PGM:Fire("TEAMS")
    end
end

function PGM:CycleStatus(id, guid)
    local t = PGM:TeamById(id)
    local e = t and t.members[guid]
    if e and canEdit() then
        e.status = nextOf(PGM.STATUSES, e.status)
        share("SyncSpot", t, guid)
        PGM:Fire("TEAMS")
    end
end

-- Everyone currently in your group who is in the guild joins the team.
function PGM:AddGroupToTeam(id)
    local g = PGM.GuildDB()
    if not g then return 0 end
    local n = 0
    local function try(unit)
        local ok, guid = pcall(UnitGUID, unit)
        guid = ok and PGM.Plain(guid) or nil
        if guid and g.members[guid] and PGM:AddToTeam(id, guid) then n = n + 1 end
    end
    local prefix = IsInRaid() and "raid" or "party"
    for i = 1, GetNumGroupMembers() or 0 do try(prefix .. i) end
    try("player")
    return n
end

-- The teams a character is on, counting their main's and alts' spots.
function PGM:TeamsOf(guid)
    local out = {}
    local group = PGM:GroupOf(guid)
    for _, t in ipairs(PGM:Teams()) do
        for _, gu in ipairs(group) do
            local e = t.members[gu]
            if e then
                out[#out + 1] = { team = t, entry = e, guid = gu }
                break
            end
        end
    end
    return out
end

function PGM:TeamsText(guid)
    local parts = {}
    for _, it in ipairs(PGM:TeamsOf(guid)) do parts[#parts + 1] = it.team.name end
    return table.concat(parts, ", ")
end

-- Was this team member (or one of their characters) at that raid?
local function attended(s, guid)
    for _, gu in ipairs(PGM:GroupOf(guid)) do
        if s.present[gu] then return true end
    end
    return false
end

-- How many of a team's members make a raid night theirs. A team smaller
-- than that needs all of them (and at least three).
PGM.TEAM_NIGHT_MIN = 10

-- The team a raid night belongs to, or nil: the team with the most members
-- there (bench included, alts counting for their main), if that's at least
-- TEAM_NIGHT_MIN. A tie goes to the team with more of its roster there.
function PGM:GuessTeam(s)
    local g = PGM.GuildDB()
    local best, bestHere, bestShare
    for _, t in ipairs(PGM:Teams()) do
        local size, here = 0, 0
        for guid in pairs(t.members) do
            -- Members who left the guild stay on file (they may come back)
            -- but would otherwise count as permanent no-shows.
            if g and g.members[guid] then
                size = size + 1
                if attended(s, guid) then here = here + 1 end
            end
        end
        local need = math.max(3, math.min(PGM.TEAM_NIGHT_MIN, size))
        local share = size > 0 and here / size or 0
        if here >= need and (not best or here > bestHere or (here == bestHere and share > bestShare)) then
            best, bestHere, bestShare = t.id, here, share
        end
    end
    return best
end

-- Matches every unassigned raid night to a team. Returns how many it placed.
function PGM:AutoAssignRaids()
    local g = PGM.GuildDB()
    local n = 0
    if not canEdit() then return 0 end
    for _, s in ipairs(g and g.raids and g.raids.sessions or {}) do
        if not s.team then
            s.team = PGM:GuessTeam(s)
            if s.team then
                n = n + 1
                s.teamU = PGM.Stamp(s.teamU)
                share("SyncRaid", s)
            end
        end
    end
    if n > 0 then PGM:Fire("RAIDS") end
    return n
end

function PGM:AssignRaid(s, teamId)
    if not canEdit() then return end
    s.team = teamId
    s.teamU = PGM.Stamp(s.teamU)
    share("SyncRaid", s)
    PGM:Fire("RAIDS")
end

-- Roles, classes and missing raid buffs for the non-bench roster.
function PGM:TeamComposition(t)
    local g = PGM.GuildDB()
    local comp = { TANK = 0, HEALER = 0, DPS = 0, total = 0, bench = 0, classes = {}, missing = {} }
    for guid, e in pairs(t.members) do
        local rec = g and g.members[guid]
        if rec then
            if e.status == "bench" then
                comp.bench = comp.bench + 1
            else
                comp.total = comp.total + 1
                comp[e.role] = (comp[e.role] or 0) + 1
                if rec.class then comp.classes[rec.class] = (comp.classes[rec.class] or 0) + 1 end
            end
        end
    end
    for _, b in ipairs(PGM.RAID_BUFFS) do
        if not comp.classes[b.class] then comp.missing[#comp.missing + 1] = b end
    end
    comp.missingUtility = {}
    for _, u in ipairs(PGM.RAID_UTILITY) do
        local have = false
        for cls in pairs(u.classes) do
            if comp.classes[cls] then have = true break end
        end
        if not have then comp.missingUtility[#comp.missingUtility + 1] = u.name end
    end
    return comp
end

-- ============================================================
-- TEAMS FROM GUILD NOTES
-- ============================================================
-- Guilds tag raiders in their notes: "VA/Main/312/DPS/Anvar", "Z", "M BM
-- Tank", or an officer note of "Team Valor". A team's tags (say "Valor, VA,
-- V") pull in every main whose note carries one. Short tags (3 letters or
-- fewer) only count as the note's first part, or after "Team", so "M" never
-- matches the M in "M+". Longer ones count anywhere as a whole word.
--
-- Importing only ever adds. It skips alts (their main is the raider), and
-- anyone removed from the team by hand.

local function wholeWord(text, word)
    local from = 1
    while true do
        local a, b = text:find(word, from, true)
        if not a then return false end
        local before = a > 1 and text:sub(a - 1, a - 1) or ""
        local after = text:sub(b + 1, b + 1)
        -- "&" counts as part of a word, so "Team H" never matches "Team H&M".
        if not before:find("[%w&]") and not after:find("[%w&]") then return true end
        from = b + 1
    end
end

local function textHasTag(text, tag)
    if not text or text == "" or tag == "" then return false end
    local lt, tg = text:lower(), tag:lower()
    if wholeWord(lt, "team " .. tg) then return true end
    if #tg <= 3 then
        return lt:match("^%s*([^/%s%-:]+)") == tg
    end
    return wholeWord(lt, tg)
end

function PGM:TeamTags(t)
    local out = {}
    for tag in (t.tags or ""):gmatch("[^,]+") do
        tag = strtrim(tag)
        if tag ~= "" then out[#out + 1] = tag end
    end
    return out
end

function PGM:NoteMatchesTeam(rec, t)
    for _, tag in ipairs(PGM:TeamTags(t)) do
        if textHasTag(rec.note, tag) or textHasTag(rec.onote, tag) then return true end
    end
    return false
end

-- Role words as guilds write them: "TNK", "HLS", "Heal", "Resto", "DPS".
local ROLE_WORDS = {
    tnk = "TANK", tank = "TANK", prot = "TANK", guardian = "TANK",
    hls = "HEALER", heal = "HEALER", heals = "HEALER", healer = "HEALER", resto = "HEALER",
    disc = "HEALER", holy = "HEALER", mw = "HEALER",
    dps = "DPS",
}

function PGM:RoleFromNote(rec)
    for _, text in ipairs({ rec.note, rec.onote }) do
        for word in (text or ""):lower():gmatch("[%a]+") do
            if ROLE_WORDS[word] then return ROLE_WORDS[word] end
        end
    end
    return DEFAULT_ROLE
end

local function looksTrial(rec)
    return (rec.rank and rec.rank:lower():find("trial", 1, true))
        or (rec.onote and rec.onote:lower():find("trial", 1, true))
end

-- Adds every tagged main not on the team yet. Returns how many joined.
function PGM:ImportTeamFromNotes(id, quiet)
    local t = PGM:TeamById(id)
    local g = PGM.GuildDB()
    if not (t and g) or #PGM:TeamTags(t) == 0 or not canEdit() then return 0 end
    t.removed = t.removed or {}
    local n, added = 0, {}
    for guid, rec in pairs(g.members) do
        if not t.members[guid] and not t.removed[guid] and not PGM:IsAlt(guid)
            and PGM:NoteMatchesTeam(rec, t) then
            t.members[guid] = {
                role = PGM:RoleFromNote(rec),
                status = looksTrial(rec) and "trial" or "core",
                added = PGM.Now(),
                fromNotes = true,
            }
            n = n + 1
            added[#added + 1] = guid
        end
    end
    for _, guid in ipairs(added) do share("SyncSpot", t, guid) end
    if n > 0 and not quiet then PGM:Fire("TEAMS") end
    return n
end

local function titleCase(word)
    if word:find("&", 1, true) then return word:upper() end
    return word:sub(1, 1):upper() .. word:sub(2)
end

-- Reads "Team X" out of every note and makes a team for each X at least
-- three members mention, tagged with X, its first two letters and its first
-- letter ("Valor, VA, V"). A short tag two teams would share goes to the
-- bigger one. A team that already exists (same name) is just imported into.
-- Returns the names it created and how many members joined in all.
-- Not until this login's catch-up is in: a copy that hasn't heard the
-- guild's teams yet would make a second of each (returns nil then).
function PGM:FindTeamsInNotes()
    local g = PGM.GuildDB()
    if not g or not canEdit() then return {}, 0 end
    if PGM.SyncSettled and not PGM:SyncSettled() then return nil, 0 end
    local mentions = {}
    for _, rec in pairs(g.members) do
        local seen = {}
        for _, text in ipairs({ rec.note, rec.onote }) do
            for word in (text or ""):lower():gmatch("team%s+([%w&]+)") do
                if not seen[word] then
                    seen[word] = true
                    mentions[word] = (mentions[word] or 0) + 1
                end
            end
        end
    end

    local found = {}
    for word, n in pairs(mentions) do
        if n >= 3 then found[#found + 1] = { word = word, n = n } end
    end
    table.sort(found, function(a, b)
        if a.n ~= b.n then return a.n > b.n end
        return a.word < b.word
    end)

    -- Short tags, biggest team first; a tag already taken isn't reused.
    local taken = {}
    for _, f in ipairs(found) do
        local tags = { titleCase(f.word) }
        local letters = f.word:gsub("[^%a]", "")
        -- "H&M" is already initials: "HM", but not "H" (that's Honor's).
        local shorts = f.word:find("&", 1, true) and { letters:upper() }
            or { letters:sub(1, 2):upper(), letters:sub(1, 1):upper() }
        for _, short in ipairs(shorts) do
            if short ~= "" and not taken[short] and short:lower() ~= f.word then
                taken[short] = true
                tags[#tags + 1] = short
            end
        end
        f.tags = table.concat(tags, ", ")
    end

    local created, joined = {}, 0
    for _, f in ipairs(found) do
        local name = "Team " .. titleCase(f.word)
        local team
        for _, t in ipairs(PGM:Teams()) do
            if t.name:lower() == name:lower() then team = t end
        end
        if not team then
            team = PGM:CreateTeam(name)
            team.tags = f.tags
            team.autoSync = true
            share("SyncTeam", team)
            created[#created + 1] = name
        end
        joined = joined + PGM:ImportTeamFromNotes(team.id, true)
    end
    PGM:Fire("TEAMS")
    return created, joined
end

-- ============================================================
-- PASTED LISTS
-- ============================================================
-- A roster pasted in from outside: cells copied from a spreadsheet (they
-- arrive tab-separated), CSV, or flat JSON like a bot's output. One
-- character per line. Any column can hold the name ("Name" or
-- "Name-Realm"), and other columns may say the role (Tank, Healer, DPS,
-- or a spec like Resto) and the status (Core, Trial, Bench). Names not in
-- the guild are listed, never added. A pasted list only adds and updates:
-- nobody missing from it leaves the team. Like adding by hand, it lifts
-- removals.

local PASTE_ROLES = {
    tank = "TANK", tanks = "TANK", tnk = "TANK", prot = "TANK", protection = "TANK",
    guardian = "TANK", vengeance = "TANK", brewmaster = "TANK",
    healer = "HEALER", healers = "HEALER", heal = "HEALER", heals = "HEALER", hls = "HEALER",
    resto = "HEALER", restoration = "HEALER", disc = "HEALER", discipline = "HEALER", holy = "HEALER",
    mw = "HEALER", mistweaver = "HEALER", preservation = "HEALER",
    dps = "DPS", melee = "DPS", ranged = "DPS", damage = "DPS",
}
local PASTE_STATUS = {
    core = "core", main = "core", raider = "core", starter = "core",
    trial = "trial", trials = "trial", trialist = "trial",
    bench = "bench", backup = "bench", standby = "bench", reserve = "bench", sub = "bench",
}
-- A first line like "Name, Role, Status" is a header, not a missing member.
local PASTE_HEADER = { name = true, character = true, player = true, char = true }

local function realmKey(realm)
    return ((realm or ""):lower():gsub("[%s'%-]", ""))
end

-- Lines into cells: tabs if the line has any (a spreadsheet copy), else
-- commas, else semicolons, else spaces.
local function cellsOf(line)
    local sep = (line:find("\t", 1, true) and "\t") or (line:find(",", 1, true) and ",")
        or (line:find(";", 1, true) and ";")
    local out = {}
    if sep then
        for c in (line .. sep):gmatch("(.-)" .. sep) do
            out[#out + 1] = strtrim((c:gsub('^%s*"(.*)"%s*$', "%1")))
        end
    else
        for w in line:gmatch("%S+") do out[#out + 1] = w end
    end
    return out
end

-- Flat JSON objects, each with a "name" and maybe "realm", "role" and
-- "status" (or "rank"). Only the innermost objects are read, so a list
-- wrapped in { "characters": [ ... ] } works too.
local function jsonRows(text)
    local rows = {}
    for obj in text:gmatch("{[^{}]*}") do
        local function field(k) return obj:match('"' .. k .. '"%s*:%s*"([^"]*)"') end
        local name = field("name")
        if name then
            local realm = field("realm")
            rows[#rows + 1] = { realm and (name .. "-" .. realm) or name, field("role") or "",
                field("status") or field("rank") or "" }
        end
    end
    return rows
end

function PGM:ParseTeamPaste(text)
    text = text or ""
    if text:match("^%s*[%[{]") then return jsonRows(text) end
    local rows = {}
    for line in text:gmatch("[^\r\n]+") do
        local cells = cellsOf(line)
        if #cells > 0 then rows[#rows + 1] = cells end
    end
    return rows
end

-- The guild member a cell names, if any. A bare name shared by characters
-- on two realms is settled by a realm in another column.
local function memberIn(cell, row, g, full, short)
    local c = (strtrim(cell or ""):gsub("%s+", ""))
    if c == "" then return nil end
    local n, r = c:match("^([^%-]+)%-(.+)$")
    if n then return full[n:lower() .. "-" .. realmKey(r)] end
    local list = short[c:lower()]
    if not list then return nil end
    if #list > 1 then
        for _, other in ipairs(row) do
            local rk = realmKey(other)
            for _, guid in ipairs(list) do
                if rk ~= "" and realmKey(g.members[guid].realm) == rk then return guid end
            end
        end
    end
    return list[1]
end

-- What a pasted list would do to a team, without doing it: { add = {
-- { guid, role, status } }, change = { { guid, role?, status? } }, same =
-- how many are already on it as listed, unknown = { names not in the guild } }.
-- A role or status the list doesn't give comes from their notes and rank,
-- as with the notes import.
function PGM:PlanTeamPaste(id, text)
    local plan = { add = {}, change = {}, same = 0, unknown = {} }
    local t, g = PGM:TeamById(id), PGM.GuildDB()
    if not (t and g) then return plan end
    local full, short = {}, {}
    for guid, rec in pairs(g.members) do
        if rec.short then
            local s = rec.short:lower()
            short[s] = short[s] or {}
            table.insert(short[s], guid)
            full[s .. "-" .. realmKey(rec.realm or (rec.name or ""):match("%-(.+)$"))] = guid
        end
    end
    local seen = {}
    for _, row in ipairs(PGM:ParseTeamPaste(text)) do
        local guid, at
        for i, cell in ipairs(row) do
            guid = memberIn(cell, row, g, full, short)
            if guid then at = i break end
        end
        if not guid then
            local first = strtrim(row[1] or "")
            local header = false
            for _, cell in ipairs(row) do
                if PASTE_HEADER[strtrim(cell):lower()] then header = true end
            end
            if first ~= "" and not header then plan.unknown[#plan.unknown + 1] = first end
        elseif not seen[guid] then
            seen[guid] = true
            local role, status
            for i, cell in ipairs(row) do
                if i ~= at then
                    for word in cell:lower():gmatch("%a+") do
                        role = role or PASTE_ROLES[word]
                        status = status or PASTE_STATUS[word]
                    end
                end
            end
            local e = t.members[guid]
            if not e then
                local rec = g.members[guid]
                plan.add[#plan.add + 1] = { guid = guid, role = role or PGM:RoleFromNote(rec),
                    status = status or (looksTrial(rec) and "trial" or "core") }
            else
                role = role ~= e.role and role or nil
                status = status ~= e.status and status or nil
                if role or status then
                    plan.change[#plan.change + 1] = { guid = guid, role = role, status = status }
                else
                    plan.same = plan.same + 1
                end
            end
        end
    end
    return plan
end

-- Carry out a plan from PlanTeamPaste. Returns how many joined and how many
-- had their role or status changed.
function PGM:ApplyTeamPaste(id, plan)
    local t = PGM:TeamById(id)
    if not (t and plan) or not canEdit() then return 0, 0 end
    local added, changed = 0, 0
    for _, a in ipairs(plan.add) do
        if not t.members[a.guid] then
            place(t, a.guid, a.role, a.status)
            added = added + 1
        end
    end
    for _, c in ipairs(plan.change) do
        local e = t.members[c.guid]
        if e then
            e.role = c.role or e.role
            e.status = c.status or e.status
            share("SyncSpot", t, c.guid)
            changed = changed + 1
        end
    end
    if added + changed > 0 then PGM:Fire("TEAMS") end
    return added, changed
end

-- Teams set to stay in sync pick up newly tagged recruits after each roster
-- read. (Alts are resolved first: Alts.lua listens for ROSTER before this.)
-- Only worth redoing when notes, ranks, the roster, alt links or the teams
-- themselves changed since last time; most roster reads change none of them.
local importedFor
PGM:On("TEAMS", function() importedFor = nil end)
PGM:On("ROSTER", function()
    if not canEdit() then return end
    -- Not until this login's catch-up is in: before it, a member another
    -- officer removed while we were away would look new and be re-added.
    if PGM.SyncSettled and not PGM:SyncSettled() then return end
    local v = (PGM.notesVersion or 0) .. ":" .. (PGM.altsVersion or 0)
    if importedFor == v then return end
    importedFor = v
    local added = 0
    for _, t in ipairs(PGM:Teams()) do
        if t.autoSync then added = added + PGM:ImportTeamFromNotes(t.id, true) end
    end
    if added > 0 then PGM:Fire("TEAMS") end
end)
