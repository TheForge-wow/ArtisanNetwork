-- Artisan Network: crafting a received request from the Requests page
--
-- The game only crafts while that profession's window is open, and only from a
-- click. Two interfaces exist and WoW: Forever could use either:
--   modern:  C_TradeSkillUI (ProfessionsFrame), CraftRecipe(recipeID, count)
--   classic: TradeSkillFrame + DoTradeSkill(index, count); Enchanting in the
--            separate CraftFrame + DoCraft(index), which then asks for a target item
-- Nothing here uses protected functions, so it can't cause "action blocked" errors.
-- The cost: on the classic interface we can't open the window for you.
local ADDON, ns = ...

local ENCHANTING = 333

-- which of your characters knows a recipe: (name, profId) for the one you're on if it
-- does, else the first alt that does, else nil
function ns:WhoOfMineKnows(key)
    local kind, id = key:sub(1, 1), tonumber(key:sub(2))
    local function Knows(rec)
        for profId, r in pairs(rec and rec.recipes or {}) do
            for _, v in ipairs((kind == "s" and r.s or r.i) or {}) do
                if v == id then return profId end
            end
        end
    end
    if not ns.me then return nil end
    local p = Knows(ns:MyRecord())
    if p then return ns.me, p end
    for name, rec in pairs(ns.db.chars) do
        if name ~= ns.me then
            p = Knows(rec)
            if p then return name, p end
        end
    end
end

-- your mats for a recipe: "ok", "short" (and how many reagent types are short) or nil if unknown
function ns:CraftMats(key)
    local reagents = ns.Reagents(key)
    if not reagents then return nil end
    local short = 0
    for _, r in ipairs(reagents) do
        if ns.ItemCount(r[1]) < r[2] then short = short + 1 end
    end
    return short == 0 and "ok" or "short", short, reagents
end

local function Modern() return C_TradeSkillUI and C_TradeSkillUI.CraftRecipe and C_TradeSkillUI.GetBaseProfessionInfo end

-- the profession whose window is open now, and which interface it uses
local function OpenProfession()
    if Modern() then
        local shown = (ProfessionsFrame and ProfessionsFrame:IsShown()) or (TradeSkillFrame and TradeSkillFrame:IsShown())
        if shown then
            local ok, base = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
            return ok and base and base.professionID, "modern"
        end
        return nil, "modern"
    end
    if CraftFrame and CraftFrame:IsShown() and GetCraftDisplaySkillLine then
        local name = GetCraftDisplaySkillLine()
        return ns.ProfIdFromName(name), "craft"
    end
    if TradeSkillFrame and TradeSkillFrame:IsShown() and GetTradeSkillLine then
        local name = GetTradeSkillLine()
        return ns.ProfIdFromName(name), "trade"
    end
    return nil, "classic"
end

-- recipe spell ID for a key; "i" keys are matched through the spell -> item outputs we've seen
local function RecipeSpell(key)
    local kind, id = key:sub(1, 1), tonumber(key:sub(2))
    if kind == "s" then return id end
    for spell, item in pairs(ns.db.outputs) do
        if item == id then return spell end
    end
end

local function MatchIndex(count, recipeLink, itemLink, key)
    local kind, id = key:sub(1, 1), tonumber(key:sub(2))
    for i = 1, count do
        if kind == "s" then
            local link = recipeLink and recipeLink(i)
            if (ns.ParseID(link, "enchant") or ns.ParseID(link, "spell")) == id then return i end
        else
            if itemLink and ns.ParseID(itemLink(i), "item") == id then return i end
        end
    end
end

-- what's waiting to be confirmed by a successful cast: { entry, spell, item, t }
local pending

-- Craft one of a request's recipe. Must be called from a click.
-- Returns true, or nil and a message for the player.
function ns:CraftRequest(entry)
    local key = entry.key
    local who, profId = ns:WhoOfMineKnows(key)
    if who ~= ns.me then return nil, "This character doesn't know that recipe." end
    if InCombatLockdown and InCombatLockdown() then return nil, "You can't craft in combat." end
    local mats = ns:CraftMats(key)
    if mats == "short" then return nil, "You don't have all the reagents yet." end
    local profName = ns.ProfName(profId)
    local openProf, mode = OpenProfession()

    if openProf ~= profId then
        if mode == "modern" and C_TradeSkillUI.OpenTradeSkill then
            local ok = pcall(C_TradeSkillUI.OpenTradeSkill, profId)
            if ok then return nil, "Opened your " .. profName .. " window. Press Craft again." end
        end
        return nil, "Open your " .. profName .. " window, then press Craft again."
    end

    local spell = RecipeSpell(key)
    local _, _, link = ns.RecipeInfo(key)
    local what = link or ns.RecipeInfo(key) or "it"

    if mode == "modern" then
        if not spell then return nil, "Couldn't find that recipe in your " .. profName .. " window." end
        if profId == ENCHANTING then
            -- enchants need a target item; show the recipe so you can press Enchant yourself
            if C_TradeSkillUI.OpenRecipe then pcall(C_TradeSkillUI.OpenRecipe, spell) end
            pending = { entry = entry, spell = spell, t = GetTime() }
            return true, "Press Enchant, then click their item in the trade window's \"Will not be traded\" slot."
        end
        local ok, err = pcall(C_TradeSkillUI.CraftRecipe, spell, 1)
        if not ok then return nil, "The game refused to craft " .. what .. " (" .. tostring(err) .. ")." end
        pending = { entry = entry, spell = spell, t = GetTime() }
        return true

    elseif mode == "trade" then
        if ExpandTradeSkillSubClass then pcall(ExpandTradeSkillSubClass, 0) end
        local i = MatchIndex(GetNumTradeSkills(), GetTradeSkillRecipeLink, GetTradeSkillItemLink, key)
        if not i then return nil, "Couldn't find that recipe in your " .. profName .. " window." end
        if SelectTradeSkill then pcall(SelectTradeSkill, i) end
        local ok, err = pcall(DoTradeSkill, i, 1)
        if not ok then return nil, "The game refused to craft " .. what .. " (" .. tostring(err) .. ")." end
        pending = { entry = entry, spell = spell, t = GetTime() }
        return true

    elseif mode == "craft" then
        local i = MatchIndex(GetNumCrafts(), GetCraftRecipeLink or GetCraftItemLink, GetCraftItemLink, key)
        if not i then return nil, "Couldn't find that recipe in your " .. profName .. " window." end
        if SelectCraft then pcall(SelectCraft, i) end
        local ok, err = pcall(DoCraft, i)
        if not ok then return nil, "The game refused to start " .. what .. " (" .. tostring(err) .. ")." end
        pending = { entry = entry, spell = spell, t = GetTime() }
        return true, "Now click their item in the trade window's \"Will not be traded\" slot."
    end
    return nil, "Open your " .. profName .. " window, then press Craft again."
end

-- a successful cast of the recipe marks the request as crafted
ns:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
    if unit ~= "player" or not pending then return end
    if issecretvalue and issecretvalue(spellID) then return end -- hidden by the game; can't be matched
    if GetTime() - pending.t > 120 then pending = nil return end
    local e = pending.entry
    local match = (pending.spell and spellID == pending.spell)
        or (e.key:sub(1, 1) == "i" and ns.db.outputs[spellID] == tonumber(e.key:sub(2)))
    if not match then return end
    e.crafted = time()
    pending = nil
    ns:Fire("REQUESTS")
end)
