-- Artisan Network: item tooltips, watch alerts, minimap button, test mode, chat lookup
local ADDON, ns = ...
local W, C = ns.W, ns.W.C

------------------------------------------------------------------------
-- Item tooltips: "who can craft this?"
------------------------------------------------------------------------
local GetItemInfoCompat = ns.GetItemInfo   -- set in Professions.lua, which loads first

local function AddCrafters(tt, itemID)
    if not ns.settings or not ns.settings.tooltip or not itemID then return end
    local itemName = GetItemInfoCompat(itemID)
    local entries = {}
    for _, e in ipairs(ns:EntriesForItem(itemID, itemName)) do
        if not ns.RecipeBoP(e.key) then entries[#entries + 1] = e end   -- nobody can make BoP for you
    end
    if #entries == 0 then return end

    local seen, list = {}, {}
    for _, e in ipairs(entries) do
        for _, c in ipairs(ns:SortedCrafters(e)) do
            if not seen[c.name] then
                seen[c.name] = true
                list[#list + 1] = c
            end
        end
    end
    table.sort(list, function(a, b)
        if a.rank ~= b.rank then return a.rank < b.rank end
        return a.name < b.name
    end)

    local parts = {}
    for i = 1, math.min(5, #list) do
        local c = list[i]
        local color = c.online and ns.ClassHex(c.rec and c.rec.class) or "6a6b74"
        parts[#parts + 1] = "|cff" .. color .. ns.Short(c.name) .. "|r" .. (c.mine and " |cff8a8b94(you)|r"
            or (c.online and c.busy) and " |cffffba45(busy)|r" or "")
    end
    if #list > 5 then parts[#parts + 1] = "|cff8a8b94+" .. (#list - 5) .. " more|r" end
    local online = 0
    for _, c in ipairs(list) do if c.online and not c.mine then online = online + 1 end end

    tt:AddLine(" ")
    tt:AddDoubleLine("|cff" .. ns.AccentHex() .. "Artisan|r crafters", online .. " online", 1, 1, 1, 0.55, 0.56, 0.6)
    tt:AddLine(table.concat(parts, ", "), 1, 1, 1, true)
    tt:Show()
end

local function HookTooltips()
    if TooltipDataProcessor and Enum and Enum.TooltipDataType and TooltipDataProcessor.AddTooltipPostCall then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, data)
            if tt ~= GameTooltip and tt ~= ItemRefTooltip then return end
            pcall(AddCrafters, tt, data and data.id)
        end)
    else
        local function hook(tt)
            tt:HookScript("OnTooltipSetItem", function(self)
                local _, link = self:GetItem()
                local id = link and tonumber(link:match("item:(%d+)"))
                pcall(AddCrafters, self, id)
            end)
        end
        hook(GameTooltip)
        if ItemRefTooltip then hook(ItemRefTooltip) end
    end
end

------------------------------------------------------------------------
-- Toast pop-up
------------------------------------------------------------------------
local toast
local function ShowToast(icon, title, text, key, onClick)
    if not toast then
        toast = CreateFrame("Button", "ArtisanNetToast", UIParent)
        toast:SetSize(340, 60)
        toast:SetFrameStrata("DIALOG")
        ns:MakeMovable(toast, "toast", { "TOP", UIParent, "TOP", 0, -150 })
        W.Fill(toast, C.bg)
        W.Border(toast, { 0, 0, 0, 1 })
        local bar = toast:CreateTexture(nil, "ARTWORK")
        bar:SetWidth(3)
        bar:SetPoint("TOPLEFT")
        bar:SetPoint("BOTTOMLEFT")
        W.Accentize(bar, "tex")
        toast.icon = W.Icon(toast, 36)
        toast.icon:SetPoint("LEFT", 14, 0)
        toast.title = W.Text(toast, 12)
        toast.title:SetPoint("TOPLEFT", toast.icon, "TOPRIGHT", 12, -2)
        toast.title:SetWidth(270)
        toast.text = W.Text(toast, 11, C.dim)
        toast.text:SetPoint("BOTTOMLEFT", toast.icon, "BOTTOMRIGHT", 12, 2)
        toast.text:SetWidth(270)
        toast:SetScript("OnClick", function(self)
            if self.dragged then return end   -- the mouse-up that ends a drag isn't a click
            self:Hide()
            if self.onClick then self.onClick()
            elseif self.key then ns:ShowUI("search", self.key) end
        end)
        toast:SetScript("OnUpdate", function(self, elapsed)
            self.life = self.life - elapsed
            if self:IsMouseOver() then self.life = math.max(self.life, 1.5) end
            self:SetAlpha(math.min(1, math.max(0, self.life)))
            if self.life <= 0 then self:Hide() end
        end)
    end
    toast.icon.tex:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    toast.title:SetText(title)
    toast.text:SetText(text)
    toast.key = key
    toast.onClick = onClick
    toast.life = onClick and 20 or 8
    toast:SetAlpha(1)
    toast:Show()
    if ns.settings.alertSound then
        pcall(PlaySound, (SOUNDKIT and SOUNDKIT.TELL_MESSAGE) or 3081)
    end
end
ns.ShowToast = ShowToast

local lastAlert = {}
local function CheckWatch(name, online)
    if not online or not ns.settings.alerts or not next(ns.db.watch) then return end
    if ns:IsMine(name) or ns:IsBusy(name) then return end
    if not ns.loginTime or GetTime() - ns.loginTime < 20 then return end  -- skip the login flood
    if lastAlert[name] and GetTime() - lastAlert[name] < 600 then return end
    local rec = ns:GetRecord(name)
    if not rec or not rec.recipes then return end

    local hits = {}
    for _, r in pairs(rec.recipes) do
        for pass = 1, 2 do
            for _, id in ipairs((pass == 1 and r.s or r.i) or {}) do
                local key = (pass == 1 and "s" or "i") .. id
                if ns.db.watch[key] then hits[#hits + 1] = key end
            end
        end
    end
    if #hits == 0 then return end
    lastAlert[name] = GetTime()

    local rname, icon = ns.RecipeInfo(hits[1])
    local more = #hits > 1 and (" and " .. (#hits - 1) .. " more") or ""
    ShowToast(icon,
        "|cff" .. ns.ClassHex(rec.class) .. ns.Short(name) .. "|r is online",
        "Can craft " .. (rname or "a watched recipe") .. more,
        hits[1])
end

------------------------------------------------------------------------
-- Minimap button
------------------------------------------------------------------------
local mm
local function PositionMinimap()
    local a = math.rad(ns.settings.minimap.angle or 215)
    local r = (Minimap:GetWidth() / 2) + 6
    mm:ClearAllPoints()
    mm:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

local function CreateMinimap()
    mm = CreateFrame("Button", "ArtisanNetMinimapButton", Minimap)
    mm:SetSize(32, 32)
    mm:SetFrameStrata("MEDIUM")
    mm:SetFrameLevel(8)
    mm:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    mm:RegisterForDrag("LeftButton")
    mm:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local icon = mm:CreateTexture(nil, "ARTWORK")
    icon:SetSize(22, 22)
    icon:SetPoint("CENTER")
    icon:SetTexture(ns.MEDIA .. "Minimap")
    local border = mm:CreateTexture(nil, "OVERLAY")
    border:SetSize(54, 54)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    mm:SetScript("OnClick", function(_, button)
        if button == "RightButton" then ns:ShowUI("settings") else ns:ToggleUI() end
    end)
    mm:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local s = Minimap:GetEffectiveScale()
            px, py = px / s, py / s
            ns.settings.minimap.angle = math.deg(math.atan2(py - my, px - mx))
            PositionMinimap()
        end)
    end)
    mm:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    mm:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("|cff" .. ns.AccentHex() .. "Artisan|r Network")
        local n = ns:OnlineCount()
        GameTooltip:AddLine(n .. (n == 1 and " other addon user" or " other addon users") .. " online", 0.8, 0.8, 0.85)
        local upd = ns:UpdateAvailable()
        if upd then GameTooltip:AddLine("Update available: v" .. upd, 1, 0.73, 0.27) end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Left-click: open", 0.55, 0.56, 0.6)
        GameTooltip:AddLine("Right-click: settings", 0.55, 0.56, 0.6)
        GameTooltip:AddLine("Drag: move", 0.55, 0.56, 0.6)
        GameTooltip:Show()
    end)
    mm:SetScript("OnLeave", function() GameTooltip:Hide() end)
    PositionMinimap()
