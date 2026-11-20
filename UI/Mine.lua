-- Artisan Network: My Characters page
local ADDON, ns = ...
local W, C = ns.W, ns.W.C
local UI = ns.UI

------------------------------------------------------------------------
-- My Characters page: character list, account overview, character view
------------------------------------------------------------------------
local AMBER = { 1, 0.73, 0.27 }

local function CooldownText(ready)
    local left = (ready or 0) - time()
    if left <= 0 then return "|cff52de7cReady now|r" end
    local d, h, m = math.floor(left / 86400), math.floor(left % 86400 / 3600), math.floor(left % 3600 / 60)
    if d > 0 then return "Ready in " .. d .. "d " .. h .. "h" end
    if h > 0 then return "Ready in " .. h .. "h " .. m .. "m" end
    return "Ready in " .. math.max(1, m) .. "m"
end

local function CooldownIcon(cd)
    if cd.spell then
        local _, icon = ns.RecipeInfo("s" .. cd.spell)
        return icon
    elseif cd.item then
        return ns.ItemIcon(cd.item)
    end
end

local function RecipeCount(rec, profId)
    local r = rec.recipes and rec.recipes[profId]
    if not r then return nil end
    return #(r.s or {}) + #(r.i or {})
end

local function CharName(name, rec)
    local txt = "|cff" .. ns.ClassHex(rec and rec.class) .. ((rec and rec.display) or ns.Short(name)) .. "|r"
    return txt
end

