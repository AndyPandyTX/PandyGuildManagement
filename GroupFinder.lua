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

-- A post (as G:Post takes it) for that activity.
local function postFor(id, entry)
    local a = readable(call(LFG.GetActivityInfoTable, id))
    if not a then return nil end
    local full = str(a.fullName) or ""
    local what, paren = full:match("^(.-)%s*%((.-)%)%s*$")
    what = what or full
    local kind = "O"
    if P(a.isMythicPlusActivity) then
        kind = "M"
    elseif P(a.isCurrentRaidActivity) or num(a.categoryID) == 3 then
        kind = "R"
    elseif full:lower():find("delve", 1, true) then
        kind = "D"
    end
    local level = ""
    if kind == "M" then
        local map, keyLevel = G.ReadMyKey()
        local mine = map and G.DungeonName(map)
        if mine and full:find(mine, 1, true) then
            level = tostring(keyLevel)
        else
            local ok, lv = pcall(string.match, str(entry and entry.name) or "", "%+(%d+)")
            level = ok and lv or ""
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
        dismissed, lastSig = false, nil
        G:Fire("POSTS")
        return
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
