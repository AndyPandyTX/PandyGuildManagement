-- Crafters.lua (UI): a "Guild crafters" panel on Blizzard's profession
-- window. Pick a recipe (in your own profession, or a guildie's recipe view)
-- and it lists the guildies who know it, online first: click to whisper,
-- right-click for more. It hangs off the window's right edge on the recipe
-- page only, and the header folds it away.
--
-- It's a plain frame parented to Blizzard's: nothing of theirs is changed,
-- and the recipe comes from the event their recipe list already sends.

local _, NS = ...
local PGM = NS.PGM
local C = PGM.C
local UI = PGM.UI
local W = UI.W

local WIDTH, HEIGHT = 220, 320
local panel
local current   -- { recipe, line, name }

local function whisperTarget(it)
    return it.rec.online and it.rec or it.onlineAs or it.rec
end

local function row(list)
    local r = W.Row(list)
    r.name = W.FS(r, 11, C.text)
    r.name:SetPoint("LEFT", 6, 0)
    r.name:SetWidth(100)
    r.status = W.FS(r, 10, C.text2, "RIGHT")
    r.status:SetPoint("RIGHT", -4, 0)
    r.status:SetWidth(96)
    r:SetScript("OnClick", function(s, button)
        local it = s.it
        if button == "RightButton" then
            UI:MemberMenu(s, it.guid)
        else
            UI:Whisper(whisperTarget(it))
        end
    end)
    r.onEnter = function(s)
        local it = s.it
        GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
        GameTooltip:SetText(PGM.ColorName(it.rec))
        local main = PGM.GuildDB() and PGM.GuildDB().members[it.main]
        if it.main ~= it.guid and main then GameTooltip:AddLine(main.short .. "'s alt", 0.7, 0.55, 1) end
        if not it.rec.online and it.onlineAs then
            GameTooltip:AddLine("Online now as " .. it.onlineAs.short, 0.33, 0.82, 0.58)
        end
        GameTooltip:AddLine("Click to whisper" .. (it.rec.online and "" or (it.onlineAs and (" " .. it.onlineAs.short) or "")),
            0.45, 0.45, 0.45)
        GameTooltip:Show()
    end
    return r
end

local function update(r, it)
    r.it = it
    r.name:SetText(PGM.ColorName(it.rec))
    if it.rec.online then
        r.status:SetText(PGM.Hex(C.jade) .. "Online|r")
    elseif it.onlineAs then
        r.status:SetText(PGM.Hex(C.jade) .. "as " .. (it.onlineAs.short or "?") .. "|r")
    else
        r.status:SetText(PGM.AgoText(it.rec.lastOnline))
    end
    local alpha = (it.rec.online or it.onlineAs) and 1 or 0.5
    r.name:SetAlpha(alpha)
    r.status:SetAlpha(alpha)
end

local function folded()
    return PGM.opt("craftersFolded") and true or false
end

local function paint()
    if not panel then return end
    local fold = folded()
    panel:SetHeight(fold and 26 or HEIGHT)
    panel.body:SetShown(not fold)
    panel.arrow:SetText(fold and "+" or "-")
    if fold then return end
    if not IsInGuild() then
        panel.recipe:SetText("")
        panel.count:SetText("Not in a guild on this character.")
        panel.list:SetData({})
        return
    end
    if not current then
        panel.recipe:SetText("")
        panel.count:SetText("Pick a recipe to see which guildies know it.")
        panel.list:SetData({})
        return
    end
    panel.recipe:SetText(current.name or "")
    local list = PGM:KnownCrafters(current.line, current.recipe)
    if not list then
        panel.count:SetText(PGM.Hex(C.text3) .. (PGM:CraftersAsking(current.line, current.recipe)
            and "Asking the guild...|r" or "No answer from the server. Pick the recipe again to ask again.|r"))
        panel.list:SetData({})
        return
    end
    local on = 0
    for _, it in ipairs(list) do if it.rec.online or it.onlineAs then on = on + 1 end end
    if #list == 0 then
        panel.count:SetText("Nobody in the guild knows this one.")
    else
        panel.count:SetText(("%d %s it  ·  %s%d online|r"):format(#list, #list == 1 and "guildie knows" or "guildies know",
            PGM.Hex(C.jade), on))
    end
    panel.list:SetData(list)
end

local function choose(recipeInfo)
    local recipe = recipeInfo and PGM.Plain(recipeInfo.recipeID)
    if not recipe then return end
    local line = PGM:RecipeProfession(recipe)
    if not line then return end
    current = { recipe = recipe, line = line, name = PGM.Plain(recipeInfo.name) }
    PGM:RecipeCrafters(line, recipe, function() paint() end)
    paint()
end

local function build()
    if panel or not ProfessionsFrame then return end
    -- On the recipe page only; the window's other tabs don't have a recipe.
    local parent = ProfessionsFrame.CraftingPage or ProfessionsFrame
    panel = CreateFrame("Frame", "PandyGuildManagementCrafters", parent, "BackdropTemplate")
    panel:SetSize(WIDTH, HEIGHT)
    panel:SetPoint("TOPLEFT", ProfessionsFrame, "TOPRIGHT", 4, -24)
    W.Backdrop(panel, C.bg, C.frame, 0.96)
    panel:SetFrameStrata(ProfessionsFrame:GetFrameStrata())

    local head = CreateFrame("Button", nil, panel)
    head:SetPoint("TOPLEFT")
    head:SetPoint("TOPRIGHT")
    head:SetHeight(26)
    local title = W.FS(head, 12, C.accent)
    title:SetPoint("LEFT", 8, 0)
    title:SetText("Guild crafters")
    panel.arrow = W.FS(head, 14, C.text2, "RIGHT")
    panel.arrow:SetPoint("RIGHT", -8, 0)
    head:SetScript("OnClick", function()
        PGM.setOpt("craftersFolded", not folded() or nil)
        paint()
    end)
    head:SetScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_TOP")
        GameTooltip:SetText("Pandy Guild Management", 1, 1, 1)
        GameTooltip:AddLine("Guildies who know the selected recipe, from the game's guild data. Click to fold.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    head:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local body = CreateFrame("Frame", nil, panel)
    body:SetPoint("TOPLEFT", 0, -26)
    body:SetPoint("BOTTOMRIGHT")
    panel.body = body
    local line = W.Divider(body)
    line:SetPoint("TOPLEFT", 8, 0)
    line:SetPoint("TOPRIGHT", -8, 0)
    panel.recipe = W.FS(body, 12, C.text)
    panel.recipe:SetPoint("TOPLEFT", 8, -8)
    panel.recipe:SetPoint("TOPRIGHT", -8, -8)
    panel.count = W.FS(body, 10, C.text2)
    panel.count:SetPoint("TOPLEFT", 8, -26)
    panel.count:SetPoint("TOPRIGHT", -8, -26)
    panel.count:SetWordWrap(true)
    panel.list = W.List(body, 20, row, update)
    panel.list:SetPoint("TOPLEFT", 4, -46)
    panel.list:SetPoint("BOTTOMRIGHT", -4, 6)

    -- Blizzard's recipe list says when a recipe is picked.
    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("ProfessionsRecipeListMixin.Event.OnRecipeSelected", function(_, recipeInfo)
            choose(recipeInfo)
        end, panel)
    end
    panel:SetScript("OnShow", paint)
    paint()
end

PGM:On("CRAFTERS", function() paint() end)
PGM:On("ROSTER", function() if panel and panel:IsVisible() then paint() end end)

-- Blizzard's profession window loads on demand.
if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_Professions") then
    build()
else
    PGM:RegisterEvent("ADDON_LOADED", function(_, name)
        if name == "Blizzard_Professions" then build() end
    end)
end
