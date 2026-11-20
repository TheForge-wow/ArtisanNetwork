-- Artisan Network: Requests page
local ADDON, ns = ...
local W, C = ns.W, ns.W.C
local UI = ns.UI

local READY_TEX = "|TInterface\\RaidFrame\\ReadyCheck-Ready:12|t"

-- the third line of a received request: what this character can do with it
local function CraftLine(it)
    if it.crafted then
        return READY_TEX .. " |cff52de7cCrafted " .. ns.Ago(it.crafted) .. "|r  ·  let them know it's ready", "done"
    end
    local who = ns:WhoOfMineKnows(it.key)
    if not who then return "", "none" end
    if who ~= ns.me then
        local rec = ns.db.chars[who]
        return "Known by |cff" .. ns.ClassHex(rec and rec.class) .. ns.Short(who) .. "|r  ·  log in there to craft it", "alt"
    end
    local state, short, reagents = ns:CraftMats(it.key)
    if not state then return "Mats unknown: check your profession window", "ready" end
    local parts = {}
    for _, r in ipairs(reagents) do
        local have = ns.ItemCount(r[1])
        local icon = ns.ItemIcon(r[1])
        parts[#parts + 1] = (icon and ("|T" .. icon .. ":14|t ") or "")
            .. (have >= r[2] and "|cff52de7c" or "|cffff6b6b") .. have .. "|r|cff62636c/" .. r[2] .. "|r"
    end
    local tail = state == "ok" and "|cff52de7call here|r"
        or ("|cffff6b6bmissing " .. short .. "|r  ·  trade them first")
    return "Mats in your bags:  " .. table.concat(parts, "   ") .. "   " .. tail, state == "ok" and "ready" or "short"
end

------------------------------------------------------------------------
-- Requests page: crafting requests you sent and received in the last day
------------------------------------------------------------------------
function UI.Build.Requests(content)
    local p = CreateFrame("Frame", nil, content)
    p:SetAllPoints()
    local title = W.Text(p, 15)
    title:SetPoint("TOPLEFT", 24, -22)
    title:SetText("Requests")
    local desc = W.Text(p, 11, C.dim)
    desc:SetPoint("TOPLEFT", 24, -44)
    desc:SetText("Crafting requests you sent and received in the last day.")
    local clear = W.Button(p, "Clear", 70, 24)
    clear:SetPoint("TOPRIGHT", -20, -24)
    clear:SetScript("OnClick", function() ns:ClearRequestLog() end)
    W.Tip(clear, "Clear", "Removes every request from this list.")

    local list = W.List(p, 62, function(lst)
        local r = W.RowBase(lst)
        r.icon = W.Icon(r, 28)
        r.icon:SetPoint("LEFT", 10, 0)
        r.name = W.Text(r, 12)
        r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 10, -1)
        r.name:SetWidth(420)
        r.sub = W.Text(r, 10, C.dim)
        r.sub:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -4)
        r.sub:SetWidth(480)
        r.line3 = W.Text(r, 10, C.faint)
        r.line3:SetPoint("TOPLEFT", r.sub, "BOTTOMLEFT", 0, -5)
        r.line3:SetWidth(500)
        r.btn = W.Button(r, "Whisper", 76, 22)
        r.btn:SetPoint("RIGHT", -8, 0)
        r.btn:SetScript("OnClick", function()
            local it = r.item
            if not it then return end
            if it.dir == "in" then
                local _, _, link = ns.RecipeInfo(it.key)
                local rname = ns.RecipeInfo(it.key)
                ns:WhisperText(it.from, "Hi! I can craft " .. (link or rname or "that") .. " for you.")
            else
                ns:ShowUI("search", it.key)
            end
        end)
        W.Tip(r.btn, function() return r.item and r.item.dir == "in" and "Whisper" or "Find a Crafter" end,
            function()
                if not r.item then return nil end
                if r.item.dir == "in" then return "Opens a whisper offering to craft it." end
                return "Opens this recipe in Find a Crafter to see who can make it now."
            end)
        -- Craft (or, once crafted, "Tell them") for received requests this character can make
        r.craft = W.Button(r, "Craft", 86, 22)
        r.craft:SetPoint("RIGHT", r.btn, "LEFT", -8, 0)
        r.craft:SetScript("OnClick", function()
            local it = r.item
            if not it then return end
            if it.crafted then
                local _, _, link = ns.RecipeInfo(it.key)
                local rname = ns.RecipeInfo(it.key)
                ns:WhisperText(it.from, "Your " .. (link or rname or "craft") .. " is ready!")
                return
            end
            local ok, msg = ns:CraftRequest(it)
            if msg then ns.Print(msg) end
            UI:Refresh()
        end)
        W.Tip(r.craft, function() return r.item and r.item.crafted and "Tell them" or "Craft" end, function()
            local it = r.item
            if not it then return nil end
            if it.crafted then return "Opens a whisper telling them it's ready. Press Enter to send it." end
            if r.craftState == "short" then return "You don't have all the reagents yet. Trade them first; this updates as they land in your bags." end
            return "Crafts one for them. The profession window has to be open; if it isn't, you'll be told which one to open."
        end)
        r:SetScript("OnClick", function(self) if self.item then ns:ShowUI("search", self.item.key) end end)
        return r
    end, function(r, it, i)
        r:SetStripe(i)
        local rname, icon = ns.RecipeInfo(it.key)
        r.icon.tex:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        r.name:SetText(rname or "Loading...")
        local parts = {}
        if it.dir == "in" then
            local rec = ns:GetRecord(it.from)
            local who = (rec and rec.display) or ns.Short(it.from)
            parts[1] = "|cff52de7cReceived|r from |cff" .. ns.ClassHex(rec and rec.class) .. who .. "|r"
        else
            parts[1] = "|cff6fb7ffSent|r to " .. (it.n or 0) .. ((it.n or 0) == 1 and " crafter" or " crafters")
        end
        parts[#parts + 1] = ns.Ago(it.t)
        if it.note and it.note ~= "" then parts[#parts + 1] = "|cffdbd1b3\"" .. it.note .. "\"|r" end
        r.sub:SetText(table.concat(parts, "  ·  "))
        if it.dir == "in" then
            r.btn:SetLabel("Whisper")
            r.btn:SetEnabled(ns:IsOnline(it.from))
            local text, state = CraftLine(it)
            r.line3:SetText(text)
            r.craftState = state
            if state == "done" then
                r.craft:SetLabel("Tell them"); r.craft:SetActive(false); r.craft:SetEnabled(true); r.craft:Show()
            elseif state == "ready" or state == "short" then
                r.craft:SetLabel("Craft"); r.craft:SetActive(state == "ready"); r.craft:SetEnabled(state == "ready"); r.craft:Show()
            else
                r.craft:Hide()
            end
        else
            r.btn:SetLabel("Find")
            r.btn:SetEnabled(true)
            r.line3:SetText("")
            r.craft:Hide()
        end
        r:SetSelected(false)
    end)
    list:SetPoint("TOPLEFT", 20, -74)
    list:SetPoint("BOTTOMRIGHT", -20, 18)

    local page = { frame = p }
    function page.refresh()
        local log = ns:RequestLog()
        clear:SetEnabled(#log > 0)
        list:SetData(log, "No requests yet.\n\nPress Request on any recipe in Find a Crafter, and requests other players send you show up here too.")
    end
    function page.onShow()
        ns.db.requestsUnseen = 0
        if ns.UpdateBroker then ns:UpdateBroker() end
        UI:UpdateNav()
    end
    return page
end
