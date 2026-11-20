-- Artisan Network: Find a Crafter page
local ADDON, ns = ...
local W, C = ns.W, ns.W.C
local UI = ns.UI
local DETAIL_W = UI.DETAIL_W
local IsTest, NameText, PresenceText = UI.IsTest, UI.NameText, UI.PresenceText

------------------------------------------------------------------------
-- Search page
------------------------------------------------------------------------
-- the yellow raid-marker star: present in every client
local FAV_TEX = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"
local GOLD = { 1, 0.77, 0.25 }

function UI.Build.Search(content)
    local st = { query = "", prof = nil, recipe = nil }
    local p = CreateFrame("Frame", nil, content)
    p:SetAllPoints()

    local box = W.EditBox(p, 200, 30, "Search recipes...  or shift-click an item")
    ns.searchBox = box
    box:SetPoint("TOPLEFT", 20, -18)
    box:SetPoint("TOPRIGHT", -170, -18)

    local onlineToggle = W.Toggle(p, "Online only",
        function() return ns.settings.onlineOnly end,
        function(v) ns.settings.onlineOnly = v; UI:Refresh() end)
    onlineToggle:SetWidth(130)
    onlineToggle:SetPoint("TOPRIGHT", -20, -22)

    -- profession filter chips
    local chips = {}
    local function MakeChip(profId)
        local b = CreateFrame("Button", nil, p)
        b:SetSize(profId and 28 or 44, 28)
        b.bg = W.Fill(b, { 1, 1, 1, 0.04 })
        W.Border(b)
        b.prof = profId
        if profId == "fav" then
            b.icon = b:CreateTexture(nil, "ARTWORK")
            b.icon:SetPoint("TOPLEFT", 5, -5)
            b.icon:SetPoint("BOTTOMRIGHT", -5, 5)
            b.icon:SetTexture(FAV_TEX)
            W.Tip(b, "Favorites", "Show only your favorite recipes. Hover any recipe and click its star to add it.")
        elseif profId then
            b.icon = b:CreateTexture(nil, "ARTWORK")
            b.icon:SetPoint("TOPLEFT", 3, -3)
            b.icon:SetPoint("BOTTOMRIGHT", -3, 3)
            b.icon:SetTexture(ns.ProfIcon(profId))
            b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            W.Tip(b, ns.ProfName(profId))
        else
            b.text = W.Text(b, 11, C.text, "CENTER")
            b.text:SetPoint("CENTER")
            b.text:SetText("All")
        end
        b:SetScript("OnClick", function() st.prof = profId; UI:Refresh() end)
        chips[#chips + 1] = b
    end
    MakeChip(nil)
    MakeChip("fav")
    for _, id in ipairs(ns.PROF_ORDER) do
        if not ns.IsGathering(id) then MakeChip(id) end
    end

    local function LayoutChips()
        local present = {}
        for _, e in ipairs(ns:GetIndex()) do present[e.prof] = true end
        local x = 20
        local r, g, bb = ns.Accent()
        for _, b in ipairs(chips) do
            if not b.prof or b.prof == "fav" or present[b.prof] or st.prof == b.prof then
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", x, -60)
                b:Show()
                x = x + b:GetWidth() + 6
                local sel = st.prof == b.prof
                if sel then
                    W.SetBorderColor(b, r, g, bb, 1)
                    b.bg:SetColorTexture(r, g, bb, 0.15)
                else
                    W.SetBorderColor(b, unpack(C.border))
                    b.bg:SetColorTexture(1, 1, 1, 0.04)
                end
                if b.icon then
                    b.icon:SetDesaturated(not sel and st.prof ~= nil)
                    b.icon:SetAlpha((sel or not st.prof) and 1 or 0.55)
                end
                if b.text then b.text:SetTextColor(unpack(sel and { r, g, bb } or C.dim)) end
            else
                b:Hide()
            end
        end
    end

    local lowToggle = W.Toggle(p, "Hide low level",
        function() return ns.settings.hideLow end,
        function(v) ns.settings.hideLow = v; UI:Refresh() end)
    lowToggle:SetWidth(130)
    lowToggle:SetPoint("TOPRIGHT", -20, -63)
    W.Tip(lowToggle, "Hide low level",
        function() return "Hides recipes whose crafted item is below level " .. (ns.settings.lowCutoff or 40)
            .. ". Change the level in Settings. Right-click any recipe to hide or show it by hand." end)

    local lblRecipe = W.Label(p, "Recipe")
    lblRecipe:SetPoint("TOPLEFT", 28, -102)
    local lblCount = W.Text(p, 10, C.faint, "RIGHT")
    lblCount:SetPoint("TOPRIGHT", -(DETAIL_W + 36), -102)
    local hiddenBtn = CreateFrame("Button", nil, p)
    hiddenBtn:SetHeight(14)
    hiddenBtn:SetPoint("RIGHT", lblCount, "LEFT", -12, 0)
    hiddenBtn.text = W.Text(hiddenBtn, 10, C.dim, "RIGHT")
    hiddenBtn.text:SetPoint("RIGHT")
    hiddenBtn:SetScript("OnClick", function()
        ns.settings.showHidden = not ns.settings.showHidden
        UI:Refresh()
    end)
    hiddenBtn:SetScript("OnEnter", function(self) self.text:SetTextColor(1, 1, 1) end)
    hiddenBtn:SetScript("OnLeave", function(self) self.text:SetTextColor(unpack(C.dim)) end)

    -- detail panel
    local d = W.Panel(p)
    d:SetPoint("TOPRIGHT", -20, -100)
    d:SetPoint("BOTTOMRIGHT", -20, 18)
    d:SetWidth(DETAIL_W)
    d.empty = W.Text(d, 12, C.faint, "CENTER")
    d.empty:SetPoint("CENTER")
    d.empty:SetWidth(DETAIL_W - 40)
    d.empty:SetWordWrap(true)
    d.empty:SetText("Select a recipe to see who can craft it.")

    -- "Getting started": fills the empty panel while the network is still small
    local START_UNTIL = 5   -- other players sharing recipes; at this many the card steps aside
    local READY = "|TInterface\\RaidFrame\\ReadyCheck-Ready:13|t "
    local TODO = "|TInterface\\RaidFrame\\ReadyCheck-Waiting:13|t "
    local start = CreateFrame("Frame", nil, d)
    start:SetAllPoints()
    start:Hide()
    start.title = W.Text(start, 14)
    start.title:SetPoint("TOPLEFT", 16, -16)
    start.title:SetText("Getting started")
    start.intro = W.Text(start, 11, C.dim)
    start.intro:SetPoint("TOPLEFT", start.title, "BOTTOMLEFT", 0, -8)
    start.intro:SetWidth(DETAIL_W - 32)
    start.intro:SetWordWrap(true)
    start.intro:SetText("Artisan Network grows with every player who joins. Recipes from your guild, your groups and players you meet show up here on their own.")
    local function Step(anchor, gap)
        local s = {}
        s.head = W.Text(start, 12)
        s.head:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -gap)
        s.head:SetWidth(DETAIL_W - 32)
        s.text = W.Text(start, 11, C.dim)
        s.text:SetPoint("TOPLEFT", s.head, "BOTTOMLEFT", 0, -4)
        s.text:SetWidth(DETAIL_W - 32)
        s.text:SetWordWrap(true)
        return s
    end
    start.s1 = Step(start.intro, 18)
    start.s2 = Step(start.s1.text, 16)
    start.invite = W.Button(start, "Invite", 90, 22)
    start.invite:SetPoint("TOPLEFT", start.s2.text, "BOTTOMLEFT", 0, -8)
    start.invite:SetScript("OnClick", function() ns:InviteText() end)
    W.Tip(start.invite, "Invite", function()
        return "Puts a short invite with the download link in your " .. (IsInGuild() and "guild chat" or "chat")
            .. " box. Nothing is sent until you press Enter."
    end)
    start.s3 = Step(start.invite, 16)
    start.test = W.Button(start, "Test mode", 90, 22)
    start.test:SetPoint("TOPLEFT", start.s3.text, "BOTTOMLEFT", 0, -8)
    start.test:SetScript("OnClick", function() ns:ToggleTestMode(); UI:Refresh() end)
    start.hide = CreateFrame("Button", nil, start)
    start.hide:SetHeight(14)
    start.hide:SetPoint("BOTTOMRIGHT", -16, 12)
    start.hide.text = W.Text(start.hide, 10, C.faint, "RIGHT")
    start.hide.text:SetPoint("RIGHT")
    start.hide.text:SetText("Don't show this again")
    start.hide:SetWidth(start.hide.text:GetStringWidth() + 4)
    start.hide:SetScript("OnClick", function() ns.settings.hideStart = true; UI:Refresh() end)
    start.hide:SetScript("OnEnter", function(self) self.text:SetTextColor(1, 1, 1) end)
    start.hide:SetScript("OnLeave", function(self) self.text:SetTextColor(unpack(C.faint)) end)

    -- other players sharing recipes (not you, not test players)
    local function NetworkSize()
        local n = 0
        for name, rec in pairs(ns.db.players) do
            if not ns:IsMine(name) and rec.recipes and next(rec.recipes) then n = n + 1 end
        end
        return n
    end
    function start:Wanted()
        return not ns.settings.hideStart and not ns.testPlayers and NetworkSize() < START_UNTIL
    end
    function start:Refresh()
        -- 1. your professions
        local missing = {}
        local rec = ns.me and ns:MyRecord()
        for id in pairs(rec and rec.profs or {}) do
            if not ns.IsGathering(id) and not (rec.recipes and rec.recipes[id]) then
                missing[#missing + 1] = ns.ProfName(id)
            end
        end
        table.sort(missing)
        if #missing == 0 then
            self.s1.head:SetText(READY .. "Your recipes are shared")
            self.s1.text:SetText("They update by themselves whenever you open a profession window.")
        else
            self.s1.head:SetText(TODO .. "Open your profession windows")
            self.s1.text:SetText("Open " .. table.concat(missing, ", ") .. " once on this character so your recipes are shared.")
        end
        -- 2. your guild
        local users, total = ns:GuildAdoption()
        if users then
            self.s2.head:SetText((users > 1 and READY or TODO) .. "Get your guild on board")
            self.s2.text:SetText("|cffffffff" .. users .. " of " .. total .. "|r in your guild use Artisan Network. One guild using it together is already a working crafting directory.")
        else
            self.s2.head:SetText(TODO .. "Invite your friends")
            self.s2.text:SetText("Everyone you group with who runs it shows up here. Share it with friends, or join a guild that uses it.")
        end
        -- 3. test mode
        self.s3.head:SetText("Want a preview?")
        self.s3.text:SetText("Test mode fills every screen with sample players. Nothing is sent.")
    end

    local body = CreateFrame("Frame", nil, d)
    body:SetAllPoints()
    body.icon = W.Icon(body, 42)
    body.icon:SetPoint("TOPLEFT", 16, -16)
    body.icon:EnableMouse(true)
    body.icon:SetScript("OnEnter", function(self)
        if not st.recipe then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        ns.SetRecipeTooltip(GameTooltip, st.recipe)
        GameTooltip:Show()
    end)
    body.icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
    body.name = W.Text(body, 14)
    body.name:SetPoint("TOPLEFT", body.icon, "TOPRIGHT", 12, -4)
    body.name:SetWidth(DETAIL_W - 90)
    -- Favorite toggle, right side of the profession line
    body.fav = CreateFrame("Button", nil, body)
    body.fav:SetHeight(16)
    body.fav:SetPoint("BOTTOMRIGHT", body, "TOPRIGHT", -16, -(16 + 42 - 2))
    body.fav.icon = body.fav:CreateTexture(nil, "ARTWORK")
    body.fav.icon:SetSize(13, 13)
    body.fav.icon:SetPoint("LEFT")
    body.fav.icon:SetTexture(FAV_TEX)
    body.fav.text = W.Text(body.fav, 11, C.dim)
    body.fav.text:SetPoint("LEFT", body.fav.icon, "RIGHT", 4, 0)
    body.fav.text:SetText("Favorite")
    body.fav:SetWidth(17 + body.fav.text:GetStringWidth())
    function body.fav:Paint(hover)
        local on = st.recipe and ns:IsFavorite(st.recipe)
        self.icon:SetDesaturated(not on)
        self.icon:SetAlpha(on and 1 or (hover and 0.9 or 0.5))
        self.text:SetTextColor(unpack(on and GOLD or (hover and C.text or C.dim)))
    end
    body.fav:SetScript("OnClick", function() if st.recipe then ns:ToggleFavorite(st.recipe) end end)
    body.fav:SetScript("OnEnter", function(self) self:Paint(true) end)
    body.fav:SetScript("OnLeave", function(self) self:Paint(false) end)
    W.Tip(body.fav, "Favorite", function()
        return (st.recipe and ns:IsFavorite(st.recipe)) and "A favorite: listed first, and shown by the star filter. Click to remove it."
            or "Click to add to your favorites. They're listed first and have their own filter. No pop-ups, unlike Watch."
    end)
    body.prof = W.Text(body, 11, C.dim)
    body.prof:SetPoint("BOTTOMLEFT", body.icon, "BOTTOMRIGHT", 12, 4)
    body.prof:SetPoint("RIGHT", body.fav, "LEFT", -8, 0)

    body.watch = W.Button(body, "Watch", 84, 24)
    body.watch:SetPoint("TOPLEFT", 16, -74)
    body.watch:SetScript("OnClick", function()
        if not st.recipe then return end
        ns.db.watch[st.recipe] = (not ns.db.watch[st.recipe]) or nil
        UI:Refresh()
    end)
    W.Tip(body.watch, "Watch", "Get a pop-up whenever someone who can craft this comes online.")
    body.link = W.Button(body, "Link", 84, 24)
    body.link:SetPoint("LEFT", body.watch, "RIGHT", 8, 0)
    body.link:SetScript("OnClick", function() if st.recipe then ns:LinkRecipe(st.recipe) end end)
    W.Tip(body.link, "Link in chat", "Puts a link to this recipe in your chat box.")
    body.request = W.Button(body, "Request", 84, 24)
    body.request:SetPoint("LEFT", body.link, "RIGHT", 8, 0)
    body.request:SetScript("OnClick", function() if st.recipe then UI:OpenRequest(st.recipe) end end)
    W.Tip(body.request, "Request a craft", function()
        local e = st.recipe and ns.byKey and ns.byKey[st.recipe]
        local n = e and #ns:RequestTargets(e) or 0
        if e and ns.RecipeBoP(e.key) then return "Bind on Pickup: crafters can only make this for themselves." end
        if n == 0 then
            local on, others = 0, 0
            if e then on, others = ns:CountOnline(e) end
            if others == 0 then return "Only your own characters know this recipe, so there's nobody to ask." end
            if on > 0 then return "Everyone online who can craft this is busy right now." end
            return "Nobody else who can craft this is online right now. Press Watch to get a pop-up when one logs in."
        end
        return "Sends a pop-up to the " .. n .. " available " .. (n == 1 and "crafter" or "crafters")
            .. " online who can make this. They can answer with one click."
    end)

    -- reagents
    local lblReagents = W.Label(body, "Reagents")
    lblReagents:SetPoint("TOPLEFT", 16, -112)
    -- legend for the numbers under the icons, and whether you have everything
    body.reagentSum = W.Text(body, 10, C.faint, "RIGHT")
    body.reagentSum:SetPoint("TOPRIGHT", -16, -112)
    body.reagents = {}
    for k = 1, 7 do
        local ic = W.Icon(body, 26)
        ic:SetPoint("TOPLEFT", 21 + (k - 1) * 38, -126)
        -- "have / need" under the icon: green = enough in your bags, yellow = enough
        -- counting your bank, red = not enough
        ic.have = body:CreateFontString(nil, "OVERLAY")
        ic.have:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
        ic.have:SetPoint("TOP", ic, "BOTTOM", 0, -2)
        ic:EnableMouse(true)
        ic:SetScript("OnEnter", function(self)
            if not self.item then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. self.item)
            GameTooltip:AddLine(" ")
            GameTooltip:AddDoubleLine("Needed", self.need, 0.7, 0.7, 0.75, 1, 1, 1)
            GameTooltip:AddDoubleLine("In your bags", self.bags, 0.7, 0.7, 0.75, unpack(self.color))
            if self.bank > 0 then
                GameTooltip:AddDoubleLine("In your bank", self.bank, 0.7, 0.7, 0.75, 1, 1, 1)
            end
            GameTooltip:Show()
        end)
        ic:SetScript("OnLeave", function() GameTooltip:Hide() end)
        body.reagents[k] = ic
    end
    body.noReagents = W.Text(body, 11, C.faint)
    body.noReagents:SetPoint("TOPLEFT", 16, -134)
    body.noReagents:SetWidth(DETAIL_W - 32)
    body.noReagents:SetText("Not known yet. They appear once someone with this recipe opens it.")
    body.noReagents:SetWordWrap(true)

    local lblCrafters = W.Label(body, "Crafters")
    lblCrafters:SetPoint("TOPLEFT", 16, -178)
    body.count = W.Text(body, 10, C.faint, "RIGHT")
    body.count:SetPoint("TOPRIGHT", -16, -178)
    local sep = W.Line(body, true)
    sep:SetPoint("TOPLEFT", 16, -194)
    sep:SetPoint("TOPRIGHT", -16, -194)

    local crafters = W.List(body, 34, function(list)
        local r = W.RowBase(list)
        r.dot = r:CreateTexture(nil, "ARTWORK")
        r.dot:SetSize(12, 12)
        r.dot:SetPoint("LEFT", 8, 0)
        r.name = W.Text(r, 12)
        r.name:SetPoint("TOPLEFT", 26, -4)
        r.name:SetWidth(170)
        r.sub = W.Text(r, 10, C.dim)
        r.sub:SetPoint("BOTTOMLEFT", 26, 4)
        r.sub:SetWidth(170)
        r.btn = W.Button(r, "Whisper", 64, 20)
        r.btn:SetPoint("RIGHT", -6, 0)
        r.btn:SetScript("OnClick", function() if r.item then ns:Whisper(r.item.name, st.recipe) end end)
        r:SetScript("OnClick", function() if r.item then UI:ShowPlayer(r.item.name) end end)
        r:HookScript("OnEnter", function(self)
            local c = self.item
            if not (c and c.rec and c.rec.note) then return end
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:AddLine(ns.Short(c.name), 1, 1, 1)
            GameTooltip:AddLine("\"" .. c.rec.note .. "\"", 0.86, 0.82, 0.70, true)
            GameTooltip:Show()
        end)
        r:HookScript("OnLeave", function() GameTooltip:Hide() end)
        return r
    end, function(r, c, i)
        r:SetStripe(i)
        r.dot:SetTexture(c.online and W.ONLINE_ICON or W.OFFLINE_ICON)
        r.name:SetText(NameText(c.name, c.rec))
        local e = ns.byKey and ns.byKey[st.recipe]
        local prof = e and c.rec and c.rec.profs and c.rec.profs[e.prof]
        local rank = prof and prof[1] and prof[1] > 0 and (prof[1] .. "/" .. prof[2] .. "  ·  ") or ""
        local spec = ns.SpecName(prof)
        if spec then rank = rank .. "|cffc9b98a" .. spec .. "|r  ·  " end
        r.sub:SetText(rank .. PresenceText(c.name, c.rec))
        r.btn:SetShown(c.online and not c.busy and not ns:IsMine(c.name) and not IsTest(c.name)
            and not (e and ns.RecipeBoP(e.key)))
        r:SetSelected(false)
    end)
    crafters:SetPoint("TOPLEFT", 8, -200)
    crafters:SetPoint("BOTTOMRIGHT", -8, 8)

    local function RefreshDetail()
        local e = st.recipe and ns.byKey and ns.byKey[st.recipe]
        if not e then
            body:Hide()
            if start:Wanted() then
                d.empty:Hide()
                start:Refresh()
                start:Show()
            else
                start:Hide()
                d.empty:Show()
            end
            return
        end
        start:Hide()
        d.empty:Hide()
        body:Show()
        body.icon.tex:SetTexture(e.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        body.name:SetText(e.name)
        body.prof:SetText(ns.ProfName(e.prof) .. (ns.RecipeBoP(e.key) and "  ·  |cffff8a5cBind on Pickup|r" or "") .. (e.rare and ("  ·  |cffa178ffRare|r |cff8a8b94(" .. #e.crafters
            .. (#e.crafters == 1 and " crafter" or " crafters") .. ")|r") or ""))
        local reagents = ns.Reagents(e.key)
        local short, bankOk = 0, 0
        for k, ic in ipairs(body.reagents) do
            local r = reagents and reagents[k]
            if r then
                ic.item = r[1]
                ic.tex:SetTexture(ns.ItemIcon(r[1]) or "Interface\\Icons\\INV_Misc_QuestionMark")
                local bags = ns.ItemCount(r[1])
                local total = math.max(bags, ns.ItemCount(r[1], true))
                ic.need, ic.bags, ic.bank = r[2], bags, total - bags
                local hex
                if bags >= r[2] then
                    ic.color, hex = { 0.32, 0.87, 0.49 }, "52de7c"
                elseif total >= r[2] then
                    ic.color, hex = { 1, 0.73, 0.27 }, "ffba45"
                    bankOk = bankOk + 1
                else
                    ic.color, hex = { 1, 0.42, 0.42 }, "ff6b6b"
                    short = short + 1
                end
                ic.have:SetText("|cff" .. hex .. bags .. "|r|cff8a8b94/" .. r[2] .. "|r")
                ic:Show(); ic.have:Show()
            else
                ic.item = nil
                ic:Hide(); ic.have:Hide()
            end
        end
        body.noReagents:SetShown(not reagents)
        if not reagents then
            body.reagentSum:SetText("")
        elseif short > 0 then
            body.reagentSum:SetText("in bags / needed  ·  |cffff6b6bmissing " .. short .. "|r")
        elseif bankOk > 0 then
            body.reagentSum:SetText("in bags / needed  ·  |cffffba45some in bank|r")
        else
            body.reagentSum:SetText("in bags / needed  ·  |cff52de7cyou have it all|r")
        end
        body.request:SetEnabled(not ns.RecipeBoP(e.key) and #ns:RequestTargets(e) > 0)
        body.fav:Paint(body.fav:IsMouseOver())
        local watching = ns.db.watch[e.key]
        body.watch:SetLabel(watching and "Watching" or "Watch")
        body.watch:SetActive(watching and true or false)
        local list = ns:SortedCrafters(e)
        local on, others, mine = ns:CountOnline(e)
        body.count:SetText(others == 0 and (mine and "only you" or "")
            or (on .. " online  /  " .. others .. (mine and "  ·  you" or "")))
        crafters:SetData(list)
    end

    -- Group results under slot headers (Chest, Legs, Bags...). Favorites get their own
    -- group on top. Folded headers are remembered in ns.db.collapsed.
    local function Grouped(data)
        if #data == 0 then return data end
        local groups, favs = {}, {}
        local favGroup = st.prof ~= "fav"
        for _, e in ipairs(data) do
            if favGroup and e.fav then
                favs[#favs + 1] = e
            else
                local slot = ns.RecipeSlot(e)
                groups[slot] = groups[slot] or {}
                table.insert(groups[slot], e)
            end
        end
        local out = {}
        local collapsed = ns.db.collapsed
        local function Add(label, list)
            local folded = collapsed[label] and true or false
            out[#out + 1] = { header = true, label = label, n = #list, folded = folded }
            if not folded then
                for _, e in ipairs(list) do out[#out + 1] = e end
            end
        end
        if #favs > 0 then Add("Favorites", favs) end
        for _, slot in ipairs(ns.SLOT_ORDER) do
            if groups[slot] then Add(slot, groups[slot]) end
        end
        return out
    end

    -- results list
    local results = W.List(p, 36, function(list)
        local r = W.RowBase(list)
        r.icon = W.Icon(r, 26)
        r.icon:SetPoint("LEFT", 8, 0)
        r.count = W.Text(r, 11, C.text, "RIGHT")
        r.count:SetPoint("RIGHT", -12, 0)
        r.dot = r:CreateTexture(nil, "ARTWORK")
        r.dot:SetSize(12, 12)
        r.dot:SetPoint("RIGHT", r.count, "LEFT", -4, 0)
        -- favorite star: gold on favorites, faint on the row under the mouse, hidden otherwise
        r.fav = CreateFrame("Button", nil, r)
        r.fav:SetSize(16, 16)
        r.fav:SetPoint("RIGHT", r.dot, "LEFT", -8, 0)
        r.fav.tex = r.fav:CreateTexture(nil, "ARTWORK")
        r.fav.tex:SetAllPoints()
        r.fav.tex:SetTexture(FAV_TEX)
        function r:PaintFav()
            if self.item and self.item.header then self.fav:Hide() return end
            local on = self.item and self.item.fav
            local hot = self:IsMouseOver()
            self.fav:SetShown(on or hot)
            self.fav.tex:SetDesaturated(not on)
            self.fav.tex:SetAlpha(on and 1 or (self.fav:IsMouseOver() and 0.95 or 0.45))
        end
        r.fav:SetScript("OnClick", function() if r.item then ns:ToggleFavorite(r.item.key) end end)
        r.fav:SetScript("OnEnter", function(self)
            r:PaintFav()
            if r.hl then r.hl:Show() end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local on = r.item and r.item.fav
            GameTooltip:AddLine(on and "Remove from favorites" or "Add to favorites", 1, 1, 1)
            GameTooltip:AddLine("Favorites stay at the top and have their own filter.", 0.7, 0.7, 0.75, true)
            GameTooltip:Show()
        end)
        r.fav:SetScript("OnLeave", function()
            GameTooltip:Hide()
            if r.hl and not r:IsMouseOver() then r.hl:Hide() end
            r:PaintFav()
        end)
        r.name = W.Text(r, 12)
        r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 10, -1)
        r.name:SetPoint("RIGHT", r.fav, "LEFT", -6, 0)
        r.sub = W.Text(r, 10, C.dim)
        r.sub:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 10, 1)
        r.star = W.Text(r, 10, C.dim)
        r.star:SetPoint("LEFT", r.sub, "RIGHT", 6, 0)
        -- header look: a tinted band with a +/- button and the group name
        r.hdrBg = r:CreateTexture(nil, "BACKGROUND", nil, 1)
        r.hdrBg:SetPoint("TOPLEFT", 0, -6)
        r.hdrBg:SetPoint("BOTTOMRIGHT")
        r.hdrBg:SetColorTexture(1, 1, 1, 0.035)
        r.hdrLine = r:CreateTexture(nil, "ARTWORK")
        r.hdrLine:SetHeight(1)
        r.hdrLine:SetPoint("BOTTOMLEFT")
        r.hdrLine:SetPoint("BOTTOMRIGHT")
        r.hdrLine:SetColorTexture(1, 1, 1, 0.06)
        r.hdrIcon = r:CreateTexture(nil, "ARTWORK")
        r.hdrIcon:SetSize(14, 14)
        r.hdrIcon:SetPoint("BOTTOMLEFT", 8, 6)
        r.hdrStar = r:CreateTexture(nil, "ARTWORK")
        r.hdrStar:SetSize(13, 13)
        r.hdrStar:SetPoint("LEFT", r.hdrIcon, "RIGHT", 7, 0)
        r.hdrStar:SetTexture(FAV_TEX)
        r.hdrText = W.Text(r, 11, C.text)
        r.hdrText:SetPoint("LEFT", r.hdrIcon, "RIGHT", 8, 0)
        function r:SetHeader(e)
            local h = e and e.header
            for _, x in ipairs({ self.hdrBg, self.hdrLine, self.hdrIcon, self.hdrText }) do x:SetShown(h) end
            self.hdrStar:SetShown(h and e.label == "Favorites")
            for _, x in ipairs({ self.icon, self.name, self.sub, self.star, self.count, self.dot }) do x:SetShown(not h) end
            if not h then return end
            self.fav:Hide()
            self.stripe:SetColorTexture(1, 1, 1, 0)
            self:SetSelected(false)
            self.hdrIcon:SetTexture(e.folded and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
            self.hdrText:ClearAllPoints()
            self.hdrText:SetPoint("LEFT", e.label == "Favorites" and self.hdrStar or self.hdrIcon, "RIGHT", 7, 0)
            self.hdrText:SetText(e.label:upper() .. "  |cff61636f(" .. e.n .. ")|r")
            self.hdrText:SetTextColor(unpack(e.folded and C.dim or C.text))
        end
        r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        r:SetScript("OnClick", function(self, button)
            if not self.item then return end
            if self.item.header then
                local label = self.item.label
                ns.db.collapsed[label] = not ns.db.collapsed[label] or nil
                UI:Refresh()
                return
            end
            if button == "RightButton" then
                ns:ToggleRecipeHidden(self.item.key)
            else
                st.recipe = self.item.key
            end
            UI:Refresh()
        end)
        r:HookScript("OnEnter", function(self)
            if not self.item then return end
            if self.item.header then
                GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
                GameTooltip:AddLine(self.item.folded and "Click to show these recipes" or "Click to fold this group away", 1, 1, 1)
                GameTooltip:Show()
                return
            end
            self:PaintFav()
            GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
            ns.SetRecipeTooltip(GameTooltip, self.item.key)
            local why = ns:RecipeHidden(self.item.key, true)
            GameTooltip:AddLine(" ")
            if why == "bop" then
                GameTooltip:AddLine("Bind on Pickup: crafters can only make this for themselves. Right-click to always show it.", 1, 0.54, 0.36, true)
            elseif why == "low" then
                GameTooltip:AddLine("Hidden as low level. Right-click to always show it.", 1, 0.73, 0.27)
            elseif why == "manual" then
                GameTooltip:AddLine("Hidden by you. Right-click to show it again.", 1, 0.73, 0.27)
            else
                GameTooltip:AddLine("Right-click to hide this recipe.", 0.55, 0.56, 0.6)
            end
            GameTooltip:Show()
        end)
        r:HookScript("OnLeave", function(self)
            GameTooltip:Hide()
            self:PaintFav()
        end)
        return r
    end, function(r, e, i)
        r:SetHeader(e)
        if e.header then return end
        r:SetStripe(i)
        r.icon.tex:SetTexture(e.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        r.name:SetText(e.name)
        r.sub:SetText(ns.ProfName(e.prof))
        r:PaintFav()
        local tags = {}
        if ns.db.watch[e.key] then tags[#tags + 1] = "|cff" .. ns.AccentHex() .. "watching|r" end
        if e.rare then tags[#tags + 1] = "|cffa178ffrare|r" end
        if e.bop then tags[#tags + 1] = "|cffff8a5cBoP|r" end
        if e.hidden then tags[#tags + 1] = "|cffffba45hidden|r" end
        r.star:SetText(table.concat(tags, "  "))
        r.icon:SetAlpha(e.hidden and 0.45 or 1)
        r.name:SetAlpha(e.hidden and 0.5 or 1)
        local on, others = e.online or 0, e.others or #e.crafters
        r.dot:SetTexture(on > 0 and W.ONLINE_ICON or W.OFFLINE_ICON)
        UI.SetCrafterCount(r.count, on, others, e.mine, "offline")
        r:SetSelected(e.key == st.recipe)
    end)
    results:SetPoint("TOPLEFT", 20, -118)
    results:SetPoint("BOTTOMRIGHT", -(DETAIL_W + 34), 18)

    box.onChange = function(text)
        st.query = text or ""
        results.offset = 0
        UI:Refresh()
    end

    local page = { frame = p }
    function page.refresh()
        LayoutChips()
        local data, nHidden = ns:Search(st.query, st.prof, ns.settings.onlineOnly)
        local shown = #data - (ns.settings.showHidden and nHidden or 0)
        if st.prof == "fav" then
            lblCount:SetText(shown .. (shown == 1 and " favorite" or " favorites"))
        else
            lblCount:SetText(shown .. (shown == 1 and " recipe" or " recipes"))
        end
        if nHidden > 0 then
            hiddenBtn.text:SetText(ns.settings.showHidden and (nHidden .. " hidden shown  ·  hide them")
                or (nHidden .. " hidden  ·  show"))
            hiddenBtn:SetWidth(hiddenBtn.text:GetStringWidth() + 4)
            hiddenBtn:Show()
        else
            hiddenBtn:Hide()
        end
        lowToggle:Refresh()
        local emptyText
        if st.prof == "fav" and st.query == "" and nHidden == 0 and #data == 0 then
            emptyText = "No favorites yet.\n\nHover any recipe and click its star, or press Favorite on a recipe, to add it here."
        elseif #ns:GetIndex() == 0 then
            emptyText = "No recipes shared yet.\n\nOpen your profession windows so your own recipes are captured, and have guildmates or friends install Artisan Network.\n\nType |cffffffff/artisan test|r to preview with sample data."
        else
            emptyText = nHidden > 0 and "Nothing to show. Some matching recipes are hidden; click \"show\" above to see them."
                or "Nothing matches that search."
        end
        results:SetData(Grouped(data), emptyText)
        onlineToggle:Refresh()
        RefreshDetail()
    end
    function page.onShow(recipeKey, query)
        if recipeKey then
            st.recipe = recipeKey
            st.prof = nil
            local e = ns:GetIndex() and ns.byKey[recipeKey]
            box:SetText(e and e.lname ~= "" and e.name or "")
        elseif query then
            box:SetText(query)
        end
    end
    return page
end
