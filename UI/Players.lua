-- Artisan Network: Players page
local ADDON, ns = ...
local W, C = ns.W, ns.W.C
local UI = ns.UI
local DETAIL_W = UI.DETAIL_W
local IsTest, NameText, PresenceText = UI.IsTest, UI.NameText, UI.PresenceText

------------------------------------------------------------------------
-- Players / My Characters page
------------------------------------------------------------------------
function UI.Build.Players(content, mine)
    local st = { query = "", mode = "all", sel = nil, prof = nil }
    local p = CreateFrame("Frame", nil, content)
    p:SetAllPoints()

    local box = W.EditBox(p, 200, 30, mine and "Filter your characters..." or "Filter players by name...")
    box:SetPoint("TOPLEFT", 20, -18)
    box:SetPoint("TOPRIGHT", mine and -20 or -396, -18)

    local seg
    if not mine then
        seg = W.Segmented(p, {
            { value = "all", label = "All" },
            { value = "online", label = "Online" },
            { value = "guild", label = "Guild" },
        }, function() return st.mode end, function(v) st.mode = v; UI:Refresh() end, 88)
        seg:SetPoint("TOPRIGHT", -20, -21)
        local refresh = W.Button(p, "Refresh", 88, 26)
        refresh:SetPoint("TOPRIGHT", -294, -20)
        refresh:SetScript("OnClick", function(self)
            local ok, n = ns:RefreshNetwork()
            if not ok then
                ns.Print("Refreshed recently. Try again in " .. ns:RefreshReadyIn() .. "s.")
                return
            end
            self:SetLabel("Checking...")
            self:Disable()
            C_Timer.After(ns.REFRESH_COOLDOWN, function() self:SetLabel("Refresh"); self:Enable() end)
            if n == 0 then ns.Print("Announced. Everyone you know is already showing online, or nobody's been seen lately.") end
        end)
        W.Tip(refresh, "Refresh", "Announces you and checks who's online among the players you know. Answers come in over the next minute.")
    end

    local lbl = W.Label(p, mine and "Your characters" or "Players")
    lbl:SetPoint("TOPLEFT", 28, -64)
    local lblCount = W.Text(p, 10, C.faint, "RIGHT")
    lblCount:SetPoint("TOPRIGHT", -(DETAIL_W + 36), -64)

    -- detail panel
    local d = W.Panel(p)
    d:SetPoint("TOPRIGHT", -20, -62)
    d:SetPoint("BOTTOMRIGHT", -20, 18)
    d:SetWidth(DETAIL_W)
    d.empty = W.Text(d, 12, C.faint, "CENTER")
    d.empty:SetPoint("CENTER")
    d.empty:SetWidth(DETAIL_W - 40)
    d.empty:SetWordWrap(true)
    d.empty:SetText(mine and "Select a character." or "Select a player to see their professions.")

    local body = CreateFrame("Frame", nil, d)
    body:SetAllPoints()
    body.name = W.Text(body, 16)
    body.name:SetPoint("TOPLEFT", 16, -16)
    body.name:SetWidth(DETAIL_W - 32)
    body.sub = W.Text(body, 11, C.dim)
    body.sub:SetPoint("TOPLEFT", 16, -40)
    body.sub:SetWidth(DETAIL_W - 32)
    body.sub2 = W.Text(body, 10, C.faint)
    body.sub2:SetPoint("TOPLEFT", 16, -56)
    body.sub2:SetWidth(DETAIL_W - 32)

    body.whisper = W.Button(body, "Whisper", 80, 24)
    body.whisper:SetPoint("TOPLEFT", 16, -78)
    body.whisper:SetScript("OnClick", function() if st.sel then ns:Whisper(st.sel) end end)
    body.ping = W.Button(body, "Ping", 70, 24)
    body.ping:SetPoint("LEFT", body.whisper, "RIGHT", 6, 0)
    body.ping:SetScript("OnClick", function() if st.sel then ns:Ping(st.sel, true) end end)
    W.Tip(body.ping, "Ping", "Checks right now whether this player is online and running the addon.")
    body.refresh = W.Button(body, "Re-sync", 80, 24)
    body.refresh:SetPoint("LEFT", body.ping, "RIGHT", 6, 0)
    body.refresh:SetScript("OnClick", function()
        if st.sel then ns:RequestNow(st.sel); ns.Print("Requesting recipes from " .. ns.Short(st.sel) .. "...") end
    end)
    W.Tip(body.refresh, "Re-sync", "Ask this player to send their full recipe list again.")
    body.note = W.Text(body, 11, { 0.86, 0.82, 0.70 })
    body.note:SetPoint("TOPLEFT", 16, -110)
    body.note:SetWidth(DETAIL_W - 32)
    body.note:SetWordWrap(true)
    body.note:SetJustifyH("LEFT")
    body.hint = W.Text(body, 11, C.dim)
    body.hint:SetPoint("TOPLEFT", 16, -82)
    body.hint:SetWidth(DETAIL_W - 32)
    body.hint:SetWordWrap(true)

    local lblProfs = W.Label(body, "Professions")
    lblProfs:SetPoint("TOPLEFT", 16, -120)
    body.lblProfs = lblProfs

    body.profRows = {}
    for i = 1, 6 do
        local r = CreateFrame("Button", nil, body)
        r:SetHeight(34)
        r.idx = i
        r.bg = W.Fill(r, { 1, 1, 1, 0 })
        r.icon = W.Icon(r, 20)
        r.icon:SetPoint("LEFT", 8, 2)
        r.name = W.Text(r, 12)
        r.name:SetPoint("LEFT", r.icon, "RIGHT", 10, 0)
        r.rank = W.Text(r, 11, C.dim, "RIGHT")
        r.rank:SetPoint("RIGHT", -10, 2)
        r.barBg = r:CreateTexture(nil, "ARTWORK")
        r.barBg:SetColorTexture(1, 1, 1, 0.06)
        r.barBg:SetHeight(3)
        r.barBg:SetPoint("BOTTOMLEFT", 8, 3)
        r.barBg:SetPoint("BOTTOMRIGHT", -10, 3)
        r.bar = r:CreateTexture(nil, "OVERLAY")
        r.bar:SetHeight(3)
        r.bar:SetPoint("BOTTOMLEFT", r.barBg, "BOTTOMLEFT")
        r:SetScript("OnClick", function(self) st.prof = self.prof; UI:Refresh() end)
        r:SetScript("OnEnter", function(self) if st.prof ~= self.prof then self.bg:SetColorTexture(1, 1, 1, 0.04) end end)
        r:SetScript("OnLeave", function() UI:Refresh() end)
        body.profRows[i] = r
    end

    body.lblRecipes = W.Label(body, "Recipes")
    body.recipeCount = W.Text(body, 10, C.faint, "RIGHT")
    body.recipeHint = W.Text(body, 11, C.faint)
    body.recipeHint:SetWordWrap(true)
    body.recipeHint:SetWidth(DETAIL_W - 32)

    local recipes = W.List(body, 24, function(list)
        local r = W.RowBase(list)
        r.icon = W.Icon(r, 18)
        r.icon:SetPoint("LEFT", 6, 0)
        r.name = W.Text(r, 11)
        r.name:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
        r.name:SetPoint("RIGHT", -6, 0)
        r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        r:SetScript("OnClick", function(self, button)
            if not self.item then return end
            if button == "RightButton" then ns:ToggleRecipeHidden(self.item.key); UI:Refresh()
            else ns:ShowUI("search", self.item.key) end
        end)
        r:HookScript("OnEnter", function(self)
            if not self.item then return end
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            ns.SetRecipeTooltip(GameTooltip, self.item.key)
            GameTooltip:AddLine("Click to see everyone who can craft this.", 0.5, 0.8, 0.75)
            GameTooltip:Show()
        end)
        r:HookScript("OnLeave", function() GameTooltip:Hide() end)
        return r
    end, function(r, e, i)
        r:SetStripe(i)
        r.icon.tex:SetTexture(e.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        r.name:SetText(e.name .. (e.bop and "  |cffff8a5cBoP|r" or ""))
        r.name:SetAlpha(e.hidden and 0.5 or 1)
        r.icon:SetAlpha(e.hidden and 0.45 or 1)
        r:SetSelected(false)
    end)

    local function RecipeData(rec, profId)
        local out = {}
        local r = rec.recipes and rec.recipes[profId]
        if not r then return out end
        for pass = 1, 2 do
            for _, id in ipairs((pass == 1 and r.s or r.i) or {}) do
                local key = (pass == 1 and "s" or "i") .. id
                local hidden = ns:RecipeHidden(key)
                if hidden then out.hidden = (out.hidden or 0) + 1 end
                if ns.settings.showHidden or not hidden then
                    local name, icon = ns.RecipeInfo(key)
                    out[#out + 1] = { key = key, name = name or "Loading...", icon = icon, hidden = hidden, bop = ns.RecipeBoP(key) }
                end
            end
        end
        table.sort(out, function(a, b) return a.name < b.name end)
        return out
    end

    local function RefreshDetail()
        local name = st.sel
        local rec = name and ns:GetRecord(name)
        if not rec then
            body:Hide()
            d.empty:Show()
            return
        end
        d.empty:Hide()
        body:Show()
        local online = ns:IsOnline(name)
        body.name:SetText(NameText(name, rec))
        local parts = {}
        if rec.level and rec.level > 0 then parts[#parts + 1] = "Level " .. rec.level .. " " .. ns.ClassName(rec.class) end
        parts[#parts + 1] = online and (rec.busy and "|cffffba45Busy|r" or "|cff52de7cOnline|r") or ("Last seen " .. ns.Ago(rec.lastSeen))
        if not ns:IsMine(name) then
            local via = ns.ViaLabel(name, rec)
            if via then parts[#parts + 1] = via end
        end
        body.sub:SetText(table.concat(parts, "  ·  "))

        local state, got, total = ns:TransferState(name)
        if state == "receiving" then
            body.sub2:SetText(string.format("Receiving recipes... %d / %d", got, total))
        elseif state == "requested" then
            body.sub2:SetText("Recipe list requested...")
        elseif rec.scope == "G" and not ns:IsGuildmate(name) then
            body.sub2:SetText("Shares recipes with their guild only")
        elseif rec.scope == "N" then
            body.sub2:SetText("Not sharing recipes")
        elseif rec.updated then
            body.sub2:SetText("Recipes updated " .. ns.Ago(rec.updated) .. (rec.version and ("  ·  v" .. rec.version) or ""))
        else
            body.sub2:SetText(rec.version and ("Artisan Network v" .. rec.version) or "")
        end

        local isMine, test = ns:IsMine(name), IsTest(name)
        body.whisper:SetShown(not isMine)
        body.ping:SetShown(not isMine and not test)
        body.refresh:SetShown(not isMine and not test)
        body.whisper:SetEnabled(online and not rec.busy)
        if isMine then
            body.hint:SetText(name == ns.me and "Open each profession window to capture its recipes. They are shared automatically."
                or "Log in on this character and open its profession windows to update it.")
            body.hint:Show()
        else
            body.hint:Hide()
        end

        -- crafter note: pushes the professions down by its height
        local off = 0
        if not isMine and rec.note and rec.note ~= "" then
            body.note:SetText("\"" .. rec.note .. "\"")
            body.note:Show()
            off = math.ceil(body.note:GetStringHeight() or 12) + 6
        else
            body.note:Hide()
        end
        body.lblProfs:ClearAllPoints()
        body.lblProfs:SetPoint("TOPLEFT", 16, -120 - off)
        for _, row in ipairs(body.profRows) do
            local ry = -134 - off - (row.idx - 1) * 36
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 8, ry)
            row:SetPoint("TOPRIGHT", -8, ry)
        end

        -- professions
        local profs = ns.SortedProfs(rec)
        if not st.prof or not (rec.profs and rec.profs[st.prof]) then
            st.prof = nil
            for _, id in ipairs(profs) do
                if not ns.IsGathering(id) then st.prof = id break end
            end
            st.prof = st.prof or profs[1]
        end
        local r, g, bb = ns.Accent()
        local shown = 0
        for i, row in ipairs(body.profRows) do
            local id = profs[i]
            if id then
                shown = i
                local pr = rec.profs[id]
                row.prof = id
                row.icon.tex:SetTexture(ns.ProfIcon(id))
                local spec = ns.SpecName(pr)
                row.name:SetText(ns.ProfName(id) .. (spec and ("  |cff8a8b94" .. spec .. "|r") or ""))
                row.rank:SetText((pr[1] or 0) > 0 and (pr[1] .. " / " .. pr[2]) or "")
                local frac = (pr[2] and pr[2] > 0) and math.min(1, pr[1] / pr[2]) or 0
                row.bar:SetWidth(math.max(1, (row.barBg:GetWidth() or 200) * frac))
                row.bar:SetColorTexture(r, g, bb, 0.9)
                row.bar:SetShown(frac > 0)
                local sel = st.prof == id
                row.bg:SetColorTexture(r, g, bb, sel and 0.10 or 0)
                row.name:SetTextColor(unpack(sel and C.text or C.dim))
                row:Show()
            else
                row:Hide()
            end
        end
        local y = -134 - off - shown * 36 - 10
        if shown == 0 then
            body.lblRecipes:Hide(); body.recipeCount:Hide(); recipes:Hide()
            body.recipeHint:ClearAllPoints()
            body.recipeHint:SetPoint("TOPLEFT", 16, -136 - off)
            body.recipeHint:SetText(isMine and "No professions found yet." or "No profession data received yet.")
            body.recipeHint:Show()
            return
        end
        body.lblRecipes:ClearAllPoints()
        body.lblRecipes:SetPoint("TOPLEFT", 16, y)
        body.lblRecipes:SetText((st.prof and ns.ProfName(st.prof) or "Recipes"):upper())
        body.lblRecipes:Show()
        body.recipeCount:ClearAllPoints()
        body.recipeCount:SetPoint("TOPRIGHT", -16, y)
        body.recipeCount:Show()
        recipes:ClearAllPoints()
        recipes:SetPoint("TOPLEFT", 8, y - 16)
        recipes:SetPoint("BOTTOMRIGHT", -8, 8)
        recipes:Show()

        local data = st.prof and RecipeData(rec, st.prof) or {}
        local nHidden = data.hidden or 0
        local nShown = #data - (ns.settings.showHidden and nHidden or 0)
        body.recipeCount:SetText((nShown + nHidden) > 0 and (nShown .. " shown" .. (nHidden > 0 and ("  ·  " .. nHidden .. " hidden") or "")) or "")
        local hint
        if #data == 0 then
            if st.prof and ns.IsGathering(st.prof) then
                hint = "Gathering profession, nothing to craft."
            elseif isMine then
                hint = "Open your " .. ns.ProfName(st.prof) .. " window on this character to capture its recipes."
            else
                hint = "No recipe list received for this profession yet."
            end
        end
        recipes:SetData(data, hint)
        body.recipeHint:Hide()
    end

    local list = W.List(p, 40, function(lst)
        local r = W.RowBase(lst)
        r.dot = r:CreateTexture(nil, "ARTWORK")
        r.dot:SetSize(12, 12)
        r.dot:SetPoint("LEFT", 10, 0)
        r.name = W.Text(r, 12)
        r.name:SetPoint("TOPLEFT", 30, -6)
        r.name:SetWidth(170)
        r.sub = W.Text(r, 10, C.dim)
        r.sub:SetPoint("BOTTOMLEFT", 30, 6)
        r.sub:SetWidth(170)
        r.profs = {}
        for i = 1, 3 do
            local ic = W.Icon(r, 18)
            ic:SetPoint("RIGHT", -(12 + (3 - i) * 56 + 26), 0)
            ic.rank = W.Text(r, 10, C.dim)
            ic.rank:SetPoint("LEFT", ic, "RIGHT", 4, 0)
            W.ProfIconTip(ic, r)
            r.profs[i] = ic
        end
        r:SetScript("OnClick", function(self)
            if self.item then st.sel = self.item.name; st.prof = nil; UI:Refresh() end
        end)
        return r
    end, function(r, it, i)
        r:SetStripe(i)
        r.dot:SetTexture(it.online and W.ONLINE_ICON or W.OFFLINE_ICON)
        r.name:SetText(NameText(it.name, it.rec))
        local lvl = it.rec.level and it.rec.level > 0 and (it.rec.level .. " " .. ns.ClassName(it.rec.class) .. "  ·  ") or ""
        local via = ns.ViaLabel(it.name, it.rec, true)
        r.sub:SetText(lvl .. PresenceText(it.name, it.rec) .. (via and ("  ·  " .. via) or ""))
        local profs = ns.SortedProfs(it.rec)
        for k = 1, 3 do
            local ic, id = r.profs[k], profs[k]
            if id then
                ic.tex:SetTexture(ns.ProfIcon(id))
                local pr = it.rec.profs[id]
                ic.rank:SetText((pr[1] or 0) > 0 and pr[1] or "")
                ic.prof = id
                ic.rankText = (pr[1] or 0) > 0 and (pr[1] .. " / " .. pr[2]) or nil
                ic.spec = ns.SpecName(pr)
                ic:Show(); ic.rank:Show()
            else
                ic:Hide(); ic.rank:Hide()
            end
        end
        r:SetSelected(it.name == st.sel)
    end)
    list:SetPoint("TOPLEFT", 20, -80)
    list:SetPoint("BOTTOMRIGHT", -(DETAIL_W + 34), 18)

    box.onChange = function(text)
        st.query = (text or ""):lower()
        list.offset = 0
        UI:Refresh()
    end

    local page = { frame = p }
    function page.refresh()
        local data = {}
        for name, rec in pairs(ns:AllPlayers()) do
            local isMine = ns:IsMine(name)
            if isMine == (mine and true or false) then
                local online = ns:IsOnline(name)
                local ok = st.query == "" or name:lower():find(st.query, 1, true)
                if ok and not mine then
                    if st.mode == "online" and not online then ok = false end
                    if st.mode == "guild" and not ns:IsGuildmate(name) then ok = false end
                end
                if ok then data[#data + 1] = { name = name, rec = rec, online = online } end
            end
        end
        table.sort(data, function(a, b)
            if mine then
                if (a.name == ns.me) ~= (b.name == ns.me) then return a.name == ns.me end
            elseif a.online ~= b.online then
                return a.online
            end
            return a.name < b.name
        end)
        if mine and not st.sel then st.sel = ns.me end
        lblCount:SetText(#data .. (mine and " characters" or " players"))
        list:SetData(data, mine and "" or "Nobody found yet.\n\nPlayers show up here when their Artisan Network says hello in your guild or your group, through a guildmate's introduction, or after /artisan add First Surname.")
        if seg then seg:Refresh() end
        RefreshDetail()
    end
    function page.onShow(name)
        if name then
            st.sel = name
            st.prof = nil
            box:SetText("")
        end
    end
    return page
end