end

function ns:UpdateMinimap()
    if not mm then CreateMinimap() end
    mm:SetShown(not ns.settings.minimap.hide)
    if ns.UI then ns.UI:Refresh() end
end

------------------------------------------------------------------------
-- Test mode: fake players so every screen can be tried solo. Nothing is sent.
------------------------------------------------------------------------
local TEST_ITEMS = {
    [171] = { 13510, 13446, 13452, 9206, 5634, 13457, 13455, 12360 },  -- Alchemy
    [164] = { 12784, 12640 },                                           -- Blacksmithing
    [202] = { 10646, 15993, 4390 },                                     -- Engineering
    [165] = { 15063 },                                                  -- Leatherworking
    [197] = { 14046, 14342 },                                           -- Tailoring
    [185] = { 21023 },                                                  -- Cooking
    [129] = { 14530 },                                                  -- First Aid
}
local TEST_NAMES = { "Thornwick", "Elowen", "Brakka", "Sylvaris", "Grumbold", "Mirella", "Kaztor", "Velindra", "Osric", "Nyxie" }
local TEST_CLASSES = { "WARRIOR", "MAGE", "PRIEST", "ROGUE", "HUNTER", "WARLOCK", "DRUID", "PALADIN", "SHAMAN" }
local testTicker

function ns:ToggleTestMode()
    if ns.testPlayers then
        ns.testPlayers = nil
        ns.testChars = nil
        if testTicker then testTicker:Cancel(); testTicker = nil end
        ns.Print("Test mode off.")
    else
        local profIds = {}
        for id in pairs(TEST_ITEMS) do profIds[#profIds + 1] = id end
        table.sort(profIds)
        local t = {}
        for i, n in ipairs(TEST_NAMES) do
            local profs, recipes = {}, {}
            local picks = { profIds[(i % #profIds) + 1], profIds[((i * 3) % #profIds) + 1] }
            for _, pid in ipairs(picks) do
                profs[pid] = { math.random(150, 300), 300 }
                -- sample specializations
                local specs = ({ [165] = { "ds", "el", "tr" }, [202] = { "gn", "gb" }, [164] = { "ar", "we-sw", "we" } })[pid]
                if specs and i % 3 ~= 1 then profs[pid][3] = specs[(i % #specs) + 1] end
                local items = {}
                for _, it in ipairs(TEST_ITEMS[pid]) do
                    if math.random() < 0.75 then items[#items + 1] = it end
                end
                if #items == 0 then items[1] = TEST_ITEMS[pid][1] end
                table.sort(items)
                recipes[pid] = { s = {}, i = items }
            end
            if i % 3 == 0 then profs[186] = { math.random(100, 300), 300 } end
            if i % 4 == 0 then profs[182] = { math.random(100, 300), 300 } end
            t[n .. "-Test"] = {
                class = TEST_CLASSES[(i % #TEST_CLASSES) + 1], level = 60,
                profs = profs, recipes = recipes, online = (i % 2 == 0),
                lastSeen = time() - i * 3600, updated = time() - i * 600, test = true, version = ns.VERSION,
                busy = (i == 6) or nil,   -- one online sample player is busy
                note = (i == 2 and "Free with your mats, tips welcome")
                    or (i == 4 and "Usually on evenings and weekends")
                    or (i == 7 and "Bring mats + 1g, mail is fine") or nil,
            }
        end
        ns.testPlayers = t

        -- sample alts for the My Characters page
        local now = time()
        local function alt(class, level, profs, recipes, cooldowns, seen, scanned)
            local r = {}
            for pid, items in pairs(recipes) do r[pid] = { s = {}, i = items, t = now - scanned } end
            return { class = class, level = level, profs = profs, recipes = r, cooldowns = cooldowns,
                     lastSeen = now - seen, test = true }
        end
        ns.testChars = {
            ["Elarith-Test"] = alt("PRIEST", 60, { [171] = { 300, 300 }, [182] = { 300, 300 } },
                { [171] = TEST_ITEMS[171] },
                { transmute = { name = "Transmute", prof = 171, ready = 0, spell = 17187 } }, 3 * 86400, 3 * 86400),
            ["Thornwick-Test"] = alt("WARLOCK", 60, { [197] = { 300, 300 }, [185] = { 225, 300 } },
                { [197] = TEST_ITEMS[197], [185] = TEST_ITEMS[185] },
                { mooncloth = { name = "Mooncloth", prof = 197, ready = now + 2 * 86400 + 6 * 3600, spell = 18560 } },
                6 * 3600, 6 * 3600),
            ["Velkara-Test"] = alt("DRUID", 44, { [165] = { 210, 225 }, [393] = { 225, 225 } }, {}, nil, 5 * 86400, 0),
        }
        -- flip someone online/offline every 25s so presence changes and alerts can be seen
        testTicker = C_Timer.NewTicker(25, function()
            if not ns.testPlayers then return end
            local name = TEST_NAMES[math.random(#TEST_NAMES)] .. "-Test"
            local rec = ns.testPlayers[name]
            rec.online = not rec.online
            if not rec.online then rec.lastSeen = time() end
            ns:Fire("PRESENCE", name, rec.online)
        end)
        ns.Print("Test mode on: 10 sample players added. Watch a recipe to see pop-up alerts. /artisan test to turn off.")
    end
    ns:MarkIndexDirty()
    ns:Fire("PLAYERS")
end

------------------------------------------------------------------------
-- /artisan who <text>
------------------------------------------------------------------------
function ns:PrintWho(query)
    if not query or query == "" then
        ns.Print("Usage: /artisan who <recipe name>")
        return
    end
    local res = ns:Search(query, nil, false)
    if #res == 0 then
        ns.Print("Nobody known can craft anything matching '" .. query .. "'.")
        return
    end
    for i = 1, math.min(5, #res) do
        local e = res[i]
        local _, _, link = ns.RecipeInfo(e.key)
        local names = {}
        for _, c in ipairs(ns:SortedCrafters(e)) do
            if #names >= 6 then break end
            names[#names + 1] = (c.online and ("|cff" .. ns.ClassHex(c.rec and c.rec.class)) or "|cff6a6b74") .. ns.Short(c.name) .. "|r"
        end
        ns.Print((link or e.name) .. ": " .. table.concat(names, ", "))
    end
    if #res > 5 then ns.Print("...and " .. (#res - 5) .. " more. Open /artisan to see everything.") end
end

------------------------------------------------------------------------
------------------------------------------------------------------------
-- Shift-click an item (bags, chat links, loot...) while the window is open
-- to search for it. When a chat box is open the link goes to chat as usual.
------------------------------------------------------------------------
local function OnInsertLink(link)
    if type(link) ~= "string" or ns.linking then return end
    local f = _G.ArtisanNetFrame
    if not (f and f:IsShown()) then return end
    local name = link:match("|h%[(.-)%]|h")
    if not name or name == "" then return end
    local chatOpen = (ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow())
    if chatOpen and not (ns.searchBox and ns.searchBox:HasFocus()) then return end
    ns:ShowUI("search", nil, name)
end

local function HookShiftClick()
    if ChatEdit_InsertLink then hooksecurefunc("ChatEdit_InsertLink", OnInsertLink) end
    if ChatFrameUtil and ChatFrameUtil.InsertLink then hooksecurefunc(ChatFrameUtil, "InsertLink", OnInsertLink) end
end

------------------------------------------------------------------------
-- Data bars (EllesmereUI, ElvUI, Titan Panel, ChocolateBar, Bazooka...): an
-- Artisan Network entry through LibDataBroker. Nothing is bundled: when a bar
-- addon has loaded the library, we use it; without one this does nothing.
------------------------------------------------------------------------
local broker
local ONLINE_TEX = "|TInterface\\FriendsFrame\\StatusIcon-Online:0|t"
local OFFLINE_TEX = "|TInterface\\FriendsFrame\\StatusIcon-Offline:0|t"
local BUSY_TEX = "|TInterface\\FriendsFrame\\StatusIcon-Away:0|t"

local function OthersOnline()
    local t = {}
    for name, rec in pairs(ns:AllPlayers()) do
        if not ns:IsMine(name) and ns:IsOnline(name) then t[#t + 1] = { name = name, rec = rec } end
    end
    table.sort(t, function(a, b) return a.name < b.name end)
    return t
end

local function BrokerText()
    if not ns.me then return "Artisan" end
    local on = ns:OnlineCount()
    local parts = {}
    if ns:MyRecord().busy then
        parts[1] = BUSY_TEX .. " |cffffba45Busy|r"
        parts[2] = on .. " online"
    elseif on > 0 then
        parts[1] = ONLINE_TEX .. " " .. on .. " online"
    else
        parts[1] = OFFLINE_TEX .. " |cff8a8b94nobody online|r"
    end
    local unseen = ns.db.requestsUnseen or 0
    if unseen > 0 then
        parts[#parts + 1] = "|cff" .. ns.AccentHex() .. unseen .. (unseen == 1 and " request" or " requests") .. "|r"
    end
    return table.concat(parts, " |cff62636c·|r ")
end

local function BrokerTooltip(tt)
    if not tt or not tt.AddLine then return end
    tt:AddLine("|cff" .. ns.AccentHex() .. "Artisan|r Network")
    if not ns.me then tt:AddLine("Loading...", 0.6, 0.6, 0.65) return end
    local busy = ns:MyRecord().busy
    tt:AddDoubleLine("You", busy and "Busy" or "Available to craft", 1, 1, 1,
        busy and 1 or 0.32, busy and 0.73 or 0.87, busy and 0.27 or 0.49)
    tt:AddLine(" ")
    tt:AddLine("Online now", 0.55, 0.56, 0.6)
    local list = OthersOnline()
    for i, it in ipairs(list) do
        if i > 10 then
            tt:AddLine("+" .. (#list - 10) .. " more", 0.55, 0.56, 0.6)
            break
        end
        local profs = {}
        for _, id in ipairs(ns.SortedProfs(it.rec)) do
            if not ns.IsGathering(id) and #profs < 2 then
                local p = it.rec.profs[id]
                profs[#profs + 1] = ns.ProfName(id) .. ((p[1] or 0) > 0 and (" " .. p[1]) or "")
            end
        end
        local who = "|cff" .. ns.ClassHex(it.rec.class) .. ((it.rec.display) or ns.Short(it.name)) .. "|r"
            .. (it.rec.busy and " |cffffba45(busy)|r" or "")
        tt:AddDoubleLine(who, table.concat(profs, " · "), 1, 1, 1, 0.6, 0.6, 0.65)
    end
    if #list == 0 then tt:AddLine("Nobody else with the addon is online.", 0.6, 0.6, 0.65) end

    tt:AddLine(" ")
    local unseen = ns.db.requestsUnseen or 0
    local watched = 0
    if next(ns.db.watch) then
        ns:GetIndex()
        for key in pairs(ns.db.watch) do
            local e = ns.byKey and ns.byKey[key]
            if e and ns:CountOnline(e) > 0 then watched = watched + 1 end
        end
    end
    local known = 0
    for name in pairs(ns:AllPlayers()) do if not ns:IsMine(name) then known = known + 1 end end
    tt:AddDoubleLine("New requests", unseen, 1, 1, 1, unseen > 0 and 1 or 0.6, unseen > 0 and 0.73 or 0.6, unseen > 0 and 0.27 or 0.65)
    tt:AddDoubleLine("Watched recipes with a crafter online", watched, 1, 1, 1, 1, 1, 1)
    tt:AddDoubleLine("Players known", known, 1, 1, 1, 0.6, 0.6, 0.65)
    tt:AddLine(" ")
    tt:AddLine("Click to open Artisan Network", 0.37, 0.78, 0.71)
    tt:AddLine("Right-click to switch Available / Busy", 0.37, 0.78, 0.71)
    tt:AddLine("Shift-click to open Requests", 0.37, 0.78, 0.71)
end

function ns:UpdateBroker()
    if broker then broker.text = BrokerText() end
end

local function SetupBroker()
    if broker then return end
    local LS = _G.LibStub
    local ldb = LS and LS("LibDataBroker-1.1", true)
    if not ldb then return end
    broker = ldb:NewDataObject("Artisan Network", {
        type = "data source",
        label = "Artisan",
        text = "Artisan",
        icon = ns.MEDIA .. "Icon",
        OnClick = function(_, button)
            if not ns.me then return end
            if button == "RightButton" then
                ns:SetBusy(not ns:MyRecord().busy)
            elseif IsShiftKeyDown() then
                ns:ShowUI("requests")
            else
                ns:ToggleUI()
            end
        end,
        OnTooltipShow = function(tt) pcall(BrokerTooltip, tt) end,
    })
    if not broker then return end   -- another copy already registered the name
    for _, msg in ipairs({ "PLAYERS", "PRESENCE", "REQUESTS", "NETWORK", "ACCENT", "DATA_CHANGED" }) do
        ns:Listen(msg, function() ns:Debounce("broker", 0.5, function() ns:UpdateBroker() end) end)
    end
    ns:UpdateBroker()
end
-- Most bars load the library before PLAYER_LOGIN, so we register then. Some UI suites
-- load their data bar part later on demand, so we also try again whenever any addon
-- finishes loading, and a little after login, until we're registered.
local brokerErr
local function TrySetupBroker()
    if broker then return end
    local ok, err = pcall(SetupBroker)
    if not ok then brokerErr = tostring(err) end
end
ns:On("PLAYER_LOGIN", TrySetupBroker)
ns:On("ADDON_LOADED", TrySetupBroker)

-- for /artisan status
function ns.BrokerStatus()
    if broker then return "|cff52de7cconnected|r (pick \"Artisan Network\" in your bar's settings)" end
    if brokerErr then return "|cffff6b6berror|r " .. brokerErr end
    local LS = _G.LibStub
    if LS and LS("LibDataBroker-1.1", true) then return "|cffe0b050library found, not registered yet|r" end
    return "|cff8a8b94no data bar addon found|r"
end

------------------------------------------------------------------------
-- "Choose a look": asked once, a few seconds after login, until answered.
-- Settings > Appearance > Style changes it later.
------------------------------------------------------------------------
local stylePop
local LOOKS = {
    { key = "artisan", name = "Artisan", desc = "Flat and dark, with an accent color you pick.",
      bg = { 0.047, 0.047, 0.055 }, head = { 0.062, 0.062, 0.072 }, side = { 0.053, 0.053, 0.062 },
      line = { 1, 1, 1, 0.08 }, title = { 0.20, 0.82, 0.74 }, btn = { 0.20, 0.82, 0.74, 0.25 }, rim = { 0.20, 0.82, 0.74 } },
    { key = "forever", name = "Forever", desc = "Brown and gold, like WoW: Forever's own windows.",
      bg = { 0.145, 0.110, 0.082 }, head = { 0.110, 0.070, 0.040 }, side = { 0.165, 0.125, 0.094 },
      line = { 0.62, 0.49, 0.30, 1 }, title = { 1, 0.82, 0.2 }, btn = { 0.45, 0.07, 0.04, 1 }, rim = { 0.80, 0.62, 0.25 } },
}

-- a tiny drawing of the window in that style
local function MiniWindow(parent, look)
    local m = CreateFrame("Frame", nil, parent)
    m:SetSize(176, 92)
    W.Fill(m, { look.bg[1], look.bg[2], look.bg[3], 1 })
    W.Border(m, { look.line[1], look.line[2], look.line[3], 1 })
    local hd = m:CreateTexture(nil, "ARTWORK")
    hd:SetPoint("TOPLEFT", 1, -1); hd:SetPoint("TOPRIGHT", -1, -1); hd:SetHeight(16)
    hd:SetColorTexture(look.head[1], look.head[2], look.head[3], 1)
    local hl = m:CreateTexture(nil, "ARTWORK", nil, 1)
    hl:SetPoint("TOPLEFT", hd, "BOTTOMLEFT"); hl:SetPoint("TOPRIGHT", hd, "BOTTOMRIGHT"); hl:SetHeight(1)
    hl:SetColorTexture(unpack(look.line))
    local sd = m:CreateTexture(nil, "ARTWORK")
    sd:SetPoint("TOPLEFT", hd, "BOTTOMLEFT", 0, -1); sd:SetPoint("BOTTOMLEFT", 1, 1); sd:SetWidth(40)
    sd:SetColorTexture(look.side[1], look.side[2], look.side[3], 1)
    local t = W.Text(m, 9, look.title, look.key == "forever" and "CENTER" or "LEFT")
    if look.key == "forever" then t:SetPoint("TOP", 0, -4) else t:SetPoint("TOPLEFT", 6, -4) end
    t:SetText(look.key == "forever" and "Artisan Network" or "ARTISAN NETWORK")
    for i = 1, 4 do -- sidebar entries and list rows
        local nav = m:CreateTexture(nil, "OVERLAY")
        nav:SetSize(26, 3); nav:SetPoint("TOPLEFT", 7, -24 - (i - 1) * 9)
        nav:SetColorTexture(look.title[1], look.title[2], look.title[3], i == 1 and 0.9 or 0.35)
        local row = m:CreateTexture(nil, "OVERLAY")
        row:SetSize(78, 3); row:SetPoint("TOPLEFT", 50, -26 - (i - 1) * 12)
        row:SetColorTexture(look.title[1], look.title[2], look.title[3], 0.45)
    end
    local b = m:CreateTexture(nil, "OVERLAY")
    b:SetSize(36, 12); b:SetPoint("BOTTOMRIGHT", -8, 8)
    b:SetColorTexture(unpack(look.btn))
    local rim = CreateFrame("Frame", nil, m)
    rim:SetAllPoints(b)
    W.Border(rim, { look.rim[1], look.rim[2], look.rim[3], 1 })
    if look.key == "forever" then -- the round portrait, kept square here
        local por = m:CreateTexture(nil, "OVERLAY", nil, 2)
        por:SetSize(14, 14); por:SetPoint("CENTER", m, "TOPLEFT", 6, -6)
        por:SetColorTexture(0.62, 0.49, 0.30, 1)
        local inner = m:CreateTexture(nil, "OVERLAY", nil, 3)
        inner:SetSize(10, 10); inner:SetPoint("CENTER", por)
        inner:SetColorTexture(0.07, 0.10, 0.16, 1)
    end
    return m
end

local function PickStyle(key)
    ns.settings.stylePicked = true
    ns.settings.style = key
    if stylePop then stylePop:Hide() end
    if key ~= (W.style or "artisan") then
        ReloadUI() -- styles are built at load
    else
        ns.Print("Style: " .. (key == "forever" and "Forever" or "Artisan") .. ". Change it any time in Settings > Appearance.")
    end
end

local function ShowStylePicker()
    if ns.settings.stylePicked then return end
    if InCombatLockdown() then
        C_Timer.After(5, ShowStylePicker)
        return
    end
    if not stylePop then
        local f = CreateFrame("Frame", "ArtisanNetStylePicker", UIParent)
        stylePop = f
        f:SetSize(440, 268)
        f:SetPoint("CENTER", 0, 80)
        f:SetFrameStrata("DIALOG")
        f:SetClampedToScreen(true)
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        W.Fill(f, C.bg)
        W.Border(f, W.forever and C.border or { 1, 1, 1, 0.12 })
        tinsert(UISpecialFrames, "ArtisanNetStylePicker")
        -- closing without picking keeps the current style and doesn't ask again
        f:SetScript("OnHide", function()
            if not ns.settings.stylePicked then
                ns.settings.stylePicked = true
                ns.Print("Keeping the current style. Change it any time in Settings > Appearance.")
            end
        end)

        local icon = f:CreateTexture(nil, "ARTWORK")
        icon:SetSize(22, 22)
        icon:SetPoint("TOPLEFT", 18, -16)
        icon:SetTexture(ns.MEDIA .. "Icon")
        local title = W.Text(f, 15, W.forever and W.GOLD or C.text)
        title:SetPoint("LEFT", icon, "RIGHT", 9, 0)
        title:SetText("Choose a look for Artisan Network")
        local close = CreateFrame("Button", nil, f)
        close:SetSize(24, 24)
        close:SetPoint("TOPRIGHT", -10, -12)
        close.text = W.Text(close, 13, C.dim, "CENTER")
        close.text:SetPoint("CENTER")
        close.text:SetText("x")
        close:SetScript("OnClick", function() f:Hide() end)
        close:SetScript("OnEnter", function(s) s.text:SetTextColor(1, 1, 1) end)
        close:SetScript("OnLeave", function(s) s.text:SetTextColor(unpack(C.dim)) end)

        for i, look in ipairs(LOOKS) do
            local card = CreateFrame("Button", nil, f)
            card:SetSize(196, 176)
            card:SetPoint("TOPLEFT", 18 + (i - 1) * 208, -52)
            card.bg = W.Fill(card, { 1, 1, 1, 0.03 })
            W.Border(card, C.border)
            local mini = MiniWindow(card, look)
            mini:SetPoint("TOP", 0, -10)
            local name = W.Text(card, 13, look.title)
            name:SetPoint("TOPLEFT", mini, "BOTTOMLEFT", 0, -10)
            name:SetText(look.name)
            local desc = W.Text(card, 11, C.dim)
            desc:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -4)
            desc:SetWidth(176)
            desc:SetWordWrap(true)
            desc:SetJustifyV("TOP")
            desc:SetText(look.desc)
            card:SetScript("OnClick", function() PickStyle(look.key) end)
            card:SetScript("OnEnter", function(s)
                s.bg:SetColorTexture(look.title[1], look.title[2], look.title[3], 0.10)
                W.SetBorderColor(s, look.title[1], look.title[2], look.title[3], 1)
                GameTooltip:SetOwner(s, "ANCHOR_BOTTOM")
                GameTooltip:AddLine("Use " .. look.name, 1, 1, 1)
                if look.key ~= (W.style or "artisan") then
                    GameTooltip:AddLine("Your interface reloads to apply it.", 0.7, 0.7, 0.75, true)
                end
                GameTooltip:Show()
            end)
            card:SetScript("OnLeave", function(s)
                s.bg:SetColorTexture(1, 1, 1, 0.03)
                W.SetBorderColor(s, unpack(C.border))
                GameTooltip:Hide()
            end)
        end

        local foot = W.Text(f, 10, C.faint, "CENTER")
        foot:SetPoint("BOTTOM", 0, 14)
        foot:SetText("Click one to use it. You can change this any time in Settings > Appearance.")
    end
    stylePop:Show()
end

function ns:InitExtras()
    HookTooltips()
    HookShiftClick()
    ns:UpdateMinimap()
    ns:Listen("PRESENCE", CheckWatch)
    TrySetupBroker()
    C_Timer.After(10, TrySetupBroker)
    C_Timer.After(30, TrySetupBroker)
    ns:UpdateBroker()
    C_Timer.After(4, ShowStylePicker)
end
