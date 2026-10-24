-- GroupFinder.lua: Blizzard's Group Finder, with the guild in it.
--
-- LIST ONCE: list a group in the Group Finder and it's posted to the guild
-- too: the dungeon, your key's level, the roles still open (from who's in
-- your group). Delisting closes the guild post. Closing the guild post by
-- hand (or it filling) leaves the listing alone and doesn't post it again.
--
-- APPLICANTS: everyone who applies is read here and shown on the Groups
-- page beside guild asks, guildies first, with their character's, main's and
-- warband's M+ scores and the roles each was earned on. Invite and Decline
-- go through the Group Finder, from your click.
--
-- IN BLIZZARD'S WINDOWS: search results led by a guildie (or with guildies
-- in them) and applicants who are guildies get a jade edge, and their
-- tooltips say who they are. Sorting is left to Blizzard (and to Premade
-- Groups Filter, if it's installed), so the two never fight.
--
-- MIDNIGHT: the Group Finder can hand back secret or locked values, mostly
-- inside restricted content. Every read goes through `readable` or PGM.Plain;
-- what can't be read is skipped.

local _, NS = ...
local G = NS.G
if not G.ok then return end
local PGM = G.PGM
local C = PGM.C
local P = PGM.Plain

-- A table from the game we may look inside, or nil.
local function readable(t)
    if type(t) ~= "table" then return nil end
    if issecretvalue and issecretvalue(t) then return nil end
    if issecrettable and issecrettable(t) then return nil end
    if canaccesstable and not canaccesstable(t) then return nil end
    return t
end

-- The first result of a game call, or nil if it failed.
local function call(fn, ...)
    if not fn then return nil end
    local ok, v = pcall(fn, ...)
    if ok then return v end
end

local function str(v)
    v = P(v)
    return type(v) == "string" and v or nil
end

local function num(v)
    v = P(v)
    return type(v) == "number" and v or nil
end

local LFG = C_LFGList or {}

-- ============================================================
-- MY LISTING -> A GUILD POST
-- ============================================================

-- The activity I'm listed for, and the entry, or nil.
local function listed()
    if not P(call(LFG.HasActiveEntryInfo)) then return nil end
    local entry = readable(call(LFG.GetActiveEntryInfo))
    local id = entry and (num(entry.activityID) or (readable(entry.activityIDs) and num(entry.activityIDs[1])))
    -- The same fallback OAK LFG Sorter uses when the ids come back locked.
    if not id and securecallfunction then
        local ok, v = pcall(securecallfunction, function()
            local e = LFG.GetActiveEntryInfo()
            local ids = e and e.activityIDs
            return type(ids) == "table" and ids[1] or nil
        end)
        id = ok and num(v) or nil
    end
    if id and id > 0 then return id, entry end
end

-- An activity's kind (G.KINDS), its name without the bracket, and what
-- was in the bracket ("Mythic Keystone", "Heroic", "Tier 8").
local function activityParts(a)
    local full = str(a.fullName) or ""
    local what, paren = full:match("^(.-)%s*%((.-)%)%s*$")
    what = what or full
    local kind = "O"
    if P(a.isMythicPlusActivity) then
        kind = "M"
    elseif P(a.isCurrentRaidActivity) or num(a.categoryID) == 3 then
        kind = "R"
    elseif num(a.categoryID) == 121 or full:lower():find("delve", 1, true) then
        kind = "D"
    end
    return kind, what, paren, full
end

-- A key level in some text: "14", "+14", "14+", "+ 14 Learning"...: the
-- same patterns RaiderIO reads them with, most certain first. Group Finder
-- titles and comments from other players are protected strings
-- ("|Ks1969|k0000000000000000|k") that the game draws but addons can't
-- read, so those are never parsed: their digits aren't the key.
local LEVEL_PATTERNS = { "%+%s*(%d+)", "(%d+)%s*%+", "^%s*(%d+)", "(%d+)" }
local function levelIn(text)
    if not text or text == "" or text:find("|K", 1, true) then return nil end
    for _, pat in ipairs(LEVEL_PATTERNS) do
        local ok, lv = pcall(string.match, text, pat)
        lv = ok and tonumber(lv)
        if lv and lv > 1 and lv < 40 then return lv end
    end
end

-- A post (as G:Post takes it) for that activity.
local function postFor(id, entry)
    local a = readable(call(LFG.GetActivityInfoTable, id))
    if not a then return nil end
    local kind, what, paren, full = activityParts(a)
    local level = ""
    if kind == "M" then
        local map, keyLevel = G.ReadMyKey()
        local mine = map and G.DungeonName(map)
        if mine and full:find(mine, 1, true) then
            level = tostring(keyLevel)
        else
            local lv = levelIn(str(entry and entry.name))
            level = lv and tostring(lv) or ""
        end
    elseif kind == "R" and paren then
        level = paren:sub(1, 1)          -- Normal, Heroic, Mythic
    elseif kind == "D" and paren then
        level = paren:match("%d+") or ""  -- the tier
    end
    local size = num(a.maxNumPlayers)
    size = (size and size > 1) and math.min(size, 40) or G.KIND_SIZE[kind]

    -- Still needed: the kind's usual roles, less who's already here.
    local need = {}
    for r, n in pairs(G.KIND_NEED[kind]) do need[r] = n end
    local function take(r)
        r = r or "D"
        if need[r] > 0 then need[r] = need[r] - 1 end
    end
    take(G.ROLE_OF[str(UnitGroupRolesAssigned("player")) or ""] or G.SpecRole())
    for _, m in ipairs(G.GroupNames()) do take(m.role) end

    local ok, note = pcall(G.Clean, str(entry and entry.comment) or "", 70)
    return { kind = kind, what = what, level = level, size = size, need = need,
             note = ok and note or "", guildFirst = 0, lfg = true, fromLFG = true }
end

local function signature(spec)
    return table.concat({ spec.kind, spec.what, spec.level, spec.size, spec.need.T, spec.need.H, spec.need.D, spec.note }, "|")
end

-- Closed by hand, or full: don't post this listing again until it's gone.
local dismissed = false
local lastSig

local closeMine = G.CloseMine
function G:CloseMine(why)
    if G.mine and G.mine.fromLFG then dismissed = true end
    return closeMine(self, why)
end

local function syncListing()
    local id, entry = listed()
    local p = G.mine
    if not id then
        if p and p.fromLFG then G:CloseMine("c") end
        if p and not p.fromLFG and p.lfg then
            p.lfg, p.u = false, PGM.Stamp(p.u)
            G.SendPost(p, true)
        end
        if G.wasListed then
            G.wasListed = false
            G:Fire("LISTED", false)
        end
        dismissed, lastSig = false, nil
        G:Fire("POSTS")
        return
    end
    if not G.wasListed then
        G.wasListed = true
        G:Fire("LISTED", true)
    end
    -- A post made by hand: it just says it's in the Group Finder too.
    if p and not p.fromLFG then
        if not p.lfg then
            p.lfg, p.u = true, PGM.Stamp(p.u)
            G.SendPost(p, true)
            G:Fire("POSTS")
        end
        return
    end
    if dismissed or G.opt("shareListing") == false or not G.IsLeader() or not G.CanTalk() then return end
    local spec = postFor(id, entry)
    if not spec then return end
    local sig = signature(spec)
    if p and sig == lastSig then return end
    if p then
        spec.id, spec.team = p.id, p.team
        if spec.note == "" then spec.note = p.note end
    end
    if G:Post(spec) then
        lastSig = sig
        if not p then PGM.Print(("Your Group Finder listing is posted to the guild too: %s."):format(G.PostTitle(G.mine))) end
    end
end

local syncTimer
local function queueSync()
    if syncTimer then return end
    syncTimer = C_Timer.NewTimer(1, function()
        syncTimer = nil
        syncListing()
    end)
end

-- For the Groups page: am I listed?
function G:IsListed()
    return listed() ~= nil
end

-- ============================================================
-- APPLICANTS
-- ============================================================

local apps = {}
local firstSeen, told = {}, {}

local function readApplicants()
    wipe(apps)
    for _, raw in ipairs(readable(call(LFG.GetApplicants)) or {}) do
        local id = num(raw)
        local info = id and readable(call(LFG.GetApplicantInfo, id))
        local status = info and str(info.applicationStatus)
        if status == "applied" or status == "invited" then
            firstSeen[id] = firstSeen[id] or GetTime()
            local members = num(info.numMembers) or 1
            local comment = G.Clean(str(info.comment) or "", 60)
            for i = 1, members do
                local ok, name, class, _, _, ilvl, _, tank, healer, damage, assigned, _, score, _, _, _, spec =
                    pcall(LFG.GetApplicantMemberInfo, id, i)
                name = ok and str(name)
                if name then
                    -- Same-realm applicants come without a realm; give them ours
                    -- so they match guild asks ("Name-Realm") and the roster.
                    local short, realm = name:match("^([^-]+)-(.+)$")
                    if not short then
                        short, realm = name, (GetNormalizedRealmName and GetNormalizedRealmName()) or nil
                        if realm then name = short .. "-" .. realm end
                    end
                    local rec = G.RecByName(name)
                    local role = G.ROLE_OF[str(assigned) or ""]
                        or (P(tank) and "T") or (P(healer) and "H") or "D"
                    local a = {
                        name = name, short = short or name, realm = realm, class = str(class), role = role,
                        offers = { T = P(tank) and true, H = P(healer) and true, D = P(damage) and true },
                        ilvl = math.floor(num(ilvl) or 0), spec = num(spec) or 0, note = comment,
                        score = num(score) or 0, at = firstSeen[id], members = members,
                        state = status == "invited" and "invited" or "new",
                    }
                    apps[#apps + 1] = { key = "lfg:" .. id .. ":" .. i, app = true, applicantID = id, rec = rec, ask = a }
                    if rec and status == "applied" and not told[name] then
                        told[name] = true
                        PGM.Print(("%s applied through the Group Finder as %s. %s"):format(G.WhoText(rec),
                            G.RoleText(role, true), G.ScoreLine(G.Scores(a.short, realm, a.score))))
                    end
                end
            end
        end
    end
    G:Fire("POSTS")
end

local appTimer
local function queueApplicants()
    if appTimer then return end
    appTimer = C_Timer.NewTimer(0.3, function()
        appTimer = nil
        readApplicants()
    end)
end

function G:Applicants()
    return apps
end

local function appByKey(key)
    for _, it in ipairs(apps) do
        if it.key == key then return it end
    end
end

-- From a click. True if it was a Group Finder applicant.
function G:InviteApplicant(key)
    local it = appByKey(key)
    if not it then return false end
    if LFG.InviteApplicant then pcall(LFG.InviteApplicant, it.applicantID) end
    return true
end

function G:DeclineApplicant(key)
    local it = appByKey(key)
    if not it then return false end
    if LFG.DeclineApplicant then pcall(LFG.DeclineApplicant, it.applicantID) end
    return true
end

-- ============================================================
-- SEARCHING
-- ============================================================

-- The same searches OAK LFG Sorter and the Group Finder make. A search is
-- a hardware-event call: it only works from a click, like Apply.
local function mask(name, fallback)
    local f = Enum and Enum.LFGListFilter
    return (f and f[name]) or fallback or 0
end
local bor = (bit and bit.bor) or function(a, b) return a + b end

G.FINDER_CATS = {
    { id = "M", label = "Mythic+", cat = 2, filters = function() return bor(mask("CurrentSeason", 0x40), mask("PvE")) end },
    { id = "R", label = "Raids", cat = 3, filters = function() return mask("Recommended") end },
    { id = "D", label = "Delves", cat = 121 },
    { id = "O", label = "Custom", cat = 6 },
}

-- From a click. True, or false and why not.
function G:SearchFinder(kind)
    local c
    for _, x in ipairs(G.FINDER_CATS) do
        if x.id == kind then c = x end
    end
    if not (c and LFG.Search) then return false, "The Group Finder can't search right now." end
    if listed() then return false, "You're listed, so the game won't search. Delist first." end
    local lang = readable(call(LFG.GetLanguageSearchFilter))
    local panel = LFGListFrame and LFGListFrame.SearchPanel
    local cross = panel and panel.searchCrossFactionListings
    if cross == nil then cross = true end
    local adv = kind == "M" and readable(call(LFG.GetAdvancedFilter)) or nil
    local ok, err = pcall(LFG.Search, c.cat, c.filters and c.filters() or 0, mask("PvE"), lang, cross, adv)
    if not ok then return false, tostring(err) end
    G.searchKind, G.searchedAt = kind, GetTime()
    return true
end

local BREZ = { DRUID = true, DEATHKNIGHT = true, WARLOCK = true, PALADIN = true }
local LUST = { MAGE = true, SHAMAN = true, EVOKER = true, HUNTER = true }

local results = {}
local declinedAt = {}   -- [resultID] = when I saw it turn declined

local DECLINED = { declined = true, declined_full = true, declined_delisted = true }
local PIN_DECLINED = 120   -- a decline stays at the top this long

-- My application to a result: "applied", "invited", "declined"... or nil.
local function appStatus(id)
    local ok, a, b = pcall(LFG.GetApplicationInfo, id)
    if not ok then return nil end
    local s = readable(a) and str(a.applicationStatus) or str(b)
    return (s and s ~= "none") and s or nil
end

local function keyLevelOf(info)
    return levelIn(str(info.name)) or levelIn(str(info.comment)) or 0
end

local function playstyleOf(info, a)
    local v = num(info.generalPlaystyle)
    if not (v and v > 0 and LFG.GetPlaystyleString) then return nil end
    local ok, s = pcall(LFG.GetPlaystyleString, nil, v, a)
    return ok and str(s) or nil
end

-- What a result's group already has, and so still needs.
local function rolesOf(id, kind, size)
    local counts = readable(call(LFG.GetSearchResultMemberCounts, id)) or {}
    local has = { T = num(counts.TANK) or 0, H = num(counts.HEALER) or 0, D = num(counts.DAMAGER) or 0 }
    local need = { T = num(counts.TANK_REMAINING), H = num(counts.HEALER_REMAINING), D = num(counts.DAMAGER_REMAINING) }
    if not (need.T and need.H and need.D) then
        -- No "remaining" counts: a five-player group wants 1 / 1 / 3.
        local base = size <= 5 and { T = 1, H = 1, D = 3 } or G.KIND_NEED[kind]
        for _, r in ipairs(G.ROLES) do need[r] = math.max(0, base[r] - has[r]) end
    end
    return need, has
end

local function readResults()
    wipe(results)
    local ok, _, list = pcall(LFG.GetSearchResults)
    for _, raw in ipairs(ok and readable(list) or {}) do
        local id = num(raw)
        local info = id and readable(call(LFG.GetSearchResultInfo, id))
        if info and not P(info.isDelisted) then
            local act = num(info.activityID) or (readable(info.activityIDs) and num(info.activityIDs[1]))
            local a = act and readable(call(LFG.GetActivityInfoTable, act))
            if a then
                local kind, what, paren = activityParts(a)
                local size = num(a.maxNumPlayers) or G.KIND_SIZE[kind]
                local level = ""
                if kind == "M" then
                    local lv = keyLevelOf(info)
                    level = lv > 0 and tostring(lv) or ""
                elseif kind == "R" and paren then
                    level = paren:sub(1, 1)
                elseif kind == "D" and paren then
                    level = paren:match("%d+") or ""
                end
                local need, has = rolesOf(id, kind, size)
                local members = num(info.numMembers) or 1
                -- Who's in it: class, role and spec, for the comp slots.
                local classes, comp, brez, lust = {}, {}, false, false
                for i = 1, members do
                    local pi = readable(call(LFG.GetSearchResultPlayerInfo, id, i))
                    local class = pi and (str(pi.classFilename) or str(pi.classFileName))
                    local role = pi and str(pi.assignedRole)
                    local spec = pi and (num(pi.specID) or num(pi.specializationID) or num(pi.specId))
                    local specName = pi and (str(pi.specName) or str(pi.specializationName) or str(pi.localizedSpecName))
                    if pi and readable(pi.lfgRoles) then
                        local lr = pi.lfgRoles
                        role = (P(lr.tank) and "TANK") or (P(lr.healer) and "HEALER") or (P(lr.dps) and "DAMAGER") or role
                    end
                    if not class and LFG.GetSearchResultMemberInfo then
                        local okm, r, cls = pcall(LFG.GetSearchResultMemberInfo, id, i)
                        if okm then class, role = str(cls), role or str(r) end
                    end
                    if class then
                        classes[#classes + 1] = class
                        comp[#comp + 1] = { class = class, role = G.ROLE_OF[role or ""] or "D", spec = spec, specName = specName,
                                            leader = pi and P(pi.isLeader) and true or false }
                        brez = brez or BREZ[class] or false
                        lust = lust or LUST[class] or false
                    end
                end
                local leader = str(info.leaderName)
                results[#results + 1] = {
                    id = id, kind = kind, what = what, level = level, size = size,
                    -- "Heroic", "Mythic", "Tier 8": what the activity's bracket says.
                    diff = (kind == "R" or kind == "D") and paren or nil,
                    need = need, has = has, members = members, classes = classes, comp = comp, brez = brez, lust = lust,
                    leader = leader, rec = leader and G.RecByName(leader) or nil,
                    mates = num(info.numGuildMates) or 0,
                    score = num(info.leaderOverallDungeonScore) or 0,
                    playstyle = playstyleOf(info, a), age = num(info.age) or 0,
                    -- The title as the game gave it: only ever drawn, never read.
                    title = str(info.name),
                    note = G.Clean(str(info.comment) or "", 60),
                    status = appStatus(id),
                }
            end
        end
    end
    for _, r in ipairs(results) do
        if DECLINED[r.status or ""] then
            declinedAt[r.id] = declinedAt[r.id] or GetTime()
        else
            declinedAt[r.id] = nil
        end
    end
    G.resultsAt = GetTime()
    G:Fire("FINDER")
end

local resultsTimer
local function queueResults()
    if resultsTimer then return end
    resultsTimer = C_Timer.NewTimer(0.3, function()
        resultsTimer = nil
        readResults()
    end)
end

function G:FinderResults()
    return results
end

-- Apply to a result, from a click: as `role`, or every role I play.
function G:ApplyFinder(id, role)
    local roles = role and { [role] = true } or G.MyRoles()
    local ok = LFG.ApplyToGroup and pcall(LFG.ApplyToGroup, id, roles.T or false, roles.H or false, roles.D or false)
    if not ok then PGM.Print("The game wouldn't send that application. Apply from the Group Finder instead.") end
    -- Pending at once, pinned to the top; the game's own status follows.
    for _, r in ipairs(results) do
        if r.id == id and ok then r.status = "applied" end
    end
    G:Fire("FINDER")
    queueResults()
end

function G:CancelFinder(id)
    if LFG.CancelApplication then pcall(LFG.CancelApplication, id) end
    for _, r in ipairs(results) do
        if r.id == id then r.status = nil end
    end
    G:Fire("FINDER")
    queueResults()
end

-- ============================================================
-- THE BOARD: GUILD POSTS AND THE GROUP FINDER, TOGETHER
-- ============================================================

-- Where my own request to a row stands: "pending", "invited", "joined",
-- "declined", or nil. Group Finder applications and guild asks alike.
function G:RowState(row)
    local res, p = row.result, row.post
    if res and res.status then
        local st = res.status
        if st == "applied" then return "pending" end
        if st == "invited" then return "invited" end
        if st == "inviteaccepted" then return "joined" end
        if DECLINED[st] then return "declined", declinedAt[res.id] end
        return nil
    end
    local a = p and G.asked[p.id]
    if a then
        if a.state == "asked" then return "pending" end
        if a.state == "invited" then return "invited" end
        if a.state == "declined" then return "declined", a.declinedAt end
    end
end

-- One row of the board: a guild post, a Group Finder result, or both (a
-- guildie's listing that's also on the guild board).
local function fromPost(p)
    local g = PGM.GuildDB()
    local rec = g and g.members[p.leader or ""]
    return {
        post = p, kind = p.kind, what = p.what, level = p.level, size = p.size, need = p.need,
        rec = rec, guild = true, note = p.note, scheduled = (p.start or 0) > 0,
        diff = p.kind == "R" and ({ N = "Normal", H = "Heroic", M = "Mythic" })[(p.level or ""):upper():sub(1, 1)] or nil,
        score = (rec and PGM:MPlusScore(rec)) or 0, u = p.u or 0,
    }
end

local function fromResult(r)
    return {
        result = r, kind = r.kind, what = r.what, level = r.level, size = r.size, need = r.need, has = r.has,
        rec = r.rec, guild = r.rec ~= nil or r.mates > 0, note = r.note, score = r.score,
        playstyle = r.playstyle, brez = r.brez, lust = r.lust, comp = r.comp, u = PGM.Now() - (r.age or 0),
        diff = r.diff,
    }
end

-- The board's rows for filter settings f (see the Groups page).
function G:Board(f)
    local rows, byLeader = {}, {}
    for _, p in ipairs(G:PostList()) do
        if not (p.mine and (p.start or 0) == 0) and (f.scheduled or (p.start or 0) == 0) then
            local row = fromPost(p)
            rows[#rows + 1] = row
            if row.rec and (p.start or 0) == 0 then byLeader[row.rec.guid] = row end
        end
    end
    for _, r in ipairs(results) do
        local merged = r.rec and byLeader[r.rec.guid]
        if merged then
            merged.result, merged.has, merged.playstyle, merged.comp = r, r.has, r.playstyle, r.comp
            merged.brez, merged.lust, merged.score = r.brez, r.lust, math.max(merged.score, r.score)
        elseif not (r.rec and r.rec.guid == PGM:MyGuid()) then
            rows[#rows + 1] = fromResult(r)
        end
    end

    local roles = G.MyRoles()
    local out = {}
    for _, row in ipairs(rows) do
        local keep = (not f.kind or row.kind == f.kind)
            and (not f.guildOnly or row.guild)
            and ((tonumber(f.minRating) or 0) <= 0 or row.score >= tonumber(f.minRating))
            and (not f.playstyle or row.playstyle == f.playstyle)
            and not (f.skip and f.skip[row.what])
            and (not f.needTank or (row.need.T or 0) > 0)
            and (not f.needHealer or (row.need.H or 0) > 0)
            and (not f.needDps or (row.need.D or 0) > 0)
            and (not f.hasTank or (row.has and row.has.T > 0) or (not row.has and row.need.T == 0))
            and (not f.hasHealer or (row.has and row.has.H > 0) or (not row.has and row.need.H == 0))
            and (not f.brez or row.brez ~= false)
            and (not f.lust or row.lust ~= false)
        if keep and f.fitsMe then
            keep = false
            for r in pairs(roles) do
                if (row.need[r] or 0) > 0 then keep = true end
            end
        end
        -- Groups I've asked to join sit on top whatever the filters say;
        -- a decline stays there a couple of minutes, then Hide declined
        -- hides it like any other.
        local state, since = G:RowState(row)
        row.state = state
        row.pinned = state ~= nil and (state ~= "declined" or (since and GetTime() - since < PIN_DECLINED)) or false
        if keep and f.hideDeclined and state == "declined" then keep = false end
        if keep or row.pinned then out[#out + 1] = row end
    end
    for _, row in ipairs(out) do
        row.icon = row.kind == "M" and G.DungeonIconByName(row.what) or nil
    end
    table.sort(out, function(a, b)
        if a.pinned ~= b.pinned then return a.pinned end
        if f.guildFirst and a.guild ~= b.guild then return a.guild end
        if a.scheduled ~= b.scheduled then return b.scheduled end
        if a.scheduled then return a.post.start < b.post.start end
        if f.sort == "rating" and a.score ~= b.score then return a.score > b.score end
        return (a.u or 0) > (b.u or 0)
    end)
    return out
end

-- The dungeons, raids or delves to filter by: { name, icon, best }. For
-- Mythic+ that's this season's dungeons; otherwise what's on the board.
function G:BoardActivities(kind)
    if kind == "M" and #G.SeasonDungeons() > 0 then return G.SeasonDungeons() end
    local seen, out = {}, {}
    for _, r in ipairs(results) do
        if r.kind == kind and r.what ~= "" and not seen[r.what] then
            seen[r.what] = true
            out[#out + 1] = { name = r.what }
        end
    end
    for _, p in pairs(G.posts) do
        if p.kind == kind and (p.what or "") ~= "" and not seen[p.what] then
            seen[p.what] = true
            out[#out + 1] = { name = p.what }
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-- Playstyles seen on the board ("Relaxed", "Learning"...), for the cycle.
function G:BoardPlaystyles()
    local seen, out = {}, {}
    for _, r in ipairs(results) do
        if r.playstyle and not seen[r.playstyle] then
            seen[r.playstyle] = true
            out[#out + 1] = r.playstyle
        end
    end
    table.sort(out)
    return out
end

-- ============================================================
-- TELLING THE GUILD, AND LISTING MY KEY
-- ============================================================

-- The keystone in my bags, as a chat link, or nil.
function G.MyKeyLink()
    if not (C_Container and C_Item and C_Item.IsItemKeystoneByID) then return nil end
    for bag = 0, 4 do
        for slot = 1, num(call(C_Container.GetContainerNumSlots, bag)) or 0 do
            local id = num(call(C_Container.GetContainerItemID, bag, slot))
            if id and P(call(C_Item.IsItemKeystoneByID, id)) then
                return str(call(C_Container.GetContainerItemLink, bag, slot))
            end
        end
    end
end

-- "1 Tank, 2 DPS", for chat: no colours or icons.
local function needsPlain(need)
    local parts = {}
    for _, r in ipairs(G.ROLES) do
        local n = need[r] or 0
        if n > 0 then parts[#parts + 1] = n .. " " .. PGM.ROLE_LABEL[G.ROLE_KEY[r]] end
    end
    return #parts > 0 and table.concat(parts, ", ") or "anyone"
end

-- The guild chat line for my group, from the template in settings. {key}
-- is my keystone's link when the group is for it.
function G:AnnounceText(p)
    p = p or G.mine
    if not p then return nil end
    local key = G.PostTitle(p)
    if p.kind == "M" then
        local map = G.ReadMyKey()
        local dungeon = map and G.DungeonName(map)
        local link = G.MyKeyLink()
        if link and dungeon and (p.what or ""):find(dungeon, 1, true) then key = link end
    end
    local name = UnitName("player")
    name = str(name) or ""
    local text = G.opt("announce")
    if not text or strtrim(text) == "" then text = "{key} - needs {needs}. Whisper me to join!" end
    -- Functions, not strings, as replacements: a link is full of "|" and
    -- a name can't be trusted to be free of "%".
    text = text:gsub("{key}", function() return key end)
    text = text:gsub("{needs}", function() return needsPlain(p.need) end)
    text = text:gsub("{name}", function() return name end)
    return text
end

-- Say it in guild chat. From a click (or /pgg tell), at most once a minute.
local lastAnnounce = -1000
function G:Announce()
    local text = G:AnnounceText()
    if not text then
        PGM.Print("Nothing to tell the guild: list a group, or post one, first.")
        return false
    end
    if GetTime() - lastAnnounce < 60 then
        PGM.Print("You told the guild under a minute ago.")
        return false
    end
    if PGM.SyncBlocked() then
        PGM.Print("Chat to the guild is blocked inside an instance.")
        return false
    end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    local ok = send and pcall(send, text, "GUILD")
    if not ok then
        PGM.Print("The game wouldn't send that to guild chat.")
        return false
    end
    lastAnnounce = GetTime()
    return true
end

-- Open the Group Finder's premade groups, from a click, to list my key.
-- That's as far as an addon may go: Start a Group's form is protected (it
-- sets the listing's title), and filling it in from addon code gets the
-- call blocked. Blizzard fills in the player's own keystone when they pick
-- Dungeons and Start a Group themselves.
function G:ListMyKey()
    if listed() then
        PGM.Print("You're already listed in the Group Finder.")
        return
    end
    if PVEFrame_ShowFrame then pcall(PVEFrame_ShowFrame, "GroupFinderFrame", "LFGListPVEStub") end
    local map, level = G.ReadMyKey()
    local key = map and (" (+" .. level .. " " .. (G.DungeonName(map) or "your key") .. ")") or ""
    PGM.Print("Group Finder is open: click Dungeons, then Start a Group. It fills in your keystone" .. key
        .. ", then List Group.")
end

-- ============================================================
-- BLIZZARD'S WINDOWS
-- ============================================================

-- A jade edge and a faint wash on a row, for guild.
local function mark(frame, on)
    if not frame.pggEdge then
        if not on then return end
        frame.pggEdge = frame:CreateTexture(nil, "OVERLAY")
        frame.pggEdge:SetPoint("TOPLEFT", 0, 0)
        frame.pggEdge:SetPoint("BOTTOMLEFT", 0, 0)
        frame.pggEdge:SetWidth(3)
        frame.pggEdge:SetColorTexture(C.jade[1], C.jade[2], C.jade[3], 1)
        frame.pggWash = frame:CreateTexture(nil, "ARTWORK")
        frame.pggWash:SetAllPoints()
        frame.pggWash:SetColorTexture(C.jade[1], C.jade[2], C.jade[3], 0.07)
    end
    frame.pggEdge:SetShown(on)
    frame.pggWash:SetShown(on)
end

-- A search result's guild side: its leader's record and how many guildies.
local function guildOf(resultID)
    local info = num(resultID) and readable(call(LFG.GetSearchResultInfo, resultID))
    if not info then return nil, 0 end
    local leader = str(info.leaderName)
    local rec = leader and G.RecByName(leader) or nil
    return rec, num(info.numGuildMates) or 0, info
end

local function onSearchEntry(entry)
    if not entry then return end
    local rec, mates = guildOf(entry.resultID)
    mark(entry, rec ~= nil or mates > 0)
end

local function onSearchTooltip(tooltip, resultID)
    local rec, mates, info = guildOf(resultID)
    if not (rec or mates > 0) then return end
    tooltip:AddLine(" ")
    tooltip:AddLine(PGM.Hex(C.jade) .. "Guild group|r")
    if rec then
        tooltip:AddLine("Led by " .. G.WhoText(rec))
        G.AddScoreLines(tooltip, G.Scores(rec.short, rec.realm, num(info.leaderOverallDungeonScore)))
    end
    if mates > 0 then tooltip:AddLine(("%d guildie%s in it"):format(mates, mates == 1 and "" or "s"), 1, 1, 1) end
    tooltip:Show()
end

local function onApplicantEnter(member)
    local d = member.pggInfo
    if not d or GameTooltip:GetOwner() ~= member then return end
    GameTooltip:AddLine(" ")
    if d.rec then GameTooltip:AddLine(PGM.Hex(C.jade) .. "Guild:|r " .. G.WhoText(d.rec)) end
    GameTooltip:AddLine(G.ScoreLine(G.Scores(d.short, d.realm, d.score)), 1, 1, 1)
    GameTooltip:Show()
end

local function onApplicantMember(member, appID, memberIdx)
    if not member then return end
    local ok, name, _, _, _, _, _, _, _, _, _, _, score = pcall(LFG.GetApplicantMemberInfo, appID, memberIdx)
    name = ok and str(name)
    local rec = name and G.RecByName(name)
    mark(member, rec ~= nil)
    if name then
        local short, realm = name:match("^([^-]+)-(.+)$")
        member.pggInfo = { rec = rec, short = short or name, realm = realm, score = num(score) }
    else
        member.pggInfo = nil
    end
    if not member.pggHooked and member.HookScript then
        member.pggHooked = true
        member:HookScript("OnEnter", onApplicantEnter)
    end
end

local hooked = false
local function hookBlizzard()
    if hooked or not LFGListSearchEntry_Update then return end
    hooked = true
    hooksecurefunc("LFGListSearchEntry_Update", onSearchEntry)
    if LFGListUtil_SetSearchEntryTooltip then
        hooksecurefunc("LFGListUtil_SetSearchEntryTooltip", onSearchTooltip)
    end
    if LFGListApplicationViewer_UpdateApplicantMember then
        hooksecurefunc("LFGListApplicationViewer_UpdateApplicantMember", onApplicantMember)
    end
    -- Browsing groups in Blizzard's window (its list of groups opening):
    -- the Groups page can open beside it (see UI/Groups.lua).
    local panel = LFGListFrame and LFGListFrame.SearchPanel
    if panel and panel.HookScript then
        panel:HookScript("OnShow", function() G:Fire("FINDER_OPENED") end)
    end
end
hookBlizzard()

-- ============================================================
-- WHEN
-- ============================================================

G:RegisterEvent("PLAYER_LOGIN", hookBlizzard)
G:RegisterEvent("ADDON_LOADED", function(_, name)
    if name == "Blizzard_GroupFinder" then hookBlizzard() end
end)
G:RegisterEvent("LFG_LIST_ACTIVE_ENTRY_UPDATE", function()
    queueSync()
    queueApplicants()
end)
G:RegisterEvent("LFG_LIST_SEARCH_RESULTS_RECEIVED", queueResults)
G:RegisterEvent("LFG_LIST_SEARCH_RESULT_UPDATED", queueResults)
G:RegisterEvent("LFG_LIST_APPLICATION_STATUS_UPDATED", queueResults)
G:RegisterEvent("LFG_LIST_APPLICANT_LIST_UPDATED", queueApplicants)
G:RegisterEvent("LFG_LIST_APPLICANT_UPDATED", queueApplicants)
-- Someone joined: the roles still open changed.
G:RegisterEvent("GROUP_ROSTER_UPDATE", queueSync)
-- Out of an instance: share a listing made (or changed) while we couldn't.
G:RegisterEvent("PLAYER_ENTERING_WORLD", function()
    C_Timer.After(5, queueSync)
end)
G:On("READY", function()
    C_Timer.After(18, function()
        queueSync()
        queueApplicants()
    end)
end)
