-- Artisan Network: Settings page
local ADDON, ns = ...
local W, C = ns.W, ns.W.C
local UI = ns.UI

------------------------------------------------------------------------
-- Settings page
------------------------------------------------------------------------
function UI.Build.Settings(content)
    local p = CreateFrame("Frame", nil, content)
    p:SetAllPoints()
    local controls = {}
    local function Track(c) controls[#controls + 1] = c; return c end

    local LX, RX = 28, 380
    local ly, ry = -24, -24
    local function Section(x, y, text)
        local t = W.Label(p, text)
        t:SetPoint("TOPLEFT", x, y)
        local line = W.Line(p, true)
        line:SetPoint("TOPLEFT", x, y - 14)
        line:SetWidth(310)
    end
    local function Desc(x, y, text)
        local t = W.Text(p, 11, C.dim)
        t:SetPoint("TOPLEFT", x, y)
        t:SetWidth(310)
        t:SetWordWrap(true)
        t:SetJustifyV("TOP")
        t:SetText(text)
        return t
    end

    -- Left column ---------------------------------------------------------
    Section(LX, ly, "Sharing"); ly = ly - 26
    local scope = Track(W.Segmented(p, {
        { value = "ALL", label = "Everyone" },
        { value = "GUILD", label = "Guild only" },
        { value = "NONE", label = "Nobody" },
    }, function() return ns.settings.shareScope end, function(v)
        ns.settings.shareScope = v
        ns:BroadcastHello(false)
    end, 100))
    scope:SetPoint("TOPLEFT", LX, ly); ly = ly - 32
    Desc(LX, ly, "Who can see your recipes. Your online status is still shared so people know you're around."); ly = ly - 40

    local noteLbl = W.Text(p, 12)
    noteLbl:SetPoint("TOPLEFT", LX, ly - 7)
    noteLbl:SetText("Crafter note")
    local noteBox = W.EditBox(p, 220, 26, "Free with your mats, tips welcome")
    noteBox.icon:Hide()
    noteBox:SetTextInsets(8, 8, 0, 0)
    noteBox.ph:ClearAllPoints()
    noteBox.ph:SetPoint("LEFT", 8, 0)
    noteBox:SetMaxLetters(ns.NOTE_MAX)
    noteBox:SetPoint("TOPLEFT", LX + 90, ly)
    noteBox:SetText(ns.settings.note or "")
    local function SaveNote(box)
        local v = ns.CleanText(box:GetText())
        if v ~= (ns.settings.note or "") then
            ns.settings.note = v
            -- let everyone online see it soon, without a hello per keystroke
            ns:Debounce("noteHello", 3, function() ns:BroadcastHello(false) end)
        end
        if box:GetText() ~= v then box:SetText(v) end
    end
    noteBox:HookScript("OnEditFocusLost", SaveNote)
    noteBox:HookScript("OnShow", function(box) if not box:HasFocus() then box:SetText(ns.settings.note or "") end end)
    W.Tip(noteBox, "Crafter note", "A short line other players see on your profile and when they hover you in a crafter list, like when you're around or what you charge. Sent with your recipes, so \"Nobody\" sharing hides it too.")
    ly = ly - 32
    Desc(LX, ly, "Shown on your profile and in crafter lists."); ly = ly - 26

    Section(LX, ly, "Network"); ly = ly - 26
    local outside = W.Toggle(p, "Find addon users outside my guild",
        function() return ns.settings.outside end,
        function(v)
            ns.settings.outside = v
            if v then ns:BroadcastHello(true) end
            UI:Refresh()
        end)
    Track(outside):SetPoint("TOPLEFT", LX, ly); ly = ly - 26
    Desc(LX, ly, "Meets addon users in your party or raid, through your guildmates' contacts, and with /artisan add. Turn off to stay guild-only.")
    ly = ly - 58

    Section(LX, ly, "Alerts & tooltips"); ly = ly - 26
    Track(W.Toggle(p, "Show crafters on item tooltips",
        function() return ns.settings.tooltip end,
        function(v) ns.settings.tooltip = v end)):SetPoint("TOPLEFT", LX, ly); ly = ly - 28
    Track(W.Toggle(p, "Pop-up when a watched crafter comes online",
        function() return ns.settings.alerts end,
        function(v) ns.settings.alerts = v end)):SetPoint("TOPLEFT", LX, ly); ly = ly - 28
    Track(W.Toggle(p, "Play a sound with pop-ups",
        function() return ns.settings.alertSound end,
        function(v) ns.settings.alertSound = v end)):SetPoint("TOPLEFT", LX, ly); ly = ly - 28
    Track(W.Toggle(p, "Receive crafting requests",
        function() return ns.settings.requests end,
        function(v) ns.settings.requests = v end)):SetPoint("TOPLEFT", LX, ly); ly = ly - 28
    Track(W.Toggle(p, "Minimap button",
        function() return not ns.settings.minimap.hide end,
        function(v) ns.settings.minimap.hide = not v; ns:UpdateMinimap() end)):SetPoint("TOPLEFT", LX, ly); ly = ly - 28

    -- Right column --------------------------------------------------------
    Section(RX, ry, "Appearance"); ry = ry - 26
    local swatchLbl = W.Text(p, 12)
    swatchLbl:SetPoint("TOPLEFT", RX, ry - 4)
    swatchLbl:SetText("Accent")
    local swatches = {}
    for i, a in ipairs(ns.ACCENTS) do
        local s = CreateFrame("Button", nil, p)
        s:SetSize(22, 22)
        s:SetPoint("TOPLEFT", RX + 70 + (i - 1) * 28, ry)
        W.Fill(s, { a.c[1], a.c[2], a.c[3], 1 }, "BACKGROUND", 3)
        W.Border(s)
        s.key = a.key
        s:SetScript("OnClick", function()
            ns.settings.accent = a.key
            W.RefreshAccent()
            UI:UpdateNav()
            UI:Refresh()
        end)
        swatches[#swatches + 1] = s
    end
    if W.forever then
        -- Forever always uses gold; the accent applies to the Artisan style
        for _, sw in ipairs(swatches) do
            sw:SetAlpha(0.35)
            W.Tip(sw, "Accent", "Used by the Artisan style. Forever always uses gold.")
        end
    end
    ry = ry - 34
    local scaleLbl = W.Text(p, 12)
    scaleLbl:SetPoint("TOPLEFT", RX, ry - 6)
    scaleLbl:SetText("Scale")
    Track(W.Segmented(p, {
        { value = 0.9, label = "90%" }, { value = 1, label = "100%" },
        { value = 1.1, label = "110%" }, { value = 1.25, label = "125%" },
    }, function() return ns.settings.scale end, function(v)
        ns.settings.scale = v
        UI.main:SetScale(v)
    end, 60)):SetPoint("TOPLEFT", RX + 70, ry); ry = ry - 34
    local styleLbl = W.Text(p, 12)
    styleLbl:SetPoint("TOPLEFT", RX, ry - 6)
    styleLbl:SetText("Style")
    local bReload = W.Button(p, "Reload now", 92, 24)
    local styleSeg = Track(W.Segmented(p, {
        { value = "artisan", label = "Artisan", tip = "The flat, dark look with your accent color." },
        { value = "forever", label = "Forever", tip = "Matches WoW: Forever's own windows: brown and gold, red buttons, checkboxes." },
    }, function() return ns.settings.style or "artisan" end, function(v)
        ns.settings.style = v
        bReload:SetShown(v ~= W.style)
    end, 70))
    styleSeg:SetPoint("TOPLEFT", RX + 70, ry)
    bReload:SetPoint("LEFT", styleSeg, "RIGHT", 10, 0)
    bReload:SetScript("OnClick", function() ReloadUI() end)
    W.Tip(bReload, "Reload now", "The new style is used after a reload of your interface (/reload).")
    bReload:SetShown((ns.settings.style or "artisan") ~= W.style)
    ry = ry - 48

    Section(RX, ry, "Recipes"); ry = ry - 26
    Track(W.Toggle(p, "Hide low-level recipes",
        function() return ns.settings.hideLow end,
        function(v) ns.settings.hideLow = v end)):SetPoint("TOPLEFT", RX, ry); ry = ry - 30
    local cutLbl = W.Text(p, 12)
    cutLbl:SetPoint("TOPLEFT", RX, ry - 6)
    cutLbl:SetText("Below level")
    Track(W.Segmented(p, {
        { value = 20, label = "20" }, { value = 30, label = "30" },
        { value = 40, label = "40" }, { value = 50, label = "50" },
    }, function() return ns.settings.lowCutoff end, function(v) ns.settings.lowCutoff = v end, 56))
        :SetPoint("TOPLEFT", RX + 86, ry); ry = ry - 32
    Desc(RX, ry, "Uses the crafted item's level. Enchants go by their materials or rank (Minor, Lesser...). Right-click any recipe to hide or show it."); ry = ry - 40
    Track(W.Toggle(p, "Show Bind on Pickup recipes",
        function() return ns.settings.showBoP end,
        function(v) ns.settings.showBoP = v end)):SetPoint("TOPLEFT", RX, ry); ry = ry - 30
    local bUnhide = W.Button(p, "Unhide all recipes", 150, 26)
    bUnhide:SetPoint("TOPLEFT", RX, ry)
    bUnhide:SetScript("OnClick", function()
        local n = 0
        for k, v in pairs(ns.db.hidden) do
            if v == true then n = n + 1 end
            ns.db.hidden[k] = nil
        end
        ns:Fire("HIDDEN")
        ns.Print(n .. (n == 1 and " recipe" or " recipes") .. " unhidden.")
    end)
    ry = ry - 44

    Section(RX, ry, "Data"); ry = ry - 26
    local pruneLbl = W.Text(p, 12)
    pruneLbl:SetPoint("TOPLEFT", RX, ry - 6)
    pruneLbl:SetText("Forget after")
    Track(W.Segmented(p, {
        { value = 7, label = "7 days" }, { value = 30, label = "30 days" }, { value = 90, label = "90 days" },
    }, function() return ns.settings.pruneDays end, function(v) ns.settings.pruneDays = v end, 76))
        :SetPoint("TOPLEFT", RX + 82, ry); ry = ry - 40

    -- "Announce now" was replaced by Refresh on the Players page; test mode is /artisan test
    local bScan = W.Button(p, "Rescan skills", 150, 26)
    bScan:SetPoint("TOPLEFT", RX, ry)
    bScan:SetScript("OnClick", function()
        ns:ScanSkillLevels(); ns:RebuildPayload(); UI:Refresh()
        ns.Print("Skill levels rescanned.")
    end)
    local bForget = W.Button(p, "Forget players", 150, 26)
    bForget:SetPoint("LEFT", bScan, "RIGHT", 10, 0)
    W.Tip(bForget, "Forget players", "Clears every other player and their recipes. They come back as they announce themselves. Your own characters are kept. Click twice to confirm.")
    bForget:SetScript("OnClick", function(self)
        if self.armed then
            self.armed = nil
            self:SetLabel("Forget players")
            ns:ResetData()
        else
            self.armed = true
            self:SetLabel("Click again to confirm")
            C_Timer.After(3, function() self.armed = nil; self:SetLabel("Forget players") end)
        end
    end)
    ry = ry - 50

    local foot = W.Text(p, 10, C.faint)
    foot:SetPoint("BOTTOMLEFT", LX, 18)
    foot:SetText("Artisan Network v" .. ns.VERSION .. "   ·   /artisan help for commands")

    local page = { frame = p }
    function page.refresh()
        for _, c in ipairs(controls) do c:Refresh() end
        for _, s in ipairs(swatches) do
            if s.key == ns.settings.accent then W.SetBorderColor(s, 1, 1, 1, 0.9)
            else W.SetBorderColor(s, unpack(C.border)) end
        end
    end
    return page
end
