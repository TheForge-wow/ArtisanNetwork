-- Artisan Network: profession scanning, encoding and the searchable recipe index
local ADDON, ns = ...

ns.PROFS = {
    [171] = { name = "Alchemy",        icon = "Interface\\Icons\\Trade_Alchemy" },
    [164] = { name = "Blacksmithing",  icon = "Interface\\Icons\\Trade_BlackSmithing" },
    [333] = { name = "Enchanting",     icon = "Interface\\Icons\\Trade_Engraving" },
    [202] = { name = "Engineering",    icon = "Interface\\Icons\\Trade_Engineering" },
    [755] = { name = "Jewelcrafting",  icon = "Interface\\Icons\\INV_Misc_Gem_01" },
    [773] = { name = "Inscription",    icon = "Interface\\Icons\\INV_Inscription_Tradeskill01" },
    [165] = { name = "Leatherworking", icon = "Interface\\Icons\\Trade_LeatherWorking" },
    [197] = { name = "Tailoring",      icon = "Interface\\Icons\\Trade_Tailoring" },
    [185] = { name = "Cooking",        icon = "Interface\\Icons\\INV_Misc_Food_15" },
    [129] = { name = "First Aid",      icon = "Interface\\Icons\\Spell_Holy_SealOfSacrifice" },
    [182] = { name = "Herbalism",      icon = "Interface\\Icons\\Spell_Nature_NatureTouchGrow", gather = true },
    [186] = { name = "Mining",         icon = "Interface\\Icons\\Trade_Mining",                 gather = true },
    [393] = { name = "Skinning",       icon = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01",        gather = true },
    [356] = { name = "Fishing",        icon = "Interface\\Icons\\Trade_Fishing",                gather = true },
}
ns.PROF_ORDER = { 171, 164, 333, 202, 755, 773, 165, 197, 185, 129, 182, 186, 393, 356 }

-- localized profession name -> skill line id
ns.profByName = {}
for id, p in pairs(ns.PROFS) do
    p.lname = p.name
    if C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillDisplayName then
        local ok, n = pcall(C_TradeSkillUI.GetTradeSkillDisplayName, id)
        if ok and type(n) == "string" and n ~= "" then p.lname = n end
    end
    ns.profByName[p.name:lower()] = id
    ns.profByName[p.lname:lower()] = id
end

function ns.ProfName(id)
    local p = ns.PROFS[id]
    return p and p.lname or ("Profession " .. tostring(id))
end
function ns.ProfIcon(id)
    local p = ns.PROFS[id]
    return p and p.icon or "Interface\\Icons\\INV_Misc_QuestionMark"
end
function ns.ProfIdFromName(name)
    return name and ns.profByName[name:lower()]
end
function ns.IsGathering(id)
    local p = ns.PROFS[id]
    return p and p.gather
end

------------------------------------------------------------------------
-- API compatibility (Retail-style client vs Classic-style client)
------------------------------------------------------------------------
local function SpellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    return GetSpellInfo and (GetSpellInfo(id)) or nil
end
local function SpellIcon(id)
    if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(id) end
    if GetSpellTexture then return GetSpellTexture(id) end
    return GetSpellInfo and select(3, GetSpellInfo(id)) or nil
end
local function SpellLink(id)
    if C_Spell and C_Spell.GetSpellLink then return C_Spell.GetSpellLink(id) end
    return GetSpellLink and GetSpellLink(id) or nil
end
local GetItemInfoCompat = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetItemIconCompat = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
local GetItemCountCompat = (C_Item and C_Item.GetItemCount) or GetItemCount
local GetItemInfoInstantCompat = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
ns.GetItemInfo = GetItemInfoCompat   -- for the other files

function ns.ItemIcon(id)
    return GetItemIconCompat and GetItemIconCompat(id) or nil
end

-- how many you carry; includeBank adds what's in your bank. 0 when unknown
function ns.ItemCount(id, includeBank)
    if not GetItemCountCompat then return 0 end
    local ok, n
    if includeBank then ok, n = pcall(GetItemCountCompat, id, true)
    else ok, n = pcall(GetItemCountCompat, id) end
    return ok and n or 0
end

ns.pendingItems = {}
function ns:RequestItem(id)
    if ns.pendingItems[id] then return end
    ns.pendingItems[id] = true
    if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
end
ns:On("GET_ITEM_INFO_RECEIVED", function(itemID)
    if itemID and ns.pendingItems[itemID] then
        ns.pendingItems[itemID] = nil
        ns:Debounce("iteminfo", 0.5, function() ns:MarkIndexDirty() end)
    end
end)

-- Which item a recipe spell creates. Learned when a profession window is scanned and
-- shared with other players; as a last resort the client is asked directly.
local noOutput = {}
function ns.OutputItem(spellID)
    local known = ns.db and ns.db.outputs[spellID]
    if known then return known end
    if noOutput[spellID] then return nil end
    noOutput[spellID] = true
    local T = C_TradeSkillUI
    if T and T.GetRecipeSchematic then
        local ok, s = pcall(T.GetRecipeSchematic, spellID, false)
        if ok and type(s) == "table" and (s.outputItemID or 0) > 0 then
            ns.db.outputs[spellID] = s.outputItemID
            return s.outputItemID
        end
    end
end

-- recipe keys are "s<spellID>" (preferred) or "i<itemID>" (fallback for clients without recipe links)
-- Item-making recipes use the crafted item's icon, link and tooltip; the recipe spell's own
-- icon is usually just the profession icon (or blank, which shows as the WoW logo).
function ns.RecipeInfo(key)
    local kind, id = key:sub(1, 1), tonumber(key:sub(2))
    if not id then return nil end
    if kind == "s" then
        local name, icon, link = SpellName(id), nil, nil
        local out = ns.OutputItem(id)
        if out then
            local iname, ilink = GetItemInfoCompat(out)
            if not iname then ns:RequestItem(out) end
            icon = GetItemIconCompat and GetItemIconCompat(out)
            link = ilink
            name = name or iname
        end
        return name, icon or SpellIcon(id), link or SpellLink(id)
    end
    local name, link, _, _, _, _, _, _, _, icon = GetItemInfoCompat(id)
    if not name then ns:RequestItem(id) end
    return name, icon or (GetItemIconCompat and GetItemIconCompat(id)), link
end

function ns.SetRecipeTooltip(tt, key)
    local kind, id = key:sub(1, 1), tonumber(key:sub(2))
    local out = kind == "s" and ns.OutputItem(id)
    local link = out and ("item:" .. out) or ((kind == "s" and "spell:" or "item:") .. tostring(id))
    if not pcall(tt.SetHyperlink, tt, link) then
        tt:AddLine((ns.RecipeInfo(key)) or key)
    end
end

------------------------------------------------------------------------
-- Skill levels
------------------------------------------------------------------------
------------------------------------------------------------------------
-- Specializations: each one is a spell the crafter knows. Stored as p[3] on a
-- profession entry, a "-"-joined list of short codes ("ds", "we-sw").
------------------------------------------------------------------------
local SPECS = {
    -- Leatherworking
    { spell = 10656, prof = 165, code = "ds", name = "Dragonscale" },
    { spell = 10658, prof = 165, code = "el", name = "Elemental" },
    { spell = 10660, prof = 165, code = "tr", name = "Tribal" },
    -- Engineering
    { spell = 20219, prof = 202, code = "gn", name = "Gnomish" },
    { spell = 20222, prof = 202, code = "gb", name = "Goblin" },
    -- Blacksmithing (a master smith is also a weaponsmith, so only the master is shown)
    { spell = 9788,  prof = 164, code = "ar", name = "Armorsmith" },
    { spell = 9787,  prof = 164, code = "we", name = "Weaponsmith" },
    { spell = 17039, prof = 164, code = "sw", name = "Master Swordsmith", master = true },
    { spell = 17040, prof = 164, code = "hm", name = "Master Hammersmith", master = true },
    { spell = 17041, prof = 164, code = "ax", name = "Master Axesmith", master = true },
    -- Tailoring and Alchemy (only exist on later rule sets; harmless otherwise)
    { spell = 26798, prof = 197, code = "mo", name = "Mooncloth" },
    { spell = 26801, prof = 197, code = "sh", name = "Shadoweave" },
    { spell = 26797, prof = 197, code = "sf", name = "Spellfire" },
    { spell = 28672, prof = 171, code = "tm", name = "Transmutation Master" },
    { spell = 28675, prof = 171, code = "pm", name = "Potion Master" },
    { spell = 28677, prof = 171, code = "em", name = "Elixir Master" },
}
local SPEC_NAME = {}
for _, sp in ipairs(SPECS) do SPEC_NAME[sp.code] = sp.name end

local function Knows(spell)
    if IsPlayerSpell then
        local ok, v = pcall(IsPlayerSpell, spell)
        if ok and v then return true end
    end
    if IsSpellKnown then
        local ok, v = pcall(IsSpellKnown, spell)
        if ok and v then return true end
    end
    return false
end

-- your specialization codes for one profession, or nil
local function DetectSpec(profId)
    local codes, master = {}, false
    for _, sp in ipairs(SPECS) do
        if sp.prof == profId and Knows(sp.spell) then
            codes[#codes + 1] = sp
            if sp.master then master = true end
        end
    end
    local out = {}
    for _, sp in ipairs(codes) do
        if not (master and sp.code == "we") then out[#out + 1] = sp.code end
    end
    return #out > 0 and table.concat(out, "-") or nil
end

-- "Dragonscale", "Master Swordsmith"... for a profession entry { rank, max, spec }, or nil
function ns.SpecName(p)
    local codes = type(p) == "table" and p[3]
    if not codes or codes == "" then return nil end
    local names = {}
    for code in codes:gmatch("[^-]+") do
        if SPEC_NAME[code] then names[#names + 1] = SPEC_NAME[code] end
    end
    return #names > 0 and table.concat(names, ", ") or nil
end

-- only letters and "-": the code travels inside our ":", ";", "," and "." separators
local function CleanSpec(s)
    s = s and s:gsub("[^%a%-]", "") or ""
    return s ~= "" and s:sub(1, 12) or nil
end

function ns:ScanSkillLevels()
    if not ns.me then return end
    local found = {}
    if GetProfessions and GetProfessionInfo then
        local list = { GetProfessions() }
        for i = 1, 6 do
            local idx = list[i]
            if idx then
                local name, _, rank, maxRank, _, _, skillLine = GetProfessionInfo(idx)
                local id = (skillLine and ns.PROFS[skillLine] and skillLine) or ns.ProfIdFromName(name)
                if id then found[id] = { rank or 0, maxRank or 0 } end
            end
        end
    end
    if not next(found) and GetNumSkillLines and GetSkillLineInfo then
        for i = 1, GetNumSkillLines() do
            local name, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
            if not isHeader then
                local id = ns.ProfIdFromName(name)
                if id then found[id] = { rank or 0, maxRank or 0 } end
            end
        end
    end
    -- skill data can be empty very early in loading; never wipe what we have in that case
    if not next(found) then return end
    for id, p in pairs(found) do p[3] = DetectSpec(id) end
    local rec = ns:MyRecord()
    rec.profs = found
    for id in pairs(rec.recipes) do
        if not found[id] then rec.recipes[id] = nil end
    end
end

local function OnSkillChanged()
    if not ns.me then return end
    ns:Debounce("skills", 2, function()
        ns:ScanSkillLevels()
        ns:RebuildPayload()
        ns:Fire("PLAYERS")
    end)
end
ns:On("SKILL_LINES_CHANGED", OnSkillChanged)
ns:On("LEARNED_SPELL_IN_TAB", OnSkillChanged)   -- learning a specialization
ns:On("CHAT_MSG_SKILL", OnSkillChanged)

------------------------------------------------------------------------
-- Recipe scanning (runs when you open a profession window)
------------------------------------------------------------------------
local function ParseID(link, kind)
    if type(link) ~= "string" then return nil end
    return tonumber(link:match(kind .. ":(%d+)"))
end

local function StoreRecipes(profId, spells, items, merge, rank, maxRank)
    local rec = ns:MyRecord()
    local cur = rec.recipes[profId]
    if merge and cur then
        local seenS, seenI = {}, {}
        for _, v in ipairs(cur.s or {}) do seenS[v] = true end
        for _, v in ipairs(cur.i or {}) do seenI[v] = true end
        for _, v in ipairs(spells) do seenS[v] = true end
        for _, v in ipairs(items) do seenI[v] = true end
        spells, items = {}, {}
        for v in pairs(seenS) do spells[#spells + 1] = v end
        for v in pairs(seenI) do items[#items + 1] = v end
    end
    table.sort(spells)
    table.sort(items)
    local before = cur and ((#(cur.s or {})) + (#(cur.i or {}))) or 0
    rec.recipes[profId] = { s = spells, i = items, t = time() }
    if rank and rank > 0 then rec.profs[profId] = { rank, maxRank or rank } end
    if not rec.profs[profId] then rec.profs[profId] = { 0, 0 } end

    local count = #spells + #items
    if ns:RebuildPayload() then
        if count ~= before then
            ns.Print(string.format("Captured %d %s recipes.", count, ns.ProfName(profId)))
        end
        ns:Debounce("announce", 8, function() ns:BroadcastHello(false) end)
    end
    ns:Fire("PLAYERS")
end

ns.ParseID = ParseID   -- for Crafting.lua

local function RetailOutput(id)
    local T = C_TradeSkillUI
    if T.GetRecipeSchematic then
        local ok, s = pcall(T.GetRecipeSchematic, id, false)
        if ok and type(s) == "table" and (s.outputItemID or 0) > 0 then return s.outputItemID end
    end
    if T.GetRecipeOutputItemData then
        local ok, d = pcall(T.GetRecipeOutputItemData, id)
        if ok and type(d) == "table" then
            if (d.itemID or 0) > 0 then return d.itemID end
            local x = ParseID(d.hyperlink, "item")
            if x then return x end
        end
    end
    if T.GetRecipeItemLink then
        local ok, l = pcall(T.GetRecipeItemLink, id)
        if ok then return ParseID(l, "item") end
    end
end

------------------------------------------------------------------------
-- Reagents: captured from your own profession windows, or read live from
-- the client when it can describe a recipe it hasn't seen opened.
------------------------------------------------------------------------
local function SchematicReagents(recipeID)
    local T = C_TradeSkillUI
    if not (T and T.GetRecipeSchematic) then return nil end
    local ok, s = pcall(T.GetRecipeSchematic, recipeID, false)
    if not ok or type(s) ~= "table" or type(s.reagentSlotSchematics) ~= "table" then return nil end
    local list = {}
    for _, slot in ipairs(s.reagentSlotSchematics) do
        local r = slot.reagents and slot.reagents[1]
        if slot.required ~= false and r and r.itemID and (slot.quantityRequired or 0) > 0 then
            list[#list + 1] = { r.itemID, slot.quantityRequired }
        end
    end
    return #list > 0 and list or nil
end

local noReagents = {}
function ns.Reagents(key)
    local known = ns.db.reagents[key]
    if known then return known end
    if noReagents[key] or key:sub(1, 1) ~= "s" then return nil end
    local list = SchematicReagents(tonumber(key:sub(2)))
    if list then ns.db.reagents[key] = list else noReagents[key] = true end
    return list
end

local function ClassicReagents(numFn, infoFn, linkFn, i)
    if not numFn or not linkFn then return nil end
    local list = {}
    for r = 1, (numFn(i) or 0) do
        local _, _, count = infoFn(i, r)
        local id = ParseID(linkFn(i, r), "item")
        if id and count then list[#list + 1] = { id, count } end
    end
    return #list > 0 and list or nil
end

local function ScanRetail()
    local T = C_TradeSkillUI
    if (T.IsTradeSkillLinked and T.IsTradeSkillLinked())
        or (T.IsTradeSkillGuild and T.IsTradeSkillGuild())
        or (T.IsNPCCrafting and T.IsNPCCrafting()) then
        return
    end
    local base = T.GetBaseProfessionInfo()
    local profId = base and base.professionID
    if not profId or not ns.PROFS[profId] then return end
    local ids = T.GetAllRecipeIDs()
    if not ids or #ids == 0 then return end
    local spells = {}
    for _, id in ipairs(ids) do
        local info = T.GetRecipeInfo(id)
        if info and info.learned and not info.isDummyRecipe and not info.isRecraft then
            spells[#spells + 1] = id
            local out = RetailOutput(id)
            if out then ns.db.outputs[id] = out end
            local reagents = SchematicReagents(id)
            if reagents then ns.db.reagents["s" .. id] = reagents end
            if T.GetRecipeCooldown then
                local ok, cd, _, _, maxCharges = pcall(T.GetRecipeCooldown, id)
                if ok and ((type(cd) == "number" and cd > 0) or (maxCharges and maxCharges > 0)) then
                    ns.db.cdSpells[id] = profId
                end
            end
        end
    end
    StoreRecipes(profId, spells, {}, false)
end

local function ScanClassicTrade()
    if not GetNumTradeSkills or not GetTradeSkillLine then return end
    if IsTradeSkillLinked and IsTradeSkillLinked() then return end
    local name, rank, maxRank = GetTradeSkillLine()
    local profId = ns.ProfIdFromName(name)
    if not profId then return end
    if ExpandTradeSkillSubClass then pcall(ExpandTradeSkillSubClass, 0) end
    local spells, items = {}, {}
    for i = 1, GetNumTradeSkills() do
        local rname, kind = GetTradeSkillInfo(i)
        if rname and kind ~= "header" and kind ~= "subheader" then
            local sid
            if GetTradeSkillRecipeLink then
                local link = GetTradeSkillRecipeLink(i)
                sid = ParseID(link, "enchant") or ParseID(link, "spell")
            end
            local iid = GetTradeSkillItemLink and ParseID(GetTradeSkillItemLink(i), "item")
            local reagents = ClassicReagents(GetTradeSkillNumReagents, GetTradeSkillReagentInfo, GetTradeSkillReagentItemLink, i)
            if reagents and (sid or iid) then ns.db.reagents[sid and ("s" .. sid) or ("i" .. iid)] = reagents end
            if sid then
                spells[#spells + 1] = sid
                if iid then ns.db.outputs[sid] = iid end
                if GetTradeSkillCooldown then
                    local ok, cd = pcall(GetTradeSkillCooldown, i)
                    if ok and type(cd) == "number" and cd > 0 then ns.db.cdSpells[sid] = profId end
                end
            elseif iid then
                items[#items + 1] = iid
            end
        end
    end
    if #spells + #items > 0 then StoreRecipes(profId, spells, items, true, rank, maxRank) end
end

-- Classic-style Enchanting uses the separate "craft" window
local function ScanClassicCraft()
    if not GetNumCrafts or not GetCraftDisplaySkillLine then return end
    local name, rank, maxRank = GetCraftDisplaySkillLine()
    local profId = ns.ProfIdFromName(name)
    if not profId then return end   -- e.g. Hunter Beast Training
    local spells, items = {}, {}
    for i = 1, GetNumCrafts() do
        local cname, _, kind = GetCraftInfo(i)
        if cname and kind ~= "header" then
            local link = (GetCraftRecipeLink and GetCraftRecipeLink(i)) or (GetCraftItemLink and GetCraftItemLink(i))
            local sid = ParseID(link, "enchant") or ParseID(link, "spell")
            local reagents = ClassicReagents(GetCraftNumReagents, GetCraftReagentInfo, GetCraftReagentItemLink, i)
            if reagents and sid then ns.db.reagents["s" .. sid] = reagents end
            if sid then
                spells[#spells + 1] = sid
                local iid = GetCraftItemLink and ParseID(GetCraftItemLink(i), "item")
                if iid then ns.db.outputs[sid] = iid end
            else
                local iid = ParseID(link, "item")
                if iid then items[#items + 1] = iid end
            end
        end
    end
    if #spells + #items > 0 then StoreRecipes(profId, spells, items, true, rank, maxRank) end
end

local function ScanTrade()
    if not ns.me then return end
    local ok, err
    if C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs and C_TradeSkillUI.GetBaseProfessionInfo then
        ok, err = pcall(ScanRetail)
    else
        ok, err = pcall(ScanClassicTrade)
    end
    if not ok then geterrorhandler()(err) end
end

------------------------------------------------------------------------
-- Crafting cooldowns (Transmutes, Mooncloth, Salt Shaker, and any recipe
-- seen with a cooldown). Stored per character as rec.cooldowns[key] =
-- { name, prof, ready = epoch seconds (0 = ready), spell | item }.
------------------------------------------------------------------------
ns.CD_GROUPS = {
    { key = "transmute", name = "Transmute", prof = 171,
      spells = { 17187, 17559, 17560, 17561, 17562, 17563, 17564, 17565, 17566, 11479, 11480, 25146 } },
    { key = "mooncloth", name = "Mooncloth", prof = 197, spells = { 18560 } },
    { key = "saltshaker", name = "Salt Shaker", prof = 165, item = 15846 },
}
local groupSpell = {}
for _, g in ipairs(ns.CD_GROUPS) do
    for _, id in ipairs(g.spells or {}) do groupSpell[id] = true end
end

local function SpellCD(id)
    if C_Spell and C_Spell.GetSpellCooldown then
        local ok, info = pcall(C_Spell.GetSpellCooldown, id)
        if ok and type(info) == "table" then return info.startTime or 0, info.duration or 0 end
    end
    if GetSpellCooldown then
        local ok, s, d = pcall(GetSpellCooldown, id)
        if ok then return s or 0, d or 0 end
    end
    return 0, 0
end

local function ItemCD(id)
    local f = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
    if f then
        local ok, s, d = pcall(f, id)
        if ok then return s or 0, d or 0 end
    end
    return 0, 0
end

-- The game can hand addons "secret" numbers (mostly in combat) that can't be compared
-- or used in math. Treat those as unreadable instead of erroring.
local function Plain(v)
    if v == nil then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    if type(v) ~= "number" then return nil end
    return v
end

-- When the cooldown can't be read, returns nil so the last known value is kept.
local function ReadyAt(start, dur)
    start, dur = Plain(start), Plain(dur)
    if not start or not dur then return nil end
    local ok, r = pcall(function()
        -- ignore the global cooldown and other short ones
        if dur > 60 and start > 0 then
            return time() + math.max(0, math.floor(start + dur - GetTime()))
        end
        return 0
    end)
    return ok and r or nil
end

local pendingAfterCombat
function ns:ScanCooldowns()
    if not ns.me then return end
    -- cooldown numbers are often hidden in combat; scan again once it ends
    if InCombatLockdown and InCombatLockdown() then
        pendingAfterCombat = true
        return
    end
    local rec = ns:MyRecord()
    local old = rec.cooldowns or {}
    local known = {}
    for _, r in pairs(rec.recipes) do
        for _, s in ipairs(r.s or {}) do known[s] = true end
    end
    local function Knows(id)
        if known[id] then return true end
        if IsPlayerSpell then
            local ok, k = pcall(IsPlayerSpell, id)
            return ok and k
        end
    end

    local cds = {}
    for _, g in ipairs(ns.CD_GROUPS) do
        if g.item then
            if ns.ItemCount(g.item) > 0 then
                local s, d = ItemCD(g.item)
                local r = ReadyAt(s, d) or (old[g.key] and old[g.key].ready) or 0
                cds[g.key] = { name = g.name, prof = g.prof, ready = r, item = g.item }
            end
        else
            for _, id in ipairs(g.spells) do
                if Knows(id) then
                    local s, d = SpellCD(id)
                    local r = ReadyAt(s, d) or (old[g.key] and old[g.key].ready) or 0
                    if not cds[g.key] or r > cds[g.key].ready then
                        cds[g.key] = { name = g.name, prof = g.prof, ready = r, spell = id }
                    end
                end
            end
        end
    end
    for id, prof in pairs(ns.db.cdSpells) do
        if not groupSpell[id] and Knows(id) then
            local r
            if C_TradeSkillUI and C_TradeSkillUI.GetRecipeCooldown then
                local ok, cd = pcall(C_TradeSkillUI.GetRecipeCooldown, id)
                cd = ok and Plain(cd)
                if cd and cd > 0 then r = time() + math.floor(cd) end
            end
            if not r then r = ReadyAt(SpellCD(id)) end
            if not r then r = (old["s" .. id] and old["s" .. id].ready) or 0 end
            cds["s" .. id] = { name = SpellName(id) or ("Recipe " .. id), prof = prof, ready = r, spell = id }
        end
    end
    rec.cooldowns = cds
    ns:Fire("COOLDOWNS")
end

local function QueueCooldowns() ns:Debounce("cooldowns", 2, function() ns:ScanCooldowns() end) end
ns:On("SPELL_UPDATE_COOLDOWN", QueueCooldowns)
ns:On("BAG_UPDATE_COOLDOWN", QueueCooldowns)
ns:On("PLAYER_REGEN_ENABLED", function()
    if pendingAfterCombat then
        pendingAfterCombat = nil
        QueueCooldowns()
    end
end)
ns:Listen("READY", function() C_Timer.After(5, function() ns:ScanCooldowns() end) end)
ns:Listen("DATA_CHANGED", QueueCooldowns)

local function QueueTradeScan()
    ns:Debounce("tradescan", 0.6, function()
        ScanTrade()
        QueueCooldowns()
    end)
end
local function QueueCraftScan() ns:Debounce("craftscan", 0.6, function() if ns.me then ScanClassicCraft() end end) end
ns:On("TRADE_SKILL_SHOW", QueueTradeScan)
ns:On("TRADE_SKILL_LIST_UPDATE", QueueTradeScan)
ns:On("TRADE_SKILL_DATA_SOURCE_CHANGED", QueueTradeScan)
ns:On("NEW_RECIPE_LEARNED", QueueTradeScan)
ns:On("CRAFT_SHOW", QueueCraftScan)
ns:On("CRAFT_UPDATE", QueueCraftScan)

------------------------------------------------------------------------
-- Encoding: profession blocks "id:rank:max:spells:items:outputs" joined by ";"
-- recipe ids are sorted, delta-encoded and written in base 36.
-- outputs (added in 1.0.2) lists the item each spell creates, in the same order
-- as spells, 0 when none; older versions simply ignore the extra field.
------------------------------------------------------------------------
local function EncodeList(list)
    local out, prev = {}, 0
    for i, v in ipairs(list) do
        out[i] = ns.B36(v - prev)
        prev = v
    end
    return table.concat(out, ",")
end

local function DecodeList(str)
    local list, prev = {}, 0
    if not str or str == "" then return list end
    for tok in str:gmatch("[^,]+") do
        local d = ns.UnB36(tok)
        if d then
            prev = prev + d
            list[#list + 1] = prev
        end
    end
    return list
end

function ns:EncodeRecord(rec, withRanks)
    local ids, seen = {}, {}
    for id in pairs(rec.profs or {}) do ids[#ids + 1] = id; seen[id] = true end
    for id in pairs(rec.recipes or {}) do if not seen[id] then ids[#ids + 1] = id end end
    table.sort(ids)
    local blocks = {}
    for _, id in ipairs(ids) do
        local p = (rec.profs and rec.profs[id]) or { 0, 0 }
        local r = (rec.recipes and rec.recipes[id]) or {}
        local outs, any = {}, false
        for k, sid in ipairs(r.s or {}) do
            local o = ns.db.outputs[sid]
            outs[k] = o and ns.B36(o) or "0"
            if o then any = true end
        end
        blocks[#blocks + 1] = table.concat({
            ns.B36(id),
            withRanks and ns.B36(p[1]) or "",
            withRanks and ns.B36(p[2]) or "",
            EncodeList(r.s or {}),
            EncodeList(r.i or {}),
            any and table.concat(outs, ",") or "",
            withRanks and p[3] or "",   -- specialization (older versions ignore it)
        }, ":")
    end
    return table.concat(blocks, ";")
end

function ns:DecodePayload(str)
    local profs, recipes = {}, {}
    for block in (str or ""):gmatch("[^;]+") do
        local id, rank, maxR, s, i, o, spec = strsplit(":", block)
        id = ns.UnB36(id)
        if id then
            profs[id] = { ns.UnB36(rank) or 0, ns.UnB36(maxR) or 0, CleanSpec(spec) }
            local sl, il = DecodeList(s), DecodeList(i)
            if o and o ~= "" then
                local k = 0
                for tok in o:gmatch("[^,]+") do
                    k = k + 1
                    local item, sid = ns.UnB36(tok), sl[k]
                    if sid and item and item > 0 and not ns.db.outputs[sid] then
                        ns.db.outputs[sid] = item
                    end
                end
            end
            if #sl > 0 or #il > 0 then recipes[id] = { s = sl, i = il } end
        end
    end
    return profs, recipes
end

function ns:SummaryString(profs)
    local t = {}
    for id, p in pairs(profs or {}) do
        t[#t + 1] = ns.B36(id) .. "." .. ns.B36(p[1]) .. "." .. ns.B36(p[2]) .. (p[3] and ("." .. p[3]) or "")
    end
    table.sort(t)
    return table.concat(t, ",")
end

function ns:DecodeSummary(str)
    local t = {}
    for tok in (str or ""):gmatch("[^,]+") do
        local a, b, c, d = strsplit(".", tok)
        a = ns.UnB36(a)
        if a then t[a] = { ns.UnB36(b) or 0, ns.UnB36(c) or 0, CleanSpec(d) } end
    end
    return t
end

-- The hash only covers recipes, so skill-ups don't make everyone re-download your list.
-- Returns true when the recipe data changed.
function ns:RebuildPayload()
    local rec = ns:MyRecord()
    ns.myPayload = ns:EncodeRecord(rec, true)
    local hash = ns.Hash(ns:EncodeRecord(rec, false))
    local changed = hash ~= rec.hash
    rec.hash = hash
    if changed then
        ns:MarkIndexDirty()
        ns:Fire("DATA_CHANGED")
    end
    return changed
end

------------------------------------------------------------------------
-- Recipe index (who can craft what)
ns.RARE_MAX_CRAFTERS = 2
ns.RARE_MIN_NETWORK = 10
------------------------------------------------------------------------
ns.indexDirty = true

function ns:MarkIndexDirty()
    ns.indexDirty = true
    ns:Debounce("indexfire", 0.3, function() ns:Fire("INDEX") end)
end

function ns:GetIndex()
    if ns.index and not ns.indexDirty then return ns.index end
    local list, byKey, byName, byOut = {}, {}, {}, {}
    for name, rec in pairs(ns:AllPlayers()) do
        for profId, r in pairs(rec.recipes or {}) do
            for pass = 1, 2 do
                local arr = pass == 1 and r.s or r.i
                local pre = pass == 1 and "s" or "i"
                for _, id in ipairs(arr or {}) do
                    local key = pre .. id
                    local e = byKey[key]
                    if not e then
                        e = { key = key, prof = profId, crafters = {} }
                        byKey[key] = e
                        list[#list + 1] = e
                    end
                    e.crafters[#e.crafters + 1] = name
                end
            end
        end
    end
    for _, e in ipairs(list) do
        local n, icon = ns.RecipeInfo(e.key)
        e.name = n or ("Loading item " .. e.key:sub(2) .. "...")
        e.lname = (n or ""):lower()
        e.icon = icon
        if e.key:sub(1, 1) == "s" then
            local out = ns.db.outputs[tonumber(e.key:sub(2))]
            if out then
                byOut[out] = byOut[out] or {}
                table.insert(byOut[out], e)
            end
        end
        if n then
            -- "Transmute: Arcanite Bar" should match an Arcanite Bar tooltip too
            local plain = e.lname:gsub("^[^:]+:%s*", "")
            for _, k in ipairs(plain ~= e.lname and { e.lname, plain } or { e.lname }) do
                byName[k] = byName[k] or {}
                table.insert(byName[k], e)
            end
        end
    end
    -- "rare": known by at most 2 players, once the network is big enough for that to mean something
    local crafters = 0
    for _, rec in pairs(ns:AllPlayers()) do
        if rec.recipes and next(rec.recipes) then crafters = crafters + 1 end
    end
    ns.networkCrafters = crafters
    for _, e in ipairs(list) do
        e.rare = crafters >= ns.RARE_MIN_NETWORK and #e.crafters <= ns.RARE_MAX_CRAFTERS
    end
    ns.index, ns.byKey, ns.byName, ns.byOut = list, byKey, byName, byOut
    ns.indexDirty = false
    return list
end

-- other players only: your own characters never count as "online crafters".
-- returns others online, others in total, and whether one of your characters knows it
function ns:CountOnline(e)
    local n, total, mine = 0, 0, false
    for _, c in ipairs(e.crafters) do
        if ns:IsMine(c) then
            mine = true
        else
            total = total + 1
            if ns:IsOnline(c) then n = n + 1 end
        end
    end
    return n, total, mine
end

------------------------------------------------------------------------
-- Hiding recipes: low-level ones (by the crafted item's level) and any you
-- hide by hand. db.hidden[key] = true hides a recipe, false always shows it.
------------------------------------------------------------------------
local levelCache = {}

-- Enchants make no item, so their level comes from the reagents (dusts, essences
-- and shards each belong to a level band), or failing that from the rank word in
-- the name ("Minor", "Lesser", ... "Major"). Values are rough character levels.
local REAGENT_LEVEL = {
    [10940] = 15, [11083] = 30, [11137] = 40, [11176] = 50, [16204] = 58,   -- dusts
    [10938] = 12, [10939] = 15, [10998] = 22, [11082] = 25, [11134] = 32,   -- essences
    [11135] = 35, [11174] = 42, [11175] = 45, [16202] = 52, [16203] = 55,
    [10978] = 18, [11084] = 25, [11138] = 32, [11139] = 38, [11177] = 44,   -- shards
    [11178] = 48, [14343] = 54, [14344] = 58, [20725] = 60,
}
local RANK_LEVEL = { minor = 10, inferior = 15, lesser = 20, greater = 40, superior = 50, major = 58 }

local function EnchantLevel(key)
    local best
    for _, r in ipairs(ns.Reagents(key) or {}) do
        local lv = REAGENT_LEVEL[r[1]]
        if lv and (not best or lv > best) then best = lv end
    end
    if best then return best end
    local name = ns.RecipeInfo(key)
    if not name then return nil end
    -- the word right after the dash: "Enchant Bracer - Minor Stamina" -> "minor"
    local word = name:match("%-%s*(%a+)")
    return word and RANK_LEVEL[word:lower()] or nil
end

-- required level of the crafted item, else its item level; for enchants, see above.
-- nil when unknown
function ns.RecipeLevel(key)
    local lv = levelCache[key]
    if lv then return lv end
    local kind, id = key:sub(1, 1), tonumber(key:sub(2))
    local item = kind == "i" and id or (kind == "s" and ns.OutputItem(id))
    if not item then
        if kind ~= "s" then return nil end
        lv = EnchantLevel(key)
        if lv then levelCache[key] = lv end
        return lv
    end
    local name, _, _, ilvl, minLevel = GetItemInfoCompat(item)
    if not name then ns:RequestItem(item) return nil end
    lv = ((minLevel or 0) > 0 and minLevel) or ilvl or 0
    levelCache[key] = lv
    return lv
end

-- Bind on Pickup: the crafted item can't be traded, so nobody can make it for you.
-- true / false, nil while the item isn't loaded yet. Enchants (no item) are never BoP.
local bopCache = {}
function ns.RecipeBoP(key)
    local v = bopCache[key]
    if v ~= nil then return v end
    local kind, id = key:sub(1, 1), tonumber(key:sub(2))
    local item = kind == "i" and id or (kind == "s" and ns.OutputItem(id))
    if not item then return nil end
    local name, _, _, _, _, _, _, _, _, _, _, _, _, bindType = GetItemInfoCompat(item)
    if not name then ns:RequestItem(item) return nil end
    v = bindType == 1
    bopCache[key] = v
    return v
end

-- returns "manual", "low" or nil (Bind on Pickup is left out of Find a Crafter in ns:Search)
function ns:RecipeHidden(key, forSearch)
    local h = ns.db.hidden[key]
    if h == true then return "manual" end
    if h == false then return nil end
    if ns.settings.hideLow then
        local lv = ns.RecipeLevel(key)
        if lv and lv > 0 and lv < (ns.settings.lowCutoff or 40) then return "low" end
    end
end

-- right-click cycle: shown -> hidden; hidden by hand -> shown; hidden for level/BoP -> always shown
function ns:ToggleRecipeHidden(key)
    local why = ns:RecipeHidden(key, true)
    if why == "manual" then ns.db.hidden[key] = nil
    elseif why == "low" or why == "bop" then ns.db.hidden[key] = false
    else ns.db.hidden[key] = true end
    if ns.db.hidden[key] == nil and ns:RecipeHidden(key, true) then ns.db.hidden[key] = false end
    ns:Fire("HIDDEN")
end

-- favorites: starred recipes, listed first in Find a Crafter and with their own filter
function ns:IsFavorite(key) return ns.db.favorites[key] == true end
function ns:ToggleFavorite(key)
    ns.db.favorites[key] = (not ns.db.favorites[key]) or nil
    ns:Fire("FAVORITES")
end

-- profFilter: a profession id, "fav" for favorites only, or nil for everything
function ns:Search(query, profFilter, onlineOnly)
    local favOnly = profFilter == "fav"
    if favOnly then profFilter = nil end
    local q = (query or ""):lower()
    local res, hidden = {}, 0
    local showHidden = ns.settings.showHidden
    for _, e in ipairs(ns:GetIndex()) do
        -- Bind on Pickup can't be crafted for anyone else: left out of Find a Crafter entirely
        local bop = ns.RecipeBoP(e.key)
        local fav = ns.db.favorites[e.key] == true
        if (not profFilter or e.prof == profFilter) and (not favOnly or fav)
            and (q == "" or e.lname:find(q, 1, true))
            and (ns.settings.showBoP or not bop) then
            e.fav = fav
            local on, others, mine = ns:CountOnline(e)
            e.online, e.others, e.mine = on, others, mine
            if not onlineOnly or on > 0 then
                e.hidden = ns:RecipeHidden(e.key, true)
                e.bop = bop
                if e.hidden then hidden = hidden + 1 end
                if showHidden or not e.hidden then res[#res + 1] = e end
            end
        end
    end
    table.sort(res, function(a, b)
        if a.fav ~= b.fav then return a.fav end
        if (a.online > 0) ~= (b.online > 0) then return a.online > 0 end
        if a.lname ~= b.lname then return a.lname < b.lname end
        return a.key < b.key
    end)
    return res, hidden
end

-- crafters sorted: other players online and available, then online but busy, then your
------------------------------------------------------------------------
-- Slot groups: where a crafted item goes (Chest, Legs...) or what kind of thing it is
-- (Bags, Consumables...). Used for the headers in Find a Crafter.
------------------------------------------------------------------------
ns.SLOT_ORDER = { "Head", "Neck", "Shoulder", "Back", "Chest", "Shirt", "Tabard", "Wrist", "Hands", "Waist",
    "Legs", "Feet", "Ring", "Trinket", "Weapons", "Off-hand", "Ranged", "Bags", "Ammo", "Consumables",
    "Materials", "Other" }
local SLOT_RANK = {}
for i, v in ipairs(ns.SLOT_ORDER) do SLOT_RANK[v] = i end
ns.SLOT_RANK = SLOT_RANK

local EQUIP = {
    INVTYPE_HEAD = "Head", INVTYPE_NECK = "Neck", INVTYPE_SHOULDER = "Shoulder", INVTYPE_CLOAK = "Back",
    INVTYPE_CHEST = "Chest", INVTYPE_ROBE = "Chest", INVTYPE_BODY = "Shirt", INVTYPE_TABARD = "Tabard",
    INVTYPE_WRIST = "Wrist", INVTYPE_HAND = "Hands", INVTYPE_WAIST = "Waist", INVTYPE_LEGS = "Legs",
    INVTYPE_FEET = "Feet", INVTYPE_FINGER = "Ring", INVTYPE_TRINKET = "Trinket",
    INVTYPE_WEAPON = "Weapons", INVTYPE_2HWEAPON = "Weapons", INVTYPE_WEAPONMAINHAND = "Weapons",
    INVTYPE_WEAPONOFFHAND = "Weapons", INVTYPE_SHIELD = "Off-hand", INVTYPE_HOLDABLE = "Off-hand",
    INVTYPE_RANGED = "Ranged", INVTYPE_RANGEDRIGHT = "Ranged", INVTYPE_THROWN = "Ranged", INVTYPE_RELIC = "Ranged",
    INVTYPE_BAG = "Bags", INVTYPE_QUIVER = "Bags", INVTYPE_AMMO = "Ammo",
}
-- item class IDs: 0 consumable, 1 container, 6 projectile, 7 trade goods, 11 quiver
local CLASS = { [0] = "Consumables", [1] = "Bags", [6] = "Ammo", [7] = "Materials", [11] = "Bags" }
-- enchants go by the gear they enchant ("Enchant Boots - Minor Stamina")
local ENCHANT = {
    { "boots", "Feet" }, { "bracer", "Wrist" }, { "gloves", "Hands" }, { "chest", "Chest" },
    { "cloak", "Back" }, { "shield", "Off-hand" }, { "ring", "Ring" }, { "weapon", "Weapons" },
    { "head", "Head" }, { "shoulder", "Shoulder" }, { "leg", "Legs" }, { "belt", "Waist" },
}

local function ItemSlot(id)
    if not id or not GetItemInfoInstantCompat then return nil end
    local ok, _, _, _, equip, _, classID = pcall(GetItemInfoInstantCompat, id)
    if not ok then return nil end
    if equip and EQUIP[equip] then return EQUIP[equip] end
    if classID == 2 then return "Weapons" end
    return classID and CLASS[classID] or "Other"
end

-- The group label for a recipe entry; remembered on the entry once known.
function ns.RecipeSlot(e)
    if e.slot then return e.slot end
    local kind, id = e.key:sub(1, 1), tonumber(e.key:sub(2))
    local slot
    if kind == "i" then
        slot = ItemSlot(id)
    else
        local out = ns.db.outputs[id]
        if out then
            slot = ItemSlot(out)
        else
            local n = (e.lname or ""):match("^enchant%s+(.-)%s*%-") or ""
            for _, m in ipairs(ENCHANT) do
                if n:find(m[1], 1, true) then slot = m[2] break end
            end
        end
    end
    e.slot = slot or "Other"
    return e.slot
end

-- own characters, then offline players; then by name
function ns:SortedCrafters(e)
    local t = {}
    for _, name in ipairs(e.crafters) do
        local online = ns:IsOnline(name)
        local busy = ns:IsBusy(name)
        local mine = ns:IsMine(name)
        t[#t + 1] = { name = name, rec = ns:GetRecord(name), online = online, busy = busy, mine = mine,
                      rank = mine and 3 or online and (busy and 2 or 1) or 4 }
    end
    table.sort(t, function(a, b)
        if a.rank ~= b.rank then return a.rank < b.rank end
        return a.name < b.name
    end)
    return t
end

function ns:EntriesForItem(itemID, itemName)
    ns:GetIndex()
    local out, seen = {}, {}
    local e = itemID and ns.byKey["i" .. itemID]
    if e then out[#out + 1] = e; seen[e] = true end
    for _, x in ipairs((itemID and ns.byOut[itemID]) or {}) do
        if not seen[x] then out[#out + 1] = x; seen[x] = true end
    end
    local list = itemName and ns.byName[itemName:lower()]
    if list then
        for _, x in ipairs(list) do
            if not seen[x] then out[#out + 1] = x; seen[x] = true end
        end
    end
    return out
end