function UI.Build.Mine(content)
    local st = { sel = "overview", prof = nil, query = "" }
    local p = CreateFrame("Frame", nil, content)
    p:SetAllPoints()
    local MAIN_X, MAIN_W = 228, 488

    -- Left column ----------------------------------------------------------
    local ov = W.RowBase(p)
    ov:SetHeight(38)
    ov:SetPoint("TOPLEFT", 20, -18)
    ov:SetWidth(184)
    local ovIcon = ov:CreateTexture(nil, "ARTWORK")
    ovIcon:SetSize(20, 20)
    ovIcon:SetPoint("LEFT", 10, 0)
    ovIcon:SetTexture(ns.MEDIA .. "Icon")
    local ovName = W.Text(ov, 12)
    ovName:SetPoint("TOPLEFT", 40, -6)
    ovName:SetText("Account overview")
    local ovSub = W.Text(ov, 10, C.dim)
    ovSub:SetPoint("BOTTOMLEFT", 40, 6)
    ov:SetScript("OnClick", function() st.sel = "overview"; UI:Refresh() end)

    local lblChars = W.Label(p, "Characters")
    lblChars:SetPoint("TOPLEFT", 28, -72)

    local chars = W.List(p, 44, function(list)
        local r = W.RowBase(list)
        r.name = W.Text(r, 12)
        r.name:SetPoint("TOPLEFT", 12, -7)
        r.name:SetWidth(104)
        r.sub = W.Text(r, 10, C.dim)
        r.sub:SetPoint("BOTTOMLEFT", 12, 7)
        r.sub:SetWidth(104)
        r.icons = {}
        for k = 1, 2 do
            local ic = W.Icon(r, 16)
            ic:SetPoint("RIGHT", -8 - (2 - k) * 20, 0)
            W.ProfIconTip(ic, r)
            r.icons[k] = ic
        end
        r.warn = W.Text(r, 12, AMBER, "RIGHT")
        r:SetScript("OnClick", function(self)
            if self.item then st.sel = self.item.name; st.prof = nil; UI:Refresh() end
        end)
        r:HookScript("OnEnter", function(self)
            if not (self.item and self.item.unscanned) then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Not scanned yet", 1, 0.73, 0.27)
            GameTooltip:AddLine("Some of this character's professions haven't been scanned. Log in on it and open each profession window once to share its recipes.", 0.8, 0.8, 0.85, true)
            GameTooltip:Show()
        end)
        r:HookScript("OnLeave", function() GameTooltip:Hide() end)
        return r
    end, function(r, it, i)
        r:SetStripe(i)
        r.name:SetText(CharName(it.name, it.rec))
        local parts = {}
        if (it.rec.level or 0) > 0 then parts[1] = it.rec.level .. " " .. ns.ClassName(it.rec.class) end
        if it.name == ns.me then parts[#parts + 1] = "|cff8a8b94you|r" end
        r.sub:SetText(table.concat(parts, " · "))
        -- show up to 2 professions, main ones before Cooking, First Aid and Fishing
        local SECONDARY = { [185] = true, [129] = true, [356] = true }
        local profs = {}
        for _, id in ipairs(ns.SortedProfs(it.rec)) do if not SECONDARY[id] then profs[#profs + 1] = id end end
        for _, id in ipairs(ns.SortedProfs(it.rec)) do if SECONDARY[id] then profs[#profs + 1] = id end end
        local n = math.min(2, #profs)
        r.name:SetWidth(176 - 12 - (8 + n * 20 + (it.unscanned and 14 or 0) + 6))
        for k = 1, 2 do
            local id = profs[k - (2 - n)]
            if k > 2 - n and id then
                local pr = it.rec.profs[id] or {}
                r.icons[k].tex:SetTexture(ns.ProfIcon(id))
                r.icons[k].prof = id
                r.icons[k].rankText = (pr[1] or 0) > 0 and (pr[1] .. " / " .. pr[2]) or nil
                r.icons[k].spec = ns.SpecName(pr)
                r.icons[k]:Show()
            else
                r.icons[k]:Hide()
            end
        end
        r.warn:ClearAllPoints()
        if n > 0 then
            r.warn:SetPoint("RIGHT", r.icons[3 - n], "LEFT", -5, 0)
        else
            r.warn:SetPoint("RIGHT", -10, 0)
        end
        r.warn:SetText(it.unscanned and "!" or "")
        r:SetSelected(st.sel == it.name)
    end)
    chars:SetPoint("TOPLEFT", 20, -86)
    chars:SetPoint("BOTTOMRIGHT", p, "BOTTOMLEFT", 204, 18)

    local sep = W.Line(p, false)
    sep:SetPoint("TOPLEFT", 212, -18)
    sep:SetPoint("BOTTOMLEFT", 212, 18)

    local main = CreateFrame("Frame", nil, p)
    main:SetPoint("TOPLEFT", MAIN_X, -18)
    main:SetPoint("BOTTOMRIGHT", -20, 18)

    -- Account overview -----------------------------------------------------
    local ovf = CreateFrame("Frame", nil, main)
    ovf:SetAllPoints()
    local ovTitle = W.Text(ovf, 16)
    ovTitle:SetPoint("TOPLEFT", 0, 0)
    ovTitle:SetText("Account overview")
    local ovStats = W.Text(ovf, 11, C.dim)
    ovStats:SetPoint("TOPLEFT", 0, -24)

    local COLS = { prof = 36, char = 148, skill = 260, recipes = 350, scanned = 402 }
    local function Head(text, x, w, justify)
        local t = W.Label(ovf, text)
        t:SetPoint("TOPLEFT", x, -56)
        if w then t:SetWidth(w); t:SetJustifyH(justify or "LEFT") end
    end
    Head("Profession", COLS.prof)
    Head("Character", COLS.char)
    Head("Skill", COLS.skill)
    Head("Recipes", COLS.recipes, 50, "RIGHT")
    Head("Scanned", COLS.scanned, 76, "RIGHT")
    local hl = W.Line(ovf, true)
    hl:SetPoint("TOPLEFT", 0, -72)
    hl:SetPoint("TOPRIGHT", 0, -72)

    local table_ = W.List(ovf, 30, function(list)
        local r = W.RowBase(list)
        r.icon = W.Icon(r, 18)
        r.icon:SetPoint("LEFT", 8, 0)
        r.prof = W.Text(r, 12)
        r.prof:SetPoint("LEFT", COLS.prof, 0)
        r.prof:SetWidth(108)
        r.char = W.Text(r, 12)
        r.char:SetPoint("LEFT", COLS.char, 0)
        r.char:SetWidth(108)
        r.skill = W.Text(r, 10, C.dim)
        r.skill:SetPoint("TOPLEFT", COLS.skill, -4)
        r.barBg = r:CreateTexture(nil, "ARTWORK")
        r.barBg:SetColorTexture(1, 1, 1, 0.06)
        r.barBg:SetSize(70, 3)
        r.barBg:SetPoint("BOTTOMLEFT", COLS.skill, 6)
        r.bar = r:CreateTexture(nil, "OVERLAY")
        r.bar:SetHeight(3)
        r.bar:SetPoint("LEFT", r.barBg, "LEFT")
        r.recipes = W.Text(r, 11, C.text, "RIGHT")
        r.recipes:SetPoint("LEFT", COLS.recipes, 0)
        r.recipes:SetWidth(50)
        r.scanned = W.Text(r, 10, C.dim, "RIGHT")
        r.scanned:SetPoint("LEFT", COLS.scanned, 0)
        r.scanned:SetWidth(70)
        r:SetScript("OnClick", function(self)
            if self.item then st.sel = self.item.name; st.prof = self.item.prof; UI:Refresh() end
        end)
        return r
    end, function(r, it, i)
        r:SetStripe(i)
        r.icon.tex:SetTexture(ns.ProfIcon(it.prof))
        r.prof:SetText(ns.ProfName(it.prof))
        r.char:SetText(CharName(it.name, it.rec))
        local pr = it.rec.profs[it.prof]
        r.skill:SetText((pr[1] or 0) > 0 and (pr[1] .. " / " .. pr[2]) or "")
        local frac = (pr[2] and pr[2] > 0) and math.min(1, pr[1] / pr[2]) or 0
        local cr, cg, cb = ns.Accent()
        r.bar:SetColorTexture(cr, cg, cb, 0.9)
        r.bar:SetWidth(math.max(1, 70 * frac))
        r.bar:SetShown(frac > 0)
        if it.count then
            r.recipes:SetText(it.count)
            r.scanned:SetText(it.scanned and ns.Ago(it.scanned) or "")
            r.scanned:SetTextColor(unpack(C.dim))
        else
            r.recipes:SetText("|cff616370–|r")
            r.scanned:SetText("not scanned")
            r.scanned:SetTextColor(unpack(AMBER))
        end
        r:SetSelected(false)
    end)
    table_:SetPoint("TOPLEFT", 0, -76)
    table_:SetPoint("TOPRIGHT", 0, -76)
    table_:SetHeight(210)

    local lblCd = W.Label(ovf, "Cooldowns")
    lblCd:SetPoint("TOPLEFT", 0, -302)
    local cl = W.Line(ovf, true)
    cl:SetPoint("TOPLEFT", 0, -318)
    cl:SetPoint("TOPRIGHT", 0, -318)

    local function CdRow(list)
        local r = W.RowBase(list)
        r.icon = W.Icon(r, 18)
        r.icon:SetPoint("LEFT", 8, 0)
        r.name = W.Text(r, 12)
        r.name:SetPoint("LEFT", COLS.prof, 0)
        r.name:SetWidth(108)
        r.char = W.Text(r, 12)
        r.char:SetPoint("LEFT", COLS.char, 0)
        r.char:SetWidth(150)
        r.state = W.Text(r, 11, C.dim, "RIGHT")
        r.state:SetPoint("RIGHT", -12, 0)
        return r
    end
    local function CdUpdate(r, it, i, showChar)
        r:SetStripe(i)
        r.icon.tex:SetTexture(CooldownIcon(it.cd) or ns.ProfIcon(it.cd.prof))
        r.name:SetText(it.cd.name)
        r.char:SetText(showChar and CharName(it.name, it.rec) or ("|cff949ba3" .. ns.ProfName(it.cd.prof) .. "|r"))
        r.state:SetText(CooldownText(it.cd.ready))
        r:SetSelected(false)
    end
    local cdList = W.List(ovf, 30, CdRow, function(r, it, i) CdUpdate(r, it, i, true) end)
    cdList:SetPoint("TOPLEFT", 0, -322)
    cdList:SetPoint("TOPRIGHT", 0, -322)
    cdList:SetHeight(90)
    cdList.empty:ClearAllPoints()
    cdList.empty:SetPoint("TOPLEFT", 8, -10)
    cdList.empty:SetPoint("TOPRIGHT", -8, -10)
    cdList.empty:SetJustifyH("LEFT")

    local warn = W.Panel(ovf)
    warn:SetPoint("TOPLEFT", 0, -426)
    warn:SetPoint("TOPRIGHT", 0, -426)
    warn:SetHeight(44)
    W.SetBorderColor(warn, 1, 0.73, 0.27, 0.35)
    W.Fill(warn, { 1, 0.73, 0.27, 0.06 }, "BACKGROUND", 1)
    local warnMark = W.Text(warn, 13, AMBER)
    warnMark:SetPoint("LEFT", 14, 0)
    warnMark:SetText("!")
    warn.text = W.Text(warn, 11)
    warn.text:SetPoint("LEFT", 32, 0)
    warn.text:SetWidth(MAIN_W - 48)
    warn.text:SetWordWrap(true)

    -- Character view ---------------------------------------------------------
    local cf = CreateFrame("Frame", nil, main)
    cf:SetAllPoints()
    cf.name = W.Text(cf, 16)
    cf.name:SetPoint("TOPLEFT", 0, 0)
    cf.name:SetWidth(300)
    cf.sub = W.Text(cf, 11, C.dim)
    cf.sub:SetPoint("TOPLEFT", 0, -24)
    cf.sub:SetWidth(300)

    local share = W.Toggle(cf, "Share this character",
        function()
            local rec = st.sel and ns:GetRecord(st.sel)
            return not (rec and rec.share == false)
        end,
        function(v)
            local rec = st.sel and ns:GetRecord(st.sel)
            if not rec then return end
            if v then rec.share = nil else rec.share = false end
            if st.sel == ns.me then ns:BroadcastHello(false) end
            UI:Refresh()
        end)
    share:SetWidth(160)
    share:SetPoint("TOPRIGHT", 0, -4)
    W.Tip(share, "Share this character",
        "When off, this character's recipes are hidden from other players. For an alt, the change applies the next time you log in on it.")

    local remove = W.Button(cf, "Remove", 70, 22)
    remove:SetPoint("TOPRIGHT", 0, -30)
    remove:SetScript("OnClick", function(self)
        if not self.armed then
            self.armed = true
            self:SetLabel("Sure?")
            C_Timer.After(3, function() self.armed = nil; self:SetLabel("Remove") end)
            return
        end
        self.armed = nil
        self:SetLabel("Remove")
        if st.sel and st.sel ~= ns.me and ns.db.chars[st.sel] then
            ns.db.chars[st.sel] = nil
            st.sel = "overview"
            ns:MarkIndexDirty()
            ns:Fire("PLAYERS")
        end
    end)
    W.Tip(remove, "Remove character", "Forget this character, for example one you deleted or transferred. It comes back if you log in on it again.")

    local lblProfs = W.Label(cf, "Professions")
    lblProfs:SetPoint("TOPLEFT", 0, -56)

    local cards = {}
    for k = 1, 6 do
        local c = CreateFrame("Button", nil, cf)
        c:SetHeight(58)
        c.bg = W.Fill(c, C.panel)
        W.Border(c)
        c.icon = W.Icon(c, 24)
        c.icon:SetPoint("TOPLEFT", 10, -10)
        c.name = W.Text(c, 12)
        c.name:SetPoint("TOPLEFT", 42, -11)
        c.rank = W.Text(c, 11, C.dim, "RIGHT")
        c.rank:SetPoint("TOPRIGHT", -10, -12)
        c.barBg = c:CreateTexture(nil, "ARTWORK")
        c.barBg:SetColorTexture(1, 1, 1, 0.06)
        c.barBg:SetHeight(3)
        c.barBg:SetPoint("TOPLEFT", 42, -30)
        c.barBg:SetPoint("TOPRIGHT", -10, -30)
        c.bar = c:CreateTexture(nil, "OVERLAY")
        c.bar:SetHeight(3)
        c.bar:SetPoint("LEFT", c.barBg, "LEFT")
        c.line = W.Text(c, 10, C.dim)
        c.line:SetPoint("TOPLEFT", 42, -40)
        c:SetScript("OnClick", function(self)
            if self.prof and not ns.IsGathering(self.prof) then st.prof = self.prof; UI:Refresh() end
        end)
        c:SetScript("OnEnter", function(self)
            if self.prof ~= st.prof and not ns.IsGathering(self.prof) then self.bg:SetColorTexture(1, 1, 1, 0.05) end
            if not self.prof then return end
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:AddLine(ns.ProfName(self.prof), 1, 1, 1)
            if self.rankText ~= "" then GameTooltip:AddLine("Skill " .. self.rankText, 0.8, 0.8, 0.85) end
            if self.spec then GameTooltip:AddLine(self.spec, 0.79, 0.73, 0.54) end
            GameTooltip:AddLine(self.tip, self.tipWarn and 1 or 0.8, self.tipWarn and 0.73 or 0.8, self.tipWarn and 0.27 or 0.85, true)
            GameTooltip:Show()
        end)
        c:SetScript("OnLeave", function() GameTooltip:Hide(); UI:Refresh() end)
        cards[k] = c
    end

    local lblCdc = W.Label(cf, "Cooldowns")
    local cdPanel = W.Panel(cf)
    local cdRows = {}
    for k = 1, 4 do
        local r = CdRow(cdPanel)
        r:SetHeight(30)
        r:SetPoint("TOPLEFT", 0, -(k - 1) * 30)
        r:SetPoint("TOPRIGHT", 0, -(k - 1) * 30)
        cdRows[k] = r
    end

    local lblRecipes = W.Label(cf, "Recipes")
    lblRecipes:Hide()
    st.mode = "known"
    local modeSeg = W.Segmented(cf, {
        { value = "known", label = "Known" },
        { value = "learn", label = "Could learn",
          tip = "Recipes for this profession that other players know and this character doesn't. Click one to see who knows it." },
    }, function() return st.mode end, function(v) st.mode = v; UI:Refresh() end, 110)
    local recCount = W.Text(cf, 10, C.faint)
    local box = W.EditBox(cf, 200, 26, "Search recipes...")
    box:SetFont(STANDARD_TEXT_FONT, 11, "")
    box.onChange = function(text) st.query = (text or ""):lower(); UI:Refresh() end

    local function Cell(row)
        local c = CreateFrame("Button", nil, row)
        c.hl = c:CreateTexture(nil, "BACKGROUND", nil, 1)
        c.hl:SetAllPoints()
        c.hl:SetColorTexture(1, 1, 1, 0.05)
        c.hl:Hide()
        c.icon = W.Icon(c, 18)
        c.icon:SetPoint("LEFT", 6, 0)
        c.name = W.Text(c, 11)
        c.name:SetPoint("LEFT", c.icon, "RIGHT", 8, 0)
        c.name:SetPoint("RIGHT", -4, 0)
        c:SetScript("OnEnter", function(self)
            if not self.key then return end
            self.hl:Show()
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            ns.SetRecipeTooltip(GameTooltip, self.key)
            if self.knownBy then
                GameTooltip:AddLine("Known by " .. self.knownBy .. (self.knownBy == 1 and " player" or " players"), 1, 1, 1)
            end
            GameTooltip:AddLine("Click to see everyone who can craft this.", 0.5, 0.8, 0.75)
            GameTooltip:AddLine(ns:RecipeHidden(self.key) and "Right-click to show it again." or "Right-click to hide this recipe.", 0.55, 0.56, 0.6)
            GameTooltip:Show()
        end)
        c:SetScript("OnLeave", function(self) self.hl:Hide(); GameTooltip:Hide() end)
        c:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        c:SetScript("OnClick", function(self, button)
            if not self.key then return end
            if button == "RightButton" then ns:ToggleRecipeHidden(self.key); UI:Refresh()
            else ns:ShowUI("search", self.key) end
        end)
        return c
    end
    local grid = W.List(cf, 26, function(list)
        local r = W.RowBase(list)
        r:EnableMouse(false)
        r.a = Cell(r)
        r.a:SetPoint("TOPLEFT")
        r.a:SetPoint("BOTTOMRIGHT", r, "BOTTOM", -4, 0)
        r.b = Cell(r)
        r.b:SetPoint("TOPLEFT", r, "TOP", 4, 0)
        r.b:SetPoint("BOTTOMRIGHT")
        return r
    end, function(r, pair, i)
        r:SetStripe(i)
        for k, cell in ipairs({ r.a, r.b }) do
            local e = pair[k]
            if e then
                cell.key = e.key
                cell.knownBy = e.knownBy
                cell.icon.tex:SetTexture(e.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                cell.name:SetText(e.name .. (e.bop and "  |cffff8a5cBoP|r" or "") .. (e.rare and "  |cffa178ffrare|r" or "") .. (e.learn or ""))
                cell.name:SetAlpha(e.hidden and 0.5 or 1)
                cell.icon:SetAlpha(e.hidden and 0.45 or 1)
                cell:Show()
            else
                cell.key = nil
                cell:Hide()
            end
        end
        r:SetSelected(false)
    end)

    local function RecipeEntries(rec, profId)
        local out = {}
        local r = rec.recipes and rec.recipes[profId]
        if not r then return out end
        for pass = 1, 2 do
            for _, id in ipairs((pass == 1 and r.s or r.i) or {}) do
                local key = (pass == 1 and "s" or "i") .. id
                local name, icon = ns.RecipeInfo(key)
                name = name or "Loading..."
                if st.query == "" or name:lower():find(st.query, 1, true) then
                    local hidden = ns:RecipeHidden(key)
                    if hidden then out.hidden = (out.hidden or 0) + 1 end
                    if ns.settings.showHidden or not hidden then
                        local ie = ns.byKey and ns.byKey[key]
                        out[#out + 1] = { key = key, name = name, icon = icon, hidden = hidden, rare = ie and ie.rare,
                                          bop = ns.RecipeBoP(key) }
                    end
                end
            end
        end
        table.sort(out, function(a, b) return a.name < b.name end)
        return out
    end

    local function LearnEntries(rec, profId)
        local out = {}
        local mine = rec.recipes and rec.recipes[profId] or {}
        local known = {}
        for _, id in ipairs(mine.s or {}) do known["s" .. id] = true end
        for _, id in ipairs(mine.i or {}) do known["i" .. id] = true end
        for _, e in ipairs(ns:GetIndex()) do
            if e.prof == profId and not known[e.key] then
                local onlyMine = true
                for _, c in ipairs(e.crafters) do
                    if not ns:IsMine(c) then onlyMine = false break end
                end
                if not onlyMine and (st.query == "" or e.lname:find(st.query, 1, true)) then
                    local hidden = ns:RecipeHidden(e.key)
                    if hidden then out.hidden = (out.hidden or 0) + 1 end
                    if ns.settings.showHidden or not hidden then
                        local n = #e.crafters
                        out[#out + 1] = { key = e.key, name = e.name, icon = e.icon, hidden = hidden, rare = e.rare,
                                          learn = "  |cff8a8b94(" .. n .. ")|r", knownBy = n }
                    end
                end
            end
        end
        table.sort(out, function(a, b) return a.name < b.name end)
        return out
    end

    -- Refresh ------------------------------------------------------------
    local function Collect()
        local list, rows, cds, unscanned = {}, {}, {}, {}
        local nProfs, nRecipes = 0, 0
        for name, rec in pairs(ns:MyChars()) do
            local item = { name = name, rec = rec }
            for id in pairs(rec.profs or {}) do
                if not ns.IsGathering(id) then
                    local count = RecipeCount(rec, id)
                    local r = rec.recipes and rec.recipes[id]
                    rows[#rows + 1] = { name = name, rec = rec, prof = id, count = count, scanned = r and r.t }
                    nProfs = nProfs + 1
                    nRecipes = nRecipes + (count or 0)
                    if not count then
                        item.unscanned = true
                        unscanned[#unscanned + 1] = { name = name, rec = rec, prof = id }
                    end
                end
            end
            for _, cd in pairs(rec.cooldowns or {}) do
                cds[#cds + 1] = { name = name, rec = rec, cd = cd }
            end
            list[#list + 1] = item
        end
        table.sort(list, function(a, b)
            if (a.name == ns.me) ~= (b.name == ns.me) then return a.name == ns.me end
            if (a.rec.level or 0) ~= (b.rec.level or 0) then return (a.rec.level or 0) > (b.rec.level or 0) end
            return a.name < b.name
        end)
        local order = {}
        for i, id in ipairs(ns.PROF_ORDER) do order[id] = i end
        table.sort(rows, function(a, b)
            if a.prof ~= b.prof then return (order[a.prof] or 99) < (order[b.prof] or 99) end
            return (a.rec.profs[a.prof][1] or 0) > (b.rec.profs[b.prof][1] or 0)
        end)
        table.sort(cds, function(a, b)
            local ra, rb = (a.cd.ready or 0) <= time(), (b.cd.ready or 0) <= time()
            if ra ~= rb then return ra end
            if (a.cd.ready or 0) ~= (b.cd.ready or 0) then return (a.cd.ready or 0) < (b.cd.ready or 0) end
            return a.name < b.name
        end)
        return list, rows, cds, unscanned, nProfs, nRecipes
    end

    local function RefreshOverview(list, rows, cds, unscanned, nProfs, nRecipes)
        ovStats:SetText(string.format("%d %s  ·  %d crafting %s  ·  %d recipes",
            #list, #list == 1 and "character" or "characters",
            nProfs, nProfs == 1 and "profession" or "professions", nRecipes))
        table_:SetData(rows, "No professions found yet. Log in on each character so the addon can read its skills.")
        cdList:SetData(cds, "No crafting cooldowns found yet. They appear once you open a profession that has one, such as Transmutes or Mooncloth.")
        if #unscanned > 0 then
            local u = unscanned[1]
            local who = (u.rec.display or ns.Short(u.name))
            local txt = who .. "'s |cffffffff" .. ns.ProfName(u.prof) .. "|r hasn't been scanned. Log in on "
                .. ns.Short(u.name) .. " and open the " .. ns.ProfName(u.prof) .. " window to share it."
            if #unscanned > 1 then txt = txt .. "  |cff949ba3(" .. (#unscanned - 1) .. " more)|r" end
            warn.text:SetText(txt)
            warn:Show()
        else
            warn:Hide()
        end
    end

    local function RefreshCharacter()
        local name = st.sel
        local rec = ns:GetRecord(name)
        local isMe = name == ns.me
        local tag = isMe and " |cff8a8b94(you)|r" or (ns.testChars and ns.testChars[name] and " |cff8a8b94(test)|r" or " |cff8a8b94(alt)|r")
        cf.name:SetText(CharName(name, rec) .. tag)
        local parts = {}
        if (rec.level or 0) > 0 then parts[1] = "Level " .. rec.level .. " " .. ns.ClassName(rec.class) end
        parts[#parts + 1] = isMe and (rec.busy and "|cff52de7conline now|r  ·  |cffffba45busy|r" or "|cff52de7conline now|r")
            or ("last online " .. ns.Ago(rec.lastSeen))
        cf.sub:SetText(table.concat(parts, "  ·  "))
        share:Refresh()
        remove:SetShown(not isMe and ns.db.chars[name] ~= nil)

        -- profession cards
        local profs = ns.SortedProfs(rec)
        rec.profs = rec.profs or {}
        if not st.prof or not rec.profs[st.prof] or ns.IsGathering(st.prof) then
            st.prof = nil
            for _, id in ipairs(profs) do
                if not ns.IsGathering(id) then st.prof = id break end
            end
        end
        local n = math.min(6, #profs)
        local perRow = n >= 3 and 3 or 2
        local cw = math.floor((MAIN_W - (perRow - 1) * 10) / perRow)
        local cr, cg, cb = ns.Accent()
        for k, c in ipairs(cards) do
            local id = profs[k]
            if id and k <= 6 then
                local pr = rec.profs[id]
                local row, col = math.floor((k - 1) / perRow), (k - 1) % perRow
                c:ClearAllPoints()
                c:SetPoint("TOPLEFT", col * (cw + 10), -74 - row * 68)
                c:SetWidth(cw)
                c.prof = id
                c.icon.tex:SetTexture(ns.ProfIcon(id))
                c.spec = ns.SpecName(pr)
                c.name:SetText(ns.ProfName(id))
                -- wide cards show the skill top right; narrow ones (3 per row) put it on the bottom line
                local wide = cw >= 200
                local rankText = (pr[1] or 0) > 0 and (pr[1] .. "/" .. pr[2]) or ""
                c.rankText = rankText
                c.rank:SetText(wide and rankText or "")
                c.name:SetWidth(wide and (cw - 42 - 70) or (cw - 52))
                c.line:SetWidth(cw - 52)
                local pre = (not wide and rankText ~= "") and (rankText .. "  ·  ") or ""
                local frac = (pr[2] and pr[2] > 0) and math.min(1, pr[1] / pr[2]) or 0
                c.bar:SetColorTexture(cr, cg, cb, 0.9)
                c.bar:SetWidth(math.max(1, (cw - 52) * frac))
                c.bar:SetShown(frac > 0)
                local count = RecipeCount(rec, id)
                if ns.IsGathering(id) then
                    c.line:SetText(pre .. "gathering")
                    c.line:SetTextColor(unpack(C.dim))
                    c.tip, c.tipWarn = "Gathering profession: nothing to craft.", false
                elseif count then
                    local r = rec.recipes[id]
                    c.line:SetText(pre .. count .. " recipes" .. ((wide and r.t) and ("  ·  scanned " .. ns.Ago(r.t)) or ""))
                    c.line:SetTextColor(unpack(C.dim))
                    c.tip = count .. " recipes" .. (r.t and (", scanned " .. ns.Ago(r.t)) or "") .. ". Click to list them."
                    c.tipWarn = false
                else
                    c.line:SetText(pre .. (wide and "Not scanned: open this profession" or "not scanned"))
                    c.line:SetTextColor(unpack(AMBER))
                    c.tip = "Not scanned yet. Open the " .. ns.ProfName(id) .. " window on this character once to capture and share its recipes."
                    c.tipWarn = true
                end
                local sel = st.prof == id
                c.bg:SetColorTexture(sel and cr or C.panel[1], sel and cg or C.panel[2], sel and cb or C.panel[3], sel and 0.10 or 1)
                if sel then W.SetBorderColor(c, cr, cg, cb, 0.8) else W.SetBorderColor(c, unpack(C.border)) end
                c:Show()
            else
                c.prof = nil
                c:Hide()
            end
        end
        local y = -74 - math.max(1, math.ceil(n / perRow)) * 68 - 6
        if n == 0 then
            cards[1]:Hide()
            y = -80
        end

        -- cooldowns
        local cdl = {}
        for _, cd in pairs(rec.cooldowns or {}) do cdl[#cdl + 1] = { name = name, rec = rec, cd = cd } end
        table.sort(cdl, function(a, b) return (a.cd.ready or 0) < (b.cd.ready or 0) end)
        if #cdl > 0 then
            lblCdc:ClearAllPoints()
            lblCdc:SetPoint("TOPLEFT", 0, y)
            lblCdc:Show()
            local shown = math.min(4, #cdl)
            cdPanel:ClearAllPoints()
            cdPanel:SetPoint("TOPLEFT", 0, y - 16)
            cdPanel:SetPoint("TOPRIGHT", 0, y - 16)
            cdPanel:SetHeight(shown * 30)
            cdPanel:Show()
            for k, r in ipairs(cdRows) do
                if cdl[k] and k <= shown then
                    CdUpdate(r, cdl[k], 1, false)
                    r:Show()
                else
                    r:Hide()
                end
            end
            y = y - 16 - shown * 30 - 16
        else
            lblCdc:Hide()
            cdPanel:Hide()
        end

        -- recipes
        modeSeg:ClearAllPoints()
        modeSeg:SetPoint("TOPLEFT", 0, y + 1)
        recCount:ClearAllPoints()
        recCount:SetPoint("LEFT", modeSeg, "RIGHT", 10, 0)
        box:ClearAllPoints()
        box:SetPoint("TOPRIGHT", 0, y + 2)
        grid:ClearAllPoints()
        grid:SetPoint("TOPLEFT", 0, y - 30)
        grid:SetPoint("BOTTOMRIGHT")
        local who = ns.Short(name)
        box.ph:SetText("Search recipes...")

        local total = st.prof and RecipeCount(rec, st.prof)
        local learnable = (st.prof and total) and LearnEntries(rec, st.prof) or {}
        modeSeg.buttons[1].text:SetText("Known" .. (total and (" (" .. total .. ")") or ""))
        modeSeg.buttons[2].text:SetText("Could learn" .. ((st.prof and total) and (" (" .. #learnable .. ")") or ""))
        modeSeg:Refresh()
        local entries = st.mode == "learn" and learnable or (st.prof and RecipeEntries(rec, st.prof) or {})
        local nHidden = entries.hidden or 0
        recCount:SetText(nHidden > 0 and (nHidden .. " hidden") or "")
        local pairs_ = {}
        for k = 1, #entries, 2 do pairs_[#pairs_ + 1] = { entries[k], entries[k + 1] } end
        local hint
        if not st.prof then
            hint = "No crafting professions on this character."
        elseif not total then
            hint = isMe and ("Open your " .. ns.ProfName(st.prof) .. " window to capture its recipes.")
                or ("Log in on " .. who .. " and open the " .. ns.ProfName(st.prof) .. " window to capture its recipes.")
        elseif #entries == 0 then
            if st.mode == "learn" then
                hint = st.query ~= "" and "No recipes match that search."
                    or ("Nobody you've seen knows a " .. ns.ProfName(st.prof) .. " recipe that " .. who .. " doesn't.")
            else
                hint = "No recipes match that search."
            end
        end
        grid:SetData(pairs_, hint)
    end

    local page = { frame = p }
    function page.refresh()
        local list, rows, cds, unscanned, nProfs, nRecipes = Collect()
        ovSub:SetText(#list .. (#list == 1 and " character" or " characters"))
        ov:SetSelected(st.sel == "overview")
        chars:SetData(list)
        if st.sel ~= "overview" and not ns:GetRecord(st.sel) then st.sel = "overview" end
        if st.sel == "overview" then
            cf:Hide()
            ovf:Show()
            RefreshOverview(list, rows, cds, unscanned, nProfs, nRecipes)
        else
            ovf:Hide()
            cf:Show()
            RefreshCharacter()
        end
    end
    function page.onShow(name, prof)
        if name then
            st.sel = name
            st.prof = prof
            st.query = ""
            box:SetText("")
        end
    end
    return page
end
