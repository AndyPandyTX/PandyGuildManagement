-- TeamPaste.lua (UI): paste a roster into a raid team. Copy the cells from a
-- spreadsheet (a wowaudit sheet, say), or paste CSV or a bot's JSON, and see
-- what it would do before anything changes. Teams.lua does the reading;
-- PasteBox.lua is the window.

local _, NS = ...
local PGM = NS.PGM
local C = PGM.C
local UI = PGM.UI

local function names(list, fmt)
    local g = PGM.GuildDB()
    local parts = {}
    for _, it in ipairs(list) do
        local rec = g and g.members[it.guid]
        if rec then parts[#parts + 1] = fmt(it, rec) end
    end
    return table.concat(parts, ", ")
end

local function spot(role, status)
    local bits = {}
    if role then bits[#bits + 1] = PGM.Hex(PGM.ROLE_COLOR[role]) .. PGM.ROLE_LABEL[role] .. "|r" end
    if status then bits[#bits + 1] = PGM.Hex(PGM.STATUS_COLOR[status]) .. PGM.STATUS_LABEL[status] .. "|r" end
    return table.concat(bits, " ")
end

local function describe(plan)
    if #plan.add + #plan.change + plan.same + #plan.unknown == 0 then
        return PGM.Hex(C.text3) .. "Nothing to import yet.|r", false
    end
    local lines = {}
    lines[#lines + 1] = ("%sAdds %d|r   %sUpdates %d|r   %s%d already on the team|r"):format(
        PGM.Hex(C.jade), #plan.add, PGM.Hex(C.accent), #plan.change, PGM.Hex(C.text2), plan.same)
    if #plan.add > 0 then
        lines[#lines + 1] = PGM.Hex(C.text2) .. "Adds:|r " .. names(plan.add, function(it, rec)
            return PGM.ColorName(rec) .. " (" .. spot(it.role, it.status) .. ")"
        end)
    end
    if #plan.change > 0 then
        lines[#lines + 1] = PGM.Hex(C.text2) .. "Updates:|r " .. names(plan.change, function(it, rec)
            return PGM.ColorName(rec) .. " to " .. spot(it.role, it.status)
        end)
    end
    if #plan.unknown > 0 then
        lines[#lines + 1] = PGM.Hex(C.amber) .. "Not in the guild, skipped:|r " .. table.concat(plan.unknown, ", ")
    end
    return table.concat(lines, "\n\n"), #plan.add + #plan.change > 0
end

function UI:ShowTeamPaste(team)
    local id = team.id
    UI:ShowPasteBox({
        title = "Paste a list into " .. team.name,
        hint = "One character per line. Copy the cells from a spreadsheet (name, and optionally role and Core / Trial / Bench), or paste CSV. Only adds and updates; nobody is taken off the team.",
        preview = function(text) return describe(PGM:PlanTeamPaste(id, text)) end,
        import = function(text)
            local t = PGM:TeamById(id)
            if not t then return end
            local added, changed = PGM:ApplyTeamPaste(id, PGM:PlanTeamPaste(id, text))
            PGM.Print(("%s: added %d, updated %d from the pasted list."):format(t.name, added, changed))
        end,
    })
end
